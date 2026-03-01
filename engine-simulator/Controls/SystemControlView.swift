//
//  SystemControlView.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import SwiftUI

struct SystemControlView: View {
    @ObservedObject var vm: EngineViewModel
    
    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let availableHeight = geo.size.height
            let size = min(min(availableWidth / 2.5, availableHeight * 0.9), 120)
            
            HStack(spacing: 0) {
                Spacer()
                IgnitionSwitch(isOn: Binding(get: { vm.isIgnitionOn }, set: { _ in vm.toggleIgnition() }), size: size)
                    .frame(width: size, height: size)
                Spacer()
                StarterButton(isPressed: vm.isStarterOn, action: { vm.toggleStarter() }, size: size)
                    .frame(width: size, height: size)
                Spacer()
            }
            .frame(width: availableWidth, height: availableHeight)
        }
    }
}

struct StarterButton: View {
    var isPressed: Bool
    var action: () -> Void
    var size: CGFloat
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(size * 0.05)
                
                Circle()
                    .fill(RadialGradient(gradient: Gradient(colors: [isPressed ? Color.red : Color.red.opacity(0.8), Color(red: 0.3, green: 0, blue: 0)]), center: .center, startRadius: 5, endRadius: size / 2))
                    .padding(size * 0.12)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.4), lineWidth: 1)
                            .padding(size * 0.12)
                    )
                
                VStack(spacing: 0) {
                    Text("ENGINE").font(.system(size: size * 0.12, weight: .bold))
                    Text("START").font(.system(size: size * 0.12, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .white.opacity(isPressed ? 0.8 : 0), radius: 5)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
    }
}

struct IgnitionSwitch: View {
    @Binding var isOn: Bool
    var size: CGFloat
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            VStack(spacing: size * 0.1) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().stroke(Color(white: 0.3), lineWidth: 1))
                    
                    Rectangle()
                        .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
                        .frame(width: size * 0.18, height: size * 0.5)
                        .cornerRadius(size * 0.04)
                        .rotationEffect(.degrees(isOn ? 90 : 0))
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isOn)
                    
                    // Fixed labels - moved inwards
                    Text("OFF").font(.system(size: size * 0.09, weight: .bold)).foregroundColor(.gray).offset(y: -size * 0.28)
                    Text("ON").font(.system(size: size * 0.09, weight: .bold)).foregroundColor(isOn ? .orange : .gray).offset(x: size * 0.28)
                }
                .frame(width: size * 0.8, height: size * 0.8)
                
                Text("IGNITION")
                    .font(.system(size: size * 0.12, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
        .buttonStyle(.plain)
    }
}
