//
//  EcuTuningView.swift
//  engine-simulator
//
//  Tuner-style 2D map editor. Tabs switch between an ignition-advance map
//  and a fuel-trim map; both are colour-coded heatmaps indexed by RPM
//  (columns) and manifold absolute pressure (rows). The currently active
//  operating point is drawn as a live tracer dot with a short trail of the
//  last ~3 seconds of samples — so the user can literally see which cells
//  the engine is hitting as they drive or sweep the dyno.
//

import SwiftUI

private let cellSpacing: CGFloat = 1
private let cellCornerRadius: CGFloat = 2
private let labelChannelWidth: CGFloat = 44
private let labelChannelHeight: CGFloat = 20
private let stepBumpScale: Double = 5.0  // big-bump button multiplies the per-cell step

/// Thin wrapper that only observes vm. When the engine is swapped, vm.ecu is
/// replaced with a brand-new EcuTuneModel — keying the inner editor's `.id`
/// to `ObjectIdentifier(vm.ecu)` guarantees the editor is fully re-created
/// (fresh @ObservedObject on the new model, fresh @State) so the tracer dot
/// and cell display start tracking the new engine immediately.
struct EcuTuningView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        EcuTuningEditor(vm: vm, ecu: vm.ecu)
            .id(ObjectIdentifier(vm.ecu))
    }
}

private struct EcuTuningEditor: View {
    @ObservedObject var vm: EngineViewModel
    @ObservedObject var ecu: EcuTuneModel
    @State private var activeMap: EcuMapKind = .ignition
    @State private var selectedCell: EcuCellCoord = EcuCellCoord(loadIndex: 0, rpmIndex: 0)

    var body: some View {
        VStack(spacing: 8) {
            tabBar
            mapBody
            controlRow
            liveReadouts
        }
        .padding(10)
        .background(Color.appBackground)
        .onAppear { selectTopLeftCell() }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 6) {
            TabButton(label: "IGNITION", active: activeMap == .ignition) {
                activeMap = .ignition
            }
            TabButton(label: "FUEL", active: activeMap == .fuel) {
                activeMap = .fuel
            }
            Spacer()
        }
    }

    /// Cell the live tracer dot is currently sitting in. Used to draw the
    /// green border so the user can see which cell affects the engine now.
    private var liveCell: EcuCellCoord? {
        guard !ecu.rpmBins.isEmpty, !ecu.loadBins.isEmpty else { return nil }
        let rpmIdx = nearestBinIndex(value: ecu.currentRpm, bins: ecu.rpmBins)
        let loadIdx = nearestBinIndex(value: ecu.currentLoadKpa, bins: ecu.loadBins)
        return EcuCellCoord(loadIndex: loadIdx, rpmIndex: rpmIdx)
    }

    // MARK: - Map body (heatmap + tracer)

    private var mapBody: some View {
        HStack(alignment: .top, spacing: 4) {
            // Y axis title — rotated so it reads bottom-to-top alongside the
            // numeric labels.
            Text("MAP  (kPa)")
                .modifier(RetroFont(size: 9))
                .foregroundColor(.white.opacity(0.45))
                .tracking(1.0)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(width: 14)
                .padding(.top, labelChannelHeight)

            // Y axis numeric labels (load, high at top).
            VStack(spacing: cellSpacing) {
                Color.clear.frame(height: labelChannelHeight)
                ForEach((0..<ecu.loadBins.count).reversed(), id: \.self) { rowIdx in
                    Text("\(Int(ecu.loadBins[rowIdx]))")
                        .modifier(RetroFont(size: 9))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 4)
                }
            }
            .frame(width: labelChannelWidth)

            VStack(spacing: 2) {
                heatmapGrid
                xAxisLabels
                Text("ENGINE  SPEED  (rpm)")
                    .modifier(RetroFont(size: 9))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(1.0)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 1)
            }
        }
    }

    private var heatmapGrid: some View {
        GeometryReader { geo in
            let cellW = (geo.size.width - cellSpacing * CGFloat(ecu.rpmBins.count - 1)) / CGFloat(ecu.rpmBins.count)
            let cellH = (geo.size.height - cellSpacing * CGFloat(ecu.loadBins.count - 1)) / CGFloat(ecu.loadBins.count)

            ZStack(alignment: .topLeading) {
                // Cells (high load at top → iterate loadBins in reverse).
                VStack(spacing: cellSpacing) {
                    ForEach((0..<ecu.loadBins.count).reversed(), id: \.self) { rowIdx in
                        HStack(spacing: cellSpacing) {
                            ForEach(0..<ecu.rpmBins.count, id: \.self) { colIdx in
                                cellView(rowIdx: rowIdx, colIdx: colIdx)
                                    .frame(width: cellW, height: cellH)
                            }
                        }
                    }
                }

                // Trace trail + live tracer.
                tracerLayer(cellW: cellW, cellH: cellH)
            }
        }
        .frame(minHeight: 180)
    }

    private func cellView(rowIdx: Int, colIdx: Int) -> some View {
        let coord = EcuCellCoord(loadIndex: rowIdx, rpmIndex: colIdx)
        let value = ecu.value(in: activeMap, at: coord)
        let isSelected = selectedCell == coord
        let isLive = (liveCell == coord)
        return Button {
            selectedCell = coord
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: cellCornerRadius)
                    .fill(heatColor(for: value))
                // Always-on green border on the cell the engine is currently
                // operating in — edits to THIS cell take effect immediately.
                if isLive {
                    RoundedRectangle(cornerRadius: cellCornerRadius)
                        .stroke(Color.green, lineWidth: 2)
                        .shadow(color: .green.opacity(0.5), radius: 3)
                }
                // Selected (edit-target) cell. White when also live, yellow
                // otherwise — so the user can see when they're tuning ahead
                // of the engine's current operating point.
                if isSelected {
                    RoundedRectangle(cornerRadius: cellCornerRadius)
                        .stroke(isLive ? Color.white : Color.yellow, lineWidth: 2)
                }
                Text(formatValue(value))
                    .modifier(RetroFont(size: 10))
                    .foregroundColor(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.7), radius: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .buttonStyle(.plain)
    }

    private var xAxisLabels: some View {
        GeometryReader { geo in
            let count = ecu.rpmBins.count
            let cellW = (geo.size.width - cellSpacing * CGFloat(count - 1)) / CGFloat(count)
            HStack(spacing: cellSpacing) {
                ForEach(0..<count, id: \.self) { idx in
                    Text(rpmLabel(ecu.rpmBins[idx]))
                        .modifier(RetroFont(size: 9))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: cellW)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .frame(height: labelChannelHeight)
    }

    private func tracerLayer(cellW: CGFloat, cellH: CGFloat) -> some View {
        ZStack {
            // Recent operating-point trail.
            ForEach(ecu.tracerTrail) { sample in
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 4, height: 4)
                    .position(pixelPos(rpm: sample.rpm,
                                       loadKpa: sample.loadKpa,
                                       cellW: cellW, cellH: cellH))
            }
            // Live tracer dot at the current operating point.
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
                .shadow(color: .green, radius: 5)
                .position(pixelPos(rpm: ecu.currentRpm,
                                   loadKpa: ecu.currentLoadKpa,
                                   cellW: cellW, cellH: cellH))
                .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Control row (always visible)

    /// One always-visible row with the selected cell readout, per-cell ± edits
    /// and map-wide actions (bump-all / smooth / reset). Nothing appears or
    /// disappears based on selection state.
    private var controlRow: some View {
        let coord = selectedCell
        let value = ecu.value(in: activeMap, at: coord)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(cellLabel(coord))
                    .modifier(RetroFont(size: 9))
                    .foregroundColor(.white.opacity(0.7))
                Text(formatValue(value))
                    .modifier(RetroFont(size: 16))
                    .foregroundColor(.white)
            }
            .frame(minWidth: 140, alignment: .leading)

            HStack(spacing: 3) {
                EditButton(label: "− \(formatStep(stepBumpScale))") {
                    ecu.bumpCell(in: activeMap, at: coord, by: -mapStep() * stepBumpScale)
                }
                EditButton(label: "−") {
                    ecu.bumpCell(in: activeMap, at: coord, by: -mapStep())
                }
                EditButton(label: "+") {
                    ecu.bumpCell(in: activeMap, at: coord, by: +mapStep())
                }
                EditButton(label: "+ \(formatStep(stepBumpScale))") {
                    ecu.bumpCell(in: activeMap, at: coord, by: +mapStep() * stepBumpScale)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 3) {
                SmallActionButton(label: "−ALL") { ecu.bumpAll(in: activeMap, by: -mapStep()) }
                SmallActionButton(label: "+ALL") { ecu.bumpAll(in: activeMap, by: +mapStep()) }
                SmallActionButton(label: "SMOOTH") { ecu.smooth(activeMap) }
                SmallActionButton(label: "RESET") { ecu.reset(activeMap) }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.04)))
    }

    // MARK: - Live readouts

    private var liveReadouts: some View {
        // Absolute spark advance currently being commanded = base curve at this
        // rpm + the offset we last pushed to the engine. Matches the live cell
        // value the user sees on the map.
        let totalAdvance = ecu.baseTiming(at: vm.rpm) + vm.ignitionOffset
        return HStack(spacing: 14) {
            Readout(label: "RPM", value: String(format: "%.0f", vm.rpm))
            Readout(label: "MAP",
                    value: String(format: "%.0f kPa", clampedLiveLoadKpa()))
            Readout(label: "ADV",
                    value: String(format: "%.1f°", totalAdvance))
            Readout(label: "Δ",
                    value: String(format: "%+.1f°", vm.ignitionOffset))
            Readout(label: "TRIM",
                    value: String(format: "%.2fx", vm.fuelTrim))
            Readout(label: "AFR",
                    value: String(format: "%.1f", vm.intakeAFR))
            Spacer()
        }
    }

    // MARK: - Helpers

    private func mapStep() -> Double {
        switch activeMap {
        case .ignition: return EcuTuneModel.ignitionBumpStep
        case .fuel:     return EcuTuneModel.fuelBumpStep
        }
    }

    private func formatValue(_ value: Double) -> String {
        switch activeMap {
        case .ignition: return String(format: "%+.1f", value)
        case .fuel:     return String(format: "%.2f", value)
        }
    }

    private func formatStep(_ mult: Double) -> String {
        switch activeMap {
        case .ignition: return String(format: "%.1f°", mapStep() * mult)
        case .fuel:     return String(format: "%.2f", mapStep() * mult)
        }
    }

    private func rpmLabel(_ rpm: Double) -> String {
        rpm >= 1000 ? String(format: "%.1fk", rpm / 1000.0) : String(format: "%.0f", rpm)
    }

    private func cellLabel(_ coord: EcuCellCoord) -> String {
        let safe = ecu.clampToBounds(coord)
        let rpm = ecu.rpmBins[safe.rpmIndex]
        let load = ecu.loadBins[safe.loadIndex]
        let unit = activeMap == .ignition ? "° adv" : "x trim"
        return "\(rpmLabel(rpm)) RPM · \(Int(load)) kPa · \(unit)"
    }

    private func clampedLiveLoadKpa() -> Double {
        return max(0, ecu.currentLoadKpa)
    }

    /// Cold-blue → green → red rainbow over the editable range. Neutral
    /// (0° for ignition, 1.0 for fuel) lands roughly in the green zone, which
    /// matches how HP Tuners / EFILive colour their stock tunes.
    private func heatColor(for value: Double) -> Color {
        let norm: Double
        switch activeMap {
        case .ignition:
            let r = EcuTuneModel.ignitionRange
            norm = (value - r.lowerBound) / (r.upperBound - r.lowerBound)
        case .fuel:
            let r = EcuTuneModel.fuelRange
            norm = (value - r.lowerBound) / (r.upperBound - r.lowerBound)
        }
        let clamped = max(0.0, min(1.0, norm))
        let hue = 0.62 - clamped * 0.62  // blue (0.62) → red (0.0)
        return Color(hue: hue, saturation: 0.62, brightness: 0.58)
    }

    private func pixelPos(rpm: Double, loadKpa: Double,
                          cellW: CGFloat, cellH: CGFloat) -> CGPoint {
        let rpmFrac = binFraction(value: rpm, bins: ecu.rpmBins)
        let loadFrac = binFraction(value: loadKpa, bins: ecu.loadBins)
        let totalRows = CGFloat(ecu.loadBins.count)
        let x = (rpmFrac + 0.5) * cellW + rpmFrac * cellSpacing
        // High load at top means y is inverted relative to load bin index.
        let invertedRow = totalRows - 1 - loadFrac
        let y = (invertedRow + 0.5) * cellH + invertedRow * cellSpacing
        return CGPoint(x: x, y: y)
    }

    /// Returns fractional bin index: 0 at first bin, bins.count-1 at last.
    private func binFraction(value: Double, bins: [Double]) -> CGFloat {
        guard let first = bins.first, let last = bins.last, bins.count > 1 else { return 0 }
        if value <= first { return 0 }
        if value >= last { return CGFloat(bins.count - 1) }
        for i in 0..<(bins.count - 1) {
            let lo = bins[i], hi = bins[i + 1]
            if value >= lo && value < hi {
                let local = (value - lo) / (hi - lo)
                return CGFloat(Double(i) + local)
            }
        }
        return CGFloat(bins.count - 1)
    }

    private func selectTopLeftCell() {
        guard !ecu.rpmBins.isEmpty, !ecu.loadBins.isEmpty else { return }
        // Top-left of the visible grid = highest load row (rendered at top),
        // first RPM column (rendered at left).
        selectedCell = EcuCellCoord(loadIndex: ecu.loadBins.count - 1, rpmIndex: 0)
    }

    private func nearestBinIndex(value: Double, bins: [Double]) -> Int {
        var bestIdx = 0
        var bestDelta = Double.infinity
        for (i, b) in bins.enumerated() {
            let d = abs(b - value)
            if d < bestDelta { bestDelta = d; bestIdx = i }
        }
        return bestIdx
    }
}

// MARK: - Small UI pieces

private struct TabButton: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .modifier(RetroFont(size: 10))
                .foregroundColor(active ? .white : .white.opacity(0.5))
                .tracking(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Color.orange.opacity(0.25) : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(active ? Color.orange.opacity(0.8) : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SmallActionButton: View {
    let label: String
    var accent: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .modifier(RetroFont(size: 9))
                .foregroundColor(accent == .white ? .white.opacity(0.8) : accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accent == .white ? Color.white.opacity(0.05) : accent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(accent == .white ? Color.white.opacity(0.15) : accent.opacity(0.6), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct EditButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .modifier(RetroFont(size: 12))
                .foregroundColor(.white)
                .frame(minWidth: 36)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(colors: [Color(white: 0.22), Color(white: 0.10)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.2), lineWidth: 0.7))
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
}

private struct Readout: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .modifier(RetroFont(size: 8))
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .modifier(RetroFont(size: 11))
                .foregroundColor(.white)
        }
    }
}
