//
//  GaugeConfiguration.swift
//  engine-simulator
//
//  Created by Claude on 1/7/26.
//

import SwiftUI

// MARK: - GaugeBand
/// Colored arc section on the gauge face
struct GaugeBand: Identifiable {
    let id = UUID()
    var color: Color
    var start: Double           // Start value on gauge scale
    var end: Double             // End value on gauge scale
    var width: CGFloat          // Arc thickness in points
    var radialOffset: CGFloat   // Offset from outer edge (positive = inward)
    var shortenStart: CGFloat   // Angle reduction at start (radians)
    var shortenEnd: CGFloat     // Angle reduction at end (radians)

    init(color: Color, start: Double, end: Double, width: CGFloat = 3.0,
         radialOffset: CGFloat = 6.0, shortenStart: CGFloat = 0, shortenEnd: CGFloat = 0) {
        self.color = color
        self.start = start
        self.end = end
        self.width = width
        self.radialOffset = radialOffset
        self.shortenStart = shortenStart
        self.shortenEnd = shortenEnd
    }
}

// MARK: - GaugeTickConfig
/// Configuration for tick marks on the gauge
struct GaugeTickConfig {
    var minorStep: Double       // Interval between minor ticks
    var majorStep: Double       // Interval between major ticks
    var minorTickWidth: CGFloat
    var majorTickWidth: CGFloat
    var minorTickLength: CGFloat
    var majorTickLength: CGFloat
    var maxMinorTick: Double    // Value above which minor ticks stop appearing

    static let defaultConfig = GaugeTickConfig(
        minorStep: 5,
        majorStep: 10,
        minorTickWidth: 1,
        majorTickWidth: 2,
        minorTickLength: 5,
        majorTickLength: 10,
        maxMinorTick: .infinity
    )
}

// MARK: - GaugeNeedleConfig
/// Configuration for the needle including physics parameters
struct GaugeNeedleConfig {
    var innerRadiusRatio: CGFloat   // Ratio of gauge radius for needle start (-0.1 extends past center)
    var outerRadiusRatio: CGFloat   // Ratio of gauge radius for needle end (0.7 = 70%)
    var width: CGFloat              // Needle line width
    var ks: Double                  // Spring constant (higher = faster response)
    var kd: Double                  // Damping coefficient (higher = less oscillation)
    var maxVelocity: Double         // Maximum needle velocity

    static let defaultConfig = GaugeNeedleConfig(
        innerRadiusRatio: -0.1,
        outerRadiusRatio: 0.7,
        width: 4.0,
        ks: 500.0,    // Spring constant: lower = slower response
        kd: 50.0,     // Damping: higher = less oscillation, smoother
        maxVelocity: 2.0
    )
}

// MARK: - GaugeConfiguration
/// Complete configuration for a gauge
struct GaugeConfiguration {
    var title: String
    var unit: String
    var precision: Int
    var spaceBeforeUnit: Bool

    var minValue: Double
    var maxValue: Double
    var gamma: Double           // Non-linear scaling exponent (1.0 = linear)

    var thetaMin: Double        // Start angle in radians (0 = right, positive = counter-clockwise)
    var thetaMax: Double        // End angle in radians

    var ticks: GaugeTickConfig
    var needle: GaugeNeedleConfig
    var bands: [GaugeBand]

    var needleColor: Color
    var tickColor: Color
    var labelColor: Color
    var backgroundColor: Color

    // Default angular range matching C++ implementation
    // thetaMin = pi * 1.2 (~216 degrees, lower left)
    // thetaMax = -pi * 0.2 (~-36 degrees, upper right)
    static let defaultThetaMin: Double = .pi * 1.2
    static let defaultThetaMax: Double = -.pi * 0.2
    static let shortenAngle: CGFloat = 0.01745  // ~1 degree in radians

    init(
        title: String,
        unit: String,
        precision: Int = 0,
        spaceBeforeUnit: Bool = true,
        minValue: Double,
        maxValue: Double,
        gamma: Double = 1.0,
        thetaMin: Double = GaugeConfiguration.defaultThetaMin,
        thetaMax: Double = GaugeConfiguration.defaultThetaMax,
        ticks: GaugeTickConfig = .defaultConfig,
        needle: GaugeNeedleConfig = .defaultConfig,
        bands: [GaugeBand] = [],
        needleColor: Color = .red,
        tickColor: Color = .white,
        labelColor: Color = .gray,
        backgroundColor: Color = .appBackground
    ) {
        self.title = title
        self.unit = unit
        self.precision = precision
        self.spaceBeforeUnit = spaceBeforeUnit
        self.minValue = minValue
        self.maxValue = maxValue
        self.gamma = gamma
        self.thetaMin = thetaMin
        self.thetaMax = thetaMax
        self.ticks = ticks
        self.needle = needle
        self.bands = bands
        self.needleColor = needleColor
        self.tickColor = tickColor
        self.labelColor = labelColor
        self.backgroundColor = backgroundColor
    }

    // MARK: - Helper Methods

    /// Convert a value to normalized position (0-1) with gamma applied.
    /// Returns 0 (rather than NaN) when min == max — important because some
    /// gauges are configured from live engine state (e.g. tachometer's max
    /// is derived from redline) and that state can transiently be 0 during
    /// an engine swap or load failure. NaN coords reaching context.draw()
    /// trip libmalloc heap corruption assertions.
    func normalizedPosition(for value: Double) -> Double {
        let span = maxValue - minValue
        guard span > 0, span.isFinite else { return 0 }
        let clampedValue = min(max(value, minValue), maxValue)
        let normalized = (clampedValue - minValue) / span
        return pow(normalized, gamma)
    }

    /// Convert a normalized position (0-1) to angle in radians
    func angle(for normalizedPosition: Double) -> Double {
        return thetaMin + normalizedPosition * (thetaMax - thetaMin)
    }

    /// Convert a value directly to angle in radians
    func angle(forValue value: Double) -> Double {
        return angle(for: normalizedPosition(for: value))
    }

    /// Format a value for display
    func formattedValue(_ value: Double) -> String {
        let format = "%.\(precision)f"
        let valueStr = String(format: format, value)
        if unit.isEmpty {
            return valueStr
        }
        return spaceBeforeUnit ? "\(valueStr) \(unit)" : "\(valueStr)\(unit)"
    }
}