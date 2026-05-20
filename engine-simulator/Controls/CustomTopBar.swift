//
//  CustomTopBar.swift
//  engine-simulator
//
//  A custom top bar that replaces the native toolbar for engine controls and status.
//

import SwiftUI

struct CustomTopBar: View {
    @ObservedObject var vm: EngineViewModel
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Side: Sidebar + Tactile Physical Controls
            HStack(spacing: 24) {
                Button(action: { SidebarManager.shared.toggleSidebar() }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.05))
                                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
                .help("Toggle Sidebar")
                
                HStack(spacing: 30) {
                    // High-Fidelity Ignition Toggle
                    IgnitionToggleSystem(isOn: Binding(get: { vm.isIgnitionOn }, set: { _ in vm.toggleIgnition() }))
                    
                    // High-Fidelity Starter Button
                    TactileStarterButton(isPressed: vm.isStarterOn) {
                        vm.toggleStarter()
                    }
                }
            }
            .padding(.leading, 20)
            
            Spacer()
            
            // Center: Title + Check Engine Icon
            HStack(spacing: 12) {
                CheckEngineIcon()
                    .stroke(
                        LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5
                    )
                    .frame(width: 28, height: 28)
                    .shadow(color: .orange.opacity(0.5), radius: 6)
                
                VStack(alignment: .leading, spacing: -2) {
                    Text("ENGINE")
                        .modifier(RetroFont(size: 8))
                        .foregroundColor(.gray)
                    Text("SIMULATOR")
                        .modifier(RetroFont(size: 16))
                        .foregroundColor(.white)
                        .tracking(1)
                }
            }
            
            Spacer()
            
            // Right Side: Gauge Cluster Status Lights
            HStack(spacing: 12) {
                GaugeLight(label: "IGN", active: vm.isIgnitionOn, color: .red) {
                    IgnitionIcon()
                }
                
                GaugeLight(label: "START", active: vm.isStarterOn, color: .green) {
                    StarterIcon()
                }
                
                GaugeLight(label: "CLUTCH", active: !vm.clutchPressed, color: .blue) {
                    ClutchIcon()
                }
                
                GaugeLight(label: "DYNO", active: vm.dynoEnabled, color: .orange) {
                    DynoIcon()
                }
                
                GaugeLight(label: "HOLD", active: vm.throttleHeld, color: .yellow) {
                    HoldIcon()
                }
            }
            .padding(.trailing, 20)
        }
        .frame(height: 80)
        .background(
            ZStack {
                Color.appBackground
                // Subtle brushed metal texture effect
                LinearGradient(colors: [Color.white.opacity(0.03), Color.clear], startPoint: .top, endPoint: .bottom)
            }
        )
        .border(Color.white.opacity(0.15), width: 1, edges: [.bottom])
    }
}

// MARK: - High Fidelity Controls

struct IgnitionToggleSystem: View {
    @Binding var isOn: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            Text("IGNITION")
                .modifier(RetroFont(size: 8))
                .foregroundColor(.gray)
            
            Button(action: { isOn.toggle() }) {
                ZStack {
                    // Switch Housing
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(colors: [Color(white: 0.1), Color(white: 0.2)], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 2)
                    
                    // The Toggle Paddle
                    ZStack {
                        // Shadow for depth
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 14, height: 28)
                            .offset(y: isOn ? 2 : -2)
                        
                        // Paddle body
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Color(white: 0.35), Color(white: 0.15)],
                                    startPoint: isOn ? .bottom : .top,
                                    endPoint: isOn ? .top : .bottom
                                )
                            )
                            .frame(width: 14, height: 28)
                            .overlay(
                                // Metallic highlight
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(
                                        LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 1
                                    )
                            )
                        
                        // Pivot indicator
                        Circle()
                            .fill(isOn ? Color.orange : Color.gray.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .shadow(color: isOn ? .orange.opacity(0.8) : .clear, radius: 2)
                    }
                    .rotationEffect(.degrees(isOn ? 0 : 0)) // We simulate the flip with gradients and offsets
                    .offset(y: isOn ? 4 : -4)
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isOn)
        }
    }
}

struct TactileStarterButton: View {
    var isPressed: Bool
    var action: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            Text("ENGINE START")
                .modifier(RetroFont(size: 8))
                .foregroundColor(.gray)
            
            Button(action: action) {
                ZStack {
                    // Outer Bezel (Brushed Metal)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.4), Color(white: 0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(colors: [.white.opacity(0.5), .black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 1
                                )
                        )
                    
                    // Inset Shadow Ring
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 44, height: 44)
                    
                    // Button Surface
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    isPressed ? Color(red: 0.9, green: 0.1, blue: 0.1) : Color(red: 0.5, green: 0.05, blue: 0.05),
                                    Color(red: 0.2, green: 0, blue: 0)
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 22
                            )
                        )
                        .frame(width: 42, height: 42)
                        .overlay(
                            // Concentric texture lines
                            Circle()
                                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                                .padding(4)
                        )
                        .overlay(
                            // Inner Glow when pressed
                            Circle()
                                .stroke(isPressed ? Color.red.opacity(0.8) : Color.clear, lineWidth: 2)
                                .blur(radius: 2)
                        )
                    
                    // Labeling
                    VStack(spacing: -1) {
                        Text("START")
                            .font(.system(size: 9, weight: .black))
                        Text("STOP")
                            .font(.system(size: 7, weight: .bold))
                            .opacity(0.7)
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                }
                .shadow(color: isPressed ? .red.opacity(0.3) : .black.opacity(0.3), radius: isPressed ? 8 : 4, x: 0, y: isPressed ? 0 : 4)
            }
            .buttonStyle(.plain)
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .animation(.interactiveSpring(), value: isPressed)
        }
    }
}

// MARK: - Status Components

struct GaugeLight<Icon: Shape>: View {
    let label: String
    let active: Bool
    let color: Color
    let icon: Icon
    
    init(label: String, active: Bool, color: Color, @ViewBuilder icon: () -> Icon) {
        self.label = label
        self.active = active
        self.color = color
        self.icon = icon()
    }
    
    private var lightColor: Color {
        active ? color : color.opacity(0.15)
    }
    
    private var textColor: Color {
        active ? .white : .white.opacity(0.3)
    }
    
    var body: some View {
        VStack(spacing: 3) {
            icon
                .stroke(lightColor, lineWidth: 2.0)
                .background(icon.fill(lightColor.opacity(active ? 0.3 : 0.05)))
                .frame(width: 22, height: 22)
                .shadow(color: active ? color.opacity(0.6) : .clear, radius: 4)
            
            Text(label)
                .modifier(RetroFont(size: 7))
                .foregroundColor(textColor)
        }
        .frame(width: 44)
    }
}
