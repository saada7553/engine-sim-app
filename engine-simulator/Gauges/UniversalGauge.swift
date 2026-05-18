//
//  UniversalGauge.swift
//  engine-simulator
//
//  Created by Claude on 1/7/26.
//

import SwiftUI
import CoreGraphics
import Combine

// MARK: - Needle Animation State

/// Class to manage needle physics state across TimelineView updates
/// Uses spring-damper physics for smooth, realistic needle movement
class NeedleAnimationState: ObservableObject {
    var position: Double = 0.0
    private var velocity: Double = 0.0
    private var lastUpdateTime: Date?

    /// Update needle position using spring-damper physics
    /// Returns true to trigger view update (discardable result used in TimelineView)
    @discardableResult
    func update(targetPosition: Double, currentTime: Date, config: GaugeNeedleConfig) -> Bool {
        guard let lastTime = lastUpdateTime else {
            lastUpdateTime = currentTime
            return true
        }

        let dt = currentTime.timeIntervalSince(lastTime)
        lastUpdateTime = currentTime

        // Clamp dt to avoid physics explosions on app resume
        let clampedDt = min(dt, 0.1)

        // Spring-damper physics
        // F = ks * (target - position) - kd * velocity
        let springForce = config.ks * (targetPosition - position)
        let dampingForce = config.kd * velocity
        let acceleration = springForce - dampingForce

        // Update velocity and clamp
        velocity += acceleration * clampedDt
        velocity = max(-config.maxVelocity, min(config.maxVelocity, velocity))

        // Update position and clamp to valid range
        position += velocity * clampedDt
        position = max(0.0, min(1.0, position))

        return true
    }

    /// Reset state (useful when gauge configuration changes)
    func reset(to initialPosition: Double = 0.0) {
        position = initialPosition
        velocity = 0.0
        lastUpdateTime = nil
    }
}

/// A highly configurable gauge view that supports:
/// - Colored bands with configurable positions
/// - Major and minor tick marks
/// - Smooth needle animation using spring-damper physics
/// - Non-linear gamma scaling
/// - Adaptive text/tick density based on gauge size
/// - Maintains circular aspect ratio while filling available space
struct UniversalGauge: View {
    @ObservedObject var engineVm: EngineViewModel
    let config: GaugeConfiguration
    let valueKeyPath: KeyPath<EngineViewModel, Double>

    // Smooth needle animation state (using class to persist across TimelineView updates)
    @StateObject private var needleState = NeedleAnimationState()

    private var targetValue: Double {
        engineVm[keyPath: valueKeyPath]
    }

    var body: some View {
        // TimelineView provides smooth animation updates that don't block during UI interactions
        TimelineView(.animation) { timeline in
            let _ = needleState.update(
                targetPosition: config.normalizedPosition(for: targetValue),
                currentTime: timeline.date,
                config: config.needle
            )

            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let outerRadius = size / 2 - 20  // Padding for labels

                // Determine if we should use compact mode (K abbreviation, fewer labels)
                let isCompact = size < 180
                let isVeryCompact = size < 120

                ZStack {
                    // Background
                    config.backgroundColor

                    // All gauge graphics drawn in a single Canvas
                    Canvas { context, canvasSize in
                        let canvasCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

                        // Draw bands
                        for band in config.bands {
                            drawBand(context: context, center: canvasCenter, band: band, outerRadius: outerRadius)
                        }

                        // Draw tick marks with adaptive density
                        drawTicks(context: context, center: canvasCenter, outerRadius: outerRadius,
                                  isCompact: isCompact, isVeryCompact: isVeryCompact, gaugeSize: size)

                        // Draw needle using smooth animated position
                        drawNeedle(context: context, center: canvasCenter, normalizedPosition: needleState.position, outerRadius: outerRadius)

                        // Draw center cap
                        let capSize = max(4.0, size * 0.03)
                        let capRect = CGRect(x: canvasCenter.x - capSize, y: canvasCenter.y - capSize, width: capSize * 2, height: capSize * 2)
                        context.fill(Circle().path(in: capRect), with: .color(.appBackground))
                        context.stroke(Circle().path(in: capRect), with: .color(.sidebarTextSecondary), lineWidth: 1)
                    }

                    // Value display (using SwiftUI views for text)
                    VStack(spacing: 2) {
                        Text(formattedDisplayValue(compact: isCompact))
                            .font(.system(size: size * 0.12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        if !config.unit.isEmpty {
                            Text(config.unit)
                                .font(.system(size: size * 0.05, weight: .medium, design: .monospaced))
                                .foregroundColor(config.needleColor)
                        }
                    }
                    .position(x: center.x, y: center.y + outerRadius * 0.25)

                    // Title label
                    Text(config.title)
                        .font(.system(size: max(8, size * 0.05), weight: .medium, design: .monospaced))
                        .foregroundColor(config.labelColor)
                        .position(x: center.x, y: center.y + outerRadius * 0.65)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Formatted Value

    private func formattedDisplayValue(compact: Bool) -> String {
        // Always show as integer for cleaner display
        let intValue = Int(targetValue)

        if compact && abs(intValue) >= 1000 {
            // Use K abbreviation for compact mode
            let kValue = Double(intValue) / 1000.0
            if kValue == kValue.rounded() {
                return "\(Int(kValue))K"
            }
            return String(format: "%.1fK", kValue)
        }

        return "\(intValue)"
    }

    // MARK: - Drawing Functions

    private func drawBand(context: GraphicsContext, center: CGPoint, band: GaugeBand, outerRadius: CGFloat) {
        let startPos = config.normalizedPosition(for: band.start)
        let endPos = config.normalizedPosition(for: band.end)

        var startAngle = config.angle(for: startPos) + Double(band.shortenStart)
        var endAngle = config.angle(for: endPos) - Double(band.shortenEnd)

        // Convert from mathematical angles to SwiftUI angles
        startAngle = -startAngle
        endAngle = -endAngle

        let radius = outerRadius - band.radialOffset - band.width / 2

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: Angle(radians: startAngle),
            endAngle: Angle(radians: endAngle),
            clockwise: startAngle > endAngle
        )

        context.stroke(path, with: .color(band.color), lineWidth: band.width)
    }

    private func drawTicks(context: GraphicsContext, center: CGPoint, outerRadius: CGFloat,
                           isCompact: Bool, isVeryCompact: Bool, gaugeSize: CGFloat) {
        let tickStart = outerRadius - 2

        // Adaptive step multiplier - show fewer ticks on smaller gauges
        let majorStepMultiplier: Double = isVeryCompact ? 4.0 : (isCompact ? 2.0 : 1.0)
        let effectiveMajorStep = config.ticks.majorStep * majorStepMultiplier

        // Skip minor ticks on compact gauges
        let showMinorTicks = !isCompact

        // Adaptive font size
        let fontSize = max(7, min(12, gaugeSize * 0.05))

        var tickValue = config.minValue
        while tickValue <= config.maxValue {
            let isMajor = tickValue.truncatingRemainder(dividingBy: effectiveMajorStep) == 0
            let isMinor = tickValue.truncatingRemainder(dividingBy: config.ticks.minorStep) == 0

            // Skip minor ticks on compact gauges or above maxMinorTick
            if !isMajor {
                if !showMinorTicks || tickValue > config.ticks.maxMinorTick {
                    tickValue += config.ticks.minorStep
                    continue
                }
            }

            if isMajor || isMinor {
                let normalizedPos = config.normalizedPosition(for: tickValue)
                let angle = config.angle(for: normalizedPos)

                let tickLength = isMajor ? config.ticks.majorTickLength : config.ticks.minorTickLength
                let tickWidth = isMajor ? config.ticks.majorTickWidth : config.ticks.minorTickWidth

                let innerRadius = tickStart - tickLength
                let outerPoint = CGPoint(
                    x: center.x + cos(angle) * tickStart,
                    y: center.y - sin(angle) * tickStart
                )
                let innerPoint = CGPoint(
                    x: center.x + cos(angle) * innerRadius,
                    y: center.y - sin(angle) * innerRadius
                )

                var path = Path()
                path.move(to: outerPoint)
                path.addLine(to: innerPoint)

                context.stroke(
                    path,
                    with: .color(isMajor ? config.tickColor : config.tickColor.opacity(0.5)),
                    lineWidth: tickWidth
                )

                // Draw label for major ticks
                if isMajor {
                    let labelRadius = innerRadius - max(8, gaugeSize * 0.05)
                    let labelPoint = CGPoint(
                        x: center.x + cos(angle) * labelRadius,
                        y: center.y - sin(angle) * labelRadius
                    )

                    let labelText = formatTickLabel(tickValue, compact: isCompact)
                    let font = Font.system(size: fontSize, weight: .medium, design: .monospaced)

                    context.draw(
                        Text(labelText)
                            .font(font)
                            .foregroundColor(config.tickColor),
                        at: labelPoint,
                        anchor: .center
                    )
                }
            }

            tickValue += config.ticks.minorStep
        }
    }

    private func drawNeedle(context: GraphicsContext, center: CGPoint, normalizedPosition: Double, outerRadius: CGFloat) {
        let angle = config.angle(for: normalizedPosition)
        let innerRadius = outerRadius * config.needle.innerRadiusRatio
        let needleOuterRadius = outerRadius * config.needle.outerRadiusRatio

        let startPoint = CGPoint(
            x: center.x + cos(angle) * innerRadius,
            y: center.y - sin(angle) * innerRadius
        )
        let endPoint = CGPoint(
            x: center.x + cos(angle) * needleOuterRadius,
            y: center.y - sin(angle) * needleOuterRadius
        )

        var path = Path()
        path.move(to: startPoint)
        path.addLine(to: endPoint)

        context.stroke(
            path,
            with: .color(config.needleColor),
            style: StrokeStyle(lineWidth: config.needle.width, lineCap: .round)
        )
    }

    private func formatTickLabel(_ value: Double, compact: Bool) -> String {
        let intValue = Int(value)

        if compact && abs(intValue) >= 1000 {
            // Use K abbreviation
            let kValue = Double(intValue) / 1000.0
            if kValue == kValue.rounded() {
                return "\(Int(kValue))K"
            }
            return String(format: "%.1fK", kValue)
        }

        if value == value.rounded() {
            return String(intValue)
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Preview

#Preview {
    let oscilloscopeManager = OscilloscopeManager()
    let vm = EngineViewModel(oscillioscopeManager: oscilloscopeManager)

    return VStack {
        UniversalGauge(
            engineVm: vm,
            config: GaugePresets.tachometer(redline: 6500),
            valueKeyPath: \.rpm
        )
        .frame(width: 300, height: 300)

        UniversalGauge(
            engineVm: vm,
            config: GaugePresets.speedometer(),
            valueKeyPath: \.vehicleSpeed
        )
        .frame(width: 300, height: 300)
    }
    .background(Color.appBackground)
}
