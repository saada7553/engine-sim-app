//
//  EcuTuningView.swift
//  engine-simulator
//
//  Tuner-style 2D map editor. Tabs switch between an ignition-advance map
//  and a target-AFR fuel map; both are colour-coded heatmaps indexed by RPM
//  (columns) and manifold absolute pressure (rows). The currently active
//  operating point is drawn as a live tracer dot with a short trail of the
//  last ~3 seconds of samples — so the user can literally see which cells
//  the engine is hitting as they drive or sweep the dyno.
//

import SwiftUI

private let cellSpacing: CGFloat = 1
private let cellCornerRadius: CGFloat = Theme.Radius.lamp
// iOS shrinks the Y-axis label channel and drops the rotated "MAP (kPa)"
// title so the heatmap gets back the dead space on the left.
#if os(macOS)
private let labelChannelWidth: CGFloat = 44
#else
private let labelChannelWidth: CGFloat = 26
#endif
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
    #if !os(macOS)
    /// Active paint delta; nil = read-only. Tapping a paint pill sets this,
    /// then dragging across the heatmap bumps each cell the finger crosses.
    @State private var paintMode: IosPaintMode? = nil
    /// Last cell painted in the current drag, so we don't bump the same
    /// cell repeatedly while the finger sits over it.
    @State private var lastPaintedCell: EcuCellCoord? = nil
    #endif

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            tabBar
            mapBody
            #if os(macOS)
            controlRow
            liveReadouts
            #else
            // iOS replaces the click-+/- row with a paint-mode bar: pick a
            // delta and drag across the heatmap to bump cells. liveReadouts
            // stays but scales smaller so it fits without scrolling.
            iosPaintBar
            iosLiveReadouts
            #endif
        }
        #if os(macOS)
        .padding(Theme.Space.lg)
        #else
        .padding(Theme.Space.sm)
        #endif
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
            // Rotated Y-axis title eats ~14pt of width and isn't needed on
            // iOS where every pt of heatmap counts.
            #if os(macOS)
            Text("MAP  (kPa)")
                .modifier(RetroFont(size: Theme.FontSize.footnote))
                .foregroundColor(.white.opacity(0.45))
                .tracking(1.0)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(width: 14)
                .padding(.top, labelChannelHeight)
            #endif

            // Y axis numeric labels (load, high at top).
            VStack(spacing: cellSpacing) {
                Color.clear.frame(height: labelChannelHeight)
                ForEach((0..<ecu.loadBins.count).reversed(), id: \.self) { rowIdx in
                    Text("\(Int(ecu.loadBins[rowIdx]))")
                        .modifier(RetroFont(size: Theme.FontSize.footnote))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 4)
                }
            }
            .frame(width: labelChannelWidth)

            VStack(spacing: 2) {
                heatmapGrid
                xAxisLabels
                // x-axis title is helpful on macOS, redundant on iOS where
                // the bin numbers right above clearly read as RPM.
                #if os(macOS)
                Text("ENGINE  SPEED  (rpm)")
                    .modifier(RetroFont(size: Theme.FontSize.footnote))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(1.0)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 1)
                #endif
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
            #if !os(macOS)
            // Paint-mode drag: dragging across the heatmap with an active
            // paint mode bumps every cell the finger crosses by that delta.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let mode = paintMode else { return }
                        guard let coord = cellAt(point: value.location,
                                                  cellW: cellW,
                                                  cellH: cellH) else { return }
                        if coord == lastPaintedCell { return }
                        lastPaintedCell = coord
                        // Don't touch selectedCell — the iOS heatmap has
                        // no yellow "selected" outline anymore. The paint
                        // bar reads its current cell from `lastPaintedCell`
                        // (see iosPaintBar's value lookup below).
                        ecu.bumpCell(in: activeMap,
                                     at: coord,
                                     by: mode.delta(step: mapStep()))
                    }
                    .onEnded { _ in lastPaintedCell = nil }
            )
            #endif
        }
        .frame(minHeight: 180)
    }

    #if !os(macOS)
    /// Map a touch point inside the heatmap into a cell coordinate, or nil
    /// if the touch fell outside any cell. The visual layout reverses load
    /// bins (highest at top), so y → row needs the same flip.
    private func cellAt(point: CGPoint, cellW: CGFloat, cellH: CGFloat) -> EcuCellCoord? {
        let rpmCount = ecu.rpmBins.count
        let loadCount = ecu.loadBins.count
        guard rpmCount > 0, loadCount > 0, cellW > 0, cellH > 0 else { return nil }
        let col = Int(point.x / (cellW + cellSpacing))
        let rowVisual = Int(point.y / (cellH + cellSpacing))
        guard col >= 0 && col < rpmCount,
              rowVisual >= 0 && rowVisual < loadCount else { return nil }
        let row = (loadCount - 1) - rowVisual
        return EcuCellCoord(loadIndex: row, rpmIndex: col)
    }
    #endif

    private func cellView(rowIdx: Int, colIdx: Int) -> some View {
        let coord = EcuCellCoord(loadIndex: rowIdx, rpmIndex: colIdx)
        let isLive = (liveCell == coord)
        // The live cell shows the value the engine is ACTUALLY applying. On a
        // bad tune that includes the runtime chaos surge, so the live cell's
        // number and colour jitter in lock-step with ADV / TRIM instead of
        // sitting frozen at the stored value. Every other cell shows its
        // stored tune value as before.
        let chaos = isLive ? vm.tuneChaosLevel : 0.0
        let value = (chaos > 0 ? liveAppliedValue() : nil)
            ?? ecu.value(in: activeMap, at: coord)
        // iOS doesn't render a yellow "selected cell" outline — selection
        // would fight with the paint-mode drag (the per-cell Button consumed
        // gestures, and dragging would leave a yellow trail across cells
        // the user had no intention of "selecting"). On macOS keep the
        // tap-to-select Button so the +/− controlRow knows which cell to
        // edit.
        #if os(macOS)
        let isSelected = selectedCell == coord
        return Button {
            selectedCell = coord
        } label: {
            cellFace(value: value, isLive: isLive, isSelected: isSelected, chaos: chaos)
        }
        .buttonStyle(.plain)
        #else
        return cellFace(value: value, isLive: isLive, isSelected: false, chaos: chaos)
        #endif
    }

    /// The value the engine is applying at the live operating point right now,
    /// chaos surge included — ignition as absolute advance, fuel as the AFR the
    /// applied trim corresponds to. nil when the trim is degenerate.
    private func liveAppliedValue() -> Double? {
        switch activeMap {
        case .ignition:
            return ecu.baseTiming(at: vm.rpm) + vm.ignitionOffset
        case .fuel:
            guard vm.fuelTrim > 0.01 else { return nil }
            return EcuTuneModel.stoichReferenceAfr / vm.fuelTrim
        }
    }

    private func cellFace(value: Double, isLive: Bool, isSelected: Bool, chaos: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cellCornerRadius)
                .fill(heatColor(for: value))
            // Border on the cell the engine is operating in. Normally green;
            // as the tune turns chaotic it shifts toward red and the glow swells
            // so the unstable operating point reads as a flashing alarm.
            if isLive {
                let borderColor = Color(hue: 0.33 * (1.0 - chaos),
                                        saturation: 0.9, brightness: 1.0)
                RoundedRectangle(cornerRadius: cellCornerRadius)
                    .stroke(borderColor, lineWidth: 2 + chaos * 1.5)
                    .shadow(color: borderColor.opacity(0.5 + chaos * 0.4),
                            radius: 3 + chaos * 5)
            }
            if isSelected {
                RoundedRectangle(cornerRadius: cellCornerRadius)
                    .stroke(isLive ? Color.white : Color.accentWarn, lineWidth: 2)
            }
            Text(formatValue(value))
                .modifier(RetroFont(size: Theme.FontSize.body))
                .foregroundColor(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.7), radius: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // Mono digits keep each cell's text from re-centering as
                // values change while the user paints.
                .monospacedDigit()
        }
    }

    private var xAxisLabels: some View {
        GeometryReader { geo in
            let count = ecu.rpmBins.count
            let cellW = (geo.size.width - cellSpacing * CGFloat(count - 1)) / CGFloat(count)
            HStack(spacing: cellSpacing) {
                ForEach(0..<count, id: \.self) { idx in
                    Text(rpmLabel(ecu.rpmBins[idx]))
                        .modifier(RetroFont(size: Theme.FontSize.footnote))
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
                    .fill(Color.accentOk.opacity(0.18))
                    .frame(width: 4, height: 4)
                    .position(pixelPos(rpm: sample.rpm,
                                       loadKpa: sample.loadKpa,
                                       cellW: cellW, cellH: cellH))
            }
            // Live tracer dot at the current operating point.
            Circle()
                .fill(Color.accentOk)
                .frame(width: 10, height: 10)
                .shadow(color: .accentOk, radius: 5)
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
                    .modifier(RetroFont(size: Theme.FontSize.footnote))
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
                    .frame(width: 140, alignment: .leading)
                Text(formatValue(value))
                    .modifier(RetroFont(size: Theme.FontSize.title))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .frame(width: 140, alignment: .leading)
            }
            .frame(width: 140, alignment: .leading)

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
                SmallActionButton(label: "BAD", accent: .accentDanger) { ecu.corrupt(activeMap) }
                SmallActionButton(label: "RESET") { ecu.reset(activeMap) }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Color.white.opacity(0.04)))
    }

    // MARK: - iOS paint-mode UI

    #if !os(macOS)
    /// Top-row pills on iOS: pick a delta to paint when dragging across
    /// the heatmap. Tap again to clear and return to read-only mode.
    private var iosPaintBar: some View {
        // Show the most recently painted cell so the user can verify the
        // delta they're applying; falls back to the live operating cell
        // before they've touched the heatmap.
        let displayCell = lastPaintedCell ?? liveCell ?? selectedCell
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(cellLabel(displayCell))
                    .modifier(RetroFont(size: Theme.FontSize.caption))
                    .foregroundColor(.white.opacity(0.55))
                    .monospacedDigit()
                    .frame(width: 90, alignment: .leading)
                Text(formatValue(ecu.value(in: activeMap, at: displayCell)))
                    .modifier(RetroFont(size: Theme.FontSize.control))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .frame(width: 90, alignment: .leading)
            }
            .frame(width: 90, alignment: .leading)

            // Centered paint-mode pills — only ± at the bigger step now
            // (4 buttons was too many; the small step is rarely the
            // useful one when you can also drag-paint freely).
            Spacer()
            HStack(spacing: 8) {
                ForEach(iosPaintOptions, id: \.self) { mode in
                    IosPaintPill(
                        label: mode.label(step: mapStep()),
                        active: paintMode == mode,
                        accent: mode.accent
                    ) {
                        paintMode = (paintMode == mode) ? nil : mode
                    }
                }
            }
            Spacer()

            SmallActionButton(label: "SMOOTH") { ecu.smooth(activeMap) }
            SmallActionButton(label: "BAD", accent: .accentDanger) { ecu.corrupt(activeMap) }
            SmallActionButton(label: "RESET") { ecu.reset(activeMap) }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Color.white.opacity(0.04)))
    }

    /// Just the big-step ± modes. We expose only these on iOS — the small
    /// step is rarely what you want when you can drag across many cells.
    private var iosPaintOptions: [IosPaintMode] { [.decBig, .incBig] }

    /// Compact stack of live engine telemetry on iOS — narrower than the
    /// macOS row so it sits on a single line at iPad widths.
    private var iosLiveReadouts: some View {
        let totalAdvance = ecu.baseTiming(at: vm.rpm) + vm.ignitionOffset
        return HStack(spacing: 10) {
            Readout(label: "RPM", value: String(format: "%.0f", vm.rpm))
            Readout(label: "MAP", value: String(format: "%.0f", clampedLiveLoadKpa()))
            Readout(label: "ADV", value: String(format: "%.1f°", totalAdvance))
            Readout(label: "Δ", value: String(format: "%+.1f°", vm.ignitionOffset))
            Readout(label: "TRIM", value: String(format: "%.2f", vm.fuelTrim))
            Readout(label: "AFR", value: String(format: "%.1f", vm.intakeAFR))
            Spacer()
        }
    }
    #endif

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
        case .fuel:     return String(format: "%.1f", value)
        }
    }

    private func formatStep(_ mult: Double) -> String {
        switch activeMap {
        case .ignition: return String(format: "%.1f°", mapStep() * mult)
        case .fuel:     return String(format: "%.1f", mapStep() * mult)
        }
    }

    private func rpmLabel(_ rpm: Double) -> String {
        rpm >= 1000 ? String(format: "%.1fk", rpm / 1000.0) : String(format: "%.0f", rpm)
    }

    private func cellLabel(_ coord: EcuCellCoord) -> String {
        let safe = ecu.clampToBounds(coord)
        let rpm = ecu.rpmBins[safe.rpmIndex]
        let load = ecu.loadBins[safe.loadIndex]
        let unit = activeMap == .ignition ? "° adv" : "AFR"
        return "\(rpmLabel(rpm)) RPM · \(Int(load)) kPa · \(unit)"
    }

    private func clampedLiveLoadKpa() -> Double {
        return max(0, ecu.currentLoadKpa)
    }

    /// Cold-blue → green → red rainbow over the editable range, matching how
    /// HP Tuners / EFILive colour their tables. Ignition: more advance → red.
    /// Fuel: a richer target (lower AFR) → red, leaner → blue, so the hot end
    /// always reads as "more fuel / more timing".
    private func heatColor(for value: Double) -> Color {
        let r = activeMap == .ignition ? EcuTuneModel.ignitionRange : EcuTuneModel.fuelRange
        let norm = (value - r.lowerBound) / (r.upperBound - r.lowerBound)
        let clamped = max(0.0, min(1.0, norm))
        // Ignition reddens as the value rises; fuel reddens as AFR falls.
        let hue = activeMap == .ignition ? (0.62 - clamped * 0.62) : (clamped * 0.62)
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

#if !os(macOS)

/// Paint delta selected in the iOS paint bar. Dragging across the heatmap
/// while a mode is active bumps each cell the finger crosses.
private enum IosPaintMode: Hashable {
    case decBig
    case decSmall
    case incSmall
    case incBig

    static let allOptions: [IosPaintMode] = [.decBig, .decSmall, .incSmall, .incBig]

    func delta(step: Double) -> Double {
        switch self {
        case .decBig:   return -step * stepBumpScale
        case .decSmall: return -step
        case .incSmall: return +step
        case .incBig:   return +step * stepBumpScale
        }
    }

    func label(step: Double) -> String {
        switch self {
        case .decBig:   return "−\(IosPaintMode.formatStep(step * stepBumpScale))"
        case .decSmall: return "−\(IosPaintMode.formatStep(step))"
        case .incSmall: return "+\(IosPaintMode.formatStep(step))"
        case .incBig:   return "+\(IosPaintMode.formatStep(step * stepBumpScale))"
        }
    }

    var accent: Color {
        switch self {
        case .decBig, .decSmall: return .accentDanger
        case .incSmall, .incBig: return .accentOk
        }
    }

    private static func formatStep(_ s: Double) -> String {
        s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s)
    }
}

private struct IosPaintPill: View {
    let label: String
    let active: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .modifier(RetroFont(size: Theme.FontSize.body, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize()
                .foregroundColor(active ? .black : accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .fill(active ? accent : accent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .stroke(accent.opacity(active ? 1.0 : 0.6), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#endif

private struct TabButton: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .modifier(RetroFont(size: Theme.FontSize.body))
                .foregroundColor(active ? .white : .white.opacity(0.5))
                .tracking(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .fill(active ? Color.accentLive.opacity(0.25) : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .stroke(active ? Color.accentLive.opacity(0.8) : Color.white.opacity(0.1), lineWidth: 1)
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
                .modifier(RetroFont(size: Theme.FontSize.control))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize()
                .foregroundColor(.white)
                .frame(minWidth: 36)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(colors: [Color(white: 0.22), Color(white: 0.10)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).stroke(Color.white.opacity(0.2), lineWidth: 0.7))
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
}

private struct Readout: View {
    let label: String
    let value: String
    /// Fixed width pinned to the worst-case value so the row doesn't shift
    /// when digits arrive (e.g. RPM going from "0" → "8500"). Each readout
    /// reserves enough room for its label *and* its widest expected value.
    var valueWidth: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .modifier(RetroFont(size: Theme.FontSize.caption))
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .modifier(RetroFont(size: Theme.FontSize.callout))
                .foregroundColor(.white)
                // Mono digits + a fixed leading-aligned frame: digits
                // never reflow even as the value grows.
                .monospacedDigit()
                .frame(width: valueWidth, alignment: .leading)
        }
        .frame(width: valueWidth, alignment: .leading)
    }
}
