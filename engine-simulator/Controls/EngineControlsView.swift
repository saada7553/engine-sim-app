//
//  EngineControlsView.swift
//  engine-simulator
//
//  Consolidated control surface: status indicators plus the system,
//  transmission and throttle controls in a single tile.
//

import SwiftUI

private let systemPanelHeight: CGFloat = 130
private let transmissionPanelHeight: CGFloat = 230
private let throttlePanelHeight: CGFloat = 200

struct EngineControlsView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                EngineStatusIndicators(vm: vm)

                RetroPanel("SYSTEM") {
                    SystemControlView(vm: vm)
                        .frame(height: systemPanelHeight)
                }

                RetroPanel("TRANSMISSION") {
                    GearShiftView(vm: vm)
                        .frame(height: transmissionPanelHeight)
                }

                RetroPanel("THROTTLE & CLUTCH") {
                    ThrottleView(vm: vm)
                        .frame(height: throttlePanelHeight)
                }
            }
            .padding(10)
        }
        .background(Color.appBackground)
    }
}

// MARK: - Status Indicators

struct EngineStatusIndicators: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        HStack(spacing: 6) {
            StatusIndicator(icon: "bolt.fill", label: "IGN", active: vm.isIgnitionOn)
            StatusIndicator(icon: "arrow.triangle.2.circlepath", label: "START", active: vm.isStarterOn)
            StatusIndicator(icon: "gearshape.2.fill", label: "CLUTCH", active: !vm.clutchPressed)
            StatusIndicator(icon: "chart.xyaxis.line", label: "DYNO", active: vm.dynoEnabled)
            StatusIndicator(icon: "lock.fill", label: "HOLD", active: vm.throttleHeld)
        }
    }
}

struct StatusIndicator: View {
    let icon: String
    let label: String
    let active: Bool

    private var tint: Color { active ? .orange : Color(white: 0.35) }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(tint)
                .shadow(color: active ? Color.orange.opacity(0.7) : .clear, radius: 4)
            Text(label)
                .modifier(RetroFont(size: 7))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(active ? 0.1 : 0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(tint.opacity(active ? 0.6 : 0.2), lineWidth: 1)
        )
        .cornerRadius(4)
    }
}
