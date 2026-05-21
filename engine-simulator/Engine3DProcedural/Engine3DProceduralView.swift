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
#if os(macOS)
import AppKit
typealias _SCNViewRepresentable = NSViewRepresentable
#else
import UIKit
typealias _SCNViewRepresentable = UIViewRepresentable
#endif

// Camera framing scheme — keeps EVERY engine visually centered the same way
// regardless of size or layout:
//
//   1. Compute the engine's bounding-sphere radius from its block dimensions.
//      (sqrt of half-length² + half-width² + half-height²)
//   2. Find the engine's *visual* center in world coords. The assembly's
//      outer rotation maps local +Z (bore axis) → world +Y, and the engine
//      sits ABOVE the crank, so `params.blockCenterZ` is the world-Y the
//      camera should aim at — not world origin (which is the crank center,
//      below the engine for short blocks like the Geo Metro).
//   3. Place the camera at a fixed 3/4 unit-vector direction from that
//      visual center, at a distance scaled so the bounding sphere just fits
//      the camera's FOV (with a modest buffer).
//
// Result: small inline-3 and tall V12 alike sit at the same fraction of the
// frame, with the same view angle. Previously the camera always looked at
// the crank, so short engines appeared in the upper half of the frame with
// empty space below.
private let cameraDistanceFactor: Double = 1.15
private let cameraDirX: Float = 0.9   // side
// Lowered further from 0.45 → 0.25, so the camera now sits ~10.5°
// above horizontal — nearly level with the engine, with just enough
// tilt to see the head + intake plumbing from above the cylinder line.
private let cameraDirY: Float = 0.25  // top
private let cameraDirZ: Float = 1.0   // front
/// Vertical FOV (radians) used by the framing math. Matches SCNCamera's
/// default of 60°; only used for the distance-fit calculation here — the
/// camera node itself doesn't override its fieldOfView.
private let cameraFOV: Float = 60 * .pi / 180
private let maxDtSeconds: Double = 1.0 / 30.0

struct Engine3DProceduralView: _SCNViewRepresentable {
    @ObservedObject var vm: EngineViewModel

    private func makeSCNView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = SCNScene()
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = .orbitAngleMapping
        scnView.backgroundColor = PlatformColor(Color.appBackground)
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

#if os(macOS)
    func makeNSView(context: Context) -> SCNView { makeSCNView(context: context) }
    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.currentRPM = vm.rpm
    }
#else
    func makeUIView(context: Context) -> SCNView { makeSCNView(context: context) }
    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.currentRPM = vm.rpm
    }
#endif

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
        key.light?.color = PlatformColor(white: 0.95, alpha: 1.0)
        key.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 250
        fill.light?.color = PlatformColor(white: 0.75, alpha: 1.0)
        fill.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi / 3, 0)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 120
        ambient.light?.color = PlatformColor(white: 0.4, alpha: 1.0)
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
        // 1) Bounding-sphere radius — fits the engine in any view direction.
        let halfL = Float(p.blockLength * 0.5)
        let halfW = Float(p.blockWidth  * 0.5)
        let halfH = Float(p.blockHeight * 0.5)
        let boundingRadius = sqrt(halfL * halfL + halfW * halfW + halfH * halfH)

        // 2) Engine's visual center in world coords. The assembly rotates
        //    local +Z → world +Y, so `blockCenterZ` (local Z) becomes the
        //    world Y position the camera should aim at. Kept as plain Float
        //    components because SCNVector3.y is CGFloat on macOS and Float
        //    on iOS — doing the math in Float and constructing SCNVector3
        //    at the end side-steps that mismatch.
        let centerX: Float = 0
        let centerY: Float = Float(p.blockCenterZ)
        let centerZ: Float = 0

        // 3) Distance so the bounding sphere just fits the FOV, with a
        //    modest buffer (cameraDistanceFactor). This is mathematically
        //    identical to the old `diag × 1.15` formula since
        //    diag = 2 × boundingRadius and sin(60°/2) = 0.5 → distance =
        //    boundingRadius / 0.5 × 1.15 = 2.3 × boundingRadius = diag × 1.15.
        let distance = boundingRadius / sin(cameraFOV / 2.0)
                     * Float(cameraDistanceFactor)

        // 4) Camera position: same 3/4 unit-vector direction as before, but
        //    offset from the engine's visual center (NOT world origin), so
        //    short engines no longer hover at the top of the frame.
        let dirLen = sqrt(cameraDirX * cameraDirX
                        + cameraDirY * cameraDirY
                        + cameraDirZ * cameraDirZ)
        let ux = cameraDirX / dirLen
        let uy = cameraDirY / dirLen
        let uz = cameraDirZ / dirLen
        cameraNode.position = SCNVector3(
            centerX + ux * distance,
            centerY + uy * distance,
            centerZ + uz * distance
        )
        cameraNode.look(at: SCNVector3(centerX, centerY, centerZ))
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

            // Reset the animation clock so the new engine starts at crank=0
            // (rather than wherever the previous one was spinning), and so the
            // first dt is bounded.
            accumulatedAngle = 0.0
            lastUpdateTime = 0.0

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
