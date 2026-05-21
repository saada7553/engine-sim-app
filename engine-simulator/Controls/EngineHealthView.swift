//
//  EngineHealthView.swift
//  engine-simulator
//
//  Diagnostic tile for the Tier-3 thermal + damage simulation. Single-screen
//  dense readout — no taps, no popovers. Everything fits at once: live
//  temperatures, pump states, the full per-cylinder × per-component health
//  matrix, and engine-wide component bars.
//
//  Design language matches the rest of the dashboard: appBackground,
//  hairline white-opacity borders, retro monospaced numerics, orange accent.
//

import SwiftUI

// MARK: - Layout / palette

private let tilePadding: CGFloat = 10
private let sectionSpacing: CGFloat = 7
private let sectionInnerSpacing: CGFloat = 4
private let cardCorner: CGFloat = 3
private let borderColor = Color.white.opacity(0.12)
private let subtleBorder = Color.white.opacity(0.08)
private let panelFill = Color.white.opacity(0.03)
private let mutedText = Color.white.opacity(0.45)
private let dimText = Color.white.opacity(0.65)

private let warningColor = Color.orange
private let criticalColor = Color.red
private let healthyColor = Color.green
private let coldColor = Color(red: 0.40, green: 0.55, blue: 0.75)

private let coolantWarnC: Double = 105
private let coolantCriticalC: Double = 115
private let oilWarnC: Double = 105
private let oilCriticalC: Double = 120
private let oilPsiCriticalLow: Double = 15
private let oilPsiWarnLow: Double = 25

// Per-cylinder cell color thresholds (wall temperature)
private let cellTempCool: Double = 90
private let cellTempWarn: Double = 110
private let cellTempCritical: Double = 130

// MARK: - View

struct EngineHealthView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            header
            temperaturesAndPumps
            cylinderMatrix
            engineWideBars
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

    // MARK: Temperatures + pumps (combined horizontal panel)

    private var temperaturesAndPumps: some View {
        VStack(alignment: .leading, spacing: sectionInnerSpacing) {
            Text("THERMALS")
                .modifier(RetroFont(size: 9))
                .tracking(1.0)
                .foregroundColor(mutedText)
            HStack(spacing: 8) {
                tempCard(label: "COOLANT",
                         value: vm.coolantTempC, unit: "°C",
                         range: 0...140,
                         warn: coolantWarnC, critical: coolantCriticalC,
                         lowIsBad: false)
                tempCard(label: "OIL",
                         value: vm.oilTempC, unit: "°C",
                         range: 0...150,
                         warn: oilWarnC, critical: oilCriticalC,
                         lowIsBad: false)
                tempCard(label: "OIL PSI",
                         value: vm.oilPressurePsi, unit: " psi",
                         range: 0...80,
                         warn: oilPsiWarnLow, critical: oilPsiCriticalLow,
                         lowIsBad: true)
            }
            HStack(spacing: 8) {
                pumpButton(label: "COOLANT PUMP", on: vm.coolantPumpOn) {
                    vm.toggleCoolantPump()
                }
                pumpButton(label: "OIL PUMP", on: vm.oilPumpOn) {
                    vm.toggleOilPump()
                }
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

    private func tempCard(label: String,
                          value: Double,
                          unit: String,
                          range: ClosedRange<Double>,
                          warn: Double,
                          critical: Double,
                          lowIsBad: Bool) -> some View {
        let inWarn: Bool = lowIsBad ? (value < warn) : (value > warn)
        let inCrit: Bool = lowIsBad ? (value < critical) : (value > critical)
        let fillColor: Color = inCrit ? criticalColor
                              : inWarn ? warningColor
                              : healthyColor
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .modifier(RetroFont(size: 9))
                    .tracking(0.6)
                    .foregroundColor(mutedText)
                Spacer()
                Text(formatNumber(value, precision: 0) + unit)
                    .modifier(RetroFont(size: 10))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }
            HorizontalBar(value: value, range: range,
                          fillColor: fillColor,
                          tickMarks: [warn, critical])
        }
        .frame(maxWidth: .infinity)
    }

    private func pumpButton(label: String, on: Bool, action: @escaping () -> Void) -> some View {
        let stateColor: Color = on ? healthyColor : criticalColor
        return Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: stateColor.opacity(0.7), radius: on ? 2 : 3)
                Text(label)
                    .modifier(RetroFont(size: 9))
                    .tracking(0.6)
                    .foregroundColor(on ? .white : dimText)
                Spacer(minLength: 4)
                Text(on ? "ON" : "OFF")
                    .modifier(RetroFont(size: 9))
                    .foregroundColor(stateColor)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cardCorner)
                    .fill(on ? Color.white.opacity(0.04) : criticalColor.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCorner)
                    .stroke(on ? subtleBorder : criticalColor.opacity(0.45),
                            lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Cylinder matrix

    private var cylinderMatrix: some View {
        VStack(alignment: .leading, spacing: sectionInnerSpacing) {
            Text("PER-CYLINDER")
                .modifier(RetroFont(size: 9))
                .tracking(1.0)
                .foregroundColor(mutedText)

            CylinderMatrixView(healths: vm.cylinderHealths)
        }
        .padding(7)
        .background(panelFill)
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner)
                .stroke(borderColor, lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCorner))
    }

    // MARK: Engine-wide

    private var engineWideBars: some View {
        let wide = vm.engineWideHealth
        return VStack(alignment: .leading, spacing: sectionInnerSpacing) {
            Text("ENGINE-WIDE")
                .modifier(RetroFont(size: 9))
                .tracking(1.0)
                .foregroundColor(mutedText)
            engineRow("CYL HEAD",      wide.cylinderHead)
            engineRow("CAMSHAFT",      wide.camshaft)
            engineRow("CRANKSHAFT",    wide.crankshaft)
            engineRow("MAIN BEARING",  wide.mainBearing)
            engineRow("WATER PUMP",    wide.waterPump)
            engineRow("OIL PUMP",      wide.oilPump)
        }
        .padding(7)
        .background(panelFill)
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner)
                .stroke(borderColor, lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCorner))
    }

    private func engineRow(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .modifier(RetroFont(size: 9))
                .tracking(0.5)
                .foregroundColor(mutedText)
                .frame(width: 96, alignment: .leading)
            HealthBar(value: value)
            Text(formatPercent(value))
                .modifier(RetroFont(size: 9))
                .monospacedDigit()
                .foregroundColor(.white)
                .frame(width: 38, alignment: .trailing)
        }
    }

    // MARK: Helpers

    private var isDamaged: Bool {
        if vm.engineWideHealth.cylinderHead < 0.999 { return true }
        if vm.engineWideHealth.camshaft < 0.999 { return true }
        if vm.engineWideHealth.crankshaft < 0.999 { return true }
        if vm.engineWideHealth.mainBearing < 0.999 { return true }
        if vm.engineWideHealth.waterPump < 0.999 { return true }
        if vm.engineWideHealth.oilPump < 0.999 { return true }
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

// MARK: - Cylinder matrix view

/// Dense grid: rows = components, columns = cylinders, cells = health bars.
/// Plus a wall-temp row at the bottom for live diagnostic.
private struct CylinderMatrixView: View {
    let healths: [CylinderHealthState]

    private struct ComponentRow {
        let label: String
        let value: (CylinderHealthState) -> Double
    }

    private let rows: [ComponentRow] = [
        .init(label: "GASKET",  value: { $0.headGasket }),
        .init(label: "RINGS",   value: { $0.pistonRings }),
        .init(label: "PISTON",  value: { $0.piston }),
        .init(label: "ROD",     value: { $0.rod }),
        .init(label: "R.BRG",   value: { $0.rodBearing }),
        .init(label: "IN.VLV",  value: { $0.intakeValve }),
        .init(label: "EX.VLV",  value: { $0.exhaustValve }),
    ]

    var body: some View {
        let cylCount = healths.count
        if cylCount == 0 {
            Text("NO ENGINE LOADED")
                .modifier(RetroFont(size: 9))
                .foregroundColor(mutedText)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                // Column headers
                HStack(spacing: 0) {
                    Text("").frame(width: labelWidth, alignment: .leading)
                    ForEach(0..<cylCount, id: \.self) { i in
                        Text("C\(i + 1)")
                            .modifier(RetroFont(size: 8))
                            .foregroundColor(mutedText)
                            .frame(maxWidth: .infinity)
                    }
                }
                // Component rows
                ForEach(rows.indices, id: \.self) { rowIdx in
                    let row = rows[rowIdx]
                    HStack(spacing: 0) {
                        Text(row.label)
                            .modifier(RetroFont(size: 8))
                            .tracking(0.4)
                            .foregroundColor(mutedText)
                            .frame(width: labelWidth, alignment: .leading)
                        ForEach(0..<cylCount, id: \.self) { col in
                            MatrixCell(
                                value: row.value(healths[col]),
                                seized: healths[col].seized
                            )
                            .padding(.horizontal, 1)
                        }
                    }
                }
                // Wall temp row
                HStack(spacing: 0) {
                    Text("WALL")
                        .modifier(RetroFont(size: 8))
                        .tracking(0.4)
                        .foregroundColor(mutedText)
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(0..<cylCount, id: \.self) { col in
                        Text("\(Int(healths[col].wallTempC.rounded()))")
                            .modifier(RetroFont(size: 8))
                            .monospacedDigit()
                            .foregroundColor(wallTempColor(healths[col].wallTempC))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private let labelWidth: CGFloat = 52

    private func wallTempColor(_ c: Double) -> Color {
        if c >= cellTempCritical { return criticalColor }
        if c >= cellTempWarn { return warningColor }
        if c >= cellTempCool { return healthyColor.opacity(0.85) }
        return coldColor
    }
}

private struct MatrixCell: View {
    let value: Double  // 0..1 health
    let seized: Bool

    var body: some View {
        GeometryReader { geo in
            let v = max(0.0, min(1.0, value))
            let color = healthColorFor(v)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.black.opacity(0.35))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.85))
                    .frame(height: max(2, geo.size.height * CGFloat(v)))
                if seized {
                    RoundedRectangle(cornerRadius: 1.5)
                        .stroke(criticalColor, lineWidth: 1)
                }
            }
        }
        .frame(height: 14)
    }

    private func healthColorFor(_ v: Double) -> Color {
        if v < 0.30 { return criticalColor }
        if v < 0.70 { return warningColor }
        return healthyColor
    }
}

// MARK: - Reusable bars

private struct HorizontalBar: View {
    let value: Double
    let range: ClosedRange<Double>
    let fillColor: Color
    var tickMarks: [Double] = []

    var body: some View {
        GeometryReader { geo in
            let span = max(0.0001, range.upperBound - range.lowerBound)
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            let frac = (clamped - range.lowerBound) / span
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(fillColor.opacity(0.85))
                    .frame(width: max(2, geo.size.width * CGFloat(frac)))
                ForEach(tickMarks, id: \.self) { tick in
                    let tFrac = (tick - range.lowerBound) / span
                    let x = geo.size.width * CGFloat(tFrac)
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 1, height: geo.size.height + 2)
                        .offset(x: x - 0.5, y: -1)
                }
            }
        }
        .frame(height: 6)
    }
}

private struct HealthBar: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            let v = max(0.0, min(1.0, value))
            let color = healthBarColor(v)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.85))
                    .frame(width: max(2, geo.size.width * CGFloat(v)))
            }
        }
        .frame(height: 6)
    }
}

private func healthBarColor(_ v: Double) -> Color {
    if v < 0.30 { return criticalColor }
    if v < 0.70 { return warningColor }
    return healthyColor
}

// MARK: - Formatters

private func formatNumber(_ v: Double, precision: Int) -> String {
    String(format: "%.\(precision)f", v)
}
private func formatPercent(_ v: Double) -> String {
    let clamped = max(0.0, min(1.0, v))
    return "\(Int((clamped * 100.0).rounded()))%"
}
