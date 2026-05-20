//
//  BuilderCinematicSteps.swift
//  engine-simulator
//
//  Cinematic steps for the engine builder. Each step does one thing with
//  room to breathe — slider + live visual readout, not a form grid.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Diagram constants

private enum CylinderDiagram {
    static let viewportFillFraction: CGFloat = 0.9
    static let boreWallThickness: CGFloat = 1.5
    // Cylinder head is thinner — the previous 0.22 made the deck look like a
    // brick over the piston. Real heads above a 86mm bore are closer to 12-15mm.
    static let headThicknessRatioOfBore: CGFloat = 0.13
    // Chamber clearance shrunk too — combustion chambers are tight, not the
    // cavernous gap the old 0.07 implied.
    static let chamberClearanceRatioOfBore: CGFloat = 0.035
    static let pistonRingGap: CGFloat = 4
    static let pistonSkirtBelowWristPin: CGFloat = 6
    static let wristPinRadius: CGFloat = 3
    static let rodWidthRatioOfBore: CGFloat = 0.16
    static let rodSmallEndRadius: CGFloat = 4
    static let bigEndRadiusRatioOfStroke: CGFloat = 0.18
    static let pistonInsetFromBore: CGFloat = 2
    static let ghostStrokeWidth: CGFloat = 0.5
    static let dashPattern: [CGFloat] = [3, 3]
    static let boreBottomOverhangMm: Double = 4

    // Slider maxima — used to compute a stable scale so changing any one
    // dimension does NOT visually scale the others.
    static let maxBoreMm: Double = 110
    static let maxStrokeMm: Double = 110
    static let maxRodLengthMm: Double = 200
    static let maxCompressionHeightMm: Double = 50
    static let canvasWidthSlackMm: Double = 30
    // Bottom margin must clear the full crank circle (one max-radius below
    // the crank center) plus a small breathing gap to the StatBox row below.
    static let canvasBottomMarginMm: Double = 12
}


// MARK: - Identity

struct IdentityStep: View {
    @ObservedObject var state: EngineBuilderState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 64) {
            VStack(alignment: .leading, spacing: 28) {
                BuilderSectionHeading(title: "Step 1 · Name your engine")
                Text("Every great engine starts with a name.\nIt'll show in the sidebar once you save.")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .lineSpacing(4)

                ZStack(alignment: .leading) {
                    if state.spec.name.isEmpty {
                        Text("e.g. Skyline RB26")
                            .font(.system(size: 36, weight: .regular, design: .monospaced))
                            .foregroundColor(BuilderTheme.dim.opacity(0.3))
                    }
                    TextField("", text: $state.spec.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 36, weight: .regular, design: .monospaced))
                        .foregroundColor(.white)
                        .focused($focused)
                }
                Rectangle()
                    .fill(BuilderTheme.accent)
                    .frame(height: 1)
            }
            Spacer()

            EnginePlaceholderArt(spec: state.spec)
                .frame(width: 280, height: 280)
        }
        .onAppear { focused = true }
    }
}

/// Neutral identity-side art that reflects the spec the user is composing,
/// rather than always claiming the engine is a V8. Before a layout is picked
/// it's just a couple of concentric outlines and a build-status badge.
private struct EnginePlaceholderArt: View {
    let spec: EngineSpec

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Rectangle()
                    .stroke(BuilderTheme.line, lineWidth: 1)
                    .frame(width: CGFloat(220 - i * 30), height: CGFloat(220 - i * 30))
            }
            Rectangle()
                .stroke(BuilderTheme.accent, lineWidth: 1.5)
                .frame(width: 120, height: 120)

            VStack(spacing: 6) {
                Text(spec.layout.shortLabel)
                    .font(.system(size: 24, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.accent)
                Text(String(format: "%.2fL", spec.displacementLitres))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .tracking(1)
            }
        }
    }
}

// MARK: - Layout

struct LayoutStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            BuilderSectionHeading(title: "Step 2 · Pick the architecture")

            Text("Each layout sets bank count, bank angle, and the firing order.\nEverything downstream — cam timing, intake routing — derives from this choice.")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.label)
                .lineSpacing(4)

            ScrollView {
                CardGrid(items: EngineLayout.allCases,
                         columns: 4,
                         isSelected: { state.spec.layout == $0 },
                         onSelect: { selectLayout($0) }) { layout, selected in
                    LayoutCard(layout: layout, selected: selected)
                }
            }
        }
    }

    private func selectLayout(_ newLayout: EngineLayout) {
        let cylinderCountChanged = newLayout.cylinderCount != state.spec.layout.cylinderCount
        state.spec.layout = newLayout
        // A firing order from a different cylinder count is invalid; reset.
        // Same count: keep the user's custom order so layout swaps don't blow it away.
        if cylinderCountChanged || !state.spec.firingOrderIsValid {
            state.spec.resyncFiringOrderForLayout()
        }
    }
}

private struct LayoutCard: View {
    let layout: EngineLayout
    let selected: Bool

    var body: some View {
        VStack(spacing: 12) {
            LayoutSilhouette(layout: layout, accent: selected)
                .frame(width: 90, height: 60)
            Text(layout.shortLabel)
                .font(.system(size: 22, weight: .regular, design: .monospaced))
                .foregroundColor(selected ? BuilderTheme.accent : .white)
            Text(layout.displayName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(BuilderTheme.label)
        }
    }
}

private struct LayoutSilhouette: View {
    let layout: EngineLayout
    let accent: Bool

    var body: some View {
        let color = accent ? BuilderTheme.accent : Color.white.opacity(0.75)
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let n = layout.cylinderCount
            let banks = layout.bankCount

            if banks == 1 {
                inlineSilhouette(w: w, h: h, count: n, color: color)
            } else if layout.bankHalfAngleDeg >= 80 {
                // Boxer / flat: cylinders lie horizontally, pointing away
                // from a central crankshaft. Render them as left- and
                // right-pointing rows sharing a center column.
                flatSilhouette(w: w, h: h, count: n, color: color)
            } else {
                vSilhouette(w: w, h: h, count: n,
                            tilt: layout.bankHalfAngleDeg / 90.0, color: color)
            }
        }
    }

    private func inlineSilhouette(w: CGFloat, h: CGFloat, count n: Int, color: Color) -> some View {
        let cylW = w / CGFloat(n) * 0.7
        let gap = (w - cylW * CGFloat(n)) / CGFloat(n + 1)
        return HStack(spacing: gap) {
            ForEach(0..<n, id: \.self) { _ in
                Rectangle().stroke(color, lineWidth: 1)
                    .frame(width: cylW, height: h * 0.7)
            }
        }
        .padding(.horizontal, gap)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func vSilhouette(w: CGFloat, h: CGFloat, count n: Int,
                              tilt: Double, color: Color) -> some View {
        let perBank = n / 2
        let cylW = w / CGFloat(perBank) * 0.7
        let gap = (w - cylW * CGFloat(perBank)) / CGFloat(perBank + 1)
        return VStack(spacing: 0) {
            HStack(spacing: gap) {
                ForEach(0..<perBank, id: \.self) { _ in
                    Rectangle().stroke(color, lineWidth: 1)
                        .frame(width: cylW, height: h * 0.32)
                        .rotationEffect(.degrees(-15 * tilt))
                }
            }
            HStack(spacing: gap) {
                ForEach(0..<perBank, id: \.self) { _ in
                    Rectangle().stroke(color, lineWidth: 1)
                        .frame(width: cylW, height: h * 0.32)
                        .rotationEffect(.degrees(15 * tilt))
                }
            }
        }
        .padding(.horizontal, gap)
    }

    /// Boxer layout: cylinders lie flat on either side of a vertical crank
    /// line. Each side has perBank cylinders stacked vertically.
    private func flatSilhouette(w: CGFloat, h: CGFloat, count n: Int, color: Color) -> some View {
        let perBank = n / 2
        let crankWidth: CGFloat = 4
        let sideWidth = (w - crankWidth) / 2
        let cylH = (h * 0.7) / CGFloat(perBank) * 0.7
        let rowGap = (h * 0.7 - cylH * CGFloat(perBank)) / CGFloat(perBank + 1)
        let cylW = sideWidth * 0.7

        return HStack(spacing: 0) {
            VStack(spacing: rowGap) {
                ForEach(0..<perBank, id: \.self) { _ in
                    Rectangle().stroke(color, lineWidth: 1)
                        .frame(width: cylW, height: cylH)
                }
            }
            .frame(width: sideWidth, height: h * 0.7, alignment: .trailing)

            Rectangle()
                .fill(color.opacity(0.7))
                .frame(width: crankWidth, height: h * 0.78)

            VStack(spacing: rowGap) {
                ForEach(0..<perBank, id: \.self) { _ in
                    Rectangle().stroke(color, lineWidth: 1)
                        .frame(width: cylW, height: cylH)
                }
            }
            .frame(width: sideWidth, height: h * 0.7, alignment: .leading)
        }
        .frame(width: w, height: h)
    }
}

// MARK: - Bottom End

struct BottomEndStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 22) {
                BuilderSectionHeading(title: "Step 3 · Bottom end")

                BigReadout(value: String(format: "%.2f", state.spec.displacementLitres),
                           unit: "L", label: "Displacement")
                    .padding(.bottom, 12)

                BuilderSlider(label: "Bore", value: $state.spec.boreMm,
                              range: 60...110, step: 0.5, unit: "mm")
                BuilderSlider(label: "Stroke", value: $state.spec.strokeMm,
                              range: 50...110, step: 0.5, unit: "mm")
                BuilderSlider(label: "Rod length", value: $state.spec.rodLengthMm,
                              range: 100...200, step: 0.5, unit: "mm")
                BuilderSlider(label: "Compression height", value: $state.spec.compressionHeightMm,
                              range: 20...50, step: 0.1, unit: "mm")
            }
            .frame(maxWidth: 480)

            VStack(spacing: 24) {
                BuilderSectionHeading(title: "Cylinder")
                CylinderSection(boreMm: state.spec.boreMm,
                                 strokeMm: state.spec.strokeMm,
                                 rodLengthMm: state.spec.rodLengthMm,
                                 compressionHeightMm: state.spec.compressionHeightMm)
                    .frame(width: 240, height: 340)
                HStack {
                    StatBox(label: "B / S", value: String(format: "%.2f", state.spec.boreMm / state.spec.strokeMm))
                    StatBox(label: "R / S", value: String(format: "%.2f", state.spec.rodLengthMm / state.spec.strokeMm))
                }
                .frame(width: 240)
            }
            Spacer()
        }
    }
}

/// Side cross-section of one cylinder. All sliders move what you'd expect:
/// - bore   → cylinder & piston width
/// - stroke → crank-circle radius + piston travel (BDC ghost drops further)
/// - rod    → wrist-pin → crank-journal distance (cylinder deck rises)
/// - comp.h → piston body height
private struct CylinderSection: View {
    let boreMm: Double
    let strokeMm: Double
    let rodLengthMm: Double
    let compressionHeightMm: Double

    var body: some View {
        GeometryReader { proxy in
            let layout = CylinderLayout(viewSize: proxy.size,
                                        boreMm: boreMm,
                                        strokeMm: strokeMm,
                                        rodLengthMm: rodLengthMm,
                                        compressionHeightMm: compressionHeightMm)

            ZStack {
                bdcGhost(layout: layout)
                cylinderHead(layout: layout)
                cylinderWalls(layout: layout)
                piston(layout: layout)
                connectingRod(layout: layout)
                crankCircle(layout: layout)
                dimensions(layout: layout)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func bdcGhost(layout: CylinderLayout) -> some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: CylinderDiagram.ghostStrokeWidth,
                                       dash: CylinderDiagram.dashPattern))
            .foregroundColor(BuilderTheme.line)
            .frame(width: layout.pistonWidth, height: layout.pistonHeight)
            .position(x: layout.centerX, y: layout.bdcPistonCenterY)
    }

    private func cylinderHead(layout: CylinderLayout) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .overlay(Rectangle().stroke(BuilderTheme.line,
                                        lineWidth: CylinderDiagram.boreWallThickness))
            .frame(width: layout.headWidth, height: layout.headHeight)
            .position(x: layout.centerX, y: layout.headCenterY)
    }

    private func cylinderWalls(layout: CylinderLayout) -> some View {
        Path { p in
            p.move(to: CGPoint(x: layout.boreLeftX, y: layout.boreTopY))
            p.addLine(to: CGPoint(x: layout.boreLeftX, y: layout.boreBottomY))
            p.move(to: CGPoint(x: layout.boreRightX, y: layout.boreTopY))
            p.addLine(to: CGPoint(x: layout.boreRightX, y: layout.boreBottomY))
        }
        .stroke(Color.white.opacity(0.7), lineWidth: CylinderDiagram.boreWallThickness)
    }

    private func piston(layout: CylinderLayout) -> some View {
        ZStack {
            Rectangle()
                .fill(BuilderTheme.accent.opacity(0.55))
                .frame(width: layout.pistonWidth, height: layout.pistonHeight)
                .overlay(
                    VStack(spacing: CylinderDiagram.pistonRingGap) {
                        Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1)
                        Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1)
                    }
                    .padding(.horizontal, 3)
                    .padding(.top, 6),
                    alignment: .top
                )
            Circle()
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
                .frame(width: CylinderDiagram.wristPinRadius * 2,
                       height: CylinderDiagram.wristPinRadius * 2)
                .position(x: layout.pistonWidth / 2, y: layout.wristPinOffsetY)
        }
        .frame(width: layout.pistonWidth, height: layout.pistonHeight)
        .position(x: layout.centerX, y: layout.tdcPistonCenterY)
    }

    private func connectingRod(layout: CylinderLayout) -> some View {
        let rodWidth = max(4, layout.pistonWidth * CylinderDiagram.rodWidthRatioOfBore)
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: layout.centerX, y: layout.wristPinY))
                p.addLine(to: CGPoint(x: layout.centerX, y: layout.crankJournalAtTDCY))
            }
            .stroke(Color.white.opacity(0.75), lineWidth: rodWidth)

            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                .frame(width: CylinderDiagram.rodSmallEndRadius * 2,
                       height: CylinderDiagram.rodSmallEndRadius * 2)
                .position(x: layout.centerX, y: layout.wristPinY)

            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                .frame(width: layout.bigEndDiameter, height: layout.bigEndDiameter)
                .position(x: layout.centerX, y: layout.crankJournalAtTDCY)
        }
    }

    private func crankCircle(layout: CylinderLayout) -> some View {
        ZStack {
            Circle()
                .stroke(BuilderTheme.line, lineWidth: 1)
                .frame(width: layout.crankCircleDiameter, height: layout.crankCircleDiameter)
                .position(x: layout.centerX, y: layout.crankCenterY)
            Circle()
                .fill(BuilderTheme.accent)
                .frame(width: 4, height: 4)
                .position(x: layout.centerX, y: layout.crankCenterY)
        }
    }

    private func dimensions(layout: CylinderLayout) -> some View {
        // Bore label on top, stroke marker on right, rod marker on left.
        ZStack {
            Text("BORE \(Int(boreMm)) mm")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(BuilderTheme.label)
                .position(x: layout.centerX, y: layout.headCenterY - layout.headHeight / 2 - 8)

            Text("STROKE \(Int(strokeMm))")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(BuilderTheme.accent)
                .position(x: layout.boreRightX + 26,
                          y: (layout.tdcPistonCenterY + layout.bdcPistonCenterY) / 2)

            Text("ROD \(Int(rodLengthMm))")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(BuilderTheme.label)
                .position(x: layout.boreLeftX - 22,
                          y: (layout.wristPinY + layout.crankJournalAtTDCY) / 2)
        }
    }
}

/// Pure-data layout for the cylinder cross-section. Keeps the view body simple.
private struct CylinderLayout {
    let centerX: CGFloat

    // Vertical anchors (top-down in view coords).
    let headCenterY: CGFloat
    let headHeight: CGFloat
    let headWidth: CGFloat

    let boreTopY: CGFloat
    let boreBottomY: CGFloat
    let boreLeftX: CGFloat
    let boreRightX: CGFloat

    let tdcPistonCenterY: CGFloat
    let bdcPistonCenterY: CGFloat
    let pistonWidth: CGFloat
    let pistonHeight: CGFloat
    let wristPinOffsetY: CGFloat   // y inside the piston rectangle (top-relative)
    let wristPinY: CGFloat         // y in view coords at TDC
    let crankJournalAtTDCY: CGFloat
    let crankCenterY: CGFloat
    let crankCircleDiameter: CGFloat
    let bigEndDiameter: CGFloat

    init(viewSize: CGSize,
         boreMm: Double,
         strokeMm: Double,
         rodLengthMm: Double,
         compressionHeightMm: Double) {
        // Per-element heights derived from the actual values.
        let chamberClearanceMm = boreMm * Double(CylinderDiagram.chamberClearanceRatioOfBore)
        let headHeightMm = boreMm * Double(CylinderDiagram.headThicknessRatioOfBore)
        let pistonHeightMm = compressionHeightMm + chamberClearanceMm * 0.5
        let crankRadiusMm = strokeMm / 2

        // *** Stable scale ***
        // Compute scale from the SLIDER MAXIMA, not the current values, so
        // adjusting one slider only moves the element it controls — every
        // other element stays where it is. The diagram fills less of the
        // canvas at low values, which is correct behaviour.
        let maxBore = CylinderDiagram.maxBoreMm
        let maxChamberClearance = maxBore * Double(CylinderDiagram.chamberClearanceRatioOfBore)
        let maxHeadHeight = maxBore * Double(CylinderDiagram.headThicknessRatioOfBore)
        let maxPistonHeight = CylinderDiagram.maxCompressionHeightMm + maxChamberClearance * 0.5
        let maxCrankRadius = CylinderDiagram.maxStrokeMm / 2

        // Total geometry from the top of the head all the way down to the
        // bottom of the crank circle (both halves), plus a breathing margin.
        let maxTotalHeightMm = maxHeadHeight
            + maxChamberClearance
            + maxPistonHeight
            + CylinderDiagram.maxStrokeMm
            + CylinderDiagram.maxRodLengthMm
            + maxCrankRadius                     // journal-at-TDC → crank center
            + maxCrankRadius                     // crank center → bottom of crank circle
            + CylinderDiagram.canvasBottomMarginMm
        let maxTotalWidthMm = CylinderDiagram.maxBoreMm + CylinderDiagram.canvasWidthSlackMm

        let scaleY = viewSize.height * CylinderDiagram.viewportFillFraction / maxTotalHeightMm
        let scaleX = viewSize.width  * CylinderDiagram.viewportFillFraction / maxTotalWidthMm
        let scale = CGFloat(min(scaleX, scaleY))

        // *** Stable crank anchor ***
        // Crank center is locked vertically — placed so that the full crank
        // circle (one radius below it) plus a small margin fits inside the
        // canvas. The head / bore then follow the piston upward from here, so
        // there's no oversized empty cylinder above TDC at small slider values.
        let crankAnchorYMm = maxHeadHeight
            + maxChamberClearance
            + maxPistonHeight
            + CylinderDiagram.maxStrokeMm
            + CylinderDiagram.maxRodLengthMm
            + maxCrankRadius
        let topMargin = (viewSize.height - CGFloat(maxTotalHeightMm) * scale) / 2

        func y(_ mm: Double) -> CGFloat { topMargin + CGFloat(mm) * scale }

        let bore   = CGFloat(boreMm)             * scale
        let stroke = CGFloat(strokeMm)           * scale
        let rod    = CGFloat(rodLengthMm)        * scale
        let pistonH = CGFloat(pistonHeightMm)    * scale
        let headH  = CGFloat(headHeightMm)       * scale
        let chamberClear = CGFloat(chamberClearanceMm) * scale

        self.centerX = viewSize.width / 2

        // Crank center is locked to the canvas (does not move with rod / stroke).
        self.crankCenterY = y(crankAnchorYMm)
        // Crank journal at TDC sits one crank-radius ABOVE the locked crank center.
        self.crankJournalAtTDCY = self.crankCenterY - CGFloat(crankRadiusMm) * scale
        // Wrist pin is one rod-length above the crank journal at TDC.
        self.wristPinY = self.crankJournalAtTDCY - rod
        // Piston body extends from wrist pin upward to its crown.
        let pistonTopAtTDC = self.wristPinY - pistonH * 0.7
        self.wristPinOffsetY = pistonH * 0.7
        self.tdcPistonCenterY = pistonTopAtTDC + pistonH / 2
        self.bdcPistonCenterY = self.tdcPistonCenterY + stroke

        // Bore wraps the piston travel with only chamber clearance above TDC
        // and a small overhang below BDC. The head sits directly on top of
        // the bore — no oversized gap between deck and piston crown.
        self.boreTopY = pistonTopAtTDC - chamberClear
        self.boreBottomY = self.bdcPistonCenterY + pistonH / 2
            + CGFloat(CylinderDiagram.boreBottomOverhangMm) * scale
        self.boreLeftX = centerX - bore / 2
        self.boreRightX = centerX + bore / 2

        self.headHeight = headH
        self.headWidth = bore + 16
        self.headCenterY = self.boreTopY - headH / 2

        self.pistonWidth = max(4, bore - CGFloat(CylinderDiagram.pistonInsetFromBore))
        self.pistonHeight = pistonH

        self.crankCircleDiameter = CGFloat(crankRadiusMm) * scale * 2
        self.bigEndDiameter = max(8, stroke * CGFloat(CylinderDiagram.bigEndRadiusRatioOfStroke) * 2)
    }
}

private struct StatBox: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(BuilderTheme.label)
            Text(value)
                .font(.system(size: 18, weight: .regular, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .overlay(Rectangle().stroke(BuilderTheme.line, lineWidth: 1))
    }
}

// MARK: - Cam

struct CamStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 22) {
                BuilderSectionHeading(title: "Step 4 · Camshaft")
                Text("The lobe on the cam shaft pushes a valve open as the cam rotates.\nA bigger lobe (more duration, more lift) lets the valve stay open\nlonger and open further — better at high RPM, worse at idle.")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .lineSpacing(4)

                CamSliderRow(label: "Duration @ 0.050″",
                             help: "How many crank degrees the valve stays open.",
                             value: $state.spec.camDurationDeg,
                             range: 180...290, step: 1, unit: "°")
                CamSliderRow(label: "Max lift",
                             help: "How far the valve opens at peak.",
                             value: $state.spec.camLiftMm,
                             range: 6...14, step: 0.1, unit: "mm")
                CamSliderRow(label: "Lobe separation",
                             help: "Spacing between intake & exhaust peaks. Tighter = more overlap.",
                             value: $state.spec.camLobeSeparationDeg,
                             range: 100...124, step: 0.5, unit: "°")
                CamSliderRow(label: "Cam advance",
                             help: "Shifts the intake lobe earlier (+) or later (−).",
                             value: $state.spec.camAdvanceDeg,
                             range: -10...10, step: 0.5, unit: "°")
            }
            .frame(maxWidth: 480)

            VStack(alignment: .leading, spacing: 18) {
                BuilderSectionHeading(title: "Lobe shape")
                CamLobeProfile(durationDeg: state.spec.camDurationDeg,
                                liftMm: state.spec.camLiftMm)
                    .frame(width: 240, height: 180)

                BuilderSectionHeading(title: "Valve events across 720°")
                ValveEventTimeline(durationDeg: state.spec.camDurationDeg,
                                    lobeSeparationDeg: state.spec.camLobeSeparationDeg,
                                    advanceDeg: state.spec.camAdvanceDeg)
                    .frame(width: 360, height: 110)

                CamLegend(durationDeg: state.spec.camDurationDeg,
                          liftMm: state.spec.camLiftMm,
                          lobeSeparationDeg: state.spec.camLobeSeparationDeg,
                          advanceDeg: state.spec.camAdvanceDeg,
                          overlapDeg: overlapDeg(state.spec))
                    .frame(width: 360)
            }
            Spacer()
        }
    }

    /// Approximate valve overlap in crank degrees (cam degrees × 2):
    /// width by which intake/exhaust events overlap around TDC.
    private func overlapDeg(_ spec: EngineSpec) -> Double {
        max(0, spec.camDurationDeg - spec.camLobeSeparationDeg * 2 + spec.camAdvanceDeg * 2)
    }
}

/// A slider row with an inline help blurb so the user understands what each
/// control does without having to know what duration / LSA / advance mean.
private struct CamSliderRow: View {
    let label: String
    let help: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            BuilderSlider(label: label, value: $value, range: range,
                          step: step, unit: unit)
            Text(help)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.dim)
        }
    }
}

/// Side-view of a single cam lobe: base circle plus a bump that is wider
/// when duration grows and taller when lift grows. This is what a real cam
/// lobe looks like — much more intuitive than a lift-vs-angle plot.
private struct CamLobeProfile: View {
    let durationDeg: Double
    let liftMm: Double

    private let baseRadius: CGFloat = 50
    private let liftScale: CGFloat = 4   // pixels per mm of lift

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let liftPx = CGFloat(liftMm) * liftScale
            let halfBump = durationDeg / 2

            ZStack {
                // Base circle
                Circle()
                    .stroke(BuilderTheme.line, lineWidth: 1)
                    .frame(width: baseRadius * 2, height: baseRadius * 2)
                    .position(center)

                // Lobe outline (base circle + bump at the top)
                Path { p in
                    var first = true
                    let steps = 200
                    for i in 0...steps {
                        let t = Double(i) / Double(steps)
                        // Sweep from 0..360° starting at the top (where the bump sits).
                        let angle = -90.0 + t * 360.0
                        let withinBump = abs(angularDelta(angle, -90)) <= halfBump
                        let r: CGFloat
                        if withinBump {
                            let normalized = abs(angularDelta(angle, -90)) / halfBump
                            let bump = pow(cos(normalized * .pi / 2), 2)
                            r = baseRadius + liftPx * CGFloat(bump)
                        } else {
                            r = baseRadius
                        }
                        let rad = angle * .pi / 180
                        let pt = CGPoint(x: center.x + r * CGFloat(cos(rad)),
                                         y: center.y + r * CGFloat(sin(rad)))
                        if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                    }
                    p.closeSubpath()
                }
                .fill(BuilderTheme.accent.opacity(0.2))
                .overlay(
                    Path { p in
                        var first = true
                        let steps = 200
                        for i in 0...steps {
                            let t = Double(i) / Double(steps)
                            let angle = -90.0 + t * 360.0
                            let withinBump = abs(angularDelta(angle, -90)) <= halfBump
                            let r: CGFloat
                            if withinBump {
                                let normalized = abs(angularDelta(angle, -90)) / halfBump
                                let bump = pow(cos(normalized * .pi / 2), 2)
                                r = baseRadius + liftPx * CGFloat(bump)
                            } else {
                                r = baseRadius
                            }
                            let rad = angle * .pi / 180
                            let pt = CGPoint(x: center.x + r * CGFloat(cos(rad)),
                                             y: center.y + r * CGFloat(sin(rad)))
                            if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                        }
                        p.closeSubpath()
                    }
                    .stroke(BuilderTheme.accent, lineWidth: 1.5)
                )

                // Lift callout
                Path { p in
                    p.move(to: CGPoint(x: center.x, y: center.y - baseRadius))
                    p.addLine(to: CGPoint(x: center.x, y: center.y - baseRadius - liftPx))
                }
                .stroke(BuilderTheme.accent, style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))

                Text(String(format: "%.1f mm", liftMm))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(BuilderTheme.accent)
                    .position(x: center.x + 30,
                              y: center.y - baseRadius - liftPx / 2)

                Text(String(format: "%.0f°", durationDeg))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .position(x: center.x, y: center.y + baseRadius + 12)

                // Cam shaft center
                Circle()
                    .fill(BuilderTheme.line)
                    .frame(width: 6, height: 6)
                    .position(center)
            }
        }
    }

    private func angularDelta(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }
}

/// Linear timeline showing the intake and exhaust open-windows across one
/// full crank cycle (720°). TDC marks at 0/720, BDC at 360. The overlap
/// region around TDC is highlighted.
private struct ValveEventTimeline: View {
    let durationDeg: Double          // cam degrees @ 0.050"
    let lobeSeparationDeg: Double    // cam degrees between intake & exhaust centerlines
    let advanceDeg: Double           // cam degrees of intake advance

    private let crankCycleDeg: Double = 720

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            // Events in crank degrees (cam degrees × 2).
            let durationCrank = durationDeg * 2
            let lsaCrank = lobeSeparationDeg * 2
            let advCrank = advanceDeg * 2

            // Intake centerline is 90° ATDC + advance shift on crank.
            let intakeCenter = 90.0 + lsaCrank / 2 - advCrank
            let exhaustCenter = 90.0 - lsaCrank / 2 - advCrank

            let intakeOpen = intakeCenter - durationCrank / 2
            let intakeClose = intakeCenter + durationCrank / 2
            let exhaustOpen = exhaustCenter - durationCrank / 2 + crankCycleDeg / 2
            let exhaustClose = exhaustCenter + durationCrank / 2 + crankCycleDeg / 2

            ZStack(alignment: .topLeading) {
                Rectangle().stroke(BuilderTheme.line, lineWidth: 1)

                // TDC / BDC / TDC tick marks
                tickMark(angle: 0, label: "TDC", w: w, h: h, color: BuilderTheme.label)
                tickMark(angle: 360, label: "BDC", w: w, h: h, color: BuilderTheme.label)
                tickMark(angle: 720, label: "TDC", w: w, h: h, color: BuilderTheme.label)

                // Exhaust window (white)
                eventBar(openDeg: exhaustOpen, closeDeg: exhaustClose,
                          color: Color.white.opacity(0.45),
                          label: "EXHAUST", w: w, yFrac: 0.40)

                // Intake window (accent)
                eventBar(openDeg: intakeOpen, closeDeg: intakeClose,
                          color: BuilderTheme.accent.opacity(0.85),
                          label: "INTAKE", w: w, yFrac: 0.66)
            }
        }
    }

    private func tickMark(angle: Double, label: String,
                           w: CGFloat, h: CGFloat, color: Color) -> some View {
        let x = w * CGFloat(angle / crankCycleDeg)
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: h))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(color)
                .position(x: x, y: 10)
        }
    }

    private func eventBar(openDeg: Double, closeDeg: Double,
                           color: Color, label: String,
                           w: CGFloat, yFrac: CGFloat) -> some View {
        // The bar may wrap past 720°; draw up to two segments.
        let segments = wrappedSegments(open: openDeg, close: closeDeg)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                let x0 = w * CGFloat(seg.start / crankCycleDeg)
                let x1 = w * CGFloat(seg.end / crankCycleDeg)
                Rectangle()
                    .fill(color)
                    .frame(width: max(0, x1 - x0), height: 18)
                    .position(x: (x0 + x1) / 2, y: 18 * yFrac + 18)
            }
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(color.opacity(1))
                .position(x: 38, y: 18 * yFrac + 18)
        }
    }

    /// Splits an event window into one or two segments inside [0, 720].
    private func wrappedSegments(open: Double, close: Double) -> [(start: Double, end: Double)] {
        var o = open.truncatingRemainder(dividingBy: crankCycleDeg)
        var c = close.truncatingRemainder(dividingBy: crankCycleDeg)
        if o < 0 { o += crankCycleDeg }
        if c < 0 { c += crankCycleDeg }
        if c >= o {
            return [(o, c)]
        } else {
            // Wrapped past 720.
            return [(o, crankCycleDeg), (0, c)]
        }
    }
}


private struct CamLegend: View {
    let durationDeg: Double
    let liftMm: Double
    let lobeSeparationDeg: Double
    let advanceDeg: Double
    let overlapDeg: Double

    var body: some View {
        HStack(spacing: 14) {
            legendItem(label: "DUR", value: "\(Int(durationDeg))°")
            legendItem(label: "LIFT", value: String(format: "%.1fmm", liftMm))
            legendItem(label: "LSA", value: "\(Int(lobeSeparationDeg))°")
            legendItem(label: "ADV", value: String(format: "%+.1f°", advanceDeg))
            legendItem(label: "OVERLAP", value: "\(Int(overlapDeg))°", highlight: true)
        }
    }

    private func legendItem(label: String, value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(BuilderTheme.label)
            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(highlight ? BuilderTheme.accent : .white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Firing Order

private enum FiringOrderDiagram {
    static let chipSize: CGFloat = 56
    static let chipSpacing: CGFloat = 10
    static let stepInterval: Double = 0.45     // seconds per cylinder fire in the preview
    static let lightBumpDuration: Double = 0.35
    static let diagramSize: CGFloat = 240
}

/// Drag-to-reorder firing order editor.
///
/// `state.spec.firingOrder` always contains every cylinder (1...N). The user
/// just drags chips to change the order — no separate palette / pool of
/// unassigned cylinders. The preview on the right shows the engine layout
/// with each cylinder pulsing orange in the chosen order.
struct FiringOrderStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 22) {
                BuilderSectionHeading(title: "Step 5 · Firing order")
                Text("Drag a cylinder to a new position to reorder.\nThe preview on the right cycles through your firing order.")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .lineSpacing(4)

                DraggableFiringSequence(order: orderBinding,
                                         bankCount: state.spec.layout.bankCount)

                HStack(spacing: 10) {
                    builderChip(label: "USE DEFAULT", action: useLayoutDefault)
                    Spacer()
                    Text("ORDER · \(state.spec.firingOrder.map(String.init).joined(separator: "-"))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(BuilderTheme.accent)
                }
                .frame(maxWidth: 600)
            }
            .frame(maxWidth: 600)

            VStack(spacing: 14) {
                BuilderSectionHeading(title: "Firing preview")
                FiringAnimation(layout: state.spec.layout,
                                 order: state.spec.firingOrder)
                    .frame(width: FiringOrderDiagram.diagramSize,
                           height: FiringOrderDiagram.diagramSize)
                Text("Each cylinder pulses as it fires.\nEven spacing = smoother engine.")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .lineSpacing(3)
                    .frame(width: FiringOrderDiagram.diagramSize, alignment: .leading)
            }
            Spacer()
        }
        .onAppear { ensureFullOrder() }
    }

    private var orderBinding: Binding<[Int]> {
        Binding(
            get: { state.spec.firingOrder },
            set: { state.spec.firingOrder = $0 }
        )
    }

    /// Drag reordering assumes every cylinder is in the array. If something
    /// upstream left it incomplete, snap to the layout default the moment
    /// this step appears.
    private func ensureFullOrder() {
        if !state.spec.firingOrderIsValid {
            state.spec.resyncFiringOrderForLayout()
        }
    }

    private func builderChip(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(BuilderTheme.label)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .overlay(Rectangle().stroke(BuilderTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func useLayoutDefault() {
        state.spec.resyncFiringOrderForLayout()
    }
}

/// Horizontal stack of cylinder chips. Each chip can be dragged onto another
/// to swap its position. Built on SwiftUI's `.onDrag`/`.onDrop` for the
/// reorder swap because the row isn't inside a `List` (where `.onMove` lives).
private struct DraggableFiringSequence: View {
    @Binding var order: [Int]
    let bankCount: Int
    @State private var draggingCylinder: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                BuilderSectionHeading(title: "Firing sequence")
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(BuilderTheme.accent)
                Text("DRAG CHIPS TO REORDER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(BuilderTheme.label)
            }

            LazyVGrid(columns: gridColumns,
                      alignment: .leading,
                      spacing: FiringOrderDiagram.chipSpacing) {
                ForEach(Array(order.enumerated()), id: \.element) { idx, cyl in
                    chip(position: idx + 1, cylinder: cyl)
                        .onDrag {
                            draggingCylinder = cyl
                            return NSItemProvider(object: String(cyl) as NSString)
                        }
                        .onDrop(of: [.text],
                                delegate: SwapDropDelegate(target: cyl,
                                                           order: $order,
                                                           dragging: $draggingCylinder))
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(FiringOrderDiagram.chipSize),
                                  spacing: FiringOrderDiagram.chipSpacing),
              count: min(order.count, 8))
    }

    /// Each chip wears a small grip glyph on top — combined with the
    /// open-hand cursor on hover, the drag affordance reads at a glance.
    private func chip(position: Int, cylinder: Int) -> some View {
        let lifted = draggingCylinder == cylinder
        return ZStack {
            VStack(spacing: 2) {
                Text("\(position).")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.black.opacity(0.6))
                Text("\(cylinder)")
                    .font(.system(size: 22, weight: .regular, design: .monospaced))
                    .foregroundColor(.black)
                if bankCount > 1 {
                    Text(bankFor(cylinder: cylinder))
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.black.opacity(0.45))
                }
            }

            // Drag handle in the top-right corner.
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.black.opacity(0.45))
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                }
                Spacer()
            }
        }
        .frame(width: FiringOrderDiagram.chipSize,
               height: FiringOrderDiagram.chipSize)
        .background(BuilderTheme.accent)
        .overlay(Rectangle().stroke(BuilderTheme.accent, lineWidth: 1.5))
        .opacity(lifted ? 0.4 : 1.0)
        .scaleEffect(lifted ? 0.96 : 1.0)
        .animation(.easeOut(duration: 0.12), value: lifted)
        .onHover { inside in
            if inside { NSCursor.openHand.push() }
            else { NSCursor.pop() }
        }
    }

    private func bankFor(cylinder: Int) -> String {
        cylinder.isMultiple(of: 2) ? "B" : "A"
    }
}

/// Swaps the dragged cylinder with the drop target in the order array. We
/// swap instead of insert so the array always retains every cylinder exactly
/// once — that's the constraint of a firing order.
private struct SwapDropDelegate: DropDelegate {
    let target: Int
    @Binding var order: [Int]
    @Binding var dragging: Int?

    func dropEntered(info: DropInfo) {
        guard let src = dragging, src != target,
              let srcIdx = order.firstIndex(of: src),
              let dstIdx = order.firstIndex(of: target) else { return }
        if srcIdx != dstIdx {
            order.swapAt(srcIdx, dstIdx)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

/// Engine-layout diagram that pulses each cylinder in the user's specified
/// firing order. Pure-visual preview — no physics, just a rhythm cue so the
/// user can feel the spacing.
private struct FiringAnimation: View {
    let layout: EngineLayout
    let order: [Int]

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { context in
                let phase = animationPhase(at: context.date.timeIntervalSinceReferenceDate)
                drawLayout(in: proxy.size, phase: phase)
            }
        }
    }

    private func animationPhase(at time: TimeInterval)
        -> (currentCylinder: Int?, intensity: Double)
    {
        guard !order.isEmpty else { return (nil, 0) }
        let stepInterval = FiringOrderDiagram.stepInterval
        let totalCycle = stepInterval * Double(order.count)
        let t = time.truncatingRemainder(dividingBy: totalCycle)
        let idx = Int(t / stepInterval) % order.count
        let bumpT = (t - Double(idx) * stepInterval) / FiringOrderDiagram.lightBumpDuration
        let intensity = bumpT >= 0 && bumpT <= 1 ? cos((bumpT - 0.5) * .pi) : 0
        return (order[idx], max(intensity, 0))
    }

    @ViewBuilder
    private func drawLayout(in size: CGSize,
                            phase: (currentCylinder: Int?, intensity: Double)) -> some View {
        let positions = cylinderPositions(in: size)
        ZStack {
            ForEach(positions, id: \.cylinder) { entry in
                let isFiring = phase.currentCylinder == entry.cylinder
                let glow = isFiring ? phase.intensity : 0

                Rectangle()
                    .fill(BuilderTheme.accent.opacity(0.18 + 0.65 * glow))
                    .overlay(Rectangle().stroke(BuilderTheme.accent.opacity(0.4 + 0.6 * glow),
                                                 lineWidth: 1.5))
                    .frame(width: entry.size.width, height: entry.size.height)
                    .rotationEffect(.degrees(entry.rotationDeg))
                    .position(entry.center)
                    .shadow(color: BuilderTheme.accent.opacity(glow * 0.5),
                            radius: 4 * glow)

                Text("\(entry.cylinder)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6 + 0.4 * glow))
                    .position(entry.center)
            }
        }
    }

    /// Layout-specific positions for each cylinder rectangle. Falls back to
    /// a single horizontal row for inline engines and two angled banks for V
    /// / flat engines.
    private func cylinderPositions(in size: CGSize)
        -> [CylinderRender]
    {
        let n = layout.cylinderCount
        let banks = layout.bankCount
        if banks == 1 { return inlinePositions(n: n, size: size) }
        if layout.bankHalfAngleDeg >= 80 { return flatPositions(n: n, size: size) }
        return vPositions(n: n, size: size, halfAngleDeg: layout.bankHalfAngleDeg)
    }

    private func inlinePositions(n: Int, size: CGSize) -> [CylinderRender] {
        let cylW = size.width / CGFloat(n + 1)
        let cylH = size.height * 0.45
        let totalWidth = cylW * CGFloat(n) + CGFloat(n - 1) * 6
        let startX = (size.width - totalWidth) / 2 + cylW / 2

        return (0..<n).map { i in
            CylinderRender(
                cylinder: i + 1,
                center: CGPoint(x: startX + CGFloat(i) * (cylW + 6),
                                y: size.height / 2),
                size: CGSize(width: cylW, height: cylH),
                rotationDeg: 0
            )
        }
    }

    private func vPositions(n: Int, size: CGSize, halfAngleDeg: Double) -> [CylinderRender] {
        let perBank = n / 2
        let cylW = size.width / CGFloat(perBank + 1) * 0.9
        let cylH = size.height * 0.30
        let tilt = halfAngleDeg / 90.0 * 18.0
        let startX = (size.width - (cylW * CGFloat(perBank) + CGFloat(perBank - 1) * 6)) / 2 + cylW / 2

        var out: [CylinderRender] = []
        for i in 0..<perBank {
            // Bank A — top row, odd cylinder numbers in the firing-order
            // convention used elsewhere (1,3,5...)
            out.append(CylinderRender(
                cylinder: i * 2 + 1,
                center: CGPoint(x: startX + CGFloat(i) * (cylW + 6),
                                y: size.height * 0.30),
                size: CGSize(width: cylW, height: cylH),
                rotationDeg: -tilt
            ))
            // Bank B — bottom row, even cylinders.
            out.append(CylinderRender(
                cylinder: i * 2 + 2,
                center: CGPoint(x: startX + CGFloat(i) * (cylW + 6),
                                y: size.height * 0.70),
                size: CGSize(width: cylW, height: cylH),
                rotationDeg: tilt
            ))
        }
        return out
    }

    private func flatPositions(n: Int, size: CGSize) -> [CylinderRender] {
        let perBank = n / 2
        let cylW = size.width * 0.32
        let cylH = size.height / CGFloat(perBank + 1) * 0.75
        let startY = (size.height - (cylH * CGFloat(perBank) + CGFloat(perBank - 1) * 6)) / 2 + cylH / 2

        var out: [CylinderRender] = []
        for i in 0..<perBank {
            // Left bank — odd-numbered cylinders.
            out.append(CylinderRender(
                cylinder: i * 2 + 1,
                center: CGPoint(x: size.width * 0.27,
                                y: startY + CGFloat(i) * (cylH + 6)),
                size: CGSize(width: cylW, height: cylH),
                rotationDeg: 0
            ))
            // Right bank — even-numbered cylinders.
            out.append(CylinderRender(
                cylinder: i * 2 + 2,
                center: CGPoint(x: size.width * 0.73,
                                y: startY + CGFloat(i) * (cylH + 6)),
                size: CGSize(width: cylW, height: cylH),
                rotationDeg: 0
            ))
        }
        return out
    }
}

private struct CylinderRender {
    let cylinder: Int
    let center: CGPoint
    let size: CGSize
    let rotationDeg: Double
}

// MARK: - Induction

private enum IntakeDiagram {
    static let plenumMinFraction: CGFloat = 0.45
    static let plenumMaxFraction: CGFloat = 0.92
    static let runnerMinLengthFraction: CGFloat = 0.20
    static let runnerMaxLengthFraction: CGFloat = 0.55
    static let throttleBodyHeight: CGFloat = 22
    static let throttleBodyWidth: CGFloat = 40
    static let throttleStemHeight: CGFloat = 18
    static let throttleStemWidth: CGFloat = 8
    static let throttlePlateThickness: CGFloat = 2
    static let throttlePlateInsetPx: CGFloat = 6 // shaves the ends of the plate inside the body
    static let plenumHeight: CGFloat = 26
    static let portWidth: CGFloat = 14
    /// Port = vertical pipe stub that joins each runner to the head bar.
    /// Needs visible vertical extent so the junction reads like real plumbing.
    static let portHeight: CGFloat = 12
    static let headBarHeight: CGFloat = 8
    static let minRunnerSpacing: CGFloat = 18
    static let runnerCurveOffset: CGFloat = 8
    // Runner stroke maps from skinny (low cfm) to fat (high cfm) so changing
    // the Runner CFM slider visibly changes how much air the runners can pass.
    static let runnerStrokeMinPx: CGFloat = 2.5
    static let runnerStrokeMaxPx: CGFloat = 9.0
    // Throttle plate angle: 0° is wide-open horizontal, ±85° is nearly closed
    // vertical. The script idle_throttle_plate_position is a fraction where
    // 1.0 = fully closed and 0.0 = fully open.
    static let throttlePlateMaxAngleDeg: Double = 85
}

struct InductionStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            BuilderSectionHeading(title: "Step 6 · Induction")
            Text("How much air the engine can swallow at full throttle.\nIntake CFM is the headline number; the rest fine-tunes plenum response.")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.label)
                .lineSpacing(4)

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 20) {
                    BigReadout(value: "\(Int(state.spec.intakeCfm))",
                               unit: "cfm", label: "Intake")
                        .padding(.bottom, 8)

                    BuilderSlider(label: "Intake CFM", value: $state.spec.intakeCfm,
                                  range: 200...1200, step: 10, unit: "", format: "%.0f")
                    BuilderSlider(label: "Runner CFM", value: $state.spec.runnerCfm,
                                  range: 50...600, step: 5, unit: "", format: "%.0f")
                    BuilderSlider(label: "Runner length",
                                  value: $state.spec.intakeRunnerLengthIn,
                                  range: 4...40, step: 0.5, unit: "in")
                    BuilderSlider(label: "Plenum volume",
                                  value: $state.spec.intakePlenumVolumeL,
                                  range: 0.5...4.0, step: 0.05, unit: "L", format: "%.2f")
                    BuilderSlider(label: "Plenum CSA",
                                  value: $state.spec.intakePlenumAreaCm2,
                                  range: 5...60, step: 0.5, unit: "cm²")
                    BuilderSlider(label: "Idle throttle",
                                  value: $state.spec.idleThrottlePosition,
                                  range: 0.985...0.999, step: 0.0005, unit: "", format: "%.4f")
                }
                .frame(maxWidth: 440)

                VStack(spacing: 12) {
                    BuilderSectionHeading(title: "Manifold")
                    IntakeManifoldDiagram(plenumVolumeL: state.spec.intakePlenumVolumeL,
                                           runnerLengthIn: state.spec.intakeRunnerLengthIn,
                                           intakeCfm: state.spec.intakeCfm,
                                           runnerCfm: state.spec.runnerCfm,
                                           idleThrottlePosition: state.spec.idleThrottlePosition,
                                           cylinderCount: state.spec.layout.cylinderCount,
                                           bankCount: state.spec.layout.bankCount)
                        .frame(width: 360, height: 300)
                }
            }
            Spacer()
        }
    }
}

/// Front-view schematic of an intake manifold drawn as a coherent assembly:
///
///   throttle body
///       │
///   ┌───┴───┐  ← plenum (width grows with volume)
///   │       │
///  ─┴─ ─┴─ ─┴─    ← runners (length grows with runner length slider)
///   ▆   ▆   ▆     ← cylinder head ports (one per cylinder, numbered)
///  ═══════════    ← cylinder head bar
///
/// For V layouts the runners alternate odd/even, matching the bank-0/bank-1
/// cylinder mapping the MR writer emits.
private struct IntakeManifoldDiagram: View {
    let plenumVolumeL: Double
    let runnerLengthIn: Double
    let intakeCfm: Double
    let runnerCfm: Double
    let idleThrottlePosition: Double
    let cylinderCount: Int
    let bankCount: Int

    private let plenumVolumeRange: ClosedRange<Double> = 0.5...4.0
    private let runnerLengthRange: ClosedRange<Double> = 4...40
    private let cfmRange: ClosedRange<Double> = 200...1200
    private let runnerCfmRange: ClosedRange<Double> = 50...600
    private let idleThrottleRange: ClosedRange<Double> = 0.985...0.999

    var body: some View {
        GeometryReader { proxy in
            let layout = IntakeLayout(canvas: proxy.size,
                                       cylinderCount: cylinderCount,
                                       plenumFraction: scaledPlenumFraction,
                                       runnerFraction: scaledRunnerFraction)

            ZStack(alignment: .topLeading) {
                Rectangle().stroke(BuilderTheme.line, lineWidth: 1)

                // 1. Cylinder head bar — anchored to the bottom.
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                    .frame(width: layout.headBarWidth, height: IntakeDiagram.headBarHeight)
                    .position(x: layout.centerX, y: layout.headBarY)

                // 2. Cylinder ports — thick vertical pipe stubs joining each
                // runner to the head bar. Drawn AFTER the runners below so the
                // stubs cap the runner ends cleanly.
                ForEach(0..<cylinderCount, id: \.self) { i in
                    let portX = layout.portX(at: i)
                    Text("\(i + 1)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(BuilderTheme.label)
                        .position(x: portX,
                                  y: layout.headBarY + IntakeDiagram.headBarHeight)
                }

                // 3. Runners — straight tubes from the plenum down to each port.
                ForEach(0..<cylinderCount, id: \.self) { i in
                    let portX = layout.portX(at: i)
                    let plenumOutletX = layout.plenumOutletX(at: i)
                    let plenumOutletY = layout.plenumBottomY
                    let runnerEndY = layout.headBarY - IntakeDiagram.portHeight
                    Path { p in
                        p.move(to: CGPoint(x: plenumOutletX, y: plenumOutletY))
                        // Slight curve so wide-spaced banks don't look like crooked sticks.
                        p.addQuadCurve(
                            to: CGPoint(x: portX, y: runnerEndY),
                            control: CGPoint(x: portX,
                                             y: plenumOutletY + IntakeDiagram.runnerCurveOffset)
                        )
                    }
                    .stroke(Color.white.opacity(0.85),
                            style: StrokeStyle(lineWidth: runnerStrokeWidth, lineCap: .round))
                }

                // Port stubs drawn on top of runner ends so the junction has
                // real visible thickness instead of a sliver of color.
                ForEach(0..<cylinderCount, id: \.self) { i in
                    let portX = layout.portX(at: i)
                    Rectangle()
                        .fill(BuilderTheme.accent)
                        .overlay(Rectangle().stroke(BuilderTheme.accent.opacity(0.9),
                                                    lineWidth: 1))
                        .frame(width: IntakeDiagram.portWidth,
                               height: IntakeDiagram.portHeight)
                        .position(x: portX,
                                  y: layout.headBarY - IntakeDiagram.portHeight / 2)
                }

                // 4. Plenum — fixed-position rectangle on top of the runners.
                Rectangle()
                    .fill(BuilderTheme.accent.opacity(0.25 + flowGlow * 0.4))
                    .overlay(Rectangle().stroke(BuilderTheme.accent, lineWidth: 1.5))
                    .frame(width: layout.plenumWidth, height: IntakeDiagram.plenumHeight)
                    .position(x: layout.centerX, y: layout.plenumCenterY)

                // 5. Throttle assembly — body, plate, stem are placed as
                // independent absolutely-positioned shapes so the plate
                // pivots around the body's geometric center and the stem
                // always meets the plenum top, regardless of plate angle.
                throttleStem
                    .position(x: layout.centerX, y: layout.throttleStemCenterY)
                throttleBodyBlock
                    .position(x: layout.centerX, y: layout.throttleBodyCenterY)
                throttlePlate
                    .position(x: layout.centerX, y: layout.throttleBodyCenterY)

                // 6. CFM badge bottom-right.
                cfmBadge
                    .position(x: proxy.size.width - 44, y: proxy.size.height - 26)

                // 7. Bank labels for V layouts.
                if bankCount == 2 {
                    Text("BANK A  ←        →  BANK B")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(BuilderTheme.label)
                        .position(x: layout.centerX,
                                  y: layout.headBarY + IntakeDiagram.headBarHeight + 18)
                }
            }
        }
    }

    private var scaledPlenumFraction: CGFloat {
        IntakeMath.lerp(plenumVolumeL,
                        from: plenumVolumeRange,
                        to: IntakeDiagram.plenumMinFraction...IntakeDiagram.plenumMaxFraction)
    }

    private var scaledRunnerFraction: CGFloat {
        IntakeMath.lerp(runnerLengthIn,
                        from: runnerLengthRange,
                        to: IntakeDiagram.runnerMinLengthFraction...IntakeDiagram.runnerMaxLengthFraction)
    }

    private var flowGlow: CGFloat {
        IntakeMath.lerp(intakeCfm, from: cfmRange, to: 0.15...0.95)
    }

    private var runnerStrokeWidth: CGFloat {
        IntakeMath.lerp(runnerCfm, from: runnerCfmRange,
                        to: IntakeDiagram.runnerStrokeMinPx...IntakeDiagram.runnerStrokeMaxPx)
    }

    /// Plate rotation in degrees. The script value is a near-closed fraction
    /// (e.g. 0.985 = barely open, 0.999 = nearly shut), so the closer to 1.0
    /// the closer to vertical the plate rotates.
    private var throttlePlateAngleDeg: Double {
        let clamped = min(max(idleThrottlePosition,
                              idleThrottleRange.lowerBound),
                          idleThrottleRange.upperBound)
        let span = idleThrottleRange.upperBound - idleThrottleRange.lowerBound
        let t = span > 0 ? (clamped - idleThrottleRange.lowerBound) / span : 0
        return -IntakeDiagram.throttlePlateMaxAngleDeg * t
    }

    /// Hollow rectangle — the throttle bore housing.
    private var throttleBodyBlock: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .overlay(Rectangle().stroke(Color.white.opacity(0.8), lineWidth: 1))
            .frame(width: IntakeDiagram.throttleBodyWidth,
                   height: IntakeDiagram.throttleBodyHeight)
    }

    /// The pivoting plate inside the body. Drawn as a real Rectangle (not a
    /// Path) so its bounding box is well-defined and `.rotationEffect` always
    /// pivots around the body's geometric center.
    private var throttlePlate: some View {
        Rectangle()
            .fill(BuilderTheme.accent)
            .frame(width: IntakeDiagram.throttleBodyWidth
                          - IntakeDiagram.throttlePlateInsetPx * 2,
                   height: IntakeDiagram.throttlePlateThickness)
            .rotationEffect(.degrees(throttlePlateAngleDeg))
    }

    /// Solid stub joining the throttle body to the plenum top.
    private var throttleStem: some View {
        Rectangle()
            .fill(BuilderTheme.accent)
            .frame(width: IntakeDiagram.throttleStemWidth,
                   height: IntakeDiagram.throttleStemHeight)
    }

    private var cfmBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("CFM")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(BuilderTheme.label)
            Text(String(format: "%.0f", intakeCfm))
                .font(.system(size: 18, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.accent)
        }
    }
}

/// Lays out the connected pieces of the intake manifold so the runners
/// actually meet the plenum and the ports actually meet the head bar.
private struct IntakeLayout {
    let canvas: CGSize
    let cylinderCount: Int
    let plenumFraction: CGFloat
    let runnerFraction: CGFloat

    var centerX: CGFloat { canvas.width / 2 }

    var plenumWidth: CGFloat { canvas.width * plenumFraction }
    var headBarWidth: CGFloat {
        max(plenumWidth,
            CGFloat(cylinderCount) * (IntakeDiagram.portWidth
                                       + IntakeDiagram.minRunnerSpacing))
    }

    var throttleTopY: CGFloat { 14 }
    var throttleBodyCenterY: CGFloat {
        throttleTopY + IntakeDiagram.throttleBodyHeight / 2
    }
    /// Center of the stem so it bridges throttle-body bottom to plenum top.
    var throttleStemCenterY: CGFloat {
        throttleTopY + IntakeDiagram.throttleBodyHeight
            + IntakeDiagram.throttleStemHeight / 2
    }
    var plenumTopY: CGFloat {
        throttleBodyCenterY + IntakeDiagram.throttleBodyHeight / 2
            + IntakeDiagram.throttleStemHeight
    }
    var plenumCenterY: CGFloat { plenumTopY + IntakeDiagram.plenumHeight / 2 }
    var plenumBottomY: CGFloat { plenumTopY + IntakeDiagram.plenumHeight }

    var headBarY: CGFloat {
        let runnerLengthPx = canvas.height * runnerFraction
        return min(plenumBottomY + runnerLengthPx, canvas.height - 26)
    }

    /// X position where the i-th runner meets the plenum bottom.
    func plenumOutletX(at idx: Int) -> CGFloat {
        let leftEdge = centerX - plenumWidth / 2
            + IntakeDiagram.portWidth                 // small inset
        let usable = plenumWidth - IntakeDiagram.portWidth * 2
        guard cylinderCount > 1 else { return centerX }
        let step = usable / CGFloat(cylinderCount - 1)
        return leftEdge + CGFloat(idx) * step
    }

    /// X position where the i-th runner meets its cylinder port.
    func portX(at idx: Int) -> CGFloat {
        let leftEdge = centerX - headBarWidth / 2
            + IntakeDiagram.portWidth
        let usable = headBarWidth - IntakeDiagram.portWidth * 2
        guard cylinderCount > 1 else { return centerX }
        let step = usable / CGFloat(cylinderCount - 1)
        return leftEdge + CGFloat(idx) * step
    }
}

private enum IntakeMath {
    static func lerp(_ value: Double,
                      from inputRange: ClosedRange<Double>,
                      to outputRange: ClosedRange<CGFloat>) -> CGFloat {
        let clamped = min(max(value, inputRange.lowerBound), inputRange.upperBound)
        let t = (clamped - inputRange.lowerBound)
              / (inputRange.upperBound - inputRange.lowerBound)
        return outputRange.lowerBound
             + CGFloat(t) * (outputRange.upperBound - outputRange.lowerBound)
    }
}

// MARK: - Exhaust

private enum ExhaustDiagram {
    static let primaryMinFraction: CGFloat = 0.25
    static let primaryMaxFraction: CGFloat = 0.65
    static let primaryThicknessPx: CGFloat = 4
    static let collectorMinPx: CGFloat = 10
    static let collectorMaxPx: CGFloat = 38
    static let collectorHeight: CGFloat = 22
    static let tailpipeHeight: CGFloat = 10
    static let portWidth: CGFloat = 14
    static let portHeight: CGFloat = 4
    static let headBarHeight: CGFloat = 6
    static let minPortSpacing: CGFloat = 16
    static let tailpipeMinFraction: CGFloat = 0.20
    static let tailpipeMaxFraction: CGFloat = 0.60
}

struct ExhaustStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            BuilderSectionHeading(title: "Step 7 · Exhaust & sound")

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 20) {
                    BuilderSlider(label: "Primary length",
                                  value: $state.spec.exhaustPrimaryLengthIn,
                                  range: 8...50, step: 0.5, unit: "in")
                    BuilderSlider(label: "Collector bore",
                                  value: $state.spec.exhaustCollectorBoreIn,
                                  range: 1.5...4.0, step: 0.1, unit: "in")
                    BuilderSlider(label: "Total length",
                                  value: $state.spec.exhaustLengthIn,
                                  range: 30...200, step: 1, unit: "in")
                    BuilderSlider(label: "Audio volume",
                                  value: $state.spec.exhaustAudioVolume,
                                  range: 0.05...4.0, step: 0.05, unit: "", format: "%.2f")

                    VStack(alignment: .leading, spacing: 10) {
                        BuilderSectionHeading(title: "Impulse response")
                        ForEach(ImpulseResponseChoice.allCases) { choice in
                            let selected = state.spec.impulseResponse == choice
                            Button(action: { state.spec.impulseResponse = choice }) {
                                HStack {
                                    Rectangle()
                                        .fill(selected ? BuilderTheme.accent : Color.clear)
                                        .overlay(Rectangle().stroke(selected ? BuilderTheme.accent : BuilderTheme.line))
                                        .frame(width: 10, height: 10)
                                    Text(choice.displayName)
                                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                                        .foregroundColor(selected ? .white : BuilderTheme.label)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 440)

                VStack(spacing: 12) {
                    BuilderSectionHeading(title: "Header")
                    ExhaustHeaderDiagram(primaryLengthIn: state.spec.exhaustPrimaryLengthIn,
                                          collectorBoreIn: state.spec.exhaustCollectorBoreIn,
                                          totalLengthIn: state.spec.exhaustLengthIn,
                                          cylinderCount: state.spec.layout.cylinderCount,
                                          bankCount: state.spec.layout.bankCount)
                        .frame(width: 360, height: 300)
                }
            }
            Spacer()
        }
    }
}

/// Front-view schematic of an exhaust header drawn as a coherent assembly:
///
///  ═══════════  ← cylinder head bar (numbered ports along the top)
///   ▆  ▆  ▆  ▆   ← exhaust ports
///   │  │  │  │   ← primaries (length scales with primary-length slider)
///    \ |  | /
///     \|  |/
///   ┌──┴──┴──┐   ← collector (width scales with collector bore)
///   │        │
///   └────────┴──────  ← tailpipe (length scales with total length)
///
/// For V layouts, each bank gets its own header that exits to its own
/// collector and tailpipe, matching the per-bank `exhaust_system` the MR
/// writer emits.
private struct ExhaustHeaderDiagram: View {
    let primaryLengthIn: Double
    let collectorBoreIn: Double
    let totalLengthIn: Double
    let cylinderCount: Int
    let bankCount: Int

    private let primaryRange: ClosedRange<Double> = 8...50
    private let collectorRange: ClosedRange<Double> = 1.5...4.0
    private let totalRange: ClosedRange<Double> = 30...200

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Rectangle().stroke(BuilderTheme.line, lineWidth: 1)

                if bankCount == 1 {
                    bank(in: CGRect(origin: .zero, size: proxy.size),
                         cylinders: Array(1...cylinderCount),
                         label: nil)
                } else {
                    let halfH = proxy.size.height / 2
                    let oddCyls = (1...cylinderCount).filter { !$0.isMultiple(of: 2) }
                    let evenCyls = (1...cylinderCount).filter { $0.isMultiple(of: 2) }
                    bank(in: CGRect(x: 0, y: 0,
                                    width: proxy.size.width, height: halfH),
                         cylinders: oddCyls, label: "BANK A")
                    Path { p in
                        p.move(to: CGPoint(x: 12, y: halfH))
                        p.addLine(to: CGPoint(x: proxy.size.width - 12, y: halfH))
                    }
                    .stroke(BuilderTheme.line.opacity(0.6),
                            style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    bank(in: CGRect(x: 0, y: halfH,
                                    width: proxy.size.width, height: halfH),
                         cylinders: evenCyls, label: "BANK B")
                }

                // Spec callout — bottom right, shared across banks.
                statsBadge
                    .position(x: proxy.size.width - 70,
                              y: proxy.size.height - 26)
            }
        }
    }

    // MARK: - One bank

    private func bank(in rect: CGRect, cylinders: [Int], label: String?) -> some View {
        let n = cylinders.count
        let centerX = rect.midX
        let topY = rect.minY + 18

        let primaryOut = ExhaustDiagram.primaryMinFraction...ExhaustDiagram.primaryMaxFraction
        let collectorOut = ExhaustDiagram.collectorMinPx...ExhaustDiagram.collectorMaxPx
        let tailpipeOut = ExhaustDiagram.tailpipeMinFraction...ExhaustDiagram.tailpipeMaxFraction
        let primaryLengthPx = rect.height
            * IntakeMath.lerp(primaryLengthIn, from: primaryRange, to: primaryOut)
        let collectorWidthPx = IntakeMath.lerp(collectorBoreIn,
                                                from: collectorRange,
                                                to: collectorOut) + 16
        let tailpipeLengthPx = (rect.width - collectorWidthPx) / 2
            * IntakeMath.lerp(totalLengthIn, from: totalRange, to: tailpipeOut)

        let headBarWidth = max(collectorWidthPx,
                                CGFloat(n) * (ExhaustDiagram.portWidth
                                              + ExhaustDiagram.minPortSpacing))
        let headBarY = topY
        let primariesTopY = headBarY + ExhaustDiagram.headBarHeight
        let collectorTopY = primariesTopY + primaryLengthPx
        let collectorCenterY = collectorTopY + ExhaustDiagram.collectorHeight / 2
        let tailpipeY = collectorCenterY

        return ZStack(alignment: .topLeading) {
            // Bank label
            if let label {
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(BuilderTheme.label)
                    .position(x: rect.minX + 30, y: topY - 8)
            }

            // 1. Cylinder head bar
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                .frame(width: headBarWidth, height: ExhaustDiagram.headBarHeight)
                .position(x: centerX, y: headBarY + ExhaustDiagram.headBarHeight / 2)

            // 2. Exhaust ports on the head bar
            ForEach(Array(cylinders.enumerated()), id: \.offset) { idx, cyl in
                let portX = portXFor(idx: idx, count: n,
                                      centerX: centerX, headBarWidth: headBarWidth)
                Rectangle()
                    .fill(BuilderTheme.accent)
                    .frame(width: ExhaustDiagram.portWidth,
                           height: ExhaustDiagram.portHeight)
                    .position(x: portX, y: headBarY + ExhaustDiagram.headBarHeight
                                                   + ExhaustDiagram.portHeight / 2)
                Text("\(cyl)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .position(x: portX, y: headBarY - 8)
            }

            // 3. Primary tubes (curving in to collector)
            ForEach(0..<n, id: \.self) { idx in
                let portX = portXFor(idx: idx, count: n,
                                      centerX: centerX, headBarWidth: headBarWidth)
                let portBottomY = headBarY + ExhaustDiagram.headBarHeight
                                  + ExhaustDiagram.portHeight
                primaryTubePath(fromX: portX,
                                 fromY: portBottomY,
                                 toX: centerX,
                                 toY: collectorTopY)
            }

            // 4. Collector
            Rectangle()
                .fill(BuilderTheme.accent.opacity(0.4))
                .overlay(Rectangle().stroke(BuilderTheme.accent, lineWidth: 1.5))
                .frame(width: collectorWidthPx, height: ExhaustDiagram.collectorHeight)
                .position(x: centerX, y: collectorCenterY)

            // 5. Tailpipe — exits the collector to the right.
            Rectangle()
                .fill(Color.white.opacity(0.55))
                .frame(width: tailpipeLengthPx,
                       height: ExhaustDiagram.tailpipeHeight)
                .position(x: centerX + collectorWidthPx / 2 + tailpipeLengthPx / 2,
                          y: tailpipeY)
        }
    }

    private func portXFor(idx: Int, count: Int,
                           centerX: CGFloat, headBarWidth: CGFloat) -> CGFloat {
        let leftEdge = centerX - headBarWidth / 2 + ExhaustDiagram.portWidth
        let usable = headBarWidth - ExhaustDiagram.portWidth * 2
        guard count > 1 else { return centerX }
        let step = usable / CGFloat(count - 1)
        return leftEdge + CGFloat(idx) * step
    }

    private func primaryTubePath(fromX: CGFloat, fromY: CGFloat,
                                  toX: CGFloat, toY: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: fromX, y: fromY))
            p.addQuadCurve(to: CGPoint(x: toX, y: toY),
                            control: CGPoint(x: fromX, y: toY - 4))
        }
        .stroke(Color.white.opacity(0.85),
                style: StrokeStyle(lineWidth: ExhaustDiagram.primaryThicknessPx,
                                   lineCap: .round))
    }

    private var statsBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(String(format: "PRIMARY %.0f in", primaryLengthIn))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(BuilderTheme.label)
            Text(String(format: "COLLECTOR Ø %.1f", collectorBoreIn))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(BuilderTheme.label)
            Text(String(format: "TOTAL %.0f in", totalLengthIn))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(BuilderTheme.accent)
        }
    }
}

// MARK: - Ignition + Fuel

private enum TimingDiagram {
    static let maxAdvanceDeg: Double = 50
    static let pointRadius: CGFloat = 4
    static let gridDivisions: Int = 5
}

struct IgnitionFuelStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            BuilderSectionHeading(title: "Step 8 · Ignition & Fuel")

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 20) {
                    BigReadout(value: "\(Int(state.spec.redlineRpm))",
                               unit: "rpm", label: "Redline · Rev limit")
                        .padding(.bottom, 8)

                    BuilderSlider(label: "Redline",
                                  value: redlineBinding,
                                  range: 3000...12000,
                                  step: 100,
                                  unit: "rpm",
                                  format: "%.0f")

                    BuilderSlider(label: "Limiter duration",
                                  value: $state.spec.limiterDurationSec,
                                  range: 0.02...0.5, step: 0.01, unit: "s", format: "%.2f")

                    VStack(alignment: .leading, spacing: 10) {
                        BuilderSectionHeading(title: "Fuel")
                        CardGrid(items: FuelPreset.allCases, columns: 2,
                                 isSelected: { state.spec.fuel == $0 },
                                 onSelect: { state.spec.fuel = $0 }) { fuel, selected in
                            VStack(spacing: 6) {
                                Text(fuel.displayName.uppercased())
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .tracking(2)
                                    .foregroundColor(selected ? BuilderTheme.accent : .white)
                            }
                            .padding(.vertical, 16)
                        }
                    }
                    .frame(maxWidth: 320)
                }
                .frame(maxWidth: 420)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        BuilderSectionHeading(title: "Spark advance vs RPM")
                        Spacer()
                        TimingCurveHint()
                    }
                    .frame(width: 420)

                    InteractiveTimingCurve(points: $state.spec.ignitionTiming,
                                            revLimitRpm: state.spec.revLimitRpm)
                        .frame(width: 420, height: 280)
                }
            }
            Spacer()
        }
    }

    /// Mutating redline reshapes the timing curve as well — points past the
    /// new redline get clipped to it so the graph stays clean.
    private var redlineBinding: Binding<Double> {
        Binding(
            get: { state.spec.redlineRpm },
            set: { newRedline in
                state.spec.redlineRpm = newRedline
                clampTimingToRedline(newRedline)
            }
        )
    }

    /// Keep the curve in step with the redline without spawning a point on
    /// every 100-rpm slider tick. Strategy: drop points past the new redline,
    /// then make sure each 1000-rpm stride from 1000 up to the redline has
    /// a sample. Newly-introduced samples take their advance value from a
    /// linear interpolation/extrapolation of the existing curve so they
    /// follow the previous trend instead of all reading the same value.
    private func clampTimingToRedline(_ redline: Double) {
        var pts = state.spec.ignitionTiming.sorted { $0.rpm < $1.rpm }
        pts.removeAll { $0.rpm > redline }

        let stride: Double = 1000
        // Target rpms: 1000, 2000, …, last multiple-of-1000 ≤ redline.
        let maxStride = floor(redline / stride) * stride
        var target = stride
        while target <= maxStride {
            let alreadyHas = pts.contains(where: { abs($0.rpm - target) < 0.5 })
            if !alreadyHas {
                let advance = Self.advance(at: target, on: pts)
                pts.append(TimingPoint(rpm: target, advanceDeg: advance))
            }
            target += stride
        }

        state.spec.ignitionTiming = pts.sorted { $0.rpm < $1.rpm }
    }

    /// Linear interpolation across the curve. Extrapolates past the end
    /// using the slope of the last two points; clamps below the first point.
    private static func advance(at rpm: Double, on pts: [TimingPoint]) -> Double {
        let sorted = pts.sorted { $0.rpm < $1.rpm }
        guard !sorted.isEmpty else { return 12 }
        guard sorted.count > 1 else { return sorted[0].advanceDeg }

        if rpm <= sorted.first!.rpm { return sorted.first!.advanceDeg }
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i]
            let b = sorted[i + 1]
            if rpm >= a.rpm && rpm <= b.rpm {
                let t = (rpm - a.rpm) / (b.rpm - a.rpm)
                return a.advanceDeg + t * (b.advanceDeg - a.advanceDeg)
            }
        }
        // Extrapolate from the last two points.
        let a = sorted[sorted.count - 2]
        let b = sorted[sorted.count - 1]
        guard b.rpm != a.rpm else { return b.advanceDeg }
        let slope = (b.advanceDeg - a.advanceDeg) / (b.rpm - a.rpm)
        let extrapolated = b.advanceDeg + slope * (rpm - b.rpm)
        return min(max(extrapolated, 0), TimingDiagram.maxAdvanceDeg)
    }
}

/// Hint chip that lives in the section header so the drag/click/right-click
/// affordances aren't a hidden secret.
private struct TimingCurveHint: View {
    var body: some View {
        HStack(spacing: 8) {
            label(icon: "hand.draw.fill", text: "DRAG TO EDIT")
            label(icon: "plus.circle", text: "CLICK TO ADD")
        }
    }

    private func label(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(BuilderTheme.accent)
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(BuilderTheme.label)
        }
    }
}

/// Editable timing curve. Drag a dot to move it (snapped to nearest 100 rpm
/// / 0.5°). Click empty grid to add a point at that location. Right-click /
/// option-click a point to delete it (the curve always retains at least two
/// samples so the simulator has something to interpolate).
private struct InteractiveTimingCurve: View {
    @Binding var points: [TimingPoint]
    let revLimitRpm: Double

    private let minPoints = 2
    private let rpmSnap: Double = 100
    private let advanceSnap: Double = 0.5
    private let hitRadius: CGFloat = 20
    private let handleRadius: CGFloat = 7

    @State private var draggingId: UUID? = nil
    @State private var hoveredId: UUID? = nil

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let sorted = points.sorted(by: { $0.rpm < $1.rpm })
            let maxRpm = max(revLimitRpm, sorted.last?.rpm ?? revLimitRpm)

            ZStack(alignment: .topLeading) {
                Rectangle().stroke(BuilderTheme.line, lineWidth: 1)
                gridLines(w: w, h: h)
                curvePath(sorted: sorted, w: w, h: h, maxRpm: maxRpm)
                draggablePoints(sorted: sorted, w: w, h: h, maxRpm: maxRpm)
                revLimitLine(w: w, h: h, maxRpm: maxRpm)
                axisLabels(h: h)
            }
            .contentShape(Rectangle())
            .gesture(addPointGesture(w: w, h: h, maxRpm: maxRpm))
        }
    }

    private func gridLines(w: CGFloat, h: CGFloat) -> some View {
        ForEach(1..<TimingDiagram.gridDivisions, id: \.self) { i in
            Path { p in
                let y = h * CGFloat(i) / CGFloat(TimingDiagram.gridDivisions)
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: w, y: y))
            }.stroke(BuilderTheme.line.opacity(0.4), lineWidth: 0.5)

            Path { p in
                let x = w * CGFloat(i) / CGFloat(TimingDiagram.gridDivisions)
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: h))
            }.stroke(BuilderTheme.line.opacity(0.4), lineWidth: 0.5)
        }
    }

    private func curvePath(sorted: [TimingPoint], w: CGFloat, h: CGFloat, maxRpm: Double) -> some View {
        Path { p in
            for (i, pt) in sorted.enumerated() {
                let pos = position(for: pt, w: w, h: h, maxRpm: maxRpm)
                if i == 0 { p.move(to: pos) } else { p.addLine(to: pos) }
            }
        }
        .stroke(BuilderTheme.accent, lineWidth: 1.5)
    }

    private func draggablePoints(sorted: [TimingPoint], w: CGFloat, h: CGFloat, maxRpm: Double) -> some View {
        ForEach(sorted) { pt in
            let pos = position(for: pt, w: w, h: h, maxRpm: maxRpm)
            let active = draggingId == pt.id || hoveredId == pt.id

            ZStack {
                // Outer ring — visible on hover/drag, gives a clear "you can
                // grab me" affordance without permanently crowding the curve.
                Circle()
                    .stroke(BuilderTheme.accent.opacity(active ? 0.55 : 0.0), lineWidth: 1)
                    .frame(width: handleRadius * 2 + 8, height: handleRadius * 2 + 8)

                // Inner solid handle — bumped up from the old 4pt diameter so
                // it actually looks grabbable.
                Circle()
                    .fill(BuilderTheme.accent)
                    .frame(width: handleRadius * 2, height: handleRadius * 2)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(active ? 0.95 : 0.0), lineWidth: 1.5)
                    )
                    .scaleEffect(active ? 1.15 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: active)
            }
            .frame(width: hitRadius, height: hitRadius)
            .contentShape(Circle())
            .position(pos)
            .onHover { inside in
                if inside {
                    hoveredId = pt.id
                    NSCursor.openHand.push()
                } else {
                    if hoveredId == pt.id { hoveredId = nil }
                    NSCursor.pop()
                }
            }
            .gesture(dragGesture(pointId: pt.id, w: w, h: h, maxRpm: maxRpm))
            .onTapGesture(count: 2) { deletePoint(id: pt.id) }
            .contextMenu {
                Button("Delete point", role: .destructive) { deletePoint(id: pt.id) }
            }
        }
    }

    private func revLimitLine(w: CGFloat, h: CGFloat, maxRpm: Double) -> some View {
        let revX = w * CGFloat(revLimitRpm / maxRpm)
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: revX, y: 0))
                p.addLine(to: CGPoint(x: revX, y: h))
            }
            .stroke(Color.red.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            Text("REV \(Int(revLimitRpm))")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.red.opacity(0.85))
                .position(x: revX - 22, y: 12)
        }
    }

    private func axisLabels(h: CGFloat) -> some View {
        ZStack {
            Text("0 RPM")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(BuilderTheme.label)
                .position(x: 20, y: h - 8)
            Text(String(format: "%.0f°", TimingDiagram.maxAdvanceDeg))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(BuilderTheme.label)
                .position(x: 14, y: 10)
        }
    }

    // MARK: - Gestures

    private func dragGesture(pointId: UUID, w: CGFloat, h: CGFloat, maxRpm: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                draggingId = pointId
                updatePoint(id: pointId, to: drag.location, w: w, h: h, maxRpm: maxRpm)
            }
            .onEnded { _ in draggingId = nil }
    }

    private func addPointGesture(w: CGFloat, h: CGFloat, maxRpm: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { drag in
                let dist = hypot(drag.translation.width, drag.translation.height)
                guard dist < 2 else { return }
                let (rpm, _) = invert(point: drag.location, w: w, h: h, maxRpm: maxRpm)
                // Skip if there's already a near-identical point — avoids
                // accidentally adding duplicates when clicking near a node.
                if points.contains(where: { abs($0.rpm - rpm) < rpmSnap * 0.5 }) { return }
                // Use the user's clicked Y as the advance value so manual
                // additions land where they actually clicked.
                let (_, clickAdvance) = invert(point: drag.location, w: w, h: h, maxRpm: maxRpm)
                points.append(TimingPoint(rpm: rpm, advanceDeg: clickAdvance))
                points.sort { $0.rpm < $1.rpm }
            }
    }

    // MARK: - Helpers

    private func position(for pt: TimingPoint, w: CGFloat, h: CGFloat, maxRpm: Double) -> CGPoint {
        let x = w * CGFloat(pt.rpm / maxRpm)
        let y = h - h * CGFloat(pt.advanceDeg / TimingDiagram.maxAdvanceDeg)
        return CGPoint(x: x, y: y)
    }

    private func invert(point: CGPoint, w: CGFloat, h: CGFloat, maxRpm: Double) -> (Double, Double) {
        let rawRpm = Double(point.x / w) * maxRpm
        let rawAdv = Double((h - point.y) / h) * TimingDiagram.maxAdvanceDeg
        let clampedRpm = min(max(rawRpm, 0), maxRpm)
        let clampedAdv = min(max(rawAdv, 0), TimingDiagram.maxAdvanceDeg)
        return (snap(clampedRpm, to: rpmSnap), snap(clampedAdv, to: advanceSnap))
    }

    private func snap(_ v: Double, to step: Double) -> Double {
        (v / step).rounded() * step
    }

    private func updatePoint(id: UUID, to location: CGPoint, w: CGFloat, h: CGFloat, maxRpm: Double) {
        guard let idx = points.firstIndex(where: { $0.id == id }) else { return }
        let (rpm, advance) = invert(point: location, w: w, h: h, maxRpm: maxRpm)
        points[idx].rpm = rpm
        points[idx].advanceDeg = advance
        points.sort { $0.rpm < $1.rpm }
    }

    private func deletePoint(id: UUID) {
        guard points.count > minPoints else { return }
        points.removeAll { $0.id == id }
    }
}

/// Legacy read-only graph kept here for callers that don't need editing.
private struct TimingCurveGraph: View {
    let points: [TimingPoint]
    let revLimitRpm: Double

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let sorted = points.sorted(by: { $0.rpm < $1.rpm })
            let maxRpm = max(revLimitRpm, sorted.last?.rpm ?? revLimitRpm)

            ZStack(alignment: .topLeading) {
                Rectangle().stroke(BuilderTheme.line, lineWidth: 1)

                // Grid
                ForEach(1..<TimingDiagram.gridDivisions, id: \.self) { i in
                    Path { p in
                        let y = h * CGFloat(i) / CGFloat(TimingDiagram.gridDivisions)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }.stroke(BuilderTheme.line.opacity(0.4), lineWidth: 0.5)
                    Path { p in
                        let x = w * CGFloat(i) / CGFloat(TimingDiagram.gridDivisions)
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                    }.stroke(BuilderTheme.line.opacity(0.4), lineWidth: 0.5)
                }

                // Curve
                Path { p in
                    for (i, pt) in sorted.enumerated() {
                        let x = w * CGFloat(pt.rpm / maxRpm)
                        let y = h - h * CGFloat(pt.advanceDeg / TimingDiagram.maxAdvanceDeg)
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(BuilderTheme.accent, lineWidth: 1.5)

                // Sample points
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, pt in
                    let x = w * CGFloat(pt.rpm / maxRpm)
                    let y = h - h * CGFloat(pt.advanceDeg / TimingDiagram.maxAdvanceDeg)
                    Circle()
                        .fill(BuilderTheme.accent)
                        .frame(width: TimingDiagram.pointRadius * 2,
                               height: TimingDiagram.pointRadius * 2)
                        .position(x: x, y: y)
                }

                // Rev limit indicator
                let revX = w * CGFloat(revLimitRpm / maxRpm)
                Path { p in
                    p.move(to: CGPoint(x: revX, y: 0))
                    p.addLine(to: CGPoint(x: revX, y: h))
                }
                .stroke(Color.red.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Text("REV \(Int(revLimitRpm))")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.red.opacity(0.85))
                    .position(x: revX - 22, y: 12)

                // Axis labels
                Text("0 RPM")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .position(x: 20, y: h - 8)
                Text(String(format: "%.0f°", TimingDiagram.maxAdvanceDeg))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .position(x: 14, y: 10)
            }
        }
    }
}
