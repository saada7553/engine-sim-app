//
//  UniversalGauge.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import SwiftUI

// 2.1 Universal Gauge (Speed & RPM)
struct UniversalGauge: View {
    @StateObject var engineVm: EngineViewModel
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
                    Text("\(Int(isRPM ? engineVm.rpm : engineVm.vehicleSpeed))")
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
                    .rotationEffect(.degrees(-225 + (270 * min(isRPM ? engineVm.rpm : engineVm.vehicleSpeed / maxValue, 1.05))))
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isRPM ? engineVm.rpm : engineVm.vehicleSpeed)
                
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
