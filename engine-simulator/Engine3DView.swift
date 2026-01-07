//
//  Engine3DView.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/5/26.
//

import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO

struct Engine3DView: NSViewRepresentable {
    @ObservedObject var vm: EngineViewModel

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()

        let scene = SCNScene()
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = .orbitAngleMapping
        scnView.backgroundColor = NSColor.black
        scnView.antialiasingMode = .multisampling4X

        scnView.isPlaying = true
        scnView.loops = true

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.001
        cameraNode.camera?.zFar = 1000.0
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 0)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 400
        keyLight.light?.color = NSColor(white: 0.9, alpha: 1.0)
        keyLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.intensity = 200
        fillLight.light?.color = NSColor(white: 0.7, alpha: 1.0)
        fillLight.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi / 3, 0)
        scene.rootNode.addChildNode(fillLight)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 100
        ambientLight.light?.color = NSColor(white: 0.3, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)

        let engineNode = createEngineAssembly(coordinator: context.coordinator)
        engineNode.name = "engineAssembly"
        scene.rootNode.addChildNode(engineNode)

        scnView.delegate = context.coordinator
        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.currentRPM = vm.rpm
        context.coordinator.throttlePosition = vm.throttlePosition
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - OBJ Model Loader
    func loadOBJModel(named fileName: String) -> SCNNode? {
        var url: URL?

        // Try Components subdirectory first
        url = Bundle.main.url(
            forResource: fileName,
            withExtension: "obj",
            subdirectory: "Components"
        )

        // Fall back to bundle root
        if url == nil {
            url = Bundle.main.url(forResource: fileName, withExtension: "obj")
        }

        guard let modelURL = url else {
            print("Failed to find \(fileName).obj in bundle")
            return nil
        }

        let asset = MDLAsset(url: modelURL)
        guard asset.count > 0 else {
            print("No objects in asset for \(fileName)")
            return nil
        }

        let node = SCNNode()
        for i in 0..<asset.count {
            if let mdlObject = asset.object(at: i) as? MDLMesh {
                let scnNode = SCNNode(mdlObject: mdlObject)
                node.addChildNode(scnNode)
            }
        }
        return node
    }
    
    func _normalizePivot(node: SCNNode) {
        let (min, max) = node.boundingBox
        let cX = (min.x + max.x) / 2
        let cY = (min.y + max.y) / 2
        let cZ = (min.z + max.z) / 2
        node.pivot = SCNMatrix4MakeTranslation(cX, cY, cZ)
        node.position = SCNVector3(cX, cY, cZ)
    }

    // MARK: - Engine Assembly Builder
    func createEngineAssembly(coordinator: Coordinator) -> SCNNode {
        let assembly = SCNNode()
        
        // Moving / rotating to align it with the camera.
        assembly.eulerAngles.x = -.pi / 2
        assembly.eulerAngles.y = .pi / 2
        assembly.position = SCNVector3(x: -0.172, y: 0.15, z: -0.75)

        // Inline-4 configuration
        let cylinderCount = 4
        let cylinderSpacing: Float = 0.115 // 115mm from Onshape
    
        // Phase offsets for inline-4 firing order (1-3-4-2)
        // Crank throws at: 0°, 180°, 180°, 0° (pairs fire together)
        let phaseOffsets: [Double] = [0, .pi, .pi, 0]

        // Geometry constants (derived from model inspection, adjust as needed)
        // These control the animation proportions
        let crankThrow: CGFloat = 0.035483      // Crank throw radius
        let rodLength: CGFloat = 0.2420609      // Connecting rod length
        let pistonBaseY: CGFloat = 0.15         // Base Y position for pistons
        
        coordinator.crankThrow = crankThrow
        coordinator.rodLength = rodLength
        coordinator.pistonBaseY = pistonBaseY
        coordinator.cylinderCount = cylinderCount
        coordinator.phaseOffsets = phaseOffsets

        if let engineBlock = loadOBJModel(named: "Piston - Engine_Block") {
            engineBlock.name = "engineBlock"
            assembly.addChildNode(engineBlock)
        }

        if let crankCase = loadOBJModel(named: "Piston - Crank_Case") {
            crankCase.name = "crankCase"
            assembly.addChildNode(crankCase)
        }
        
        if let cylinderHead = loadOBJModel(named: "Piston - Cylinder_Head") {
            cylinderHead.name = "cylindeHead"
            assembly.addChildNode(cylinderHead)
        }
        
        if let exhaust = loadOBJModel(named: "Piston - Exhaust") {
            exhaust.name = "exhaust"
            assembly.addChildNode(exhaust)
        }
        
        if let intake = loadOBJModel(named: "Piston - Intake") {
            intake.name = "intake"
            assembly.addChildNode(intake)
        }
        
        if let throttle = loadOBJModel(named: "Piston - Throttle") {
            throttle.name = "throttle"
            _normalizePivot(node: throttle)
            assembly.addChildNode(throttle)
            coordinator.throttleNode = throttle
        }

        if let crankshaft = loadOBJModel(named: "Piston - Crankshaft") {
            crankshaft.name = "crankshaft"
            _normalizePivot(node: crankshaft)
            assembly.addChildNode(crankshaft)
            coordinator.crankshaftNode = crankshaft
        }
        
        if let camshaft = loadOBJModel(named: "Piston - Camshaft") {
            camshaft.name = "camshaft"
            _normalizePivot(node: camshaft)
            assembly.addChildNode(camshaft)
            coordinator.camshaftNode = camshaft
        }

        // Create cylinder assemblies for inline-4
        let cylindersContainer = SCNNode()
        cylindersContainer.name = "cylinders"

        for i in 0..<cylinderCount {
            let cylinderAssembly = SCNNode()
            cylinderAssembly.name = "cylinder_\(i)"

            // Offset each cylinder along Y axis (crankshaft axis)
            let yOffset = -(Float(i) * cylinderSpacing)
            cylinderAssembly.position = SCNVector3(0, yOffset, -0.15)

            // Load piston
            if let piston = loadOBJModel(named: "Piston - Piston") {
                piston.name = "piston_\(i)"
                piston.position = SCNVector3(0, 0, Float(pistonBaseY))
                cylinderAssembly.addChildNode(piston)
                coordinator.pistonNodes.append(piston)
            }

            // Load connecting rod
            if let rod = loadOBJModel(named: "Piston - Connecting_Rod") {
                rod.name = "rod_\(i)"
                
                // Get the real bounds of the model
                let (minB, maxB) = rod.boundingBox
                let cX = (minB.x + maxB.x) / 2
                let cY = (minB.y + maxB.y) / 2
                let topToMiddleOfTopHole = 0.031778

                // Set pivot at SMALL END (top of rod / wrist pin end)
                // The rod will be positioned at the wrist pin and rotate from there
                // Small end is at maxB.z (top), so pivot there
                rod.pivot = SCNMatrix4MakeTranslation(cX, cY, maxB.z - topToMiddleOfTopHole)

                cylinderAssembly.addChildNode(rod)
                coordinator.connectingRodNodes.append(rod)
            }

            // Load wrist pin
            if let wristPin = loadOBJModel(named: "Piston - Wristpin") {
                wristPin.name = "wristPin_\(i)"
                wristPin.position = SCNVector3(0, 0, Float(pistonBaseY))
                cylinderAssembly.addChildNode(wristPin)
                coordinator.wristPinNodes.append(wristPin)
            }
            
            if let intakeVaulve = loadOBJModel(named: "Piston - Intake_Valve") {
                intakeVaulve.name = "intakeValve_\(i)"
                intakeVaulve.position = SCNVector3(0, 0, Float(pistonBaseY))
                cylinderAssembly.addChildNode(intakeVaulve)
                coordinator.intakeValveNodes.append(intakeVaulve)
            }
            
            if let exhaustVaulve = loadOBJModel(named: "Piston - Exhaust_Valve") {
                exhaustVaulve.name = "exhaustValve_\(i)"
                exhaustVaulve.position = SCNVector3(0, 0, Float(pistonBaseY))
                cylinderAssembly.addChildNode(exhaustVaulve)
                coordinator.exhaustValveNodes.append(exhaustVaulve)
            }

            cylindersContainer.addChildNode(cylinderAssembly)
        }

        assembly.addChildNode(cylindersContainer)

        return assembly
    }

    // MARK: - Animation Coordinator (Slider-Crank Kinematics)
    class Coordinator: NSObject, SCNSceneRendererDelegate {
        var currentRPM: Double = 0.0
        var throttlePosition: Double = 0.0
        var accumulatedAngle: Double = 0.0
        var lastUpdateTime: TimeInterval = 0.0

        // Geometry constants (set by createEngineAssembly)
        var crankThrow: CGFloat = 0.035
        var rodLength: CGFloat = 0.12
        var pistonBaseY: CGFloat = 0.15
        var cylinderCount: Int = 4
        var phaseOffsets: [Double] = [0, .pi, .pi, 0]

        // Node references
        weak var throttleNode: SCNNode?
        weak var crankshaftNode: SCNNode?
        weak var camshaftNode: SCNNode?
        var pistonNodes: [SCNNode] = []
        var connectingRodNodes: [SCNNode] = []
        var wristPinNodes: [SCNNode] = []
        var intakeValveNodes: [SCNNode] = []
        var exhaustValveNodes: [SCNNode] = []
        
        // Cam phase offsets (Cyl 1, 2, 3, 4)
        // Based on: 1=Power(0), 2=Exhaust(90), 3=Compression(270), 4=Intake(180) at Cam=0
        let camPhaseOffsets: [Double] = [0, .pi/2, 3 * .pi/2, .pi]

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // Calculate delta time
            let dt: Double
            if lastUpdateTime > 0 {
                dt = min(time - lastUpdateTime, 1.0/30.0)  // Cap dt to avoid jumps
            } else {
                dt = 1.0 / 60.0
            }
            lastUpdateTime = time

            // Convert RPM to angular velocity and accumulate angle
            let angularVelocity = (currentRPM / 60.0) * 2.0 * .pi  // rad/s
            accumulatedAngle += angularVelocity * dt

            // Keep angle in reasonable range
            if accumulatedAngle > 100.0 * .pi {
                accumulatedAngle = accumulatedAngle.truncatingRemainder(dividingBy: 4.0 * .pi)
            }

            // Rotate crankshaft around Y axis (the main shaft axis for inline engine)
            crankshaftNode?.eulerAngles.y = CGFloat(Float(accumulatedAngle))
            
            // Rotate Camshaft (half speed)
            camshaftNode?.eulerAngles.y = CGFloat(Float(accumulatedAngle / 2.0))
            
            // Throttle movement
            let openAngle = -Float.pi / 2
            let scaleFactor = 0.25 + (Float(throttlePosition) * 0.75)
            let finalAngle = openAngle * scaleFactor
            throttleNode?.eulerAngles.z = CGFloat(finalAngle)

            // Animate each cylinder with its phase offset
            for i in 0..<min(cylinderCount, pistonNodes.count) {
                let cylinderAngle = accumulatedAngle + phaseOffsets[i]
                animateCylinder(index: i, crankAngle: cylinderAngle)
            }
        }

        func animateCylinder(index: Int, crankAngle: Double) {
            let sinTheta = CGFloat(sin(crankAngle))
            let cosTheta = CGFloat(cos(crankAngle))

            // Slider-crank equation for piston position
            // pistonZ = r·cos(θ) + √(L² - r²·sin²(θ))
            let r = crankThrow
            let L = rodLength
            let underRoot = L * L - r * r * sinTheta * sinTheta
            let pistonZ = r * cosTheta + sqrt(max(underRoot, 0))

            // Calculate the actual piston Z position
            let pistonActualZ = Float(pistonBaseY - (L + r) + pistonZ)

            // Update piston position (moves along Z axis - up/down in cylinder)
            if index < pistonNodes.count {
                pistonNodes[index].position.z = CGFloat(pistonActualZ)
            }

            // Connecting rod angle from vertical
            // φ = arcsin(r·sin(θ) / L)
            // Negative sign: when crank rotates and big end moves +X,
            // the rod tilts so small end is at -X relative to big end
            let rodAngle = -asin(min(max(r * sinTheta / L, -1), 1))

            // Update connecting rod - pivot is at SMALL END (wrist pin)
            // Position the rod at the wrist pin location (same Z as piston)
            // The rod rotates around its small end, swinging the big end down to the crank
            if index < connectingRodNodes.count {
                // Position at wrist pin (X=0 in cylinder frame, Z=piston position)
                connectingRodNodes[index].position.x = 0
                connectingRodNodes[index].position.z = CGFloat(pistonActualZ)
                // Rotate around Y axis - rod rocks in X-Z plane
                connectingRodNodes[index].eulerAngles.y = CGFloat(Float(rodAngle))
            }

            // Wrist pin follows piston
            if index < wristPinNodes.count {
                wristPinNodes[index].position.z = CGFloat(pistonActualZ)
            }
            
            // Valve Animation
            // Cam rotates at half crankshaft speed
            let camAngle = accumulatedAngle / 2.0
            
            if index < camPhaseOffsets.count {
                let cylinderCamPhase = camPhaseOffsets[index]
                let currentCamAngle = camAngle + cylinderCamPhase
                
                // Define Lobe Centers relative to Cam Angle 0
                // Based on User Spec:
                // Cam=0 -> Cyl 4 Intake Open (Peak at 0 relative to Cyl 4 phase? No, user said Cyl 4 is Intake Open)
                // We established:
                // Intake Center = pi (180 deg)
                // Exhaust Center = pi/2 (90 deg)
                
                let intakeCenter = Double.pi
                let exhaustCenter = Double.pi / 2.0
                let lobeWidth = Double.pi / 2.0 // 90 degrees duration
                
                func calculateLift(angle: Double, center: Double) -> Float {
                    let diff = atan2(sin(angle - center), cos(angle - center))
                    if abs(diff) < lobeWidth / 2.0 {
                        // Cosine lobe shape
                        // Map diff (-width/2 ... width/2) to (-pi/2 ... pi/2)
                        let xPrime = diff * (Double.pi / lobeWidth)
                        return Float(cos(xPrime))
                    }
                    return 0.0
                }
                
                let intakeLift = calculateLift(angle: currentCamAngle, center: intakeCenter)
                let exhaustLift = calculateLift(angle: currentCamAngle, center: exhaustCenter)
                
                let maxLift: Float = 0.008 // 8mm max lift
                
                // Valves move -Z to open (into cylinder)
                if index < intakeValveNodes.count {
                    intakeValveNodes[index].position.z = pistonBaseY - CGFloat(intakeLift * maxLift)
                }
                
                if index < exhaustValveNodes.count {
                    exhaustValveNodes[index].position.z = pistonBaseY - CGFloat(exhaustLift * maxLift)
                }
            }
        }
    }
}
