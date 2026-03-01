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
                Color.black
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
        switch tile.data.type {
        case .select:
            return AnyView(SelectView(tile: tile))
        case .engine3DView:
            return AnyView(Engine3DView(vm: tile.engineVm))

        // Gauges
        case .speedometerGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.speedometer(),
                valueKeyPath: \.vehicleSpeed
            ))
        case .rpmGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.tachometer(redline: tile.engineVm.redline),
                valueKeyPath: \.rpm
            ))
        case .manifoldPressureGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.manifoldPressure(),
                valueKeyPath: \.manifoldPressure
            ))
        case .volumetricEfficiencyGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.volumetricEfficiency(),
                valueKeyPath: \.volumetricEfficiency
            ))
        case .airScfmGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.airScfm(),
                valueKeyPath: \.intakeFlowRate
            ))
        case .intakeAfrGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.intakeAfr(),
                valueKeyPath: \.intakeAFR
            ))
        case .exhaustO2Gauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.exhaustO2(),
                valueKeyPath: \.exhaustO2
            ))
        case .cylinderPressureGauge:
            return AnyView(UniversalGauge(
                engineVm: tile.engineVm,
                config: GaugePresets.cylinderPressure(),
                valueKeyPath: \.cylinderPressure
            ))

        // Controls
        case .systemControls:
            return AnyView(SystemControlView(vm: tile.engineVm))
        case .transmissionControls:
            return AnyView(GearShiftView(vm: tile.engineVm))
        case .throttleControl:
            return AnyView(ThrottleView(vm: tile.engineVm))
            
        // Oscilloscopes
        case .torqueOscilloscope:
            return AnyView(TorqueOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .powerOscilloscope:
            return AnyView(PowerOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
        case .dynoOscilloscope:
            return AnyView(DynoOscilloscopeView(manager: tile.engineVm.oscilloscopeManager))
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
