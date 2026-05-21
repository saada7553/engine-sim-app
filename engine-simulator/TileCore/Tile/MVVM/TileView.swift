//
//  TileView.swift
//  TileSurf
//
//  Created by Saad Ata on 11/25/25.
//

import Foundation
import SwiftUI

struct TileView: View {
    @ObservedObject var tile: TileViewModel
    /// Observe the engine VM directly so `engineId` / `redline` / config
    /// changes propagate to `body`. `@ObservedObject` on a nested class
    /// property inside `TileViewModel` doesn't republish through
    /// `TileViewModel.objectWillChange`, so without this an engine swap
    /// would not re-run `getView()` — the gauges would stay keyed to the
    /// old `engineResetId` and keep the previous engine's redline / bands.
    @ObservedObject var engineVm: EngineViewModel
    let isFocused: Bool
    let browserMode: BrowserMode
    let isHovered: Bool
    let hoverPosition: SplitDirection?
    let onTap: () -> Void
    let onDelete: () -> Void
    let onSplit: (SplitDirection, Bool) -> Void
    let onHover: (SplitDirection?) -> Void
    let onHoverEnd: () -> Void

    private let cornerRadius: CGFloat = 12
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.appBackground
                getView()
                if browserMode != .operational {
                    hoverModeView(geometry)
                }
            }
        }
        .toolbar(removing: .title)
        .ignoresSafeArea(edges: .top)
    }
    
    private func getView() -> some View {
        // Hard-reset hook: any view that should fully re-create when the user
        // picks a new engine gets `.id(engineResetId)`. Tied to the current
        // EngineLibrary selection so gauges drop their needle physics, the 3D
        // view rebuilds its assembly, etc. Reads from `engineVm` (the
        // @ObservedObject) so SwiftUI re-runs body — and recomputes this id
        // — when the engine swaps.
        let engineResetId = engineVm.engineId ?? UUID()

        switch tile.data.type {
        case .select:
            return AnyView(SelectView(tile: tile))
        // Both the legacy CAD-model 3D view and the new procedural view now
        // resolve to the procedural renderer. Old layouts saved with the
        // legacy type still load — they just get the new rendering.
        case .engine3DView, .engine3DProcedural:
            return AnyView(Engine3DProceduralView(vm: tile.engineVm).id(engineResetId))

        // Gauges
        case .speedometerGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.speedometer(),
                valueKeyPath: \.vehicleSpeed
            ).id(engineResetId))
        case .rpmGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.tachometer(redline: tile.engineVm.redline),
                valueKeyPath: \.rpm
            ).id(engineResetId))
        case .manifoldPressureGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.manifoldPressure(),
                valueKeyPath: \.manifoldPressure
            ).id(engineResetId))
        case .volumetricEfficiencyGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.volumetricEfficiency(),
                valueKeyPath: \.volumetricEfficiency
            ).id(engineResetId))
        case .airScfmGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.airScfm(),
                valueKeyPath: \.intakeFlowRate
            ).id(engineResetId))
        case .intakeAfrGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.intakeAfr(),
                valueKeyPath: \.intakeAFR
            ).id(engineResetId))
        case .exhaustO2Gauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.exhaustO2(),
                valueKeyPath: \.exhaustO2
            ).id(engineResetId))
        case .cylinderPressureGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.cylinderPressure(),
                valueKeyPath: \.cylinderPressure
            ).id(engineResetId))

        // Controls
        case .engineControls:
            return AnyView(EngineControlsView(vm: tile.engineVm))
        case .clutchIntake:
            return AnyView(ThrottleView(vm: tile.engineVm))
        case .clutchPanel:
            return AnyView(ClutchPanelView(vm: tile.engineVm))
        case .intakePanel:
            return AnyView(IntakePanelView(vm: tile.engineVm))
        case .ecuTuning:
            // EcuTuningView observes vm.ecu via its inner editor whose .id is
            // keyed to ObjectIdentifier(vm.ecu), so swaps are handled inside.
            return AnyView(EcuTuningView(vm: tile.engineVm).id(engineResetId))
        case .engineHealth:
            return AnyView(EngineHealthView(vm: tile.engineVm).id(engineResetId))
        case .obd2:
            return AnyView(OBD2View(vm: tile.engineVm).id(engineResetId))

        // Driver tools
        case .shiftLight:
            return AnyView(ShiftLightView(vm: tile.engineVm).id(engineResetId))
        case .zeroToSixtyTimer:
            return AnyView(ZeroToSixtyView(vm: tile.engineVm).id(engineResetId))
            
        // Oscilloscopes
        case .torqueOscilloscope:
            return AnyView(TorqueOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .powerOscilloscope:
            return AnyView(PowerOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .dynoOscilloscope:
            return AnyView(DynoOscilloscopeView(engineVm: tile.engineVm))
        case .sparkAdvanceOscilloscope:
            return AnyView(SparkAdvanceOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .totalExhaustFlowOscilloscope:
            return AnyView(TotalExhaustFlowOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .exhaustFlowOscilloscope:
            return AnyView(ExhaustFlowOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .intakeFlowOscilloscope:
            return AnyView(IntakeFlowOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .flowOscilloscope:
            return AnyView(FlowOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .exhaustValveLiftOscilloscope:
            return AnyView(ExhaustValveLiftOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .intakeValveLiftOscilloscope:
            return AnyView(IntakeValveLiftOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .valveLiftOscilloscope:
            return AnyView(ValveLiftOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .cylinderPressureOscilloscope:
            return AnyView(CylinderPressureOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .cylinderMoleculesOscilloscope:
            return AnyView(CylinderMoleculesOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .pvOscilloscope:
            return AnyView(PVOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        }
    }
    
    private var clippingRectangle: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
    
    private var focusedBorderView: some View {
        clippingRectangle
            .strokeBorder(LinearGradient.tileViewBorderGradient, lineWidth: 5)
    }
    
    func hoverModeView(_ geometry: GeometryProxy) -> some View {
        HoverDetectionView(
            mode: browserMode == .delete ? .delete : .split,
            geometry: geometry,
            isHovered: isHovered,
            hoverPosition: hoverPosition,
            onHover: onHover,
            onHoverEnd: onHoverEnd,
            onSplit: onSplit,
            onDelete: onDelete
        )
        .padding(4)
    }
}
