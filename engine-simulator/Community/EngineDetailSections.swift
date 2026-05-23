//
//  EngineDetailSections.swift
//  engine-simulator
//
//  Read-only detail sections for a community engine: the full spec sheet and a
//  non-interactive preview of the saved ECU tune (ignition + fuel heatmaps,
//  no editing controls, no live tracer). Both are driven purely from the
//  decoded EngineSpec, so they work in the browser with no live simulator.
//

import SwiftUI

// MARK: - Spec sheet

/// Grouped, labelled list of an engine's specs. Reuses DataRow (the app's
/// standard label/value row) so it matches the rest of the UI.
struct EngineSpecList: View {
    let spec: EngineSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("BOTTOM END", rows: [
                ("Layout", spec.layout.displayName),
                ("Displacement", String(format: "%.2f L", spec.displacementLitres)),
                ("Bore × Stroke", String(format: "%.1f × %.1f mm", spec.boreMm, spec.strokeMm)),
                ("Rod length", String(format: "%.1f mm", spec.rodLengthMm)),
                ("Redline", "\(Int(spec.redlineRpm)) rpm"),
                ("Firing order", spec.firingOrder.map(String.init).joined(separator: "-")),
            ])
            section("CAMSHAFT", rows: camRows)
            section("HEAD & INDUCTION", rows: [
                ("Chamber volume", String(format: "%.0f cc", spec.chamberVolumeCc)),
                ("Port flow", String(format: "%.0f%%", spec.portFlowScale * 100)),
                ("Intake plenum", String(format: "%.1f L", spec.intakePlenumVolumeL)),
                ("Intake CFM", String(format: "%.0f", spec.intakeCfm)),
                ("Runner CFM", String(format: "%.0f", spec.runnerCfm)),
            ])
            section("EXHAUST", rows: [
                ("Primary length", String(format: "%.0f in", spec.exhaustPrimaryLengthIn)),
                ("Collector bore", String(format: "%.1f in", spec.exhaustCollectorBoreIn)),
                ("Header length", String(format: "%.0f in", spec.exhaustLengthIn)),
                ("Tone", spec.impulseResponse.displayName),
                ("Fuel", spec.fuel.displayName),
            ])
            section("DRIVETRAIN & CHASSIS", rows: [
                ("Clutch torque", String(format: "%.0f lb-ft", spec.clutchTorqueLbFt)),
                ("Gears", spec.gearRatios.map { String(format: "%.2f", $0) }.joined(separator: " · ")),
                ("Final drive", String(format: "%.2f", spec.diffRatio)),
                ("Vehicle mass", String(format: "%.0f lb", spec.vehicleMassLb)),
                ("Drag coeff.", String(format: "%.2f", spec.dragCoefficient)),
                ("Tire radius", String(format: "%.1f in", spec.tireRadiusIn)),
            ])
        }
    }

    private var camRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("Duration @50", String(format: "%.0f°", spec.camDurationDeg)),
            ("Lift", String(format: "%.1f mm", spec.camLiftMm)),
            ("Lobe separation", String(format: "%.0f°", spec.camLobeSeparationDeg)),
            ("Advance", String(format: "%.0f°", spec.camAdvanceDeg)),
        ]
        if spec.vtecEnabled {
            rows.append(("VTEC crossover", "\(Int(spec.vtecCrossoverRpm)) rpm"))
            rows.append(("VTEC lift", String(format: "%.1f mm", spec.vtecCamLiftMm)))
        }
        return rows
    }

    private func section(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.accentLive.opacity(0.85))
            ForEach(rows, id: \.0) { row in
                DataRow(label: row.0, value: row.1)
            }
        }
    }
}

// MARK: - Read-only ECU tune preview

/// Non-interactive view of an engine's saved ECU tune: a tab to switch between
/// the ignition and fuel maps, each a colour-coded heatmap of stored values —
/// no editing buttons, no live operating-point tracer. Built from the spec via
/// `EcuTuneModel.forDisplay`, so it shows the author's tune (or the factory
/// tune for an engine that was never tuned).
struct EngineTunePreview: View {
    let spec: EngineSpec

    @State private var activeMap: EcuMapKind = .ignition
    private let ecu: EcuTuneModel

    init(spec: EngineSpec) {
        self.spec = spec
        self.ecu = EcuTuneModel.forDisplay(spec: spec)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                tab("IGNITION", .ignition)
                tab("FUEL", .fuel)
                Spacer()
                Text(activeMap == .ignition ? "° advance" : "target AFR")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.textMuted)
            }
            heatmap
        }
    }

    private func tab(_ label: String, _ kind: EcuMapKind) -> some View {
        Button { activeMap = kind } label: {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(activeMap == kind ? .white : .textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .fill(activeMap == kind ? Color.accentLive.opacity(0.22) : Color.surfaceLow))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .stroke(activeMap == kind ? Color.accentLive.opacity(0.8) : .clear,
                            lineWidth: Theme.Stroke.thin))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
        }
        .buttonStyle(.plain)
    }

    private var heatmap: some View {
        VStack(spacing: 1) {
            ForEach((0..<ecu.loadBins.count).reversed(), id: \.self) { rowIdx in
                HStack(spacing: 1) {
                    ForEach(0..<ecu.rpmBins.count, id: \.self) { colIdx in
                        cell(rowIdx: rowIdx, colIdx: colIdx)
                    }
                }
            }
            xAxis
        }
    }

    private func cell(rowIdx: Int, colIdx: Int) -> some View {
        let value = ecu.value(in: activeMap, at: EcuCellCoord(loadIndex: rowIdx, rpmIndex: colIdx))
        return Text(EcuMapStyle.format(value: value, kind: activeMap))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.95))
            .shadow(color: .black.opacity(0.6), radius: 1)
            .lineLimit(1).minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lamp)
                .fill(EcuMapStyle.heatColor(value: value, kind: activeMap)))
    }

    private var xAxis: some View {
        HStack(spacing: 1) {
            ForEach(0..<ecu.rpmBins.count, id: \.self) { idx in
                Text(EcuMapStyle.rpmLabel(ecu.rpmBins[idx]))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.textMuted)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }
}
