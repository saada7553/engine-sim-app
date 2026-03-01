//
//  ThrottleView.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import SwiftUI

struct ThrottleView: View {
    @ObservedObject var vm: EngineViewModel
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("CLUTCH ASSEMBLY").modifier(RetroFont(size: 10)).foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal, 8)
                
                ClutchPlateVisualizer(isEngaged: !vm.clutchPressed)
                    .frame(height: 80)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(4)
                
                ClutchPedal(isPressed: Binding(get: { vm.clutchPressed }, set: { _ in vm.toggleClutch() }))
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            
            Divider().background(Color.white.opacity(0.1))
            
            VStack(spacing: 8) {
                HStack {
                    Text("INTAKE MANIFOLD").modifier(RetroFont(size: 10)).foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal, 8)
                
                ThrottleBodyVisualizer(openPercentage: vm.throttlePosition)
                    .frame(height: 80)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(4)
                
                PrecisionThrottleSlider(value: $vm.throttlePosition)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black.opacity(0.2))
        .border(Color.white.opacity(0.1), width: 1)
    }
}

struct ThrottleBodyVisualizer: View {
    var openPercentage: Double
    
    var body: some View {
        ZStack {
            HStack {
                Rectangle().fill(Color(white: 0.3)).frame(width: 4, height: 70)
                Spacer().frame(width: 60)
                Rectangle().fill(Color(white: 0.3)).frame(width: 4, height: 70)
            }
            
            let angle = 5.0 + (85.0 * openPercentage)
            
            Circle().fill(Color(white: 0.6)).frame(width: 6, height: 6)
            
            Rectangle()
                .fill(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                .frame(width: 58, height: 4)
                .rotationEffect(.degrees(angle))
                .animation(.linear(duration: 0.05), value: openPercentage)
            
            if openPercentage > 0.1 {
                VStack(spacing: 20) {
                    Image(systemName: "arrow.down")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 10)
                        .foregroundColor(.blue.opacity(openPercentage * 0.7))
                    
                    Image(systemName: "arrow.down")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 10)
                        .foregroundColor(.blue.opacity(openPercentage * 0.7))
                }
            }
        }
    }
}

struct ClutchPlateVisualizer: View {
    var isEngaged: Bool
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cy = h / 2
            let cx = w / 2
            
            ZStack {
                Path { p in
                    p.addRect(CGRect(x: 0, y: cy - 4, width: cx - 10, height: 8))
                    p.addRect(CGRect(x: cx + 10, y: cy - 4, width: w - (cx + 10), height: 8))
                }.fill(Color.gray)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [Color(white: 0.4), Color(white: 0.7), Color(white: 0.4)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 12, height: 60)
                    .position(x: cx - 6, y: cy)
                
                let gap: CGFloat = isEngaged ? 0 : 12
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [.orange, .orange.opacity(0.6), .orange], startPoint: .top, endPoint: .bottom))
                    .frame(width: 8, height: 50)
                    .position(x: cx + 4 + gap, y: cy)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isEngaged)
            }
        }
    }
}

struct ClutchPedal: View {
    @Binding var isPressed: Bool
    
    var body: some View {
        Button(action: { isPressed.toggle() }) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 40, height: 50)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .rotation3DEffect(.degrees(isPressed ? 25 : 0), axis: (x: 1, y: 0, z: 0))
                    
                    VStack(spacing: 5) {
                        ForEach(0..<5) { _ in Rectangle().fill(Color.black.opacity(0.5)).frame(width: 32, height: 2) }
                    }
                    .rotation3DEffect(.degrees(isPressed ? 25 : 0), axis: (x: 1, y: 0, z: 0))
                }
                Text(isPressed ? "DISENGAGED" : "ENGAGED")
                    .modifier(RetroFont(size: 8))
                    .foregroundColor(isPressed ? .orange : .orange.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }
}

struct PrecisionThrottleSlider: View {
    @Binding var value: Double
    private let height: CGFloat = 32
    private let handleWidth: CGFloat = 20
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("THROTTLE INPUT").modifier(RetroFont(size: 9)).foregroundColor(.gray)
                Spacer()
                Text(String(format: "%.0f%%", value * 100)).modifier(RetroFont(size: 9)).foregroundColor(.orange)
            }
            
            GeometryReader { geo in
                let width = geo.size.width - handleWidth
                let x = width * CGFloat(value)
                
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.05))
                    HStack(spacing: 0) {
                        ForEach(0..<11) { i in
                            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1)
                            if i != 10 { Spacer() }
                        }
                    }
                    .padding(.vertical, 8)
                    
                    Rectangle()
                        .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
                        .frame(width: handleWidth)
                        .overlay(Rectangle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .overlay(HStack(spacing: 2) { ForEach(0..<3) { _ in Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1, height: 12) } })
                        .offset(x: x)
                }
                .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    value = min(max(0, Double((v.location.x - handleWidth/2) / width)), 1)
                })
            }
            .frame(height: height)
        }
    }
}
