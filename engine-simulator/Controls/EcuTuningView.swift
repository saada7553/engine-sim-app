//
//  EcuTuningView.swift
//  engine-simulator
//
//  A high-fidelity ECU Tuning Tile featuring a live 2D ignition map
//  and tactile controls for ignition and fuel trim.
//

import SwiftUI

struct EcuTuningView: View {
    @ObservedObject var vm: EngineViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Live 2D Map Section
            RetroPanel("IGNITION ADVANCE MAP") {
                IgnitionMapView(points: vm.ignitionMap, currentRpm: vm.rpm, redline: vm.redline)
                    .frame(minHeight: 180)
            }
            .padding(.bottom, 10)
            
            // Interactive Controls Section
            HStack(spacing: 12) {
                RetroPanel("IGNITION OFFSET") {
                    TactileTuningDial(
                        value: $vm.ignitionOffset,
                        range: -20...20,
                        step: 0.5,
                        unit: "°",
                        label: "ADVANCE",
                        onChanged: { vm.setIgnitionOffset($0) }
                    )
                }
                
                RetroPanel("FUEL TRIM") {
                    TactileTuningDial(
                        value: $vm.fuelTrim,
                        range: 0.5...1.5,
                        step: 0.01,
                        unit: "x",
                        label: "GLOBAL",
                        onChanged: { vm.setFuelTrim($0) }
                    )
                }
            }
            .frame(height: 160)
            
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.appBackground)
    }
}

// MARK: - Ignition Map View

struct IgnitionMapView: View {
    let points: [ScopePoint]
    let currentRpm: Double
    let redline: Double
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background Grid
                MapGrid(rows: 5, cols: 8)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                
                // The Ignition Curve
                if points.count > 1 {
                    IgnitionCurve(points: points, redline: redline)
                        .stroke(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                        .shadow(color: .orange.opacity(0.3), radius: 4)
                }
                
                // Live RPM Indicator (Vertical Line)
                let xPos = CGFloat(currentRpm / redline) * geo.size.width
                if xPos >= 0 && xPos <= geo.size.width {
                    Rectangle()
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: 1)
                        .overlay(
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                                .shadow(color: .blue, radius: 4)
                            , alignment: .bottom
                        )
                        .offset(x: xPos - geo.size.width/2)
                }
            }
        }
    }
}

private struct MapGrid: Shape {
    let rows: Int
    let cols: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0...rows {
            let y = rect.height * CGFloat(i) / CGFloat(rows)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        for i in 0...cols {
            let x = rect.width * CGFloat(i) / CGFloat(cols)
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        return path
    }
}

private struct IgnitionCurve: Shape {
    let points: [ScopePoint]
    let redline: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }
        
        let sorted = points.sorted { $0.x < $1.x }
        let minY: Double = -10
        let maxY: Double = 60
        
        for (i, p) in sorted.enumerated() {
            let x = CGFloat(p.x / redline) * rect.width
            let normalizedY = (p.y - minY) / (maxY - minY)
            let y = rect.height * (1.0 - CGFloat(normalizedY))
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

// MARK: - Tactile Tuning Dial

struct TactileTuningDial: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let label: String
    let onChanged: (Double) -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var startValue: Double = 0
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Dial Base / Bezel
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.15), Color(white: 0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .frame(width: 80, height: 80)
                
                // Rotatable Knob
                KnobView(rotation: rotationForValue())
                    .frame(width: 60, height: 60)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                if dragOffset == 0 {
                                    startValue = value
                                    dragOffset = gesture.translation.height
                                }
                                let delta = -Double(gesture.translation.height - dragOffset) * 0.1
                                let newValue = (startValue + delta).clamped(to: range)
                                value = (newValue / step).rounded() * step
                                onChanged(value)
                            }
                            .onEnded { _ in
                                dragOffset = 0
                            }
                    )
            }
            
            VStack(spacing: 2) {
                Text(String(format: "%.2f%@", value, unit))
                    .modifier(RetroFont(size: 12))
                    .foregroundColor(.white)
                
                Text(label)
                    .modifier(RetroFont(size: 8))
                    .foregroundColor(.gray)
            }
        }
    }
    
    private func rotationForValue() -> Double {
        let pct = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return (pct * 270) - 135 // -135 to 135 degrees
    }
}

private struct KnobView: View {
    let rotation: Double
    
    var body: some View {
        ZStack {
            // Main knob body with brushed texture
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(white: 0.3), Color(white: 0.1),
                            Color(white: 0.3), Color(white: 0.1),
                            Color(white: 0.3)
                        ]),
                        center: .center
                    )
                )
                .shadow(color: .black.opacity(0.5), radius: 5, x: 0, y: 3)
            
            // Grip ridges
            Circle()
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                .padding(2)
            
            // Indicator dot
            Circle()
                .fill(Color.orange)
                .frame(width: 4, height: 4)
                .offset(y: -22)
                .rotationEffect(.degrees(rotation))
        }
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
