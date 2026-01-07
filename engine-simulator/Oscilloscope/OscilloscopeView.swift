//
//  OscilloscopeView.swift
//  engine-simulator
//

import SwiftUI
import Combine

// MARK: - Base Oscilloscope View

/// Generic oscilloscope display view that renders data from OscilloscopeManager
struct OscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    let config: OscilloscopeConfig

    var showTitle: Bool = true
    var showAxisLabels: Bool = true
    var detachmentThreshold: CGFloat = 100.0

    var body: some View {
        GeometryReader { geometry in
            let bounds = manager.getAxisBounds(for: config.type, config: config)
            let points = manager.getPoints(for: config.type, config: config)
            let gridY = calculateGridLines(minVal: bounds.yMin, maxVal: bounds.yMax, size: geometry.size.height)
            let gridX = calculateGridLines(minVal: bounds.xMin, maxVal: bounds.xMax, size: geometry.size.width)

            ZStack(alignment: .topLeading) {
                // Background
                Color.black.opacity(0.8)

                // Grid
                Path { path in
                    // Horizontal lines
                    for val in gridY {
                        let y = convertY(val, bounds: bounds, size: geometry.size)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }

                    // Vertical lines
                    for val in gridX {
                        let x = convertX(val, bounds: bounds, size: geometry.size)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                }
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)

                // Zero Line
                if bounds.yMin < 0 && bounds.yMax > 0 {
                    let zeroY = convertY(0, bounds: bounds, size: geometry.size)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: zeroY))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: zeroY))
                    }
                    .stroke(config.color.opacity(0.5), lineWidth: 0.5)
                }

                // Oscilloscope Trace with fading (matches C++ line width/opacity fading)
                // C++ fades older points by making them thinner: width = lineWidth * max(s, 0.5)
                // where s = i / totalPoints (0 = oldest, 1 = newest)
                Canvas { context, size in
                    drawOscilloscopeTrace(
                        context: context,
                        points: points,
                        bounds: bounds,
                        size: size,
                        color: config.color,
                        baseLineWidth: config.lineWidth,
                        drawReverse: config.drawReverse
                    )
                }
                .clipped()

                // Y-Axis Labels
                if showAxisLabels {
                    ForEach(gridY, id: \.self) { val in
                        Text(formatValue(val))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                            .position(x: 20, y: convertY(val, bounds: bounds, size: geometry.size) - 6)
                    }
                }

                // Title
                if showTitle {
                    VStack {
                        HStack {
                            Spacer()
                            Text(config.type.displayName)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(config.color)
                                .padding(4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                    .padding(6)
                }

                // Axis Labels
                if showAxisLabels {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(config.xAxisLabel) / \(config.yAxisLabel)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.gray.opacity(0.7))
                                .padding(4)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func calculateGridLines(minVal: Double, maxVal: Double, size: CGFloat) -> [Double] {
        let range = maxVal - minVal
        guard range > 0 else { return [] }

        let targetSteps = max(2, Int(size / 40))
        let roughStep = range / Double(targetSteps)

        let magnitude = pow(10, floor(log10(roughStep)))
        let normalizedStep = roughStep / magnitude

        let step: Double
        if normalizedStep < 1.5 { step = 1.0 * magnitude }
        else if normalizedStep < 3.0 { step = 2.0 * magnitude }
        else if normalizedStep < 7.0 { step = 5.0 * magnitude }
        else { step = 10.0 * magnitude }

        var lines: [Double] = []
        var current = ceil(minVal / step) * step

        while current <= maxVal + (step * 0.001) {
            if current >= minVal - (step * 0.001) {
                lines.append(current)
            }
            current += step
        }

        return lines
    }

    private func formatValue(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return String(format: "%.1fk", value / 1000)
        } else if abs(value) < 0.01 && value != 0 {
            return String(format: "%.3f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }

    private func convertY(_ val: Double, bounds: (xMin: Double, xMax: Double, yMin: Double, yMax: Double), size: CGSize) -> CGFloat {
        let range = bounds.yMax - bounds.yMin
        guard range != 0 else { return size.height / 2 }
        return size.height * (1.0 - CGFloat((val - bounds.yMin) / range))
    }

    private func convertX(_ val: Double, bounds: (xMin: Double, xMax: Double, yMin: Double, yMax: Double), size: CGSize) -> CGFloat {
        let range = bounds.xMax - bounds.xMin
        guard range != 0 else { return 0 }
        return CGFloat((val - bounds.xMin) / range) * size.width
    }

    /// Draw oscilloscope trace with C++ style fading (older = thinner/more transparent)
    /// Matches C++ oscilloscope.cpp render() behavior
    private func drawOscilloscopeTrace(
        context: GraphicsContext,
        points: [CGPoint],
        bounds: (xMin: Double, xMax: Double, yMin: Double, yMax: Double),
        size: CGSize,
        color: Color,
        baseLineWidth: CGFloat,
        drawReverse: Bool
    ) {
        guard points.count > 1 else { return }

        let totalPoints = CGFloat(points.count)

        // Convert all points to screen coordinates
        let screenPoints: [CGPoint] = points.map { point in
            let x = convertX(point.x, bounds: bounds, size: size)
            let y = convertY(point.y, bounds: bounds, size: size)
            return CGPoint(x: x, y: y)
        }

        var prevScreenPoint = screenPoints[0]
        var lastDetached = false

        for i in 1..<screenPoints.count {
            let currentScreenPoint = screenPoints[i]

            // Calculate s = normalized position (0 = oldest, 1 = newest)
            // Matches C++ s = (float)(i) / (n0 + n1)
            let s = CGFloat(i) / totalPoints

            // Detachment logic (matches C++ exactly):
            // detached = prev.x > p_i.x || abs(p_i.x - prev.x) > pixelsToUnits(100)
            let xWentBack = prevScreenPoint.x > currentScreenPoint.x
            let largeGap = abs(currentScreenPoint.x - prevScreenPoint.x) > detachmentThreshold
            let detached = xWentBack || largeGap

            // Only draw line segment if not detached (or if drawReverse mode)
            let shouldDraw = drawReverse || (!detached && !lastDetached)

            if shouldDraw {
                // Calculate line width (matches C++ exactly):
                // width = lineWidth * max(pixelsToUnits(1.0) * s, pixelsToUnits(0.5))
                // Simplified: width = baseLineWidth * max(s, 0.5)
                var lineWidth = baseLineWidth * max(s, 0.3)

                // C++ adds extra width for newest 5%:
                // if (s > 0.95f) width += pixelsToUnits(((s - 0.95f) / 0.05f) * 2)
                if s > 0.95 {
                    lineWidth += ((s - 0.95) / 0.05) * 2.0
                }

                // Calculate opacity (older = more transparent)
                let opacity = max(s, 0.75)

                // Draw line segment
                var path = Path()
                path.move(to: prevScreenPoint)
                path.addLine(to: currentScreenPoint)

                context.stroke(
                    path,
                    with: .color(color.opacity(Double(opacity))),
                    lineWidth: lineWidth
                )
            }

            lastDetached = detached
            prevScreenPoint = currentScreenPoint
        }
    }

    // Legacy path function (kept for reference, but Canvas version is used)
    private func oscilloscopePath(points: [CGPoint], bounds: (xMin: Double, xMax: Double, yMin: Double, yMax: Double), size: CGSize) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }

        var lastPoint: CGPoint? = nil
        var lastX: Double? = nil

        for point in points {
            let x = convertX(point.x, bounds: bounds, size: size)
            let y = convertY(point.y, bounds: bounds, size: size)
            let currentPoint = CGPoint(x: x, y: y)

            if let last = lastPoint, let prevX = lastX {
                let xJumpedBack = point.x < prevX
                let largeGap = abs(currentPoint.x - last.x) > detachmentThreshold
                let detached = !config.drawReverse && (xJumpedBack || largeGap)

                if detached {
                    path.move(to: currentPoint)
                } else {
                    path.addLine(to: currentPoint)
                }
            } else {
                path.move(to: currentPoint)
            }

            lastPoint = currentPoint
            lastX = point.x
        }

        return path
    }
}

// MARK: - Specialized Oscilloscope Views

/// Torque vs RPM oscilloscope (dyno curve)
struct TorqueOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        OscilloscopeView(
            manager: manager,
            config: .standard(for: .torque)
        )
    }
}

/// Power vs RPM oscilloscope (dyno curve)
struct PowerOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        OscilloscopeView(
            manager: manager,
            config: .standard(for: .power)
        )
    }
}

/// Combined dyno view showing both torque and power curves
struct DynoOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        ZStack {
            OscilloscopeView(
                manager: manager,
                config: .standard(for: .torque),
                showTitle: false
            )

            OscilloscopeView(
                manager: manager,
                config: .standard(for: .power),
                showTitle: false
            )
            .background(Color.clear)

            // Custom title showing both
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 8, height: 8)
                            Text("Torque")
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.pink).frame(width: 8, height: 8)
                            Text("Power")
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                }
                Spacer()
            }
            .padding(6)
        }
    }
}

/// Spark advance vs RPM oscilloscope
struct SparkAdvanceOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        OscilloscopeView(
            manager: manager,
            config: .standard(for: .sparkAdvance)
        )
    }
}

/// Total exhaust flow oscilloscope (cycle-synced)
struct TotalExhaustFlowOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        OscilloscopeView(
            manager: manager,
            config: .standard(for: .totalExhaustFlow)
        )
    }
}

/// Exhaust flow oscilloscope (cycle-synced)
struct ExhaustFlowOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        OscilloscopeView(
            manager: manager,
            config: .standard(for: .exhaustFlow)
        )
    }
}

/// Intake flow oscilloscope (cycle-synced)
struct IntakeFlowOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        OscilloscopeView(
            manager: manager,
            config: .standard(for: .intakeFlow)
        )
    }
}

/// Combined intake/exhaust flow view
struct FlowOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        ZStack {
            OscilloscopeView(
                manager: manager,
                config: .standard(for: .exhaustFlow),
                showTitle: false
            )

            OscilloscopeView(
                manager: manager,
                config: .standard(for: .intakeFlow),
                showTitle: false
            )
            .background(Color.clear)

            // Custom title
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 8, height: 8)
                            Text("Exhaust")
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.blue).frame(width: 8, height: 8)
                            Text("Intake")
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                }
                Spacer()
            }
            .padding(6)
        }
    }
}

/// Exhaust valve lift oscilloscope (cycle-synced)
struct ExhaustValveLiftOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        OscilloscopeView(
            manager: manager,
            config: .standard(for: .exhaustValveLift)
        )
    }
}

/// Intake valve lift oscilloscope (cycle-synced)
struct IntakeValveLiftOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        OscilloscopeView(
            manager: manager,
            config: .standard(for: .intakeValveLift)
        )
    }
}

/// Combined valve lift view
struct ValveLiftOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        ZStack {
            OscilloscopeView(
                manager: manager,
                config: .standard(for: .exhaustValveLift),
                showTitle: false
            )

            OscilloscopeView(
                manager: manager,
                config: .standard(for: .intakeValveLift),
                showTitle: false
            )
            .background(Color.clear)

            // Custom title
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 8, height: 8)
                            Text("Exhaust")
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.blue).frame(width: 8, height: 8)
                            Text("Intake")
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                }
                Spacer()
            }
            .padding(6)
        }
    }
}

/// Cylinder pressure oscilloscope (cycle-synced)
struct CylinderPressureOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        OscilloscopeView(
            manager: manager,
            config: .standard(for: .cylinderPressure)
        )
    }
}

/// Cylinder molecules oscilloscope (cycle-synced)
struct CylinderMoleculesOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        OscilloscopeView(
            manager: manager,
            config: .standard(for: .cylinderMolecules)
        )
    }
}

/// Pressure-Volume diagram oscilloscope (parametric)
struct PVOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager

    var body: some View {
        OscilloscopeView(
            manager: manager,
            config: .standard(for: .PV)
        )
    }
}

// MARK: - Oscilloscope Selector View

/// A view that can display any oscilloscope type based on selection
struct SelectableOscilloscopeView: View {
    @ObservedObject var manager: OscilloscopeManager
    let type: EngineScopeType

    var body: some View {
        OscilloscopeView(
            manager: manager,
            config: .standard(for: type)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct OscilloscopeView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = OscilloscopeManager()

        VStack(spacing: 10) {
            TorqueOscilloscopeView(manager: manager)
                .frame(height: 150)

            CylinderPressureOscilloscopeView(manager: manager)
                .frame(height: 150)

            PVOscilloscopeView(manager: manager)
                .frame(height: 150)
        }
        .padding()
        .background(Color.black)
    }
}
#endif
