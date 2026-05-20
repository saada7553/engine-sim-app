//
//  Engine3DProceduralView.swift
//  engine-simulator
//
//  Live procedural 3D visualisation: builds the engine geometry from the
//  currently-selected EngineSpec (user-built or built-in via LUT) and rebuilds
//  whenever the spec changes. RPM drives a slider-crank animation loop.
//

import SwiftUI
import SceneKit
import Combine

// Camera framing: distance is a multiple of the engine diagonal so it always
// fits, regardless of size. Direction is a normalized vector pointing from the
// engine center toward the camera, giving a top-front-side 3/4 view.
private let cameraDistanceFactor: Double = 1.6
private let cameraDirX: Float = 0.9   // side
private let cameraDirY: Float = 0.7   // top
private let cameraDirZ: Float = 1.0   // front
private let maxDtSeconds: Double = 1.0 / 30.0

struct Engine3DProceduralView: NSViewRepresentable {
    @ObservedObject var vm: EngineViewModel

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = SCNScene()
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = .orbitAngleMapping
        scnView.backgroundColor = NSColor(Color.appBackground)
        scnView.antialiasingMode = .multisampling4X
        scnView.isPlaying = true
        scnView.loops = true

        configureLights(in: scnView.scene!)
        configureCamera(in: scnView.scene!, params: nil)

        // Initial spec — pull from the currently-selected engine entry.
        let initialSpec = currentEffectiveSpec()
        context.coordinator.attach(scnView: scnView, spec: initialSpec)

        // Live-rebuild when the selected engine changes OR when its user spec is edited.
        // EngineLibrary republishes the entries array on save, so observing both gets us
        // re-renders for layout/bore/stroke changes plus library swaps.
        context.coordinator.subscribe(to: EngineLibrary.shared)

        scnView.delegate = context.coordinator
        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.currentRPM = vm.rpm
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Helpers

    private func currentEffectiveSpec() -> EngineSpec? {
        EngineLibrary.shared.selectedEntry?.effectiveSpec
    }

    private func configureLights(in scene: SCNScene) {
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 600
        key.light?.color = NSColor(white: 0.95, alpha: 1.0)
        key.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 250
        fill.light?.color = NSColor(white: 0.75, alpha: 1.0)
        fill.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi / 3, 0)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 120
        ambient.light?.color = NSColor(white: 0.4, alpha: 1.0)
        scene.rootNode.addChildNode(ambient)
    }

    private func configureCamera(in scene: SCNScene, params: EngineGeometryParams?) {
        let cameraNode = scene.rootNode.childNode(withName: "camera", recursively: false) ?? SCNNode()
        if cameraNode.camera == nil {
            cameraNode.name = "camera"
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.zNear = 0.005
            cameraNode.camera?.zFar = 50.0
            scene.rootNode.addChildNode(cameraNode)
        }

        if let p = params {
            placeCamera(cameraNode, params: p)
        } else {
            cameraNode.position = SCNVector3(1.0, 0.7, 1.0)
            cameraNode.look(at: SCNVector3(0, 0, 0))
        }
    }

    fileprivate static func placeCameraStatic(_ cameraNode: SCNNode, params p: EngineGeometryParams) {
        let lengthSq = p.blockLength * p.blockLength
        let widthSq = p.blockWidth * p.blockWidth
        let heightSq = p.blockHeight * p.blockHeight
        let diag = sqrt(lengthSq + widthSq + heightSq)
        let distance = Float(diag * cameraDistanceFactor)
        let dirLenSq = cameraDirX * cameraDirX + cameraDirY * cameraDirY + cameraDirZ * cameraDirZ
        let dirLen = sqrt(dirLenSq)
        let scale = distance / dirLen
        cameraNode.position = SCNVector3(cameraDirX * scale, cameraDirY * scale, cameraDirZ * scale)
        cameraNode.look(at: SCNVector3(0, 0, 0))
    }

    fileprivate func placeCamera(_ cameraNode: SCNNode, params p: EngineGeometryParams) {
        Self.placeCameraStatic(cameraNode, params: p)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var currentRPM: Double = 0.0
        private var accumulatedAngle: Double = 0.0
        private var lastUpdateTime: TimeInterval = 0.0

        private weak var scnView: SCNView?
        private var parts: ProceduralEngineParts?
        private var currentSpecId: UUID?
        private var currentSpecFingerprint: Int = 0

        private var libraryCancellables = Set<AnyCancellable>()

        func attach(scnView: SCNView, spec: EngineSpec?) {
            self.scnView = scnView
            rebuild(with: spec)
        }

        func subscribe(to library: EngineLibrary) {
            library.$selectedEngineId
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refreshFromLibrary() }
                .store(in: &libraryCancellables)

            library.$entries
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refreshFromLibrary() }
                .store(in: &libraryCancellables)
        }

        private func refreshFromLibrary() {
            let spec = EngineLibrary.shared.selectedEntry?.effectiveSpec
            let fingerprint = spec.map(Coordinator.geometryFingerprint(of:)) ?? 0
            // Skip rebuild when nothing geometry-relevant changed (e.g., the user
            // tweaked timing or fuel without touching bore/stroke/layout).
            if spec?.id == currentSpecId && fingerprint == currentSpecFingerprint { return }
            rebuild(with: spec)
        }

        private func rebuild(with spec: EngineSpec?) {
            guard let scnView = scnView, let scene = scnView.scene else { return }

            // Remove any existing assembly + reset references.
            scene.rootNode.childNode(withName: "proceduralEngineRoot", recursively: false)?.removeFromParentNode()
            parts = nil

            guard let spec = spec else {
                currentSpecId = nil
                currentSpecFingerprint = 0
                return
            }

            let built = ProceduralEngineAssembly.build(spec: spec)
            let root = SCNNode()
            root.name = "proceduralEngineRoot"
            root.addChildNode(built.assemblyNode)
            scene.rootNode.addChildNode(root)
            self.parts = built

            currentSpecId = spec.id
            currentSpecFingerprint = Coordinator.geometryFingerprint(of: spec)

            // Re-frame the camera around the new engine size.
            adjustCamera(for: built.params)
        }

        private func adjustCamera(for p: EngineGeometryParams) {
            guard let scene = scnView?.scene,
                  let cameraNode = scene.rootNode.childNode(withName: "camera", recursively: false) else { return }
            Engine3DProceduralView.placeCameraStatic(cameraNode, params: p)
        }

        /// Hash of just the geometry-relevant fields. Used to skip rebuilds when
        /// only non-visual params (e.g., cam, timing) change.
        private static func geometryFingerprint(of spec: EngineSpec) -> Int {
            var hasher = Hasher()
            hasher.combine(spec.layout)
            hasher.combine(spec.boreMm)
            hasher.combine(spec.strokeMm)
            hasher.combine(spec.rodLengthMm)
            hasher.combine(spec.compressionHeightMm)
            hasher.combine(spec.firingOrder)
            // Cam-driven lobe shape and timing depend on these.
            hasher.combine(spec.camDurationDeg)
            hasher.combine(spec.camLiftMm)
            hasher.combine(spec.camLobeSeparationDeg)
            hasher.combine(spec.camAdvanceDeg)
            hasher.combine(spec.camBaseRadiusIn)
            return hasher.finalize()
        }

        // MARK: SCNSceneRendererDelegate

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt: Double
            if lastUpdateTime > 0 {
                dt = min(time - lastUpdateTime, maxDtSeconds)
            } else {
                dt = 1.0 / 60.0
            }
            lastUpdateTime = time

            let angularVelocity = (currentRPM / 60.0) * 2.0 * .pi
            accumulatedAngle += angularVelocity * dt
            if accumulatedAngle > 100.0 * .pi {
                accumulatedAngle = accumulatedAngle.truncatingRemainder(dividingBy: 4.0 * .pi)
            }

            if let parts = parts {
                ProceduralEngineAssembly.animate(parts: parts, crankAngle: accumulatedAngle)
            }
        }
    }
}
