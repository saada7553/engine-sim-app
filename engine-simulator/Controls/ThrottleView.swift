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

private let clutchAspectRatio: CGFloat = 1.55       // width / height of the drawn cross-section
private let intakeAspectRatio: CGFloat = 1.10
private let visualizerPadding: CGFloat = 6

// Clutch component sizing (all fractions of the drawing rect).
private let clutchShaftHeightFraction: CGFloat = 0.07
private let clutchFlywheelHeightFraction: CGFloat = 0.78
private let clutchFlywheelWidthFraction: CGFloat = 0.075
private let clutchFrictionHeightFraction: CGFloat = 0.56
private let clutchFrictionWidthFraction: CGFloat = 0.05
private let clutchPressurePlateHeightFraction: CGFloat = 0.68
private let clutchPressurePlateWidthFraction: CGFloat = 0.07
private let clutchDiaphragmDepthFraction: CGFloat = 0.10
private let clutchDisengageGapFraction: CGFloat = 0.045
private let clutchLabelInset: CGFloat = 4

// Intake component sizing.
private let intakeThrottleBoreHeightFraction: CGFloat = 0.18
private let intakeThrottleBoreWidthFraction: CGFloat = 0.28
private let intakePlenumHeightFraction: CGFloat = 0.22
private let intakePlenumWidthFraction: CGFloat = 0.80
private let intakeRunnerCount: Int = 4
private let intakeRunnerWidthFraction: CGFloat = 0.06
private let intakeRunnerHeightFraction: CGFloat = 0.30
private let intakeHeadHeightFraction: CGFloat = 0.08
private let intakeBladeLengthFraction: CGFloat = 0.85
private let intakeBladeThicknessFraction: CGFloat = 0.07
private let intakeBladeClosedDeg: Double = 4
private let intakeBladeOpenSweepDeg: Double = 84
private let intakeArrowVisibilityThreshold: Double = 0.08

// Shared colors keep both visualizers anchored to the app's existing palette.
private let metalLightColor = Color(white: 0.55)
private let metalMidColor = Color(white: 0.32)
private let metalDarkColor = Color(white: 0.16)
private let metalOutlineColor = Color.white.opacity(0.22)
private let frictionColor = Color.orange.opacity(0.85)
private let frictionOutlineColor = Color.orange.opacity(0.5)
private let airflowColor = Color.cyan.opacity(0.7)

struct ThrottleView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        HStack(spacing: 0) {
            column(title: "CLUTCH ASSEMBLY") {
                AspectFitContainer(aspectRatio: clutchAspectRatio) {
                    ClutchCrossSection(isEngaged: !vm.clutchPressed)
                }
                ClutchPedal(isPressed: Binding(get: { vm.clutchPressed }, set: { _ in vm.toggleClutch() }))
            }

            Divider().background(Color.white.opacity(0.1))

            column(title: "INTAKE MANIFOLD") {
                AspectFitContainer(aspectRatio: intakeAspectRatio) {
                    IntakeCrossSection(openPercentage: vm.throttlePosition)
                }
                PrecisionThrottleSlider(value: $vm.throttlePosition)
            }
        }
        .background(Color.black.opacity(0.2))
        .border(Color.white.opacity(0.1), width: 1)
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

/// Centers a fixed-aspect rectangle inside the available space, so child
/// drawings never stretch when the tile reshapes. Empty space is letterboxed
/// on whichever axis is in surplus.
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
//
// Axial side view, looking along the rotational axis of the powertrain.
// Layout from left to right:
//   1. Engine crankshaft stub (input)
//   2. Flywheel (rigid disc bolted to crankshaft)
//   3. Friction disc (splined to transmission input shaft)
//   4. Pressure plate + diaphragm fingers
//   5. Transmission input shaft (output)
//
// "Engaged" = pressure plate clamps friction disc into the flywheel.
// "Disengaged" = release bearing has pushed the diaphragm, lifting the
// pressure plate off the friction disc — both gaps open by the same amount.

private struct ClutchCrossSection: View {
    var isEngaged: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cy = h / 2

            // Position the flywheel midway along the input shaft; everything
            // else is laid out relative to it so the assembly stays centered.
            let flywheelWidth = w * clutchFlywheelWidthFraction
            let frictionWidth = w * clutchFrictionWidthFraction
            let pressurePlateWidth = w * clutchPressurePlateWidthFraction
            let diaphragmDepth = w * clutchDiaphragmDepthFraction
            let totalCoreWidth = flywheelWidth + frictionWidth + pressurePlateWidth + diaphragmDepth
            let coreStartX = (w - totalCoreWidth) / 2

            let gap = isEngaged ? 0 : w * clutchDisengageGapFraction

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

                Flywheel(rect: CGRect(
                    x: flywheelX,
                    y: cy - h * clutchFlywheelHeightFraction / 2,
                    width: flywheelWidth,
                    height: h * clutchFlywheelHeightFraction
                ))

                FrictionDisc(rect: CGRect(
                    x: frictionX,
                    y: cy - h * clutchFrictionHeightFraction / 2,
                    width: frictionWidth,
                    height: h * clutchFrictionHeightFraction
                ))

                PressurePlate(rect: CGRect(
                    x: pressurePlateX,
                    y: cy - h * clutchPressurePlateHeightFraction / 2,
                    width: pressurePlateWidth,
                    height: h * clutchPressurePlateHeightFraction
                ))

                DiaphragmSpring(
                    startX: diaphragmX,
                    endX: diaphragmX + diaphragmDepth,
                    cy: cy,
                    height: h * clutchPressurePlateHeightFraction
                )

                StateLabel(isEngaged: isEngaged)
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isEngaged)
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

private struct Flywheel: View {
    let rect: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(metalLightColor)
                .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(metalOutlineColor, lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)

            // Subtle horizontal scribes hint at machined disc faces.
            ForEach(0..<3, id: \.self) { i in
                Rectangle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: rect.width, height: 0.75)
                    .offset(x: rect.minX, y: rect.minY + rect.height * (0.25 + 0.25 * CGFloat(i)))
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

private struct PressurePlate: View {
    let rect: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(metalLightColor)
            .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(metalOutlineColor, lineWidth: 1))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

/// Diaphragm spring fingers — drawn as a fan of lines that converge near the
/// transmission-input axis. Suggests the spring stack without trying to be a
/// faithful CAD drawing.
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
    let isEngaged: Bool

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text(isEngaged ? "ENGAGED" : "DISENGAGED")
                    .modifier(RetroFont(size: 8))
                    .foregroundColor(isEngaged ? .green.opacity(0.85) : .orange.opacity(0.85))
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
// Side view of the manifold:
//
//                  ┌── throttle body (butterfly inside) ──┐
//                  │                                       │
//   ┌──────────────┴────── plenum chamber ─────────────────┴──────────────┐
//   │                                                                     │
//   │  ─runner─    ─runner─    ─runner─    ─runner─                       │
//   └─────┬──────────┬──────────┬──────────┬──────────────────────────────┘
//   ─────────────── cylinder head (intake ports) ──────────────────────────
//
// Airflow streams render through the throttle when it's open, fan across the
// plenum, and pulse down the runners. Closed throttle = no flow indicators.

private struct IntakeCrossSection: View {
    var openPercentage: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bodyWidth = w * intakeThrottleBoreWidthFraction
            let bodyHeight = h * intakeThrottleBoreHeightFraction
            let plenumWidth = w * intakePlenumWidthFraction
            let plenumHeight = h * intakePlenumHeightFraction
            let plenumX = (w - plenumWidth) / 2
            let plenumY = bodyHeight + 2

            let runnerHeight = h * intakeRunnerHeightFraction
            let runnerWidth = w * intakeRunnerWidthFraction
            let headHeight = h * intakeHeadHeightFraction
            let headY = h - headHeight
            let runnerY = plenumY + plenumHeight

            ZStack(alignment: .topLeading) {
                ThrottleBody(
                    rect: CGRect(x: (w - bodyWidth) / 2, y: 0, width: bodyWidth, height: bodyHeight),
                    openPercentage: openPercentage
                )

                PlenumChamber(rect: CGRect(x: plenumX, y: plenumY, width: plenumWidth, height: plenumHeight))

                Runners(
                    count: intakeRunnerCount,
                    width: runnerWidth,
                    height: runnerHeight,
                    plenumRect: CGRect(x: plenumX, y: plenumY, width: plenumWidth, height: plenumHeight),
                    runnerY: runnerY,
                    drawingWidth: w
                )

                CylinderHead(rect: CGRect(x: 0, y: headY, width: w, height: headHeight))

                if openPercentage > intakeArrowVisibilityThreshold {
                    AirflowOverlay(
                        intensity: openPercentage,
                        plenumRect: CGRect(x: plenumX, y: plenumY, width: plenumWidth, height: plenumHeight),
                        runnerCount: intakeRunnerCount,
                        runnerWidth: runnerWidth,
                        runnerY: runnerY,
                        runnerHeight: runnerHeight,
                        drawingWidth: w,
                        bodyTopY: 0,
                        bodyBottomY: bodyHeight
                    )
                }
            }
        }
    }
}

private struct ThrottleBody: View {
    let rect: CGRect
    let openPercentage: Double

    var body: some View {
        let angle = intakeBladeClosedDeg + intakeBladeOpenSweepDeg * openPercentage
        let wallThickness: CGFloat = 2
        let bladeLength = rect.width * intakeBladeLengthFraction
        let bladeThickness = rect.height * intakeBladeThicknessFraction

        ZStack(alignment: .topLeading) {
            // Bore walls (left and right edges of the throttle body).
            Rectangle()
                .fill(metalMidColor)
                .frame(width: wallThickness, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            Rectangle()
                .fill(metalMidColor)
                .frame(width: wallThickness, height: rect.height)
                .offset(x: rect.maxX - wallThickness, y: rect.minY)

            // Pivot pin in the middle.
            Circle()
                .fill(metalLightColor)
                .frame(width: bladeThickness * 1.4, height: bladeThickness * 1.4)
                .offset(x: rect.midX - bladeThickness * 0.7, y: rect.midY - bladeThickness * 0.7)

            // Butterfly blade.
            Rectangle()
                .fill(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                .frame(width: bladeLength, height: bladeThickness)
                .offset(x: rect.midX - bladeLength / 2, y: rect.midY - bladeThickness / 2)
                .rotationEffect(.degrees(angle), anchor: .center)
                .animation(.linear(duration: 0.05), value: openPercentage)
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
    let width: CGFloat
    let height: CGFloat
    let plenumRect: CGRect
    let runnerY: CGFloat
    let drawingWidth: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            for i in 0..<count {
                let x = runnerX(at: i)
                let rect = CGRect(x: x, y: runnerY, width: width, height: height)
                let path = Path(roundedRect: rect, cornerRadius: 1.5)
                ctx.fill(path, with: .color(metalMidColor))
                ctx.stroke(path, with: .color(metalOutlineColor), lineWidth: 1)
            }
        }
    }

    private func runnerX(at i: Int) -> CGFloat {
        let totalWidth = plenumRect.width * 0.82
        let spacing = totalWidth / CGFloat(count)
        let startX = plenumRect.midX - totalWidth / 2 + spacing / 2 - width / 2
        return startX + spacing * CGFloat(i)
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
    let runnerWidth: CGFloat
    let runnerY: CGFloat
    let runnerHeight: CGFloat
    let drawingWidth: CGFloat
    let bodyTopY: CGFloat
    let bodyBottomY: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            let alpha = min(max(intensity, 0), 1)
            let strokeColor = airflowColor.opacity(alpha)

            // Single stream descending through the throttle body, then
            // splitting evenly across runners. Drawn as dashed lines that
            // imply movement without animating frame-by-frame.
            let dash: [CGFloat] = [3, 3]
            let throttleStreamX = plenumRect.midX
            var stream = Path()
            stream.move(to: CGPoint(x: throttleStreamX, y: bodyTopY + 4))
            stream.addLine(to: CGPoint(x: throttleStreamX, y: plenumRect.minY - 1))
            ctx.stroke(stream, with: .color(strokeColor),
                       style: StrokeStyle(lineWidth: 1.5, dash: dash))

            // Branches into each runner.
            for i in 0..<runnerCount {
                let x = runnerX(at: i)
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

    private func runnerX(at i: Int) -> CGFloat {
        let totalWidth = plenumRect.width * 0.82
        let spacing = totalWidth / CGFloat(runnerCount)
        return plenumRect.midX - totalWidth / 2 + spacing / 2 + spacing * CGFloat(i)
    }
}

// MARK: - Pedal and slider (unchanged in behavior)

struct ClutchPedal: View {
    @Binding var isPressed: Bool

    var body: some View {
        Button(action: { isPressed.toggle() }) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 40, height: 50)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .rotation3DEffect(.degrees(isPressed ? 25 : 0), axis: (x: 1, y: 0, z: 0))

                    VStack(spacing: 5) {
                        ForEach(0..<5) { _ in Rectangle().fill(Color.black.opacity(0.5)).frame(width: 32, height: 2) }
                    }
                    .rotation3DEffect(.degrees(isPressed ? 25 : 0), axis: (x: 1, y: 0, z: 0))
                }
                Text(isPressed ? "DISENGAGED" : "ENGAGED")
                    .modifier(RetroFont(size: 8))
                    .foregroundColor(isPressed ? .orange : .orange.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }
}

struct PrecisionThrottleSlider: View {
    @Binding var value: Double
    private let height: CGFloat = 32
    private let handleWidth: CGFloat = 20

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("THROTTLE INPUT").modifier(RetroFont(size: 9)).foregroundColor(.gray)
                Spacer()
                Text(String(format: "%.0f%%", value * 100)).modifier(RetroFont(size: 9)).foregroundColor(.orange)
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
                        .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
                        .frame(width: handleWidth)
                        .overlay(Rectangle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .overlay(HStack(spacing: 2) { ForEach(0..<3) { _ in Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1, height: 12) } })
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
