//
//  BuilderCinematicSteps.swift
//  engine-simulator
//
//  Cinematic steps for the engine builder. Each step does one thing with
//  room to breathe — slider + live visual readout, not a form grid.
//

import SwiftUI

// MARK: - Diagram constants

private enum CylinderDiagram {
    static let viewportFillFraction: CGFloat = 0.9
    static let boreWallThickness: CGFloat = 1.5
    static let headThicknessRatioOfBore: CGFloat = 0.22
    static let chamberClearanceRatioOfBore: CGFloat = 0.07
    static let pistonRingGap: CGFloat = 4
    static let pistonSkirtBelowWristPin: CGFloat = 6
    static let wristPinRadius: CGFloat = 3
    static let rodWidthRatioOfBore: CGFloat = 0.16
    static let rodSmallEndRadius: CGFloat = 4
    static let bigEndRadiusRatioOfStroke: CGFloat = 0.18
    static let pistonInsetFromBore: CGFloat = 2
    static let ghostStrokeWidth: CGFloat = 0.5
    static let dashPattern: [CGFloat] = [3, 3]

    // Slider maxima — used to compute a stable scale so changing any one
    // dimension does NOT visually scale the others.
    static let maxBoreMm: Double = 110
    static let maxStrokeMm: Double = 110
    static let maxRodLengthMm: Double = 200
    static let maxCompressionHeightMm: Double = 50
    static let canvasWidthSlackMm: Double = 30
    static let canvasBottomMarginMm: Double = 8
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

                Spacer().frame(height: 12)

                BuilderSlider(label: "Redline",
                              value: $state.spec.redlineRpm,
                              range: 3000...12000,
                              step: 100,
                              unit: "rpm",
                              format: "%.0f")
                    .frame(maxWidth: 380)
            }
            Spacer()

            EnginePlaceholderArt()
                .frame(width: 280, height: 280)
        }
        .onAppear { focused = true }
    }
}

private struct EnginePlaceholderArt: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Rectangle()
                    .stroke(BuilderTheme.line, lineWidth: 1)
                    .frame(width: CGFloat(220 - i * 30), height: CGFloat(220 - i * 30))
            }
            Rectangle()
                .stroke(BuilderTheme.accent, lineWidth: 1.5)
                .frame(width: 90, height: 90)
            Text("V8")
                .font(.system(size: 24, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.accent)
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
                let cylW = w / CGFloat(n) * 0.7
                let gap = (w - cylW * CGFloat(n)) / CGFloat(n + 1)
                HStack(spacing: gap) {
                    ForEach(0..<n, id: \.self) { _ in
                        Rectangle().stroke(color, lineWidth: 1)
                            .frame(width: cylW, height: h * 0.7)
                    }
                }
                .padding(.horizontal, gap)
                .frame(maxHeight: .infinity, alignment: .center)
            } else {
                // V or flat: two rows
                let perBank = n / 2
                let cylW = w / CGFloat(perBank) * 0.7
                let gap = (w - cylW * CGFloat(perBank)) / CGFloat(perBank + 1)
                let tilt = layout.bankHalfAngleDeg / 90.0   // 0..1
                VStack(spacing: 0) {
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
        }
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

            VStack(spacing: 12) {
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

        let maxTotalHeightMm = maxHeadHeight
            + maxChamberClearance
            + maxPistonHeight
            + CylinderDiagram.maxStrokeMm
            + CylinderDiagram.maxRodLengthMm
            + maxCrankRadius
            + CylinderDiagram.canvasBottomMarginMm
        let maxTotalWidthMm = CylinderDiagram.maxBoreMm + CylinderDiagram.canvasWidthSlackMm

        let scaleY = viewSize.height * CylinderDiagram.viewportFillFraction / maxTotalHeightMm
        let scaleX = viewSize.width  * CylinderDiagram.viewportFillFraction / maxTotalWidthMm
        let scale = CGFloat(min(scaleX, scaleY))

        // *** Stable anchors ***
        // Crank center is FIXED — it sits at the bottom of the canvas at
        // the position implied by max rod + max stroke. From there we
        // build upward toward the (also fixed) head position. This way
        // moving rod length only changes where the piston/wrist pin sit
        // between the two anchors.
        let topAnchorMm = 0.0
        let crankAnchorYMm = maxHeadHeight
            + maxChamberClearance
            + maxPistonHeight
            + CylinderDiagram.maxStrokeMm        // anchor at BDC piston position
            + CylinderDiagram.maxRodLengthMm
            + maxCrankRadius                     // crank-center sits one radius below BDC journal
        let topMargin = (viewSize.height - CGFloat(maxTotalHeightMm) * scale) / 2

        func y(_ mm: Double) -> CGFloat { topMargin + CGFloat(mm) * scale }

        let bore   = CGFloat(boreMm)             * scale
        let stroke = CGFloat(strokeMm)           * scale
        let rod    = CGFloat(rodLengthMm)        * scale
        let pistonH = CGFloat(pistonHeightMm)    * scale
        let headH  = CGFloat(headHeightMm)       * scale
        let chamberClear = CGFloat(chamberClearanceMm) * scale

        self.centerX = viewSize.width / 2
        self.headHeight = headH
        self.headWidth = bore + 16
        self.headCenterY = y(topAnchorMm) + headH / 2

        self.boreTopY = y(topAnchorMm) + headH

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
        // Bore bottom extends just past the BDC piston bottom.
        self.boreBottomY = self.bdcPistonCenterY + pistonH / 2 + 6
        self.boreLeftX = centerX - bore / 2
        self.boreRightX = centerX + bore / 2

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
    static let cycleDeg: Double = 720
    static let chipSize: CGFloat = 56
    static let chipSpacing: CGFloat = 12
    static let timelineHeight: CGFloat = 110
    static let timelineMarkerWidth: CGFloat = 2
    static let timelineCylinderLabelInset: CGFloat = 14
}

/// Click-to-build firing order editor.
///
/// Workflow: an ordered sequence of slots (1st … Nth) sits at the top; an
/// "available cylinders" palette sits below. Tapping a palette cylinder
/// drops it into the next empty slot; tapping a filled slot returns that
/// cylinder to the palette. Filling the sequence top-to-bottom is the
/// fastest way to build a custom firing order from scratch.
struct FiringOrderStep: View {
    @ObservedObject var state: EngineBuilderState

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 22) {
                BuilderSectionHeading(title: "Step 5 · Firing order")
                Text("Tap a cylinder below to drop it into the next slot.\nTap a filled slot to return that cylinder to the pool.")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .lineSpacing(4)

                FiringOrderSequence(order: state.spec.firingOrder,
                                     cylinderCount: state.spec.layout.cylinderCount,
                                     onSlotTap: removeSlot)

                FiringOrderPalette(order: state.spec.firingOrder,
                                    cylinderCount: state.spec.layout.cylinderCount,
                                    bankCount: state.spec.layout.bankCount,
                                    onCylinderTap: addCylinder)

                HStack(spacing: 10) {
                    builderChip(label: "CLEAR", action: clearSequence)
                    builderChip(label: "USE DEFAULT", action: useLayoutDefault)
                    if !state.spec.firingOrderIsValid {
                        Text("⚠ INCOMPLETE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.orange)
                    } else {
                        Text("✓ VALID")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(BuilderTheme.accent)
                    }
                }
            }
            .frame(maxWidth: 600)

            VStack(spacing: 14) {
                BuilderSectionHeading(title: "Fire timeline (720°)")
                FiringTimeline(order: state.spec.firingOrder,
                               cylinderCount: state.spec.layout.cylinderCount)
                    .frame(width: 360, height: FiringOrderDiagram.timelineHeight)
                Text("Even spacing means smoother idle. Uneven\nfiring orders trade smoothness for character.")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(BuilderTheme.label)
                    .lineSpacing(3)
                    .frame(width: 360, alignment: .leading)
            }
            Spacer()
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

    private func addCylinder(_ cyl: Int) {
        guard !state.spec.firingOrder.contains(cyl) else { return }
        if state.spec.firingOrder.count < state.spec.layout.cylinderCount {
            state.spec.firingOrder.append(cyl)
        }
    }

    private func removeSlot(_ idx: Int) {
        guard idx >= 0, idx < state.spec.firingOrder.count else { return }
        state.spec.firingOrder.remove(at: idx)
    }

    private func clearSequence() {
        state.spec.firingOrder.removeAll()
    }

    private func useLayoutDefault() {
        state.spec.resyncFiringOrderForLayout()
    }
}

/// Top row: ordered slots showing the firing sequence under construction.
/// Empty slots are dashed placeholders. Tapping a filled slot frees it.
private struct FiringOrderSequence: View {
    let order: [Int]
    let cylinderCount: Int
    let onSlotTap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BuilderSectionHeading(title: "Sequence")

            let columns = Array(repeating:
                GridItem(.fixed(FiringOrderDiagram.chipSize),
                         spacing: FiringOrderDiagram.chipSpacing),
                count: min(cylinderCount, 8))

            LazyVGrid(columns: columns,
                      alignment: .leading,
                      spacing: FiringOrderDiagram.chipSpacing) {
                ForEach(0..<cylinderCount, id: \.self) { idx in
                    slot(at: idx)
                }
            }
        }
    }

    @ViewBuilder
    private func slot(at idx: Int) -> some View {
        if idx < order.count {
            Button(action: { onSlotTap(idx) }) {
                slotContent(position: idx + 1, cylinder: order[idx])
            }
            .buttonStyle(.plain)
        } else {
            emptySlot(position: idx + 1)
        }
    }

    private func slotContent(position: Int, cylinder: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(position).")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.black.opacity(0.6))
            Text("\(cylinder)")
                .font(.system(size: 22, weight: .regular, design: .monospaced))
                .foregroundColor(.black)
        }
        .frame(width: FiringOrderDiagram.chipSize,
               height: FiringOrderDiagram.chipSize)
        .background(BuilderTheme.accent)
        .overlay(Rectangle().stroke(BuilderTheme.accent, lineWidth: 1.5))
    }

    private func emptySlot(position: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(position).")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(BuilderTheme.label)
            Text("—")
                .font(.system(size: 22, weight: .regular, design: .monospaced))
                .foregroundColor(BuilderTheme.dim.opacity(0.4))
        }
        .frame(width: FiringOrderDiagram.chipSize,
               height: FiringOrderDiagram.chipSize)
        .background(Color.clear)
        .overlay(Rectangle().stroke(BuilderTheme.line,
                                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

/// Bottom row: a pool of every cylinder number. Used cylinders are dimmed
/// and unclickable; unused cylinders are bright and tappable.
private struct FiringOrderPalette: View {
    let order: [Int]
    let cylinderCount: Int
    let bankCount: Int
    let onCylinderTap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BuilderSectionHeading(title: "Available cylinders")

            let columns = Array(repeating:
                GridItem(.fixed(FiringOrderDiagram.chipSize),
                         spacing: FiringOrderDiagram.chipSpacing),
                count: min(cylinderCount, 8))

            LazyVGrid(columns: columns,
                      alignment: .leading,
                      spacing: FiringOrderDiagram.chipSpacing) {
                ForEach(1...cylinderCount, id: \.self) { cyl in
                    paletteChip(cyl: cyl)
                }
            }
        }
    }

    private func paletteChip(cyl: Int) -> some View {
        let used = order.contains(cyl)
        let bank = bankFor(cylinder: cyl)
        return Button(action: { if !used { onCylinderTap(cyl) } }) {
            VStack(spacing: 2) {
                Text(bank)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(BuilderTheme.label)
                Text("\(cyl)")
                    .font(.system(size: 22, weight: .regular, design: .monospaced))
                    .foregroundColor(used ? BuilderTheme.dim.opacity(0.4) : .white)
            }
            .frame(width: FiringOrderDiagram.chipSize,
                   height: FiringOrderDiagram.chipSize)
            .background(Color.white.opacity(used ? 0.01 : 0.06))
            .overlay(Rectangle().stroke(used ? BuilderTheme.line.opacity(0.4)
                                              : BuilderTheme.line,
                                        lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(used)
    }

    private func bankFor(cylinder: Int) -> String {
        if bankCount == 1 { return "" }
        return cylinder.isMultiple(of: 2) ? "B" : "A"
    }
}

private struct FiringTimeline: View {
    let order: [Int]
    let cylinderCount: Int

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let stepDeg = FiringOrderDiagram.cycleDeg / Double(max(cylinderCount, 1))

            ZStack(alignment: .topLeading) {
                Rectangle().stroke(BuilderTheme.line, lineWidth: 1)

                // 0/180/360/540/720 ticks.
                ForEach(0...4, id: \.self) { i in
                    let frac = CGFloat(i) / 4
                    Path { p in
                        p.move(to: CGPoint(x: w * frac, y: h - 14))
                        p.addLine(to: CGPoint(x: w * frac, y: h))
                    }
                    .stroke(BuilderTheme.line, lineWidth: 0.5)
                    Text("\(i * 180)°")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(BuilderTheme.label)
                        .position(x: w * frac, y: h - 4)
                }

                // Markers for each cylinder's fire event.
                ForEach(Array(order.enumerated()), id: \.offset) { idx, cyl in
                    let angle = Double(idx) * stepDeg
                    let x = w * CGFloat(angle / FiringOrderDiagram.cycleDeg)
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 14))
                        p.addLine(to: CGPoint(x: x, y: h - 14))
                    }
                    .stroke(BuilderTheme.accent, lineWidth: FiringOrderDiagram.timelineMarkerWidth)
                    Text("\(cyl)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(BuilderTheme.accent)
                        .position(x: x, y: FiringOrderDiagram.timelineCylinderLabelInset / 2 + 4)
                }
            }
        }
    }
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
    static let plenumHeight: CGFloat = 26
    static let portWidth: CGFloat = 14
    static let portHeight: CGFloat = 4
    static let headBarHeight: CGFloat = 6
    static let minRunnerSpacing: CGFloat = 18
    static let runnerCurveOffset: CGFloat = 8
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
    let cylinderCount: Int
    let bankCount: Int

    private let plenumVolumeRange: ClosedRange<Double> = 0.5...4.0
    private let runnerLengthRange: ClosedRange<Double> = 4...40
    private let cfmRange: ClosedRange<Double> = 200...1200

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

                // 2. Cylinder ports (one per cylinder) sitting on the head bar.
                ForEach(0..<cylinderCount, id: \.self) { i in
                    let portX = layout.portX(at: i)
                    Rectangle()
                        .fill(BuilderTheme.accent)
                        .frame(width: IntakeDiagram.portWidth,
                               height: IntakeDiagram.portHeight)
                        .position(x: portX,
                                  y: layout.headBarY - IntakeDiagram.portHeight / 2)
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
                    Path { p in
                        p.move(to: CGPoint(x: plenumOutletX, y: plenumOutletY))
                        // Slight curve so wide-spaced banks don't look like crooked sticks.
                        p.addQuadCurve(
                            to: CGPoint(x: portX, y: layout.headBarY - IntakeDiagram.portHeight),
                            control: CGPoint(x: portX,
                                             y: plenumOutletY + IntakeDiagram.runnerCurveOffset)
                        )
                    }
                    .stroke(Color.white.opacity(0.85),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }

                // 4. Plenum — fixed-position rectangle on top of the runners.
                Rectangle()
                    .fill(BuilderTheme.accent.opacity(0.25 + flowGlow * 0.4))
                    .overlay(Rectangle().stroke(BuilderTheme.accent, lineWidth: 1.5))
                    .frame(width: layout.plenumWidth, height: IntakeDiagram.plenumHeight)
                    .position(x: layout.centerX, y: layout.plenumCenterY)

                // 5. Throttle body — sits directly on top of the plenum, connected.
                throttleBody
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

    private var throttleBody: some View {
        ZStack {
            // Body block.
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .overlay(Rectangle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                .frame(width: IntakeDiagram.throttleBodyWidth,
                       height: IntakeDiagram.throttleBodyHeight)
            // Stem connecting it to the plenum below.
            Rectangle()
                .fill(BuilderTheme.accent)
                .frame(width: 4, height: IntakeDiagram.throttleStemHeight)
                .offset(y: IntakeDiagram.throttleBodyHeight / 2
                          + IntakeDiagram.throttleStemHeight / 2)
            // Throttle plate (line across the body).
            Path { p in
                p.move(to: CGPoint(x: -IntakeDiagram.throttleBodyWidth / 2 + 6, y: 0))
                p.addLine(to: CGPoint(x: IntakeDiagram.throttleBodyWidth / 2 - 6, y: 0))
            }
            .stroke(BuilderTheme.accent, lineWidth: 2)
            .rotationEffect(.degrees(-25))
        }
        .frame(width: IntakeDiagram.throttleBodyWidth,
               height: IntakeDiagram.throttleBodyHeight)
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

                    Text("Redline is set in the IDENTITY tab — it controls both the\ndisplayed redline and the hardware rev limiter.")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(BuilderTheme.label)
                        .lineSpacing(3)

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

                VStack(spacing: 12) {
                    BuilderSectionHeading(title: "Spark advance vs RPM")
                    TimingCurveGraph(points: state.spec.ignitionTiming,
                                      revLimitRpm: state.spec.revLimitRpm)
                        .frame(width: 360, height: 240)
                    Text("Edit the points in the Advanced tab.")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(BuilderTheme.label)
                }
            }
            Spacer()
        }
    }
}

/// Plots the user's timing-curve samples on an RPM × advance grid.
/// Read-only here — the points are editable on the Advanced tab.
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
