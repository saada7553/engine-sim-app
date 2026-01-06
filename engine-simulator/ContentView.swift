//
//  ContentView.swift
//  engine-simulator
//
//  Created by Saad Ata on 12/30/25.
//

import SwiftUI
import Combine

struct RetroFont: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight = .bold
    
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .monospaced))
    }
}

// A box with a header bar
struct RetroPanel<Content: View>: View {
    var title: String
    var content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title.uppercased())
                    .modifier(RetroFont(size: 10))
                    .foregroundColor(.black) // Replaced .retroBlack
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white)
                Spacer()
            }
            .background(Color.white.opacity(0.1))
            
            // Content
            ZStack {
                Color.black // Replaced .retroBlack
                content
                    .padding(8)
            }
        }
        .border(Color.white.opacity(0.3), width: 1)
    }
}

// MARK: - 1. ViewModel
class EngineInterface: ObservableObject {
    private var engine: EngineWrapper?
    private var timer: Timer?
    
    // Live Data
    @Published var rpm: Double = 0.0
    @Published var gear: Int = 0
    @Published var isIgnitionOn: Bool = false
    @Published var isStarterOn: Bool = false
    @Published var vehicleSpeed: Double = 0.0
    @Published var distanceTravelled: Double = 0.0
    @Published var fuelConsumed: Double = 0.0
    @Published var redline: Double
    
    // Inputs
    @Published var throttlePosition: Double = 0.0 {
        didSet { engine?.setThrottle(throttlePosition) }
    }
    
    @Published var clutchPressed: Bool = true
    
    init() {
        let newEngine = EngineWrapper()
        self.engine = newEngine
        self.redline = newEngine?.getEngineRedline() ?? 6500.0
        print(self.redline)
        self.startPolling()
        
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            let newEngine = EngineWrapper()
//            DispatchQueue.main.async {
//                self?.engine = newEngine
//                self?.redline = newEngine?.getEngineRedline() ?? 6500.0
//                self?.startPolling()
//            }
//        }
    }
    
    func startPolling() {
        timer = Timer.scheduledTimer(timeInterval: 1.0/60.0, target: self, selector: #selector(update), userInfo: nil, repeats: true)
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    @objc func update() {
        guard let engine = engine else { return }
        self.rpm = engine.getRPM()
        self.gear = Int(engine.getGear())
        self.isIgnitionOn = engine.isIgnitionOn()
        self.isStarterOn = engine.isStarterOn()
        self.vehicleSpeed = engine.getVehicleSpeed()
        self.distanceTravelled = engine.getTravelledDistance()
        self.fuelConsumed = engine.getTotalVolumeFuelConsumed()
    }
    
    func toggleIgnition() { engine?.toggleIgnition() }
    func toggleStarter() { engine?.toggleStarter() }
    func toggleClutch() {
        clutchPressed.toggle()
        engine?.toggleClutch()
    }
    func shiftUp() { engine?.shiftUp() }
    func shiftDown() { engine?.shiftDown() }
    func resetStats() {
        engine?.resetTravelledDistance()
        engine?.resetFuelConsumption()
    }
}

// 2.2 The Big Needle Gauge (Restored)
struct BigNeedleGauge: View {
    var rpm: Double
    var maxRPM: Double
    
    var body: some View {
        ZStack {
            // Dial Background
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 4)
            
            // Tick Marks
            ForEach(0..<41) { tick in
                let isMajor = tick % 5 == 0
                let fraction = Double(tick) / 40.0
                let angle = -210 + (fraction * 240)
                
                Rectangle()
                    .fill(fraction > 0.85 ? Color.red : (isMajor ? Color.white : Color.gray)) // Replaced .retroRed
                    .frame(width: isMajor ? 3 : 1.5, height: isMajor ? 12 : 6)
                    .offset(y: -85) // Adjusted for smaller container
                    .rotationEffect(.degrees(angle))
            }
            
            // Labels (Simplified to 0, 4, 8)
            ForEach(0..<9) { i in
                if i % 2 == 0 { // Only even numbers to save space
                    let fraction = Double(i) / 8.0
                    let angle = -210 + (fraction * 240)
                    Text("\(i)")
                        .modifier(RetroFont(size: 14))
                        .foregroundColor(fraction > 0.85 ? .red : .white) // Replaced .retroRed
                        .offset(y: -60)
                        .rotationEffect(.degrees(angle))
                }
            }
            
            // Digital Readout
            VStack(spacing: 0) {
                Text("\(Int(rpm))")
                    .modifier(RetroFont(size: 20, weight: .black))
                    .foregroundColor(.white)
                Text("RPM")
                    .modifier(RetroFont(size: 8))
                    .foregroundColor(.gray)
            }
            .offset(y: 40)
            
            // Needle
            Rectangle()
                .fill(Color.red) // Replaced .retroRed
                .frame(width: 3, height: 90)
                .cornerRadius(1.5)
                .offset(y: -35)
                .rotationEffect(.degrees(-210 + (240 * min(rpm / maxRPM, 1.05))))
                .animation(.easeOut(duration: 0.1), value: rpm)
            
            // Center Cap
            Circle()
                .fill(Color.black)
                .frame(width: 15, height: 15)
                .overlay(Circle().stroke(Color.gray, lineWidth: 2))
        }
        .padding(10)
    }
}

// 2.3 Scrolling Graph (For Exhaust/Right Panel)
struct ScrollingGraphView: View {
    @State private var points: [CGFloat] = Array(repeating: 20, count: 40)
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for (index, point) in points.enumerated() {
                    let x = CGFloat(index) * (geo.size.width / CGFloat(points.count - 1))
                    let y = geo.size.height / 2 + point
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.orange, lineWidth: 1.5) // Replaced .retroOrange
        }
        .background(Color.black) // Replaced .retroBlack
        .clipShape(Rectangle())
        .onReceive(Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()) { _ in
            points.removeFirst()
            // Simulating exhaust pulse
            let noise = CGFloat.random(in: -5...5)
            let pulse = CGFloat(sin(Date().timeIntervalSince1970 * 20) * 15)
            points.append(pulse + noise)
        }
    }
}

// MARK: - 3. Main Layout
struct ContentView: View {
    @StateObject var vm = EngineInterface()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all) // Replaced .retroDark
            
            VStack(spacing: 8) {
                // HEADER
                HStack {
                    Text("ENGINE CONTROLLER")
                        .modifier(RetroFont(size: 16))
                        .foregroundColor(.white)
                    Spacer()
                    Text("BUILD V0.2 // A.G.")
                        .modifier(RetroFont(size: 10))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                // MAIN CONTENT
                HStack(alignment: .top, spacing: 8) {
                    
                    // --- COLUMN 1: CONTROLS (Left) ---
                    VStack(spacing: 8) {
                        RetroPanel("CONTROLS") {
                            VStack(spacing: 12) {
                                ControlButton(label: "IGNITION", active: vm.isIgnitionOn, color: .red) { vm.toggleIgnition() } // Replaced .retroRed
                                ControlButton(label: "STARTER", active: vm.isStarterOn, color: .orange) { vm.toggleStarter() } // Replaced .retroOrange
                                ControlButton(label: "CLUTCH", active: vm.clutchPressed, color: .blue) { vm.toggleClutch() }
                                
                                Divider().background(Color.gray)
                                
                                HStack(spacing: 10) {
                                    ShiftButton(label: "-", action: { vm.shiftDown() })
                                    ShiftButton(label: "+", action: { vm.shiftUp() })
                                }
                            }
                            .padding(.vertical, 10)
                        }
                        
                        RetroPanel("DATA") {
                            VStack(spacing: 8) {
                                DataRow(label: "FUEL", value: String(format: "%.2f L", vm.fuelConsumed))
                                DataRow(label: "DIST", value: String(format: "%.1f KM", vm.distanceTravelled))
                                DataRow(label: "SPD", value: String(format: "%.0f KM/H", vm.vehicleSpeed))
                            }
                            .padding(.vertical, 5)
                        }
                        
                        Spacer()
                    }
                    .frame(width: 180)
                    
                    // --- COLUMN 2: ENGINE VISUALIZATION (Center - LARGE) ---
                    VStack(spacing: 8) {
                        RetroPanel("ENGINE VISUALIZATION") {
                            ZStack {
                                Color.black
                                Engine3DView(rpm: vm.rpm)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
                        RetroPanel("THROTTLE") {
                            HStack {
                                Text("IDLE").modifier(RetroFont(size: 10)).foregroundColor(.gray)
                                Slider(value: $vm.throttlePosition, in: 0...1)
                                    .accentColor(.orange)
                                Text("WOT").modifier(RetroFont(size: 10)).foregroundColor(.red)
                            }
                            .frame(height: 30)
                        }
                    }
                    .frame(maxWidth: .infinity) // Takes remaining space
                    
                    // --- COLUMN 3: INSTRUMENTS (Right) ---
                    VStack(spacing: 8) {
                        RetroPanel("TACHOMETER") {
                            BigNeedleGauge(rpm: vm.rpm, maxRPM: vm.redline)
                                .frame(height: 200)
                        }
                        
                        RetroPanel("GEAR") {
                            Text(vm.gear == -1 ? "N" : "\(vm.gear + 1)")
                                .font(.system(size: 90, weight: .black, design: .rounded))
                                .foregroundColor(vm.gear == -1 ? .green : .orange)
                                .frame(maxWidth: .infinity)
                                .frame(height: 100)
                        }
                        
                        // Replaced "Status" with this Graph
                        RetroPanel("EXHAUST FLOW") {
                            ScrollingGraphView()
                                .frame(height: 80)
                        }
                        
                        Spacer()
                    }
                    .frame(width: 220)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }
}

// MARK: - 4. Helper Views

struct ControlButton: View {
    var label: String
    var active: Bool
    var color: Color
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).modifier(RetroFont(size: 12))
                Spacer()
                Circle()
                    .fill(active ? color : Color.black)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    .frame(width: 12, height: 12)
            }
            .padding(12)
            .background(Color.white.opacity(active ? 0.15 : 0.05))
            .border(active ? color : Color.gray.opacity(0.3), width: 1)
        }
        .buttonStyle(.plain)
    }
}

struct ShiftButton: View {
    var label: String
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 24, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.white.opacity(0.1))
                .border(Color.white.opacity(0.3), width: 1)
        }
        .buttonStyle(.plain)
    }
}

struct DataRow: View {
    var label: String
    var value: String
    
    var body: some View {
        HStack {
            Text(label).modifier(RetroFont(size: 12)).foregroundColor(.gray)
            Spacer()
            Text(value).modifier(RetroFont(size: 12)).foregroundColor(.orange) // Replaced .retroOrange
        }
        .padding(.horizontal, 4)
        Divider().background(Color.gray.opacity(0.3))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 900, height: 600)
    }
}


import SceneKit
import SwiftUI
import ModelIO
import SceneKit.ModelIO

// MARK: - 3D Engine View (Inline-4 with OBJ Models)
struct Engine3DView: NSViewRepresentable {
    var rpm: Double

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()

        // 1. Setup Scene
        let scene = SCNScene()
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = .orbitAngleMapping
        scnView.backgroundColor = NSColor.black
        scnView.antialiasingMode = .multisampling4X

        // Enable continuous rendering (animation plays even without interaction)
        scnView.isPlaying = true
        scnView.loops = true

        // 2. Camera - positioned to see inline-4 engine
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.001
        cameraNode.camera?.zFar = 1000.0
//        cameraNode.position = SCNVector3(x: -0.95, y: 0.57, z: 0.6)
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 0)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        // 3. Lighting - balanced for metal parts
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

        // 4. Create the Engine Assembly with OBJ models
        let engineNode = createEngineAssembly(coordinator: context.coordinator)
        engineNode.name = "engineAssembly"
        scene.rootNode.addChildNode(engineNode)

        // 5. Assign Delegate for Animation
        scnView.delegate = context.coordinator

        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.currentRPM = rpm
        print("updating")
        if let cameraNode = nsView.pointOfView {
            let pos = cameraNode.position
            print("Camera Position: x: \(String(format: "%.2f", pos.x)), y: \(String(format: "%.2f", pos.y)), z: \(String(format: "%.2f", pos.z))")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - OBJ Model Loader
    func loadOBJModel(named fileName: String) -> SCNNode? {
        // Try multiple locations: subdirectory first, then root bundle
        var url: URL?

        // Try Components subdirectory first
        url = Bundle.main.url(forResource: fileName, withExtension: "obj", subdirectory: "Components")

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

    // MARK: - Engine Assembly Builder
    func createEngineAssembly(coordinator: Coordinator) -> SCNNode {
        let assembly = SCNNode()
        
        assembly.eulerAngles.x = -.pi / 2
        assembly.eulerAngles.y = .pi / 2
        assembly.position = SCNVector3(x: -0.172, y: 0.15, z: -0.75)

        // Inline-4 configuration
        let cylinderCount = 4
        let cylinderSpacing: Float = 0.115  // Spacing along crankshaft axis (Y)
    
        // Phase offsets for inline-4 firing order (1-3-4-2)
        // Crank throws at: 0°, 180°, 180°, 0° (pairs fire together)
        let phaseOffsets: [Double] = [0, .pi, .pi, 0]

        // Geometry constants (derived from model inspection, adjust as needed)
        // These control the animation proportions
        let crankThrow: CGFloat = 0.035483    // Crank throw radius
        let rodLength: CGFloat = 0.2420609      // Connecting rod length
        let pistonBaseY: CGFloat = 0.15    // Base Y position for pistons
        
        coordinator.crankThrow = crankThrow
        coordinator.rodLength = rodLength
        coordinator.pistonBaseY = pistonBaseY
        coordinator.cylinderCount = cylinderCount
        coordinator.phaseOffsets = phaseOffsets

        // Load and add static parts
        if let engineBlock = loadOBJModel(named: "Piston - Engine_Block") {
            engineBlock.name = "engineBlock"
            assembly.addChildNode(engineBlock)
        }

        if let crankCase = loadOBJModel(named: "Piston - Crank_Case") {
            crankCase.name = "crankCase"
            assembly.addChildNode(crankCase)
        }

        // Load crankshaft
        if let crankshaft = loadOBJModel(named: "Piston - Crankshaft") {
            crankshaft.name = "crankshaft"

            // Calculate bounding box center to set pivot for proper rotation
            let (minBound, maxBound) = crankshaft.boundingBox
            let centerX = (minBound.x + maxBound.x) / 2
            let centerY = (minBound.y + maxBound.y) / 2
            let centerZ = (minBound.z + maxBound.z) / 2

            // Set pivot at geometric center so crankshaft spins around its axis
            crankshaft.pivot = SCNMatrix4MakeTranslation(centerX, centerY, centerZ)
            crankshaft.position = SCNVector3(0, -0.17, -0.28)
            
            assembly.addChildNode(crankshaft)
            coordinator.crankshaftNode = crankshaft
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

            cylindersContainer.addChildNode(cylinderAssembly)
        }

        assembly.addChildNode(cylindersContainer)

        return assembly
    }

    // MARK: - Animation Coordinator (Slider-Crank Kinematics)
    class Coordinator: NSObject, SCNSceneRendererDelegate {
        var currentRPM: Double = 0.0
        var accumulatedAngle: Double = 0.0
        var lastUpdateTime: TimeInterval = 0.0

        // Geometry constants (set by createEngineAssembly)
        var crankThrow: CGFloat = 0.035
        var rodLength: CGFloat = 0.12
        var pistonBaseY: CGFloat = 0.15
        var cylinderCount: Int = 4
        var phaseOffsets: [Double] = [0, .pi, .pi, 0]

        // Node references
        weak var crankshaftNode: SCNNode?
        var pistonNodes: [SCNNode] = []
        var connectingRodNodes: [SCNNode] = []
        var wristPinNodes: [SCNNode] = []

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
        }
    }
}
