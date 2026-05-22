//
//  EngineHealthView.swift
//  engine-simulator
//
//  Diagnostic tile for the Tier-3 thermal + damage simulation. Two stacked
//  sections:
//
//    1. Thermals — three UniversalGauge dials (coolant temp, oil temp, oil
//       pressure) over a single dash-control strip that groups the coolant
//       pump, oil pump and the repair control together.
//    2. Damage — a per-cylinder component heat-map (DamageMatrixView). Hidden
//       on iPhone where there isn't room; shown on iPad and macOS.
//
//  The whole tile scales off the available space: a `scale` factor derived
//  from the tile width drives every padding / font / control dimension so
//  nothing is pinned to a fixed point size, and the gauge row + damage grid
//  flex to share the available height.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Layout metrics (base values scaled by `scale`)

private let referenceWidth: CGFloat = 380
#if os(macOS)
private let minScale: CGFloat = 0.7
#else
private let minScale: CGFloat = 0.50
#endif
private let maxScale: CGFloat = 1.25

private let tilePaddingBase: CGFloat = 12
private let sectionSpacingBase: CGFloat = 8
private let panelSpacingBase: CGFloat = 6
private let gaugeSpacingBase: CGFloat = 12
private let controlSpacingBase: CGFloat = 16
private let controlCaptionGapBase: CGFloat = 3

private let titleFontBase: CGFloat = Theme.FontSize.callout
private let sectionLabelFontBase: CGFloat = Theme.FontSize.footnote
private let captionFontBase: CGFloat = Theme.FontSize.caption

#if os(macOS)
private let switchWidthBase: CGFloat = 46
private let switchHeightBase: CGFloat = 44
#else
private let switchWidthBase: CGFloat = 36
private let switchHeightBase: CGFloat = 32
#endif

private let titleFontMin: CGFloat = 9
private let sectionLabelFontMin: CGFloat = 8
private let captionFontMin: CGFloat = 7

// Share of the tile height the gauge row may claim. Lower when the damage
// grid is present so both sections fit; higher on iPhone where thermals own
// the whole tile.
private let gaugeHeightFractionWithDamage: CGFloat = 0.30
private let gaugeHeightFractionThermalsOnly: CGFloat = 0.55
private let gaugeHeightMin: CGFloat = 78

private let cardCorner: CGFloat = Theme.Radius.small
private let mutedText = Color.textMuted
private let pumpAccent = Color.accentOk
private let repairAccent = Color.accentLive

private let pristineThreshold: Double = 0.999

// Repair control face metrics, expressed as fractions of the switch height so
// the glyph + sub-label track the rocker switches beside it.
private let repairIconHeightRatio: CGFloat = 0.34
private let repairSubFontRatio: CGFloat = 0.17
private let repairLedSize: CGFloat = 4
private let repairFacePadding: CGFloat = 3

// MARK: - View

struct EngineHealthView: View {
    @ObservedObject var vm: EngineViewModel

    private var showsDamageSection: Bool {
        #if os(macOS)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(max(geo.size.width / referenceWidth, minScale), maxScale)
            let gaugeFraction = showsDamageSection
                ? gaugeHeightFractionWithDamage
                : gaugeHeightFractionThermalsOnly
            let gaugeHeight = max(gaugeHeightMin, geo.size.height * gaugeFraction)

            VStack(alignment: .leading, spacing: sectionSpacingBase * scale) {
                header(scale: scale)
                thermalsSection(scale: scale, gaugeHeight: gaugeHeight)
                if showsDamageSection {
                    damageSection(scale: scale)
                }
            }
            .padding(tilePaddingBase * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.appBackground)
        }
    }

    // MARK: Header

    private func header(scale: CGFloat) -> some View {
        Text("ENGINE HEALTH")
            .modifier(RetroFont(size: max(titleFontMin, titleFontBase * scale)))
            .tracking(1.0)
            .foregroundColor(.white)
    }

    private func sectionLabel(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .modifier(RetroFont(size: max(sectionLabelFontMin, sectionLabelFontBase * scale)))
            .tracking(1.0)
            .foregroundColor(mutedText)
    }

    // MARK: Thermals

    private func thermalsSection(scale: CGFloat, gaugeHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: panelSpacingBase * scale) {
            if showsDamageSection {
                sectionLabel("THERMALS", scale: scale)
            }

            HStack(alignment: .center, spacing: gaugeSpacingBase * scale) {
                gauge(GaugePresets.coolantTemp(), \.coolantTempC)
                gauge(GaugePresets.oilTemp(), \.oilTempC)
                gauge(GaugePresets.oilPressure(), \.oilPressurePsi)

                controlColumn(scale: scale)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: gaugeHeight)
        }
        .padding(panelSpacingBase * scale)
        .clipShape(RoundedRectangle(cornerRadius: cardCorner))
    }

    private func gauge(_ config: GaugeConfiguration,
                       _ keyPath: KeyPath<EngineViewModel, Double>) -> some View {
        UniversalGauge(engineVm: vm, config: config, valueKeyPath: keyPath)
            .frame(maxWidth: .infinity)
    }

    // MARK: Control column — pumps + repair grouped together

    private func controlColumn(scale: CGFloat) -> some View {
        let switchWidth = switchWidthBase * scale
        let switchHeight = switchHeightBase * scale

        return VStack(spacing: panelSpacingBase * scale) {
            pumpControl(caption: "COOLANT PUMP",
                        isOn: vm.coolantPumpOn,
                        width: switchWidth, height: switchHeight, scale: scale,
                        toggle: { vm.toggleCoolantPump() })
            pumpControl(caption: "OIL PUMP",
                        isOn: vm.oilPumpOn,
                        width: switchWidth, height: switchHeight, scale: scale,
                        toggle: { vm.toggleOilPump() })
            repairControl(width: switchWidth, height: switchHeight, scale: scale)
        }
    }

    private func pumpControl(caption: String,
                             isOn: Bool,
                             width: CGFloat, height: CGFloat, scale: CGFloat,
                             toggle: @escaping () -> Void) -> some View {
        VStack(spacing: controlCaptionGapBase * scale) {
            DashRockerSwitch(topLabel: "ON",
                             bottomLabel: "OFF",
                             isOn: isOn,
                             accent: pumpAccent,
                             width: width,
                             height: height,
                             toggle: toggle)
            controlCaption(caption, scale: scale)
        }
    }

    /// Repair shares the dash-switch chrome but is momentary: pressing it once
    /// restores every component. Lit orange + actionable while the engine is
    /// damaged; dim green "OK" when nothing needs fixing.
    private func repairControl(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        let active = isDamaged
        let accent = active ? repairAccent : pumpAccent

        return VStack(spacing: controlCaptionGapBase * scale) {
            Button(action: { if active { vm.repairEngine() } }) {
                ZStack {
                    DashBezel(cornerRadius: dashBezelCorner)
                    VStack(spacing: 0) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: height * repairIconHeightRatio, weight: .bold))
                            .foregroundColor(active ? accent : .white.opacity(0.30))
                            .shadow(color: active ? accent.opacity(0.6) : .clear, radius: 3)
                            .frame(maxHeight: .infinity)
                        Text(active ? "FIX" : "OK")
                            .modifier(RetroFont(size: height * repairSubFontRatio))
                            .tracking(1.0)
                            .foregroundColor(active ? .white.opacity(0.85) : accent.opacity(0.7))
                            .frame(maxHeight: .infinity)
                        Circle()
                            .fill(accent.opacity(active ? 1.0 : 0.3))
                            .frame(width: repairLedSize, height: repairLedSize)
                            .shadow(color: active ? accent.opacity(0.9) : .clear, radius: 2.5)
                            .padding(.bottom, repairFacePadding)
                    }
                    .padding(.vertical, repairFacePadding)
                }
                .frame(width: width, height: height)
            }
            .buttonStyle(.plain)
            .disabled(!active)
            .animation(.easeInOut(duration: 0.18), value: active)
            .help(active ? "Restore all components to pristine" : "Engine is healthy")

            controlCaption("REPAIR", scale: scale)
        }
    }

    private func controlCaption(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .modifier(RetroFont(size: max(captionFontMin, captionFontBase * scale)))
            .tracking(0.6)
            .foregroundColor(mutedText)
            .lineLimit(1)
    }

    // MARK: Damage

    private func damageSection(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: panelSpacingBase * scale) {
            sectionLabel("DAMAGE", scale: scale)
            DamageMatrixView(cylinders: vm.cylinderHealths,
                             wide: vm.engineWideHealth,
                             scale: scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(panelSpacingBase * scale)
        .clipShape(RoundedRectangle(cornerRadius: cardCorner))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private var isDamaged: Bool {
        let wide = vm.engineWideHealth
        if wide.cylinderHead < pristineThreshold { return true }
        if wide.camshaft < pristineThreshold { return true }
        if wide.crankshaft < pristineThreshold { return true }
        if wide.mainBearing < pristineThreshold { return true }
        if wide.waterPump < pristineThreshold { return true }
        if wide.oilPump < pristineThreshold { return true }
        for c in vm.cylinderHealths {
            if c.seized { return true }
            if c.headGasket   < pristineThreshold { return true }
            if c.pistonRings  < pristineThreshold { return true }
            if c.piston       < pristineThreshold { return true }
            if c.rod          < pristineThreshold { return true }
            if c.rodBearing   < pristineThreshold { return true }
            if c.intakeValve  < pristineThreshold { return true }
            if c.exhaustValve < pristineThreshold { return true }
        }
        return false
    }
}
