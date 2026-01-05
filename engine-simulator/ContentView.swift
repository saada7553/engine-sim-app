////
////  ContentView.swift
////  engine-simulator
////
////  Created by Saad Ata on 12/30/25.
////
//
//import SwiftUI
//import Combine
//
//// MARK: - 1. ViewModel
//class EngineInterface: ObservableObject {
//    private var engine: EngineWrapper?
//    private var timer: Timer?
//    
//    // Live Data
//    @Published var rpm: Double = 0.0
//    @Published var gear: Int = 0
//    @Published var isIgnitionOn: Bool = false
//    @Published var isStarterOn: Bool = false
//    @Published var isClutchPressed: Bool = true
//    
//    // Inputs
//    @Published var throttlePosition: Double = 0.0 {
//        didSet { engine?.setThrottle(throttlePosition) }
//    }
//    
//    init() {
//        // Initialize on background to prevent UI freeze
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            let newEngine = EngineWrapper()
//            
//            DispatchQueue.main.async {
//                self?.engine = newEngine
//                self?.startPolling()
//            }
//        }
//    }
//    
//    func startPolling() {
//        // Add to 'common' mode so it updates while dragging sliders
//        timer = Timer.scheduledTimer(timeInterval: 1.0/60.0, target: self, selector: #selector(update), userInfo: nil, repeats: true)
//        RunLoop.current.add(timer!, forMode: .common)
//    }
//    
//    @objc func update() {
//        guard let engine = engine else { return }
//        self.rpm = engine.getRPM()
//        self.gear = Int(engine.getGear())
//        self.isIgnitionOn = engine.isIgnitionOn()
//        self.isStarterOn = engine.isStarterOn()
//    }
//    
//    // Controls
//    func toggleIgnition() { engine?.toggleIgnition() }
//    func toggleStarter() { engine?.toggleStarter() }
//    func toggleClutch() { engine?.toggleClutch() }
//    func shiftUp() { engine?.shiftUp() }
//    func shiftDown() { engine?.shiftDown() }
//}
//
//// MARK: - 3. Clean Needle Gauge
//struct NeedleGauge: View {
//    var rpm: Double
//    var maxRPM: Double = 8000
//    
//    var rotationAngle: Double {
//        let fraction = min(max(rpm / maxRPM, 0), 1.05)
//        return -210 + (fraction * 240)
//    }
//
//    var body: some View {
//        ZStack {
//            // Dial Background
//            Circle()
//                .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
//                .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 4))
//                .shadow(radius: 10)
//
//            // Tick Marks
//            ForEach(0..<41) { tick in
//                let isMajor = tick % 5 == 0
//                let fraction = Double(tick) / 40.0
//                let angle = -210 + (fraction * 240)
//                
//                Rectangle()
//                    .fill(fraction > 0.85 ? Color.red : (isMajor ? Color.white : Color.gray))
//                    .frame(width: isMajor ? 3 : 1.5, height: isMajor ? 15 : 8)
//                    .offset(y: -135)
//                    .rotationEffect(.degrees(angle))
//            }
//
//            // Labels
//            ForEach(0..<9) { i in
//                let fraction = Double(i) / 8.0
//                let angle = -210 + (fraction * 240)
//                
//                Text("\(i)")
//                    .font(.system(size: 24, weight: .bold, design: .rounded))
//                    .foregroundColor(fraction > 0.85 ? .red : .white)
//                    .rotationEffect(.degrees(-angle))
//                    .offset(y: -100)
//                    .rotationEffect(.degrees(angle))
//            }
//            
//            // Digital Readout
//            VStack {
//                Text("\(Int(rpm))")
//                    .font(.system(size: 32, weight: .black, design: .monospaced))
//                    .foregroundColor(.white)
//                Text("RPM")
//                    .font(.caption)
//                    .foregroundColor(.gray)
//            }
//            .offset(y: 50)
//
//            // The Needle
//            Rectangle()
//                .fill(Color.red)
//                .frame(width: 4, height: 140)
//                .cornerRadius(2)
//                .offset(y: -60)
//                .rotationEffect(.degrees(rotationAngle))
//                .animation(.easeOut(duration: 0.1), value: rpm)
//            
//            // Cap
//            Circle()
//                .fill(Color.black)
//                .frame(width: 20, height: 20)
//                .overlay(Circle().stroke(Color.gray, lineWidth: 2))
//        }
//        .frame(width: 300, height: 300)
//    }
//}
//
//// MARK: - 2. Piston Animation Component (Larger & Spaced)
//struct PistonAnimationView: View {
//    var rpm: Double
//    
//    // Animation State
//    @State private var crankAngle: Double = 0.0
//    @State private var lastTime: TimeInterval = Date().timeIntervalSinceReferenceDate
//    
//    // Geometry Constants (Scaled up 1.5x)
//    let crankRadius: CGFloat = 45   // Was 30
//    let rodLength: CGFloat = 135    // Was 90
//    let pistonHeight: CGFloat = 75  // Was 50
//    let pistonWidth: CGFloat = 90   // Was 60
//    
//    var body: some View {
//        TimelineView(.animation) { timeline in
//            Canvas { context, size in
//                // Move center down slightly to accommodate taller assembly
//                let center = CGPoint(x: size.width / 2, y: size.height * 0.8)
//                
//                // --- PHYSICS MATH (Double) ---
//                let angleRad = crankAngle * .pi / 180.0
//                let r = Double(crankRadius)
//                let l = Double(rodLength)
//                
//                // 1. Calculate Crank Pin Position
//                let crankX_Double = Double(center.x) + r * sin(angleRad)
//                let crankY_Double = Double(center.y) + r * cos(angleRad)
//                
//                let crankX = CGFloat(crankX_Double)
//                let crankY = CGFloat(crankY_Double)
//                
//                // 2. Calculate Piston Y Position
//                let term1 = r * cos(angleRad)
//                let term2 = sqrt(pow(l, 2.0) - pow(r * sin(angleRad), 2.0))
//                let pistonY = center.y - CGFloat(term1 + term2)
//                
//                // --- DRAWING (CGFloat) ---
//                
//                // 1. Engine Block (Translucent Wall)
//                let blockRect = CGRect(x: center.x - (pistonWidth/2) - 10,
//                                       y: center.y - rodLength - crankRadius - pistonHeight - 10,
//                                       width: pistonWidth + 20,
//                                       height: rodLength + crankRadius + 40)
//                
//                let blockPath = Path(roundedRect: blockRect, cornerRadius: 4)
//                context.fill(blockPath, with: .color(Color.gray.opacity(0.15)))
//                context.stroke(blockPath, with: .color(Color.white.opacity(0.3)), lineWidth: 1)
//                
//                // 2. Crankshaft
//                let crankPath = Path { p in
//                    p.addArc(center: center, radius: crankRadius + 5, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
//                }
//                context.stroke(crankPath, with: .color(.gray.opacity(0.5)), lineWidth: 3)
//                
//                // Counterweight
//                var weightPath = Path()
//                weightPath.addArc(center: center, radius: crankRadius, startAngle: .degrees(crankAngle + 90), endAngle: .degrees(crankAngle + 270), clockwise: false)
//                context.fill(weightPath, with: .color(.gray.opacity(0.8)))
//                
//                // 3. Connecting Rod
//                var rodPath = Path()
//                rodPath.move(to: CGPoint(x: crankX, y: crankY))
//                rodPath.addLine(to: CGPoint(x: center.x, y: pistonY))
//                context.stroke(rodPath, with: .color(.gray), lineWidth: 12) // Thicker rod
//                
//                // Pins
//                let pinRect = CGRect(x: crankX - 6, y: crankY - 6, width: 12, height: 12)
//                context.fill(Path(ellipseIn: pinRect), with: .color(.white))
//
//                // 4. Piston Head
//                let pistonRect = CGRect(x: center.x - (pistonWidth/2),
//                                        y: pistonY - (pistonHeight/2),
//                                        width: pistonWidth,
//                                        height: pistonHeight)
//                
//                context.fill(Path(roundedRect: pistonRect, cornerRadius: 5), with: .color(.cyan.opacity(0.8)))
//                
//                // Detail Lines (Rings)
//                context.stroke(Path(roundedRect: pistonRect.insetBy(dx: 0, dy: 15), cornerRadius: 2), with: .color(.black.opacity(0.5)), lineWidth: 2)
//                context.stroke(Path(roundedRect: pistonRect.insetBy(dx: 0, dy: 30), cornerRadius: 2), with: .color(.black.opacity(0.5)), lineWidth: 2)
//
//            }
//            .onChange(of: timeline.date) { newDate in
//                let currentTime = newDate.timeIntervalSinceReferenceDate
//                let dt = currentTime - lastTime
//                lastTime = currentTime
//                
//                let degreesPerSecond = rpm * 6.0
//                crankAngle += degreesPerSecond * dt
//                if crankAngle > 360 { crankAngle -= 360 }
//            }
//        }
//        // Increased Frame Size
//        .frame(width: 250, height: 450)
//    }
//}
//
//// MARK: - 3. Main View (Updated Layout)
//struct ContentView: View {
//    @StateObject var vm = EngineInterface()
//    
//    var body: some View {
//        ZStack {
//            // Background
//            Color.black.edgesIgnoringSafeArea(.all)
//            
//            VStack(spacing: 20) {
//                // Header
//                Text("ENGINE CONTROLLER")
//                    .font(.caption)
//                    .foregroundColor(.gray)
//                    .padding(.top, 40)
//                
//                Spacer()
//                
//                // MARK: Dashboard Area
//                // Increased spacing to 60 for separation
//                HStack(spacing: 60) {
//                    NeedleGauge(rpm: vm.rpm)
//                    
//                    VStack(spacing: 10) {
//                        Text("CYLINDER 1")
//                            .font(.system(.caption, design: .monospaced))
//                            .foregroundColor(.gray)
//                            .tracking(2)
//                        
//                        PistonAnimationView(rpm: vm.rpm)
//                    }
//                }
//                .padding(.horizontal)
//                
//                // Gear Display
//                Text(vm.gear == 0 ? "N" : "\(vm.gear)")
//                    .font(.system(size: 60, weight: .black, design: .rounded))
//                    .foregroundColor(.yellow)
//                    .padding()
//                    .background(RoundedRectangle(cornerRadius: 15).stroke(Color.yellow, lineWidth: 2))
//                
//                Spacer()
//                
//                // Controls
//                VStack(spacing: 20) {
//                    HStack {
//                        Text("THROTTLE").foregroundColor(.white).font(.caption)
//                        Slider(value: $vm.throttlePosition, in: 0...1).accentColor(.red)
//                    }.padding(.horizontal)
//                    
//                    LazyVGrid(columns: [GridItem(), GridItem()]) {
//                        ControlBtn(label: "IGNITION", active: vm.isIgnitionOn) { vm.toggleIgnition() }
//                        ControlBtn(label: "STARTER", active: vm.isStarterOn) { vm.toggleStarter() }
//                        ControlBtn(label: "SHIFT DOWN", active: false) { vm.shiftDown() }
//                        ControlBtn(label: "SHIFT UP", active: false) { vm.shiftUp() }
//                        ControlBtn(label: "Clutch", active: true) { vm.toggleClutch() }
//                    }.padding(.horizontal)
//                }
//                .padding(.bottom, 40)
//            }
//        }
//    }
//}
//
//// Helper Button
//struct ControlBtn: View {
//    var label: String
//    var active: Bool
//    var action: () -> Void
//    
//    var body: some View {
//        Button(action: action) {
//            Text(label)
//                .font(.system(.body, design: .monospaced))
//                .bold()
//                .frame(maxWidth: .infinity, minHeight: 50)
//                .background(active ? Color.green : Color.gray.opacity(0.3))
//                .foregroundColor(.white)
//                .cornerRadius(8)
//        }
//    }
//}


//
//  ContentView.swift
//  engine-simulator
//
//  Created by Saad Ata on 12/30/25.
//

import SwiftUI
import Combine

// MARK: - 0. Theme & Styles
extension Color {
    static let retroBlack = Color(red: 0.05, green: 0.05, blue: 0.05)
    static let retroDark = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let retroOrange = Color(red: 1.0, green: 0.55, blue: 0.0)
    static let retroRed = Color(red: 0.9, green: 0.2, blue: 0.2)
    static let retroCyan = Color(red: 0.2, green: 0.8, blue: 0.9)
    static let retroDim = Color(white: 0.4)
}

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
                    .foregroundColor(.retroBlack)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white)
                Spacer()
            }
            .background(Color.white.opacity(0.1))
            
            // Content
            ZStack {
                Color.retroBlack
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
                    .fill(fraction > 0.85 ? Color.retroRed : (isMajor ? Color.white : Color.gray))
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
                        .foregroundColor(fraction > 0.85 ? .retroRed : .white)
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
                .fill(Color.retroRed)
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
            .stroke(Color.retroOrange, lineWidth: 1.5)
        }
        .background(Color.retroBlack)
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
            Color.retroDark.edgesIgnoringSafeArea(.all)
            
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
                                ControlButton(label: "IGNITION", active: vm.isIgnitionOn, color: .retroRed) { vm.toggleIgnition() }
                                ControlButton(label: "STARTER", active: vm.isStarterOn, color: .retroOrange) { vm.toggleStarter() }
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
                                    .accentColor(.retroOrange)
                                Text("WOT").modifier(RetroFont(size: 10)).foregroundColor(.retroRed)
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
                            Text(vm.gear == 0 ? "N" : "\(vm.gear)")
                                .font(.system(size: 90, weight: .black, design: .rounded))
                                .foregroundColor(vm.gear == 0 ? .green : .retroOrange)
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
            Text(value).modifier(RetroFont(size: 12)).foregroundColor(.retroOrange)
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

// MARK: - 3D Engine View
struct Engine3DView: NSViewRepresentable {
    var rpm: Double
    
    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        
        // 1. Setup Scene
        let scene = SCNScene()
        scnView.scene = scene
        scnView.allowsCameraControl = true // You can drag/rotate with mouse
        scnView.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        
        // 2. Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 5, z: 25)
        scene.rootNode.addChildNode(cameraNode)
        
        // 3. Lighting
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(x: 10, y: 10, z: 30)
        scene.rootNode.addChildNode(lightNode)
        
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = NSColor.darkGray
        scene.rootNode.addChildNode(ambientLight)
        
        // 4. Create the Engine Model
        // NOTE: If you have a file, use: let engineNode = SCNScene(named: "engine.usdz")!.rootNode.clone()
        let engineNode = createProceduralEngine()
        engineNode.name = "engineAssembly"
        scene.rootNode.addChildNode(engineNode)
        
        // 5. Assign Delegate for Animation
        scnView.delegate = context.coordinator
        
        return scnView
    }
    
    func updateNSView(_ nsView: SCNView, context: Context) {
        // Pass the latest RPM to the coordinator so the render loop sees it
        context.coordinator.currentRPM = rpm
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Render Loop (Animation Logic)
    class Coordinator: NSObject, SCNSceneRendererDelegate {
        var currentRPM: Double = 0.0
        var currentAngle: Double = 0.0
        
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let scene = renderer.scene,
                  let assembly = scene.rootNode.childNode(withName: "engineAssembly", recursively: true) else { return }
            
            // 1. Calculate Rotation Step
            // RPM / 60 = Revolutions per Second
            // * 360 = Degrees per Second
            // * deltaTime would be better, but SceneKit loops are consistent enough for this demo
            // We use a small factor to smooth it out relative to frame refresh
            
            let rotationSpeed = (currentRPM / 60.0) * (2.0 * .pi) // Radians per second
            let dt = 1.0 / 60.0 // Assuming 60fps target
            
            currentAngle += rotationSpeed * dt
            
            // 2. Apply Rotation to Crankshaft (The parent node)
            // If you import a model, you might need to find the specific node name like "Crankshaft"
            // Here we rotate the whole assembly for effect, or specific parts
            
            // Example: Rotating the Crankshaft Node
            if let crankshaft = assembly.childNode(withName: "crankshaft", recursively: true) {
                crankshaft.eulerAngles.z = CGFloat(currentAngle)
                
                // 3. Simple Inverse Kinematics for Piston (Visual Only)
                if let piston = assembly.childNode(withName: "piston", recursively: true) {
                    // Simple Sine wave motion based on crank angle
                    let yOffset = sin(currentAngle) * 4.0 // 4.0 is crank radius
                    piston.position.y = CGFloat(10.0 + yOffset)
                }
                
                if let rod = assembly.childNode(withName: "rod", recursively: true) {
                     // Complex rod math simplified: Move with piston, rock back and forth
                    let yOffset = sin(currentAngle) * 4.0
                    let xOffset = cos(currentAngle) * 4.0
                    
                    rod.position.y = CGFloat(6 + yOffset)
                    rod.position.x = CGFloat(xOffset * 0.5) // Slight X movement
                    // Rocking angle
                    rod.eulerAngles.z = CGFloat(cos(currentAngle) * 0.2)
                }
            }
        }
    }
    
    // MARK: - Procedural Model Builder
    // This builds a "Toy" engine so you see something immediately.
    func createProceduralEngine() -> SCNNode {
        let assembly = SCNNode()
        
        // 1. Crankshaft (Center of Rotation)
        let crankGeo = SCNCylinder(radius: 1, height: 10)
        crankGeo.firstMaterial?.diffuse.contents = NSColor.gray
        let crankNode = SCNNode(geometry: crankGeo)
        crankNode.name = "crankshaft"
        crankNode.rotation = SCNVector4(1, 0, 0, Float.pi / 2) // Lay flat
        
        // Add a "Counterweight" so we can see it spinning
        let weightGeo = SCNBox(width: 4, height: 8, length: 1, chamferRadius: 0.1)
        weightGeo.firstMaterial?.diffuse.contents = NSColor.darkGray
        let weightNode = SCNNode(geometry: weightGeo)
        weightNode.position = SCNVector3(0, 0, 0)
        crankNode.addChildNode(weightNode)
        
        // 2. Connecting Rod
        let rodGeo = SCNBox(width: 1.5, height: 12, length: 1.5, chamferRadius: 0.2)
        rodGeo.firstMaterial?.diffuse.contents = NSColor.lightGray
        let rodNode = SCNNode(geometry: rodGeo)
        rodNode.name = "rod"
        rodNode.position = SCNVector3(0, 6, 0)
        rodNode.pivot = SCNMatrix4MakeTranslation(0, -5, 0) // Pivot at bottom
        
        // 3. Piston
        let pistonGeo = SCNCylinder(radius: 4, height: 6)
        pistonGeo.firstMaterial?.diffuse.contents = NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1) // Orange
        let pistonNode = SCNNode(geometry: pistonGeo)
        pistonNode.name = "piston"
        pistonNode.position = SCNVector3(0, 10, 0)
        
        // Build Hierarchy
        // We attach rod and piston to assembly, not crank, because they move differently
        assembly.addChildNode(crankNode)
        assembly.addChildNode(rodNode)
        assembly.addChildNode(pistonNode)
        
        return assembly
    }
}
