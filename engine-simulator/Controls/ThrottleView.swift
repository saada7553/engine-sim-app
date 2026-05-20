//
//  ThrottleView.swift
//  engine-simulator
//
//  Side cross-section visualizers for the clutch assembly and intake manifold.
//  Both lock to a fixed aspect ratio so geometry stays correct as the tile
//  resizes — the parent letterboxes empty space instead of stretching parts.
//

import SwiftUI

// MARK: - Layout constants

private let clutchAspectRatio: CGFloat = 1.55
private let intakeAspectRatio: CGFloat = 1.20
private let visualizerPadding: CGFloat = 6

// Clutch component sizing (all fractions of the drawing rect).
private let clutchShaftHeightFraction: CGFloat = 0.07
private let clutchFlywheelHeightFraction: CGFloat = 0.78
private let clutchFlywheelWidthFraction: CGFloat = 0.085
private let clutchFrictionHeightFraction: CGFloat = 0.56
private let clutchFrictionWidthFraction: CGFloat = 0.05
private let clutchPressurePlateHeightFraction: CGFloat = 0.68
private let clutchPressurePlateWidthFraction: CGFloat = 0.07
private let clutchDiaphragmDepthFraction: CGFloat = 0.10
private let clutchDisengageMaxGapFraction: CGFloat = 0.04
private let clutchLabelInset: CGFloat = 4
private let flywheelScribeCount: Int = 5
private let flywheelMinRpmForMotion: Double = 80

// Intake component sizing.
private let intakeThrottleBoreWidthFraction: CGFloat = 0.18
// Bore height holds enough room for the blade to rotate without poking outside;
// keyed off the blade length below so the geometry stays consistent.
private let intakeThrottleBoreHeightFraction: CGFloat = 0.22
private let intakePlenumHeightFraction: CGFloat = 0.20
private let intakePlenumWidthFraction: CGFloat = 0.86
private let intakeRunnerHeightFraction: CGFloat = 0.34
private let intakeRunnerSlotFillFraction: CGFloat = 0.68
private let intakeHeadHeightFraction: CGFloat = 0.10
private let intakeBladeLengthFraction: CGFloat = 0.78
private let intakeBladeThicknessFraction: CGFloat = 0.07
private let intakeBladeClosedDeg: Double = 4
private let intakeBladeOpenSweepDeg: Double = 84
private let intakeArrowVisibilityThreshold: Double = 0.08
private let intakeMinRunners: Int = 1
private let intakeMaxRunners: Int = 8

// Shared colors.
private let metalLightColor = Color(white: 0.55)
private let metalMidColor = Color(white: 0.32)
private let metalDarkColor = Color(white: 0.16)
private let metalOutlineColor = Color.white.opacity(0.22)
private let frictionColor = Color.orange.opacity(0.85)
private let frictionOutlineColor = Color.orange.opacity(0.5)
private let airflowColor = Color.cyan.opacity(0.7)
private let scribeColor = Color.black.opacity(0.45)

struct ThrottleView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        HStack(spacing: 0) {
            column(title: "CLUTCH ASSEMBLY") {
                AspectFitContainer(aspectRatio: clutchAspectRatio) {
                    ClutchCrossSection(
                        clutchPressure: vm.clutchPressure,
                        rpm: vm.rpm
                    )
                }
                PrecisionClutchSlider(
                    pressure: vm.clutchPressure,
                    onChange: vm.setClutchPressure
                )
            }

            Divider().background(Color.white.opacity(0.1))

            column(title: "INTAKE MANIFOLD") {
                AspectFitContainer(aspectRatio: intakeAspectRatio) {
                    IntakeCrossSection(
                        openPercentage: vm.throttlePosition,
                        runnerCount: clampedRunnerCount(vm.cylindersPerBank)
                    )
                }
                PrecisionThrottleSlider(value: $vm.throttlePosition)
            }
        }
        .background(Color.black.opacity(0.2))
        .border(Color.white.opacity(0.1), width: 1)
    }

    private func clampedRunnerCount(_ raw: Int) -> Int {
        min(max(raw, intakeMinRunners), intakeMaxRunners)
    }

    @ViewBuilder
    private func column<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).modifier(RetroFont(size: 10)).foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal, 8)

            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Aspect-locked container

private struct AspectFitContainer<Content: View>: View {
    let aspectRatio: CGFloat
    let content: Content

    init(aspectRatio: CGFloat, @ViewBuilder content: () -> Content) {
        self.aspectRatio = aspectRatio
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let available = CGSize(
                width: max(geo.size.width - visualizerPadding * 2, 0),
                height: max(geo.size.height - visualizerPadding * 2, 0)
            )
            let (w, h) = fittedSize(in: available)

            ZStack {
                Color.appBackground.cornerRadius(4)
                content
                    .frame(width: w, height: h)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fittedSize(in available: CGSize) -> (CGFloat, CGFloat) {
        let widthDrivenHeight = available.width / aspectRatio
        if widthDrivenHeight <= available.height {
            return (available.width, widthDrivenHeight)
        }
        return (available.height * aspectRatio, available.height)
    }
}

// MARK: - Clutch cross-section

private struct ClutchCrossSection: View {
    let clutchPressure: Double
    let rpm: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cy = h / 2

            let flywheelWidth = w * clutchFlywheelWidthFraction
            let frictionWidth = w * clutchFrictionWidthFraction
            let pressurePlateWidth = w * clutchPressurePlateWidthFraction
            let diaphragmDepth = w * clutchDiaphragmDepthFraction
            let totalCoreWidth = flywheelWidth + frictionWidth + pressurePlateWidth + diaphragmDepth
            let coreStartX = (w - totalCoreWidth) / 2

            // disengageAmount: 0 (fully engaged) → 1 (fully disengaged)
            let disengageAmount = max(0.0, min(1.0, 1.0 - clutchPressure))
            let gap = CGFloat(disengageAmount) * w * clutchDisengageMaxGapFraction

            let flywheelX = coreStartX
            let frictionX = flywheelX + flywheelWidth + gap
            let pressurePlateX = frictionX + frictionWidth + gap
            let diaphragmX = pressurePlateX + pressurePlateWidth

            ZStack(alignment: .topLeading) {
                ShaftPair(
                    cy: cy,
                    height: h * clutchShaftHeightFraction,
                    engineShaftEnd: flywheelX,
                    outputShaftStart: pressurePlateX,
                    drawingWidth: w
                )

                Flywheel(
                    rect: CGRect(
                        x: flywheelX,
                        y: cy - h * clutchFlywheelHeightFraction / 2,
                        width: flywheelWidth,
                        height: h * clutchFlywheelHeightFraction
                    ),
                    rpm: rpm,
                    spinsForward: true
                )

                // Friction disc rotates with the transmission input shaft —
                // shown stationary relative to the pressure plate, but it
                // still gets the flywheel scribes when engaged.
                FrictionDisc(rect: CGRect(
                    x: frictionX,
                    y: cy - h * clutchFrictionHeightFraction / 2,
                    width: frictionWidth,
                    height: h * clutchFrictionHeightFraction
                ))

                PressurePlate(
                    rect: CGRect(
                        x: pressurePlateX,
                        y: cy - h * clutchPressurePlateHeightFraction / 2,
                        width: pressurePlateWidth,
                        height: h * clutchPressurePlateHeightFraction
                    ),
                    rpm: rpm
                )

                DiaphragmSpring(
                    startX: diaphragmX,
                    endX: diaphragmX + diaphragmDepth,
                    cy: cy,
                    height: h * clutchPressurePlateHeightFraction
                )

                StateLabel(disengageAmount: disengageAmount)
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: clutchPressure)
        }
    }
}

private struct ShaftPair: View {
    let cy: CGFloat
    let height: CGFloat
    let engineShaftEnd: CGFloat
    let outputShaftStart: CGFloat
    let drawingWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(metalMidColor)
                .frame(width: engineShaftEnd, height: height)
                .offset(x: 0, y: cy - height / 2)

            Rectangle()
                .fill(metalMidColor)
                .frame(width: drawingWidth - outputShaftStart, height: height)
                .offset(x: outputShaftStart, y: cy - height / 2)
        }
    }
}

/// Rotating mass on the engine side. Scribes inside the disc translate
/// downward at a speed proportional to RPM, giving the visual impression of
/// the wheel spinning. Direction is configurable so the friction disc, which
/// in real life couples and uncouples with the flywheel, can also pulse.
private struct Flywheel: View {
    let rect: CGRect
    let rpm: Double
    let spinsForward: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(metalLightColor)
                .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(metalOutlineColor, lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)

            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                SpinScribes(
                    rect: rect,
                    rpm: rpm,
                    timestamp: context.date.timeIntervalSinceReferenceDate,
                    direction: spinsForward ? 1 : -1
                )
            }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .clipShape(RoundedRectangle(cornerRadius: 1.5))
        }
    }
}

/// Horizontal scribe lines whose vertical offset advances with elapsed time at
/// a rate proportional to RPM. Below `flywheelMinRpmForMotion` they hold
/// still — keeps the visualizer from looking jittery when the engine is off.
private struct SpinScribes: View {
    let rect: CGRect
    let rpm: Double
    let timestamp: TimeInterval
    let direction: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let count = flywheelScribeCount
            let spacing = rect.height / CGFloat(count)
            let activeRpm = max(rpm - flywheelMinRpmForMotion, 0)
            // One scribe-spacing per (60/rpm) seconds — translates RPM
            // directly into perceived rotational speed.
            let pxPerSecond = (activeRpm / 60.0) * Double(spacing) * 4.0
            let rawOffset = CGFloat(timestamp * pxPerSecond) * direction
            let phase = rawOffset.truncatingRemainder(dividingBy: spacing)
            let baseY = phase < 0 ? phase + spacing : phase

            for i in 0..<(count + 1) {
                let y = baseY + CGFloat(i) * spacing - spacing
                guard y >= 0 && y <= rect.height else { continue }
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: rect.width, y: y))
                ctx.stroke(path, with: .color(scribeColor), lineWidth: 0.75)
            }
        }
    }
}

private struct FrictionDisc: View {
    let rect: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(frictionColor)
            .overlay(RoundedRectangle(cornerRadius: 1).stroke(frictionOutlineColor, lineWidth: 1))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

/// Pressure plate — spins with the flywheel when engaged. We hint at its
/// rotation with the same scribe treatment so the assembly feels alive.
private struct PressurePlate: View {
    let rect: CGRect
    let rpm: Double

    var body: some View {
        Flywheel(rect: rect, rpm: rpm, spinsForward: true)
    }
}

private struct DiaphragmSpring: View {
    let startX: CGFloat
    let endX: CGFloat
    let cy: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let fingerCount = 6
            for i in 0..<fingerCount {
                let t = CGFloat(i) / CGFloat(fingerCount - 1)
                let y = cy - height / 2 + t * height
                var path = Path()
                path.move(to: CGPoint(x: startX, y: y))
                path.addLine(to: CGPoint(x: endX, y: cy))
                ctx.stroke(path, with: .color(metalOutlineColor), lineWidth: 1)
            }
        }
    }
}

private struct StateLabel: View {
    let disengageAmount: Double

    private var label: String {
        if disengageAmount < 0.05 { return "ENGAGED" }
        if disengageAmount > 0.95 { return "DISENGAGED" }
        return "SLIPPING"
    }

    private var color: Color {
        if disengageAmount < 0.05 { return .green.opacity(0.85) }
        if disengageAmount > 0.95 { return .orange.opacity(0.85) }
        return .yellow.opacity(0.85)
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text(label)
                    .modifier(RetroFont(size: 8))
                    .foregroundColor(color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.4))
                    .padding(clutchLabelInset)
            }
            Spacer()
        }
    }
}

// MARK: - Intake cross-section
//
// Side view of the manifold. The throttle body sits at top center; below it
// is the plenum chamber; below that a row of runners feeding into the
// cylinder head bar. Runner count tracks the active engine's cylinders per
// bank.

private struct IntakeCrossSection: View {
    let openPercentage: Double
    let runnerCount: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bodyHeight = h * intakeThrottleBoreHeightFraction
            let bodyWidth = max(w * intakeThrottleBoreWidthFraction, bodyHeight)
            let plenumHeight = h * intakePlenumHeightFraction
            let plenumWidth = w * intakePlenumWidthFraction
            let plenumX = (w - plenumWidth) / 2
            let plenumY = bodyHeight + 2

            let headHeight = h * intakeHeadHeightFraction
            let headY = h - headHeight
            let runnerY = plenumY + plenumHeight
            // Runners terminate where the cylinder head begins, so no
            // floating grey bar at the bottom anymore.
            let runnerHeight = max(headY - runnerY, h * intakeRunnerHeightFraction * 0.4)

            ZStack(alignment: .topLeading) {
                ThrottleBody(
                    rect: CGRect(
                        x: (w - bodyWidth) / 2,
                        y: 0,
                        width: bodyWidth,
                        height: bodyHeight
                    ),
                    openPercentage: openPercentage
                )

                PlenumChamber(rect: CGRect(x: plenumX, y: plenumY, width: plenumWidth, height: plenumHeight))

                Runners(
                    count: runnerCount,
                    height: runnerHeight,
                    plenumRect: CGRect(x: plenumX, y: plenumY, width: plenumWidth, height: plenumHeight),
                    runnerY: runnerY
                )

                CylinderHead(rect: CGRect(x: 0, y: headY, width: w, height: headHeight))

                if openPercentage > intakeArrowVisibilityThreshold {
                    AirflowOverlay(
                        intensity: openPercentage,
                        plenumRect: CGRect(x: plenumX, y: plenumY, width: plenumWidth, height: plenumHeight),
                        runnerCount: runnerCount,
                        runnerY: runnerY,
                        runnerHeight: runnerHeight,
                        bodyTopY: 0
                    )
                }
            }
        }
    }
}

/// Bore is drawn at least as tall as it is wide, and the blade is sized to
/// the smaller of the two so it can never poke outside the bore at any
/// rotation. Pivot anchors precisely at the geometric center of the bore.
private struct ThrottleBody: View {
    let rect: CGRect
    let openPercentage: Double

    var body: some View {
        GeometryReader { _ in
            let angle = intakeBladeClosedDeg + intakeBladeOpenSweepDeg * openPercentage
            let wallThickness: CGFloat = 2
            // Blade fits within the bore at any rotation: pick the smaller
            // bore dimension so rotation by 90° still keeps the blade inside.
            let bore = min(rect.width, rect.height)
            let bladeLength = bore * intakeBladeLengthFraction
            let bladeThickness = bore * intakeBladeThicknessFraction
            let pivotSize = bladeThickness * 1.4

            ZStack {
                // Bore walls drawn at the rect's vertical edges.
                Rectangle()
                    .fill(metalMidColor)
                    .frame(width: wallThickness, height: rect.height)
                    .position(x: rect.minX + wallThickness / 2, y: rect.midY)

                Rectangle()
                    .fill(metalMidColor)
                    .frame(width: wallThickness, height: rect.height)
                    .position(x: rect.maxX - wallThickness / 2, y: rect.midY)

                // Inner shading — gives the bore a sense of depth.
                Rectangle()
                    .fill(metalDarkColor)
                    .frame(width: rect.width - wallThickness * 2, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                Rectangle()
                    .fill(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                    .frame(width: bladeLength, height: bladeThickness)
                    .rotationEffect(.degrees(angle), anchor: .center)
                    .position(x: rect.midX, y: rect.midY)
                    .animation(.linear(duration: 0.05), value: openPercentage)

                Circle()
                    .fill(metalLightColor)
                    .frame(width: pivotSize, height: pivotSize)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }
}

private struct PlenumChamber: View {
    let rect: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(metalDarkColor)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(metalOutlineColor, lineWidth: 1))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

private struct Runners: View {
    let count: Int
    let height: CGFloat
    let plenumRect: CGRect
    let runnerY: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            for i in 0..<count {
                let (x, w) = runnerSlot(at: i)
                let rect = CGRect(x: x, y: runnerY, width: w, height: height)
                let path = Path(roundedRect: rect, cornerRadius: 1.5)
                ctx.fill(path, with: .color(metalMidColor))
                ctx.stroke(path, with: .color(metalOutlineColor), lineWidth: 1)
            }
        }
    }

    private func runnerSlot(at i: Int) -> (CGFloat, CGFloat) {
        let totalWidth = plenumRect.width * 0.88
        let slotWidth = totalWidth / CGFloat(count)
        let drawWidth = slotWidth * intakeRunnerSlotFillFraction
        let startX = plenumRect.midX - totalWidth / 2 + slotWidth / 2 - drawWidth / 2
        return (startX + slotWidth * CGFloat(i), drawWidth)
    }
}

private struct CylinderHead: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .fill(metalLightColor)
            .overlay(Rectangle().stroke(metalOutlineColor, lineWidth: 1))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

private struct AirflowOverlay: View {
    let intensity: Double
    let plenumRect: CGRect
    let runnerCount: Int
    let runnerY: CGFloat
    let runnerHeight: CGFloat
    let bodyTopY: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let alpha = min(max(intensity, 0), 1)
            let strokeColor = airflowColor.opacity(alpha)
            let dash: [CGFloat] = [3, 3]
            let throttleStreamX = plenumRect.midX

            var stream = Path()
            stream.move(to: CGPoint(x: throttleStreamX, y: bodyTopY + 4))
            stream.addLine(to: CGPoint(x: throttleStreamX, y: plenumRect.minY - 1))
            ctx.stroke(stream, with: .color(strokeColor),
                       style: StrokeStyle(lineWidth: 1.5, dash: dash))

            for i in 0..<runnerCount {
                let x = runnerCenterX(at: i)
                var branch = Path()
                branch.move(to: CGPoint(x: throttleStreamX, y: plenumRect.midY))
                branch.addQuadCurve(
                    to: CGPoint(x: x, y: runnerY + 2),
                    control: CGPoint(x: (throttleStreamX + x) / 2, y: plenumRect.maxY)
                )
                branch.addLine(to: CGPoint(x: x, y: runnerY + runnerHeight - 2))
                ctx.stroke(branch, with: .color(strokeColor),
                           style: StrokeStyle(lineWidth: 1.25, dash: dash))
            }
        }
    }

    private func runnerCenterX(at i: Int) -> CGFloat {
        let totalWidth = plenumRect.width * 0.88
        let slotWidth = totalWidth / CGFloat(runnerCount)
        return plenumRect.midX - totalWidth / 2 + slotWidth / 2 + slotWidth * CGFloat(i)
    }
}

// MARK: - Slider controls

struct PrecisionThrottleSlider: View {
    @Binding var value: Double

    var body: some View {
        PercentageSlider(
            label: "THROTTLE INPUT",
            value: $value,
            valueColor: .orange,
            fillColor: .orange.opacity(0.35)
        )
    }
}

/// Continuous clutch pressure slider. Mirrors the throttle slider so the two
/// inputs visually pair on either side of the dashboard panel.
struct PrecisionClutchSlider: View {
    let pressure: Double
    let onChange: (Double) -> Void

    /// Pedal position is the inverse of native engagement — at the left the
    /// pedal is up (clutch engaged); at the right it's mashed (disengaged).
    private var pedalPosition: Double { 1.0 - pressure }

    var body: some View {
        PercentageSlider(
            label: "CLUTCH PEDAL",
            value: Binding(
                get: { pedalPosition },
                set: { newPedal in onChange(1.0 - newPedal) }
            ),
            valueColor: pressure < 0.5 ? .orange : .green,
            fillColor: Color.orange.opacity(0.25)
        )
    }
}

/// Generic 0..1 horizontal slider with a labeled readout. Used by both
/// throttle and clutch inputs so the styling stays in lockstep.
private struct PercentageSlider: View {
    let label: String
    @Binding var value: Double
    let valueColor: Color
    let fillColor: Color
    private let height: CGFloat = 32
    private let handleWidth: CGFloat = 20

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).modifier(RetroFont(size: 9)).foregroundColor(.gray)
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .modifier(RetroFont(size: 9))
                    .foregroundColor(valueColor)
            }

            GeometryReader { geo in
                let width = geo.size.width - handleWidth
                let x = width * CGFloat(value)

                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.05))

                    HStack(spacing: 0) {
                        ForEach(0..<11) { i in
                            Rectangle().fill(Color.sidebarTextSecondary.opacity(0.3)).frame(width: 1)
                            if i != 10 { Spacer() }
                        }
                    }
                    .padding(.vertical, 8)

                    Rectangle()
                        .fill(fillColor)
                        .frame(width: x + handleWidth / 2)

                    Rectangle()
                        .fill(Color(white: 0.18))
                        .frame(width: handleWidth)
                        .overlay(Rectangle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .overlay(HStack(spacing: 2) {
                            ForEach(0..<3) { _ in
                                Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1, height: 12)
                            }
                        })
                        .offset(x: x)
                }
                .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    value = min(max(0, Double((v.location.x - handleWidth/2) / width)), 1)
                })
            }
            .frame(height: height)
        }
    }
}
