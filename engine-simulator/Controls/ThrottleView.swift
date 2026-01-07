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
        TechThrottle(value: $vm.throttlePosition)
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
