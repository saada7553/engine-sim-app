//
//  EngineControlsView.swift
//  engine-simulator
//
//  Consolidated control surface: status indicators plus the system,
//  transmission and throttle controls in a single tile.
//

import SwiftUI

// Vertical share of the remaining space (after the status row) given to each
// panel. Weights mirror the prior fixed heights (130 / 230 / 200) so the
// proportions stay familiar while the panels now resize with the tile.
private let systemPanelWeight: CGFloat = 130
private let transmissionPanelWeight: CGFloat = 230
private let throttlePanelWeight: CGFloat = 200

struct EngineControlsView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        VStack(spacing: 10) {
            EngineStatusIndicators(vm: vm)

            GeometryReader { geo in
                let totalWeight = systemPanelWeight + transmissionPanelWeight + throttlePanelWeight
                let spacing: CGFloat = 10
                let usableHeight = max(geo.size.height - 2 * spacing, 0)

                VStack(spacing: spacing) {
                    RetroPanel("SYSTEM") {
                        SystemControlView(vm: vm)
                    }
                    .frame(height: usableHeight * systemPanelWeight / totalWeight)

                    RetroPanel("TRANSMISSION") {
                        GearShiftView(vm: vm)
                    }
                    .frame(height: usableHeight * transmissionPanelWeight / totalWeight)

                    RetroPanel("THROTTLE & CLUTCH") {
                        ThrottleView(vm: vm)
                    }
                    .frame(height: usableHeight * throttlePanelWeight / totalWeight)
                }
            }
        }
        .padding(10)
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
