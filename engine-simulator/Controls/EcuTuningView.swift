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
// Left gutter that carries the load-axis header + numbers. Kept narrow (no
// rotated axis title) so the heatmap gets the width on both platforms.
private let labelChannelWidth: CGFloat = 30
private let labelChannelHeight: CGFloat = 22
private let liveDotSize: CGFloat = 6
// The coarse ± step is this multiple of the per-cell fine step (0.5° / 0.1
// AFR), so the buttons offer both a fine nudge and a big jump.
private let coarseStepScale: Double = 10.0

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
            // Same engine-swap loader the 3D tile uses — until the new engine is
            // adopted, the map below is the *previous* engine's tune, so cover it.
            .loadingOverlay(vm.isSwappingEngine, label: "Loading engine")
    }
}

private struct EcuTuningEditor: View {
    @ObservedObject var vm: EngineViewModel
    @ObservedObject var ecu: EcuTuneModel
    @State private var activeMap: EcuMapKind = .ignition
    @State private var selectedCell: EcuCellCoord = EcuCellCoord(loadIndex: 0, rpmIndex: 0)
    #if !os(macOS)
    /// Armed paint amount (the exact signed bump applied per cell) or nil when
    /// off. Touch's advantage over the desktop click model: arm a ± step with a
    /// button, then drag across the heatmap to bump every cell you cross.
    @State private var paintDelta: Double? = nil
    /// Last cell painted this drag, so holding the finger still over one cell
    /// doesn't bump it repeatedly.
    @State private var lastPaintedCell: EcuCellCoord? = nil
    #endif

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            mapBody
            bottomBar
        }
        .padding(Theme.Space.sm)
        .background(Color.appBackground)
        .onAppear { selectTopLeftCell() }
    }

    // MARK: - Bottom bar (edit controls + map selector)

    /// Everything that isn't the graph lives in one bottom strip: the edit
    /// controls on the left, and the map selector + legend filling what used
    /// to be empty space on the right. The heatmap takes the freed top space.
    private var bottomBar: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            editControls
            Spacer(minLength: Theme.Space.sm)
            mapSelector
        }
    }

    /// Map tabs over the legend, right-aligned so it sits in the bottom-right
    /// corner. The legend keeps the grid self-explanatory: a key for the green
    /// tracer dot and a plain-language label for what the cell numbers mean.
    private var mapSelector: some View {
        VStack(alignment: .trailing, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.sm) {
                TabButton(label: "IGNITION", active: activeMap == .ignition) {
                    selectMap(.ignition)
                }
                TabButton(label: "FUEL", active: activeMap == .fuel) {
                    selectMap(.fuel)
                }
            }
            HStack(spacing: Theme.Space.md) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.accentOk)
                        .frame(width: liveDotSize, height: liveDotSize)
                    Text("ENGINE NOW")
                        .modifier(RetroFont(size: Theme.FontSize.caption))
                        .foregroundColor(.white.opacity(0.55))
                }
                Text(cellLegend)
                    .modifier(RetroFont(size: Theme.FontSize.callout, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    /// Plain-language description of what each cell's number represents.
    private var cellLegend: String {
        activeMap == .ignition ? "SPARK TIMING (°)" : "AIR–FUEL RATIO"
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
            // Load axis: a compact "LOAD / kPa" header sits above the numeric
            // bins (high load at top). No rotated title — that was the big
            // dead-space gutter on the left.
            VStack(spacing: cellSpacing) {
                VStack(spacing: 0) {
                    Text("LOAD")
                        .modifier(RetroFont(size: Theme.FontSize.caption))
                        .foregroundColor(.white.opacity(0.55))
                    Text("kPa")
                        .modifier(RetroFont(size: Theme.FontSize.micro))
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(height: labelChannelHeight)

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
                Text("RPM")
                    .modifier(RetroFont(size: Theme.FontSize.caption))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1.5)
                    .frame(maxWidth: .infinity)
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
            // Touch: one gesture handles both modes. A paint direction armed →
            // bump every cell the finger crosses; nothing armed → tap selects.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Paint only while a step is armed; otherwise the touch
                        // is a no-op (the ± buttons say to arm first).
                        guard let delta = paintDelta else { return }
                        guard let coord = cellAt(point: value.location,
                                                 cellW: cellW, cellH: cellH) else { return }
                        if coord == lastPaintedCell { return }
                        lastPaintedCell = coord
                        ecu.bumpCell(in: activeMap, at: coord, by: delta)
                    }
                    .onEnded { _ in lastPaintedCell = nil }
            )
            #endif
        }
        .frame(minHeight: 180)
    }

    #if !os(macOS)
    /// Map a touch point inside the heatmap to a cell coordinate (nil if
    /// outside). The grid renders load high-to-low top-to-bottom, so the
    /// visual row is flipped back to a load-bin index.
    private func cellAt(point: CGPoint, cellW: CGFloat, cellH: CGFloat) -> EcuCellCoord? {
        let rpmCount = ecu.rpmBins.count
        let loadCount = ecu.loadBins.count
        guard rpmCount > 0, loadCount > 0, cellW > 0, cellH > 0 else { return nil }
        let col = Int(point.x / (cellW + cellSpacing))
        let rowVisual = Int(point.y / (cellH + cellSpacing))
        guard col >= 0, col < rpmCount, rowVisual >= 0, rowVisual < loadCount else { return nil }
        return EcuCellCoord(loadIndex: (loadCount - 1) - rowVisual, rpmIndex: col)
    }
    #endif

    /// Click (macOS) selects a cell for the stepper. On touch the grid-level
    /// drag gesture handles selection/painting, so the cell is a plain face
    /// there (a per-cell Button would swallow the drag).
    private func cellView(rowIdx: Int, colIdx: Int) -> some View {
        let coord = EcuCellCoord(loadIndex: rowIdx, rpmIndex: colIdx)
        let isLive = (liveCell == coord)
        // The live cell shows the value the engine is ACTUALLY applying. On a
        // bad tune that includes the runtime chaos surge, so the live cell's
        // number and colour jitter in lock-step with the engine instead of
        // sitting frozen at the stored value. Every other cell shows its
        // stored tune value.
        let chaos = isLive ? vm.tuneChaosLevel : 0.0
        let value = (chaos > 0 ? liveAppliedValue() : nil)
            ?? ecu.value(in: activeMap, at: coord)
        #if os(macOS)
        return Button {
            selectedCell = coord
        } label: {
            cellFace(value: value, isLive: isLive,
                     isSelected: selectedCell == coord, chaos: chaos)
        }
        .buttonStyle(.plain)
        #else
        // Touch paints directly, so there's no "selected cell" to outline.
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

    // MARK: - Edit controls

    /// Two clearly-labelled scopes of editing, identical on both platforms.
    /// ADJUST CELL nudges the selected cell (yellow outline); WHOLE MAP shifts
    /// or reshapes every cell at once. Each ± button carries its step and unit
    /// — a fine nudge and a coarse jump per direction — so nothing is an
    /// unlabelled glyph.
    private var editControls: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            scopeRow(title: adjustTitle) {
                cellButton(-coarseStep)
                cellButton(-mapStep())
                cellButton(+mapStep())
                cellButton(+coarseStep)
            }
            scopeRow(title: "WHOLE MAP") {
                SmallActionButton(label: "−ALL") { ecu.bumpAll(in: activeMap, by: -mapStep()) }
                SmallActionButton(label: "+ALL") { ecu.bumpAll(in: activeMap, by: +mapStep()) }
                SmallActionButton(label: "SMOOTH") { ecu.smooth(activeMap) }
                SmallActionButton(label: "BAD", accent: .accentDanger) { ecu.corrupt(activeMap) }
                SmallActionButton(label: "RESET") { ecu.reset(activeMap) }
            }
        }
    }

    /// A labelled row of action buttons. The leading title names what the
    /// buttons in the row affect.
    private func scopeRow<Buttons: View>(title: String,
                                          @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Text(title)
                .modifier(RetroFont(size: Theme.FontSize.caption))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 84, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            buttons()
        }
    }

    /// One ± step button, labelled with its signed step + unit. macOS bumps the
    /// selected cell immediately; touch arms that exact step (highlighted) so a
    /// drag across the grid paints by it.
    @ViewBuilder private func cellButton(_ delta: Double) -> some View {
        let label = (delta < 0 ? "−" : "+") + stepLabel(abs(delta))
        #if os(macOS)
        SmallActionButton(label: label) {
            ecu.bumpCell(in: activeMap, at: selectedCell, by: delta)
        }
        #else
        SmallActionButton(label: label,
                          accent: paintDelta == delta ? (delta < 0 ? .accentDanger : .accentOk) : .white) {
            togglePaint(delta)
        }
        #endif
    }

    /// macOS edits one cell at a time; touch paints, so the label teaches the
    /// gesture and reflects the armed state.
    private var adjustTitle: String {
        #if os(macOS)
        return "ADJUST CELL"
        #else
        return paintDelta == nil ? "PAINT CELLS" : "DRAG TO PAINT"
        #endif
    }

    /// Coarse step = the fine per-cell step scaled up, for big jumps.
    private var coarseStep: Double { mapStep() * coarseStepScale }

    private func selectMap(_ kind: EcuMapKind) {
        activeMap = kind
        #if !os(macOS)
        // A step armed on one map is meaningless on the other (different unit
        // and magnitude), so disarm on switch.
        paintDelta = nil
        #endif
    }

    #if !os(macOS)
    /// Arm `delta` as the paint step, or disarm if it's already armed.
    private func togglePaint(_ delta: Double) {
        paintDelta = (paintDelta == delta) ? nil : delta
    }
    #endif

    // MARK: - Helpers

    private func mapStep() -> Double {
        switch activeMap {
        case .ignition: return EcuTuneModel.ignitionBumpStep
        case .fuel:     return EcuTuneModel.fuelBumpStep
        }
    }

    /// Format a step magnitude with the active map's unit, for the ± labels.
    private func stepLabel(_ value: Double) -> String {
        switch activeMap {
        case .ignition: return String(format: "%.1f°", value)
        case .fuel:     return String(format: "%.1f", value)
        }
    }

    private func formatValue(_ value: Double) -> String {
        EcuMapStyle.format(value: value, kind: activeMap)
    }

    private func rpmLabel(_ rpm: Double) -> String { EcuMapStyle.rpmLabel(rpm) }

    /// Cold-blue → green → red rainbow over the editable range, matching how
    /// HP Tuners / EFILive colour their tables. Ignition: more advance → red.
    /// Fuel: a richer target (lower AFR) → red, leaner → blue, so the hot end
    /// always reads as "more fuel / more timing".
    private func heatColor(for value: Double) -> Color {
        EcuMapStyle.heatColor(value: value, kind: activeMap)
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

