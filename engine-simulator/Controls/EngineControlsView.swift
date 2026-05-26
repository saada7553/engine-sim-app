//
//  EngineControlsView.swift
//  engine-simulator
//
//  Consolidated control surface. On macOS this is a clean 2×2 of the four
//  driver controls — transmission, brake, clutch, intake — with no individual
//  panel chrome wrapping each one; the gear readout and the slider labels name
//  them. On iOS only the gear gate lives here (the rest sit in their own tiles).
//

import SwiftUI

struct EngineControlsView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        #if os(macOS)
        MacControlsGrid(vm: vm)
            .padding(Theme.Space.md)
            .background(Color.appBackground)
        #else
        GearShiftView(vm: vm)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Theme.Space.lg)
            .background(Color.appBackground)
        #endif
    }
}

#if os(macOS)
/// Even 2×2 grid of the four controls, no per-cell bounding boxes. Each cell
/// fills its quadrant equally so nothing crowds anything else.
private struct MacControlsGrid: View {
    @ObservedObject var vm: EngineViewModel

    private let cellSpacing = Theme.Space.md

    var body: some View {
        VStack(spacing: cellSpacing) {
            HStack(spacing: cellSpacing) {
                cell { GearShiftView(vm: vm) }
                cell { BrakeView(vm: vm) }
            }
            HStack(spacing: cellSpacing) {
                cell { ClutchControl(vm: vm) }
                cell { IntakeControl(vm: vm) }
            }
        }
    }

    private func cell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Clutch cross-section over its precision pedal slider — no title or box, the
/// slider's "CLUTCH PEDAL" label identifies it.
private struct ClutchControl: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        VStack(spacing: 6) {
            ClutchPanelView(vm: vm)
            PrecisionClutchSlider(pressure: vm.clutchPressure, onChange: vm.setClutchPressure)
        }
    }
}

/// Intake manifold cross-section over the throttle slider.
private struct IntakeControl: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        VStack(spacing: 6) {
            IntakePanelView(vm: vm)
            PrecisionThrottleSlider(value: vm.throttleInput)
        }
    }
}
#endif
