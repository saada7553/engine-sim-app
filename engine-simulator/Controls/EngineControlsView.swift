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
        VStack(spacing: Theme.Space.lg) {
            GeometryReader { geo in
                let totalWeight = transmissionPanelWeight + throttlePanelWeight
                let spacing: CGFloat = Theme.Space.lg
                let usableHeight = max(geo.size.height - 1 * spacing, 0)

                VStack(spacing: spacing) {
                    // On iOS the RetroPanel title bar is a heavy chrome that
                    // duplicates labels already present on the inner views.
                    // Strip it down to bare panels so the gauges/drawings
                    // get the room. iOS also drops the throttle/clutch
                    // drawings entirely — those live in their own
                    // `clutchIntake` tile so the Track layout can place
                    // them under the 3D viewer instead of stacked here.
                    #if os(macOS)
                    RetroPanel("TRANSMISSION") {
                        GearShiftView(vm: vm)
                    }
                    .frame(height: usableHeight * transmissionPanelWeight / totalWeight)

                    RetroPanel("THROTTLE & CLUTCH") {
                        ThrottleView(vm: vm)
                    }
                    .frame(height: usableHeight * throttlePanelWeight / totalWeight)
                    #else
                    GearShiftView(vm: vm)
                        .frame(maxHeight: .infinity)
                    #endif
                }
            }
        }
        .padding(Theme.Space.lg)
        .background(Color.appBackground)
    }
}


