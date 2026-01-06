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
//struct RetroFont: ViewModifier {
//    var size: CGFloat
//    var weight: Font.Weight = .bold
//    
//    func body(content: Content) -> some View {
//        content.font(.system(size: size, weight: weight, design: .monospaced))
//    }
//}
//
//// A box with a header bar
//struct RetroPanel<Content: View>: View {
//    var title: String
//    var content: Content
//    
//    init(_ title: String, @ViewBuilder content: () -> Content) {
//        self.title = title
//        self.content = content()
//    }
//    
//    var body: some View {
//        VStack(spacing: 0) {
//            // Header
//            HStack {
//                Text(title.uppercased())
//                    .modifier(RetroFont(size: 10))
//                    .foregroundColor(.black) // Replaced .retroBlack
//                    .padding(.horizontal, 6)
//                    .padding(.vertical, 2)
//                    .background(Color.white)
//                Spacer()
//            }
//            .background(Color.white.opacity(0.1))
//            
//            // Content
//            ZStack {
//                Color.black // Replaced .retroBlack
//                content
//                    .padding(8)
//            }
//        }
//        .border(Color.white.opacity(0.3), width: 1)
//    }
//}
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
//    @Published var vehicleSpeed: Double = 0.0
//    @Published var distanceTravelled: Double = 0.0
//    @Published var fuelConsumed: Double = 0.0
//    @Published var redline: Double
//    
//    // Inputs
//    @Published var throttlePosition: Double = 0.0 {
//        didSet { engine?.setThrottle(throttlePosition) }
//    }
//    
//    @Published var clutchPressed: Bool = true
//    
//    init() {
//        let newEngine = EngineWrapper()
//        self.engine = newEngine
//        self.redline = newEngine?.getEngineRedline() ?? 6500.0
//        print(self.redline)
//        self.startPolling()
//        
////        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
////            let newEngine = EngineWrapper()
////            DispatchQueue.main.async {
////                self?.engine = newEngine
////                self?.redline = newEngine?.getEngineRedline() ?? 6500.0
////                self?.startPolling()
////            }
////        }
//    }
//    
//    func startPolling() {
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
//        self.vehicleSpeed = engine.getVehicleSpeed()
//        self.distanceTravelled = engine.getTravelledDistance()
//        self.fuelConsumed = engine.getTotalVolumeFuelConsumed()
//    }
//    
//    func toggleIgnition() { engine?.toggleIgnition() }
//    func toggleStarter() { engine?.toggleStarter() }
//    func toggleClutch() {
//        clutchPressed.toggle()
//        engine?.toggleClutch()
//    }
//    func shiftUp() { engine?.shiftUp() }
//    func shiftDown() { engine?.shiftDown() }
//    func resetStats() {
//        engine?.resetTravelledDistance()
//        engine?.resetFuelConsumption()
//    }
//}
//
//// 2.2 The Big Needle Gauge (Restored)
//struct BigNeedleGauge: View {
//    var rpm: Double
//    var maxRPM: Double
//    
//    var body: some View {
//        ZStack {
//            // Dial Background
//            Circle()
//                .stroke(Color.gray.opacity(0.3), lineWidth: 4)
//            
//            // Tick Marks
//            ForEach(0..<41) { tick in
//                let isMajor = tick % 5 == 0
//                let fraction = Double(tick) / 40.0
//                let angle = -210 + (fraction * 240)
//                
//                Rectangle()
//                    .fill(fraction > 0.85 ? Color.red : (isMajor ? Color.white : Color.gray)) // Replaced .retroRed
//                    .frame(width: isMajor ? 3 : 1.5, height: isMajor ? 12 : 6)
//                    .offset(y: -85) // Adjusted for smaller container
//                    .rotationEffect(.degrees(angle))
//            }
//            
//            // Labels (Simplified to 0, 4, 8)
//            ForEach(0..<9) { i in
//                if i % 2 == 0 { // Only even numbers to save space
//                    let fraction = Double(i) / 8.0
//                    let angle = -210 + (fraction * 240)
//                    Text("\(i)")
//                        .modifier(RetroFont(size: 14))
//                        .foregroundColor(fraction > 0.85 ? .red : .white) // Replaced .retroRed
//                        .offset(y: -60)
//                        .rotationEffect(.degrees(angle))
//                }
//            }
//            
//            // Digital Readout
//            VStack(spacing: 0) {
//                Text("\(Int(rpm))")
//                    .modifier(RetroFont(size: 20, weight: .black))
//                    .foregroundColor(.white)
//                Text("RPM")
//                    .modifier(RetroFont(size: 8))
//                    .foregroundColor(.gray)
//            }
//            .offset(y: 40)
//            
//            // Needle
//            Rectangle()
//                .fill(Color.red) // Replaced .retroRed
//                .frame(width: 3, height: 90)
//                .cornerRadius(1.5)
//                .offset(y: -35)
//                .rotationEffect(.degrees(-210 + (240 * min(rpm / maxRPM, 1.05))))
//                .animation(.easeOut(duration: 0.1), value: rpm)
//            
//            // Center Cap
//            Circle()
//                .fill(Color.black)
//                .frame(width: 15, height: 15)
//                .overlay(Circle().stroke(Color.gray, lineWidth: 2))
//        }
//        .padding(10)
//    }
//}
//
//// 2.3 Scrolling Graph (For Exhaust/Right Panel)
//struct ScrollingGraphView: View {
//    @State private var points: [CGFloat] = Array(repeating: 20, count: 40)
//    
//    var body: some View {
//        GeometryReader { geo in
//            Path { path in
//                for (index, point) in points.enumerated() {
//                    let x = CGFloat(index) * (geo.size.width / CGFloat(points.count - 1))
//                    let y = geo.size.height / 2 + point
//                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
//                    else { path.addLine(to: CGPoint(x: x, y: y)) }
//                }
//            }
//            .stroke(Color.orange, lineWidth: 1.5) // Replaced .retroOrange
//        }
//        .background(Color.black) // Replaced .retroBlack
//        .clipShape(Rectangle())
//        .onReceive(Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()) { _ in
//            points.removeFirst()
//            // Simulating exhaust pulse
//            let noise = CGFloat.random(in: -5...5)
//            let pulse = CGFloat(sin(Date().timeIntervalSince1970 * 20) * 15)
//            points.append(pulse + noise)
//        }
//    }
//}
//
//// MARK: - 3. Main Layout
//struct ContentView: View {
//    @StateObject var vm = EngineInterface()
//    
//    var body: some View {
//        ZStack {
//            Color.black.edgesIgnoringSafeArea(.all) // Replaced .retroDark
//            
//            VStack(spacing: 8) {
//                // HEADER
//                HStack {
//                    Text("ENGINE CONTROLLER")
//                        .modifier(RetroFont(size: 16))
//                        .foregroundColor(.white)
//                    Spacer()
//                    Text("BUILD V0.2 // A.G.")
//                        .modifier(RetroFont(size: 10))
//                        .foregroundColor(.gray)
//                }
//                .padding(.horizontal)
//                .padding(.top, 10)
//                
//                // MAIN CONTENT
//                HStack(alignment: .top, spacing: 8) {
//                    
//                    // --- COLUMN 1: CONTROLS (Left) ---
//                    VStack(spacing: 8) {
//                        RetroPanel("CONTROLS") {
//                            VStack(spacing: 12) {
//                                ControlButton(label: "IGNITION", active: vm.isIgnitionOn, color: .red) { vm.toggleIgnition() } // Replaced .retroRed
//                                ControlButton(label: "STARTER", active: vm.isStarterOn, color: .orange) { vm.toggleStarter() } // Replaced .retroOrange
//                                ControlButton(label: "CLUTCH", active: vm.clutchPressed, color: .blue) { vm.toggleClutch() }
//                                
//                                Divider().background(Color.gray)
//                                
//                                HStack(spacing: 10) {
//                                    ShiftButton(label: "-", action: { vm.shiftDown() })
//                                    ShiftButton(label: "+", action: { vm.shiftUp() })
//                                }
//                            }
//                            .padding(.vertical, 10)
//                        }
//                        
//                        RetroPanel("DATA") {
//                            VStack(spacing: 8) {
//                                DataRow(label: "FUEL", value: String(format: "%.2f L", vm.fuelConsumed))
//                                DataRow(label: "DIST", value: String(format: "%.1f KM", vm.distanceTravelled))
//                                DataRow(label: "SPD", value: String(format: "%.0f KM/H", vm.vehicleSpeed))
//                            }
//                            .padding(.vertical, 5)
//                        }
//                        
//                        Spacer()
//                    }
//                    .frame(width: 180)
//                    
//                    // --- COLUMN 2: ENGINE VISUALIZATION (Center - LARGE) ---
//                    VStack(spacing: 8) {
//                        RetroPanel("ENGINE VISUALIZATION") {
//                            ZStack {
//                                Color.black
//                                Engine3DView(rpm: vm.rpm)
//                            }
//                            .frame(maxWidth: .infinity, maxHeight: .infinity)
//                        }
//                        
//                        RetroPanel("THROTTLE") {
//                            HStack {
//                                Text("IDLE").modifier(RetroFont(size: 10)).foregroundColor(.gray)
//                                Slider(value: $vm.throttlePosition, in: 0...1)
//                                    .accentColor(.orange)
//                                Text("WOT").modifier(RetroFont(size: 10)).foregroundColor(.red)
//                            }
//                            .frame(height: 30)
//                        }
//                    }
//                    .frame(maxWidth: .infinity) // Takes remaining space
//                    
//                    // --- COLUMN 3: INSTRUMENTS (Right) ---
//                    VStack(spacing: 8) {
//                        RetroPanel("TACHOMETER") {
//                            BigNeedleGauge(rpm: vm.rpm, maxRPM: vm.redline)
//                                .frame(height: 200)
//                        }
//                        
//                        RetroPanel("GEAR") {
//                            Text(vm.gear == -1 ? "N" : "\(vm.gear + 1)")
//                                .font(.system(size: 90, weight: .black, design: .rounded))
//                                .foregroundColor(vm.gear == -1 ? .green : .orange)
//                                .frame(maxWidth: .infinity)
//                                .frame(height: 100)
//                        }
//                        
//                        // Replaced "Status" with this Graph
//                        RetroPanel("EXHAUST FLOW") {
//                            ScrollingGraphView()
//                                .frame(height: 80)
//                        }
//                        
//                        Spacer()
//                    }
//                    .frame(width: 220)
//                }
//                .padding(.horizontal)
//                .padding(.bottom)
//            }
//        }
//    }
//}
//
//// MARK: - 4. Helper Views
//
//struct ControlButton: View {
//    var label: String
//    var active: Bool
//    var color: Color
//    var action: () -> Void
//    
//    var body: some View {
//        Button(action: action) {
//            HStack {
//                Text(label).modifier(RetroFont(size: 12))
//                Spacer()
//                Circle()
//                    .fill(active ? color : Color.black)
//                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
//                    .frame(width: 12, height: 12)
//            }
//            .padding(12)
//            .background(Color.white.opacity(active ? 0.15 : 0.05))
//            .border(active ? color : Color.gray.opacity(0.3), width: 1)
//        }
//        .buttonStyle(.plain)
//    }
//}
//
//struct ShiftButton: View {
//    var label: String
//    var action: () -> Void
//    
//    var body: some View {
//        Button(action: action) {
//            Text(label)
//                .font(.system(size: 24, weight: .bold))
//                .frame(maxWidth: .infinity)
//                .frame(height: 40)
//                .background(Color.white.opacity(0.1))
//                .border(Color.white.opacity(0.3), width: 1)
//        }
//        .buttonStyle(.plain)
//    }
//}
//
//struct DataRow: View {
//    var label: String
//    var value: String
//    
//    var body: some View {
//        HStack {
//            Text(label).modifier(RetroFont(size: 12)).foregroundColor(.gray)
//            Spacer()
//            Text(value).modifier(RetroFont(size: 12)).foregroundColor(.orange) // Replaced .retroOrange
//        }
//        .padding(.horizontal, 4)
//        Divider().background(Color.gray.opacity(0.3))
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

// MARK: - STYLES & FONTS
struct RetroFont: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight = .bold
    
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .monospaced))
    }
}

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
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white)
                Spacer()
            }
            .background(Color.white.opacity(0.1))
            
            // Content
            ZStack {
                Color.black
                content
                    .padding(8)
            }
        }
        .border(Color.white.opacity(0.3), width: 1)
    }
}

// MARK: - 1. ViewModel (Updated)
class EngineInterface: ObservableObject {
    private var engine: EngineWrapper?
    private var timer: Timer?
    
    // Live Data
    @Published var rpm: Double = 0.0
    @Published var gear: Int = 0 // 0=Neutral, -1=Reverse, 1-6=Gears
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
        self.startPolling()
    }
    
    func startPolling() {
        timer = Timer.scheduledTimer(timeInterval: 1.0/60.0, target: self, selector: #selector(update), userInfo: nil, repeats: true)
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    @objc func update() {
        guard let engine = engine else { return }
        self.rpm = engine.getRPM()
        self.gear = Int(engine.getGear()) // Assuming C++ returns -1 for R, 0 for N, 1-6
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
    
    // New function to support H-Shifter
    func setGear(_ newGear: Int) {
        engine?.setGear(Int32(newGear))
        // Manually update local state for instant UI feedback
        self.gear = newGear
    }
    
    // Keep these for legacy compatibility if needed
    func shiftUp() { engine?.shiftUp() }
    func shiftDown() { engine?.shiftDown() }
    func resetStats() {
        engine?.resetTravelledDistance()
        engine?.resetFuelConsumption()
    }
}

// MARK: - 2. UI Components

// 2.1 Universal Gauge (Speed & RPM)
struct UniversalGauge: View {
    var value: Double
    var maxValue: Double
    var label: String
    var units: String
    var color: Color
    var isRPM: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background ticks
                ForEach(0..<41) { tick in
                    let isMajor = tick % 5 == 0
                    let fraction = Double(tick) / 40.0
                    let angle = -225 + (fraction * 270) // 270 degree sweep
                    
                    Rectangle()
                        .fill(isMajor ? Color.white : Color.gray.opacity(0.5))
                        .frame(width: isMajor ? 2 : 1, height: isMajor ? 10 : 5)
                        .offset(y: -(geo.size.height / 2) + 10)
                        .rotationEffect(.degrees(angle))
                }
                
                // Redline zone (only for RPM)
                if isRPM {
                    TrimmedCircle(start: 0.85, end: 1.0)
                        .stroke(Color.red.opacity(0.5), lineWidth: 8)
                        .rotationEffect(.degrees(135)) // Align with end of sweep
                        .padding(20)
                }
                
                // Value Text
                VStack(spacing: 0) {
                    Text("\(Int(value))")
                        .modifier(RetroFont(size: 24, weight: .black))
                        .foregroundColor(.white)
                    Text(units)
                        .modifier(RetroFont(size: 10))
                        .foregroundColor(color)
                }
                .offset(y: 20)
                
                // Needle
                Rectangle()
                    .fill(color)
                    .frame(width: 3, height: geo.size.height / 2 - 15)
                    .cornerRadius(1.5)
                    .offset(y: -(geo.size.height / 4) + 7)
                    .rotationEffect(.degrees(-225 + (270 * min(value / maxValue, 1.05))))
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: value)
                
                // Center Cap
                Circle()
                    .fill(Color.black)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                
                // Label
                Text(label)
                    .modifier(RetroFont(size: 10))
                    .foregroundColor(.gray)
                    .position(x: geo.size.width / 2, y: geo.size.height - 20)
            }
        }
    }
}

struct TrimmedCircle: Shape {
    var start: CGFloat
    var end: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                 radius: rect.width / 2,
                 startAngle: .degrees(-225 + (Double(start) * 270)),
                 endAngle: .degrees(-225 + (Double(end) * 270)),
                 clockwise: false)
        return p
    }
}

// 2.2 H-Pattern Shifter
struct HPatternShifter: View {
    @Binding var currentGear: Int // -1 = R, 0 = N, 1-6
    var action: (Int) -> Void
    
    let gridItems = [
        GridItem(.flexible()), // Col 1: R / 2
        GridItem(.flexible()), // Col 2: 1 / 3
        GridItem(.flexible()), // Col 3: 3 / 4
        GridItem(.flexible())  // Col 4: 5 / 6
    ]
    
    var body: some View {
        ZStack {
            // The "Gate" Lines
            HStack(spacing: 0) {
                Divider().background(Color.white.opacity(0.2))
                Spacer()
                Divider().background(Color.white.opacity(0.2))
                Spacer()
                Divider().background(Color.white.opacity(0.2))
                Spacer()
                Divider().background(Color.white.opacity(0.2))
            }
            .frame(height: 50)
            .padding(.horizontal, 25)
            
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1)
            
            // The Knobs
            VStack(spacing: 20) {
                // Top Row: R, 1, 3, 5
                HStack(spacing: 15) {
                    GearButton(label: "R", gearIdx: -1, current: currentGear, action: action)
                    GearButton(label: "1", gearIdx: 1, current: currentGear, action: action)
                    GearButton(label: "3", gearIdx: 3, current: currentGear, action: action)
                    GearButton(label: "5", gearIdx: 5, current: currentGear, action: action)
                }
                
                // Bottom Row: -, 2, 4, 6
                HStack(spacing: 15) {
                    // Spacer for Reverse lockout area
                    Circle().fill(Color.clear).frame(width: 35, height: 35)
                    GearButton(label: "2", gearIdx: 2, current: currentGear, action: action)
                    GearButton(label: "4", gearIdx: 4, current: currentGear, action: action)
                    GearButton(label: "6", gearIdx: 6, current: currentGear, action: action)
                }
            }
        }
        .padding(10)
    }
}

struct GearButton: View {
    var label: String
    var gearIdx: Int
    var current: Int
    var action: (Int) -> Void
    
    var isActive: Bool { current == gearIdx }
    
    var body: some View {
        Button(action: {
            // Toggle Neutral if clicking active gear, else set gear
            if isActive { action(0) } else { action(gearIdx) }
        }) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.orange : Color.black)
                    .overlay(Circle().stroke(isActive ? Color.white : Color.gray, lineWidth: 1))
                
                Text(label)
                    .modifier(RetroFont(size: 14))
                    .foregroundColor(isActive ? .black : .white)
            }
            .frame(width: 35, height: 35)
        }
        .buttonStyle(.plain)
    }
}

// 2.3 Slim Throttle Bar
struct TechThrottle: View {
    @Binding var value: Double
    
    var body: some View {
        HStack(spacing: 10) {
            Text("THR").modifier(RetroFont(size: 10)).foregroundColor(.gray)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                    
                    // Fill
                    Rectangle()
                        .fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(value))
                        .animation(.linear(duration: 0.05), value: value)
                    
                    // Ticks
                    HStack(spacing: 0) {
                        ForEach(0..<10) { _ in
                            Spacer()
                            Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1)
                        }
                    }
                }
            }
            .frame(height: 12)
            .overlay(Rectangle().stroke(Color.gray, lineWidth: 1))
            // Invisible slider for touch interaction
            .overlay(
                GeometryReader { geo in
                    Color.white.opacity(0.001)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    let percentage = min(max(0, val.location.x / geo.size.width), 1)
                                    value = Double(percentage)
                                }
                        )
                }
            )
            
            Text("\(Int(value * 100))%").modifier(RetroFont(size: 10)).foregroundColor(.orange).frame(width: 30)
        }
    }
}

// MARK: - 3. Main Layout
struct ContentView: View {
    @StateObject var vm = EngineInterface()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // MARK: Top Bar
                HStack {
                    Text("ENGINE CONTROLLER")
                        .modifier(RetroFont(size: 16))
                        .foregroundColor(.white)
                    Spacer()
                    Text("BUILD V0.3 // A.G.")
                        .modifier(RetroFont(size: 10))
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .border(Color.white.opacity(0.1), width: 1, edges: [.bottom])
                
                HStack(alignment: .top, spacing: 10) {
                    
                    // MARK: LEFT COL - Controls
                    VStack(spacing: 10) {
                        RetroPanel("SYSTEM") {
                            VStack(spacing: 8) {
                                ControlButton(label: "IGNITION", active: vm.isIgnitionOn, color: .red) { vm.toggleIgnition() }
                                ControlButton(label: "STARTER", active: vm.isStarterOn, color: .orange) { vm.toggleStarter() }
                                ControlButton(label: "CLUTCH", active: vm.clutchPressed, color: .blue) { vm.toggleClutch() }
                            }
                        }
                        
                        RetroPanel("TRANSMISSION") {
                            VStack {
                                HPatternShifter(currentGear: $vm.gear) { newGear in
                                    vm.setGear(newGear)
                                }
                                Text(vm.gear == 0 ? "NEUTRAL" : (vm.gear == -1 ? "REVERSE" : "GEAR \(vm.gear)"))
                                    .modifier(RetroFont(size: 10))
                                    .foregroundColor(vm.gear == 0 ? .green : .orange)
                            }
                        }
                        
                        Spacer()
                    }
                    .frame(width: 220)
                    
                    // MARK: CENTER COL - Viewport
                    VStack(spacing: 10) {
                        RetroPanel("VISUALIZATION") {
                            Engine3DView(rpm: vm.rpm, throttlePosition: vm.throttlePosition)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black)
                        }
                        
                        RetroPanel("INPUT") {
                            TechThrottle(value: $vm.throttlePosition)
                                .padding(.horizontal, 4)
                        }
                        .frame(height: 40)
                    }
                    
                    // MARK: RIGHT COL - Instruments
                    VStack(spacing: 10) {
                        RetroPanel("TACHOMETER") {
                            UniversalGauge(
                                value: vm.rpm,
                                maxValue: vm.redline,
                                label: "X1000 RPM",
                                units: "",
                                color: .red,
                                isRPM: true
                            )
                            .frame(height: 150)
                        }
                        
                        RetroPanel("SPEEDOMETER") {
                            // Convert m/s to km/h (approx * 3.6)
                            UniversalGauge(
                                value: vm.vehicleSpeed * 3.6,
                                maxValue: 260.0,
                                label: "VELOCITY",
                                units: "KM/H",
                                color: .orange
                            )
                            .frame(height: 150)
                        }
                        
                        RetroPanel("TELEMETRY") {
                            VStack(spacing: 6) {
                                DataRow(label: "FUEL", value: String(format: "%.2f L", vm.fuelConsumed))
                                DataRow(label: "DIST", value: String(format: "%.1f KM", vm.distanceTravelled))
                            }
                        }
                        
                        Spacer()
                    }
                    .frame(width: 200)
                }
                .padding(10)
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
                    .foregroundColor(active ? .white : .gray) // Better contrast
                Spacer()
                
                // Status Light
                Circle()
                    .fill(active ? color : Color.black)
                    .overlay(Circle().stroke(active ? color : Color.gray, lineWidth: 1))
                    .shadow(color: active ? color.opacity(0.8) : .clear, radius: 4)
                    .frame(width: 10, height: 10)
            }
            .padding(12)
            .background(Color.white.opacity(active ? 0.15 : 0.05)) // Visible background when off
            .border(active ? color : Color.white.opacity(0.2), width: 1) // Visible border when off
        }
        .buttonStyle(.plain)
    }
}

struct DataRow: View {
    var label: String
    var value: String
    
    var body: some View {
        HStack {
            Text(label).modifier(RetroFont(size: 10)).foregroundColor(.gray)
            Spacer()
            Text(value).modifier(RetroFont(size: 10)).foregroundColor(.white)
        }
        .padding(.horizontal, 4)
        Divider().background(Color.gray.opacity(0.3))
    }
}

// Extension to allow specific border edges
extension View {
    func border(_ color: Color, width: CGFloat, edges: [Edge]) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX - width
                }
            }
            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY - width
                }
            }
            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return width
                }
            }
            var h: CGFloat {
                switch edge {
                case .top, .bottom: return width
                case .leading, .trailing: return rect.height
                }
            }
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 900, height: 600)
    }
}
