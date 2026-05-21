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

/// Class to manage needle physics state across TimelineView updates.
///
/// Uses spring-damper physics with two stability tweaks:
///
/// 1. **Substepping** — semi-implicit Euler is stable only while
///    `dt × √ks < 2`. With ks values up to 1000 that's ~63 ms; one dropped
///    frame can push real dt past that. Each call now slices the elapsed
///    time into fixed `physicsStepSeconds` chunks so the inner step never
///    sees an unstable dt, regardless of how busy the run loop is.
///
/// 2. **Damping floor** — many of the gauge presets ship with kd well below
///    `2√ks` (critical damping). That's a recipe for visible oscillation on
///    a steady target — exactly the "RPM bouncing 3-5K on idle" the user
///    reported. We always run with at least critical damping so the needle
///    asymptotes to the target instead of ringing.
class NeedleAnimationState: ObservableObject {
    var position: Double = 0.0
    private var velocity: Double = 0.0
    private var lastUpdateTime: Date?

    private static let physicsStepSeconds: Double = 1.0 / 240.0
    /// Hard cap on the elapsed time we'll catch up on in one update. If the
    /// app goes background for several seconds we don't want to spin in a
    /// substep loop — just snap the integrator forward.
    private static let maxCatchUpSeconds: Double = 0.25

    @discardableResult
    func update(targetPosition: Double, currentTime: Date, config: GaugeNeedleConfig) -> Bool {
        guard let lastTime = lastUpdateTime else {
            lastUpdateTime = currentTime
            return true
        }

        let dt = currentTime.timeIntervalSince(lastTime)
        lastUpdateTime = currentTime
        if dt <= 0 { return true }

        let cappedDt = min(dt, Self.maxCatchUpSeconds)
        let stepDt = Self.physicsStepSeconds
        let ks = config.ks
        // Damping below critical (kd_c = 2√ks) lets the needle ring on a
        // steady target. Treat the preset's kd as a floor: we never damp
        // less than critical.
        let kdMin = 2.0 * sqrt(max(ks, 0))
        let kd = max(config.kd, kdMin)

        var remaining = cappedDt
        while remaining > 0 {
            let step = min(stepDt, remaining)
            remaining -= step

            let springForce = ks * (targetPosition - position)
            let dampingForce = kd * velocity
            let acceleration = springForce - dampingForce

            velocity += acceleration * step
            velocity = max(-config.maxVelocity, min(config.maxVelocity, velocity))

            position += velocity * step
            position = max(0.0, min(1.0, position))
        }

        return true
    }

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
                // Inset scales with the gauge: a 400pt gauge gets ~14pt of
                // padding for tick labels, smaller gauges proportionally
                // less. Cap so very large gauges don't waste space either.
                let labelInset = min(size * 0.035, 14)
                let outerRadius = size / 2 - labelInset

                // Determine if we should use compact mode (K abbreviation, fewer labels).
                // iOS thresholds are lower because the global 0.7 scaleEffect
                // shrinks every gauge by 30% visually — we want minor ticks
                // to keep drawing at smaller virtual sizes so they don't
                // vanish as soon as a gauge gets a modest tile.
                #if os(macOS)
                let isCompact = size < 180
                let isVeryCompact = size < 120
                #else
                let isCompact = size < 110
                let isVeryCompact = size < 70
                #endif

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

                    // Value display (using SwiftUI views for text).
                    // iOS compact / very-compact gauges drop the unit
                    // subtitle so a five-digit RPM (e.g. an F1 V12 redline
                    // of 18K) doesn't fight a "RPM" label for the same
                    // ~80pt of vertical space. macOS keeps the full
                    // treatment at every size.
                    VStack(spacing: 2) {
                        Text(formattedDisplayValue(compact: isCompact))
                            .font(.system(size: size * 0.12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        if !config.unit.isEmpty && shouldShowUnit(isCompact: isCompact) {
                            Text(config.unit)
                                .font(.system(size: size * 0.05, weight: .medium, design: .monospaced))
                                .foregroundColor(config.needleColor)
                        }
                    }
                    .position(x: center.x, y: center.y + outerRadius * 0.25)

                    // Title label — hidden on iOS in very-compact mode
                    // since the value alone is enough info at that size.
                    if shouldShowTitle(isVeryCompact: isVeryCompact) {
                        Text(config.title)
                            .font(.system(size: max(8, size * 0.05), weight: .medium, design: .monospaced))
                            .foregroundColor(config.labelColor)
                            .position(x: center.x, y: center.y + outerRadius * 0.65)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Adaptive text density

    /// Whether to render the small unit subtitle below the value. On iOS
    /// the global 0.7 scaleEffect makes compact gauges very small visually,
    /// so we drop the subtitle to give the value digits more room.
    private func shouldShowUnit(isCompact: Bool) -> Bool {
        #if os(macOS)
        return true
        #else
        return !isCompact
        #endif
    }

    /// Whether to render the bottom title label. iOS hides it in
    /// very-compact mode — the gauge's overall placement on the dash
    /// already communicates what it measures.
    private func shouldShowTitle(isVeryCompact: Bool) -> Bool {
        #if os(macOS)
        return true
        #else
        return !isVeryCompact
        #endif
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

        // Adaptive step multiplier — show fewer ticks on smaller gauges.
        // iOS is more aggressive (3× / 6× / 1.5× even at full size) so the
        // dial doesn't end up littered with numbers — the global 0.7
        // scaleEffect shrinks the gauge so every label is already 30%
        // smaller visually, and we'd rather show fewer + readable than
        // many + tiny.
        #if os(macOS)
        let majorStepMultiplier: Double = isVeryCompact ? 4.0 : (isCompact ? 2.0 : 1.0)
        #else
        let majorStepMultiplier: Double = isVeryCompact ? 6.0 : (isCompact ? 3.0 : 1.5)
        #endif
        let effectiveMajorStep = config.ticks.majorStep * majorStepMultiplier

        // Skip minor ticks on compact gauges
        let showMinorTicks = !isCompact

        // Adaptive font size — slightly smaller floor on iOS so the tick
        // labels stay readable but never dominate the dial.
        #if os(macOS)
        let fontSize = max(7, min(12, gaugeSize * 0.05))
        #else
        let fontSize = max(6, min(10, gaugeSize * 0.04))
        #endif

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
                // Boost tick widths on iOS so they don't visually vanish
                // after the global 0.7 scaleEffect. Minor ticks get a
                // slightly larger boost than majors because they're
                // already thinner and harder to see.
                #if os(macOS)
                let tickWidth = isMajor ? config.ticks.majorTickWidth : config.ticks.minorTickWidth
                #else
                let tickWidth = (isMajor
                                 ? config.ticks.majorTickWidth * 1.4
                                 : config.ticks.minorTickWidth * 1.6)
                #endif

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

        // iOS uses "K" abbreviation at *any* size for thousands-scale
        // values (RPM, mph above 100, etc.) — "16K" reads much cleaner
        // on a small mobile dial than "16000". macOS keeps the existing
        // compact-only abbreviation.
        #if os(macOS)
        let abbreviate = compact && abs(intValue) >= 1000
        #else
        let abbreviate = abs(intValue) >= 1000
        #endif

        if abbreviate {
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
