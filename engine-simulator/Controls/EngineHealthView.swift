//
//  EngineHealthView.swift
//  engine-simulator
//
//  Diagnostic tile for the Tier-3 thermal + damage simulation. The
//  layout is two stacked sections:
//
//    1. Thermals row — three UniversalGauge dials (coolant, oil temp,
//       oil pressure) so the readouts match the gauges used everywhere
//       else in the app, plus dash-style rocker pump toggles under the
//       gauges that own the relevant pumps.
//    2. Engine schematic — a stylised cross-section view of the engine
//       block; cylinder bores tint by worst-component health, head /
//       cam / crank bars tint by their engine-wide values, and the
//       per-cylinder components are called out by hand-drawn icons on
//       either side of the block.
//
//  Design language matches the rest of the dashboard: appBackground,
//  hairline white-opacity borders, retro monospaced numerics, orange
//  accent for the REPAIR pill.
//

import SwiftUI

// MARK: - Layout / palette

private let tilePadding: CGFloat = 10
private let sectionSpacing: CGFloat = 7
private let cardCorner: CGFloat = 3
private let borderColor = Color.white.opacity(0.12)
private let panelFill = Color.white.opacity(0.03)
private let mutedText = Color.white.opacity(0.45)
private let pumpAccent = Color.green

private let pumpSwitchWidth: CGFloat = 46
private let pumpSwitchHeight: CGFloat = 40
private let pumpCaptionFontSize: CGFloat = 8
// Fixed height reserved beneath every gauge for the pump control. Columns
// without a pump (oil temp) keep an empty area of the same height so all
// three gauges stay the same size.
private let pumpAreaHeight: CGFloat = 58

// MARK: - View

struct EngineHealthView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            header
            thermalsSection
            schematicSection
        }
        .padding(tilePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.appBackground)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("ENGINE HEALTH")
                .modifier(RetroFont(size: 10))
                .tracking(1.0)
                .foregroundColor(.white)
            Spacer()
            repairButton
        }
    }

    private var repairButton: some View {
        Button(action: { vm.repairEngine() }) {
            Text("REPAIR")
                .modifier(RetroFont(size: 10))
                .tracking(0.8)
                .foregroundColor(isDamaged ? .black : mutedText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: cardCorner)
                        .fill(isDamaged ? Color.orange : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cardCorner)
                        .stroke(isDamaged
                                ? Color.orange.opacity(0.9)
                                : Color.white.opacity(0.15),
                                lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isDamaged)
        .help(isDamaged ? "Restore all components to pristine" : "Engine is healthy")
    }

    // MARK: Thermals

    private var thermalsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("THERMALS")
                .modifier(RetroFont(size: 9))
                .tracking(1.0)
                .foregroundColor(mutedText)
            HStack(alignment: .top, spacing: 12) {
                gaugeColumn(config: GaugePresets.coolantTemp(),
                            valueKeyPath: \.coolantTempC,
                            pumpCaption: "COOLANT PUMP",
                            pumpOn: vm.coolantPumpOn,
                            togglePump: { vm.toggleCoolantPump() })

                gaugeColumn(config: GaugePresets.oilTemp(),
                            valueKeyPath: \.oilTempC,
                            pumpCaption: nil,
                            pumpOn: nil,
                            togglePump: nil)

                gaugeColumn(config: GaugePresets.oilPressure(),
                            valueKeyPath: \.oilPressurePsi,
                            pumpCaption: "OIL PUMP",
                            pumpOn: vm.oilPumpOn,
                            togglePump: { vm.toggleOilPump() })
            }
        }
        .padding(7)
        .background(panelFill)
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner)
                .stroke(borderColor, lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCorner))
    }

    /// One thermals column: the shared app gauge with an optional pump
    /// rocker beneath it. Columns without a pump (oil temp) simply omit
    /// the rocker; the gauge above still aligns with its neighbours.
    private func gaugeColumn(config: GaugeConfiguration,
                             valueKeyPath: KeyPath<EngineViewModel, Double>,
                             pumpCaption: String?,
                             pumpOn: Bool?,
                             togglePump: (() -> Void)?) -> some View {
        VStack(spacing: 6) {
            UniversalGauge(engineVm: vm,
                           config: config,
                           valueKeyPath: valueKeyPath)
                .frame(maxWidth: .infinity)

            pumpArea(caption: pumpCaption, pumpOn: pumpOn, togglePump: togglePump)
        }
        .frame(maxWidth: .infinity)
    }

    /// Fixed-height region under each gauge. Renders a labelled rocker for
    /// columns that own a pump, or stays empty (but same height) for those
    /// that don't, so every gauge ends up the same size.
    private func pumpArea(caption: String?,
                          pumpOn: Bool?,
                          togglePump: (() -> Void)?) -> some View {
        VStack(spacing: 3) {
            if let pumpOn = pumpOn, let togglePump = togglePump, let caption = caption {
                DashRockerSwitch(topLabel: "ON",
                                 bottomLabel: "OFF",
                                 isOn: pumpOn,
                                 accent: pumpAccent,
                                 width: pumpSwitchWidth,
                                 height: pumpSwitchHeight,
                                 toggle: togglePump)
                Text(caption)
                    .modifier(RetroFont(size: pumpCaptionFontSize))
                    .tracking(0.6)
                    .foregroundColor(mutedText)
                    .lineLimit(1)
            }
        }
        .frame(height: pumpAreaHeight)
    }

    // MARK: Schematic

    private var schematicSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DAMAGE")
                .modifier(RetroFont(size: 9))
                .tracking(1.0)
                .foregroundColor(mutedText)
            EngineSchematicView(
                cylinders: vm.cylinderHealths,
                wide: vm.engineWideHealth,
                coolantPumpOn: vm.coolantPumpOn,
                oilPumpOn: vm.oilPumpOn
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(7)
        .background(panelFill)
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner)
                .stroke(borderColor, lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCorner))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private var isDamaged: Bool {
        let wide = vm.engineWideHealth
        if wide.cylinderHead < 0.999 { return true }
        if wide.camshaft < 0.999 { return true }
        if wide.crankshaft < 0.999 { return true }
        if wide.mainBearing < 0.999 { return true }
        if wide.waterPump < 0.999 { return true }
        if wide.oilPump < 0.999 { return true }
        for c in vm.cylinderHealths {
            if c.seized { return true }
            if c.headGasket   < 0.999 { return true }
            if c.pistonRings  < 0.999 { return true }
            if c.piston       < 0.999 { return true }
            if c.rod          < 0.999 { return true }
            if c.rodBearing   < 0.999 { return true }
            if c.intakeValve  < 0.999 { return true }
            if c.exhaustValve < 0.999 { return true }
        }
        return false
    }
}
