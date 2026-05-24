//
//  GaugeDialRenderer.swift
//  engine-simulator
//
//  The shared, stateless drawing for a UniversalGauge dial: coloured bands,
//  tick marks + labels, and the needle + centre cap. Pulled out of
//  UniversalGauge so anything that wants to look like the in-app gauge —
//  the live tiles AND the launch splash — renders through exactly the same
//  code path off the same GaugeConfiguration, instead of reimplementing the
//  geometry and drifting visually.
//
//  These are pure functions of (config, geometry, needle position); they hold
//  no state and don't observe the engine. The live needle physics live in
//  NeedleAnimationState; the caller decides where the needle points.
//

import SwiftUI
import CoreGraphics
import Foundation

enum GaugeDialRenderer {

    // MARK: - Static dial (bands + ticks + labels)

    static func drawDial(context: GraphicsContext, config: GaugeConfiguration,
                         center: CGPoint, outerRadius: CGFloat, gaugeSize: CGFloat,
                         isCompact: Bool, isVeryCompact: Bool) {
        for band in config.bands {
            drawBand(context: context, config: config, center: center,
                     band: band, outerRadius: outerRadius)
        }
        drawTicks(context: context, config: config, center: center,
                  outerRadius: outerRadius, isCompact: isCompact,
                  isVeryCompact: isVeryCompact, gaugeSize: gaugeSize)
    }

    static func drawBand(context: GraphicsContext, config: GaugeConfiguration,
                         center: CGPoint, band: GaugeBand, outerRadius: CGFloat) {
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

    static func drawTicks(context: GraphicsContext, config: GaugeConfiguration,
                          center: CGPoint, outerRadius: CGFloat,
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

    static func formatTickLabel(_ value: Double, compact: Bool) -> String {
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

    // MARK: - Needle + centre cap

    static func drawNeedle(context: GraphicsContext, config: GaugeConfiguration,
                           center: CGPoint, normalizedPosition: Double,
                           outerRadius: CGFloat, gaugeSize: CGFloat) {
        let angle = config.angle(for: normalizedPosition)
        let innerRadius = outerRadius * config.needle.innerRadiusRatio
        let needleOuterRadius = outerRadius * config.needle.outerRadiusRatio

        let startPoint = CGPoint(x: center.x + cos(angle) * innerRadius,
                                 y: center.y - sin(angle) * innerRadius)
        let endPoint = CGPoint(x: center.x + cos(angle) * needleOuterRadius,
                               y: center.y - sin(angle) * needleOuterRadius)

        var path = Path()
        path.move(to: startPoint)
        path.addLine(to: endPoint)

        context.stroke(path, with: .color(config.needleColor),
                       style: StrokeStyle(lineWidth: config.needle.width, lineCap: .round))

        // Centre cap.
        let capSize = max(4.0, gaugeSize * 0.03)
        let capRect = CGRect(x: center.x - capSize, y: center.y - capSize,
                             width: capSize * 2, height: capSize * 2)
        context.fill(Circle().path(in: capRect), with: .color(.appBackground))
        context.stroke(Circle().path(in: capRect), with: .color(.sidebarTextSecondary), lineWidth: 1)
    }
}
