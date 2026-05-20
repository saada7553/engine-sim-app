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
private let transmissionPanelWeight: CGFloat = 230
private let throttlePanelWeight: CGFloat = 200

struct EngineControlsView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let totalWeight = transmissionPanelWeight + throttlePanelWeight
                let spacing: CGFloat = 10
                let usableHeight = max(geo.size.height - 1 * spacing, 0)

                VStack(spacing: spacing) {
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


