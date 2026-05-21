//
//  GaugePresets.swift
//  engine-simulator
//
//  Created by Claude on 1/7/26.
//

import SwiftUI

/// Factory methods for creating gauge configurations
/// Based on C++ right_gauge_cluster.cpp
enum GaugePresets {

    // MARK: - Color Constants (matching C++ app colors)

    static let foregroundColor = Color.white
    static let orange = Color.orange
    static let red = Color.red
    static let blue = Color(red: 0.2, green: 0.6, blue: 1.0)
    static let green = Color.green

    // MARK: - Tachometer

    /// Tachometer gauge configuration
    /// - Parameter redline: Engine redline in RPM (bands will be 5% higher)
    static func tachometer(redline: Double) -> GaugeConfiguration {
        // Floor redline so the gauge always has a real range — if the engine
        // failed to load and redline is 0, fall back to 7000 so the tick
        // math doesn't collapse to NaN and crash the Canvas.
        let safeRedline = redline > 0 ? redline : 7000
        let adjustedRedline = safeRedline * 1.05
        let maxRpm = ceil(adjustedRedline * 1.25 / 1000.0) * 1000.0
        let redlineRounded = ceil(adjustedRedline / 500.0) * 500.0
        let redlineWarning = floor(adjustedRedline * 0.9 / 500.0) * 500.0
        let shortenAngle = GaugeConfiguration.shortenAngle

        return GaugeConfiguration(
            title: "ENGINE SPEED",
            unit: "rpm",
            precision: 0,
            spaceBeforeUnit: true,
            minValue: 0,
            maxValue: maxRpm,
            gamma: 1.0,
            ticks: GaugeTickConfig(
                minorStep: 100,
                majorStep: 1000,
                minorTickWidth: 1,
                majorTickWidth: 2,
                minorTickLength: 5,
                majorTickLength: 10,
                maxMinorTick: .infinity
            ),
            needle: GaugeNeedleConfig(
                innerRadiusRatio: -0.1,
                outerRadiusRatio: 0.7,
                width: 4.0,
                ks: 1000.0,
                kd: 20.0,
                maxVelocity: 2.0
            ),
            bands: [
                GaugeBand(color: foregroundColor, start: 400, end: 1000,
                         width: 3, radialOffset: 6),
                GaugeBand(color: orange, start: redlineWarning, end: redlineRounded,
                         width: 3, radialOffset: 6,
                         shortenStart: -shortenAngle, shortenEnd: shortenAngle),
                GaugeBand(color: red, start: redlineRounded, end: maxRpm,
                         width: 3, radialOffset: 6,
                         shortenStart: shortenAngle, shortenEnd: -shortenAngle)
            ],
            needleColor: .red,
            tickColor: .white
        )
    }

    // MARK: - Speedometer

    /// Speedometer gauge configuration
    /// - Parameter maxSpeed: Maximum speed on gauge (default 200)
    /// - Parameter isMph: Use mph units (default true, false = km/h)
    static func speedometer(maxSpeed: Double = 200, isMph: Bool = true) -> GaugeConfiguration {
        return GaugeConfiguration(
            title: "VEHICLE SPEED",
            unit: isMph ? "mph" : "km/h",
            precision: 0,
            spaceBeforeUnit: true,
            minValue: 0,
            maxValue: maxSpeed,
            gamma: 1.0,
            ticks: GaugeTickConfig(
                minorStep: 5,
                majorStep: 10,
                minorTickWidth: 1,
                majorTickWidth: 2,
                minorTickLength: 5,
                majorTickLength: 10,
                maxMinorTick: maxSpeed
            ),
            needle: GaugeNeedleConfig(
                innerRadiusRatio: -0.1,
                outerRadiusRatio: 0.7,
                width: 4.0,
                ks: 1000.0,
                kd: 20.0,
                maxVelocity: 2.0
            ),
            bands: [],
            needleColor: orange,
            tickColor: .white
        )
    }

    // MARK: - Manifold Pressure

    /// Manifold pressure gauge configuration (vacuum gauge)
    /// Default is inHg relative to atmosphere
    static func manifoldPressure() -> GaugeConfiguration {
        let shortenAngle = GaugeConfiguration.shortenAngle

        return GaugeConfiguration(
            title: "MANIFOLD PRESSURE",
            unit: "inHg",
            precision: 0,
            spaceBeforeUnit: true,
            minValue: -30,
            maxValue: 5,
            gamma: 1.0,
            ticks: GaugeTickConfig(
                minorStep: 1,
                majorStep: 5,
                minorTickWidth: 1,
                majorTickWidth: 2,
                minorTickLength: 5,
                majorTickLength: 10,
                maxMinorTick: 200
            ),
            needle: GaugeNeedleConfig(
                innerRadiusRatio: -0.1,
                outerRadiusRatio: 0.7,
                width: 4.0,
                ks: 1000.0,
                kd: 50.0,  // Higher damping for pressure gauge
                maxVelocity: 2.0
            ),
            bands: [
                // Red zone: near atmosphere or boost (overrun)
                GaugeBand(color: red, start: -5, end: -1,
                         width: 3, radialOffset: 6,
                         shortenStart: shortenAngle, shortenEnd: shortenAngle),
                // White zone: around atmospheric
                GaugeBand(color: foregroundColor, start: -1, end: 1,
                         width: 3, radialOffset: 6,
                         shortenStart: shortenAngle, shortenEnd: shortenAngle),
                // Orange zone: partial throttle
                GaugeBand(color: orange, start: -10, end: -5,
                         width: 3, radialOffset: 6,
                         shortenStart: shortenAngle, shortenEnd: shortenAngle),
                // Blue zone: cruise vacuum
                GaugeBand(color: blue, start: -22, end: -10,
                         width: 3, radialOffset: 6,
                         shortenStart: shortenAngle, shortenEnd: shortenAngle),
                // White zone: high vacuum (decel)
                GaugeBand(color: foregroundColor, start: -30, end: -22,
                         width: 3, radialOffset: 6,
                         shortenStart: shortenAngle, shortenEnd: shortenAngle)
            ],
            needleColor: .white,
            tickColor: .white
        )
    }

    // MARK: - Volumetric Efficiency

    /// Volumetric efficiency gauge configuration
    static func volumetricEfficiency() -> GaugeConfiguration {
        let shortenAngle = GaugeConfiguration.shortenAngle

        return GaugeConfiguration(
            title: "VOLUMETRIC EFF.",
            unit: "%",
            precision: 1,
            spaceBeforeUnit: false,
            minValue: 0,
            maxValue: 120,
            gamma: 1.0,
            ticks: GaugeTickConfig(
                minorStep: 5,
                majorStep: 10,
                minorTickWidth: 1,
                majorTickWidth: 2,
                minorTickLength: 5,
                majorTickLength: 10,
                maxMinorTick: 200
            ),
            needle: GaugeNeedleConfig(
                innerRadiusRatio: -0.1,
                outerRadiusRatio: 0.7,
                width: 4.0,
                ks: 1000.0,
                kd: 50.0,
                maxVelocity: 2.0
            ),
            bands: [
                // Blue zone: low efficiency (30-80%)
                GaugeBand(color: blue, start: 30, end: 80,
                         width: 3, radialOffset: 6,
                         shortenStart: 0, shortenEnd: shortenAngle),
                // Green zone: optimal efficiency (80-100%)
                GaugeBand(color: green, start: 80, end: 100,
                         width: 3, radialOffset: 6,
                         shortenStart: shortenAngle, shortenEnd: shortenAngle),
                // Red zone: over 100% (forced induction)
                GaugeBand(color: red, start: 100, end: 120,
                         width: 3, radialOffset: 6,
                         shortenStart: shortenAngle, shortenEnd: -shortenAngle)
            ],
            needleColor: .white,
            tickColor: .white
        )
    }

    // MARK: - Air SCFM

    /// Air flow gauge configuration (Standard Cubic Feet per Minute).
    ///
    /// Range capped at 500 SCFM. The built-in engines top out around
    /// 250 SCFM (small NA) to ~540 SCFM (5L V8 at redline, ~90% VE); a
    /// 1200 SCFM dial left the needle asleep below the halfway point.
    /// 500 covers every catalog engine and leaves room for a beefier
    /// custom build to peg the gauge, which is itself informative.
    static func airScfm() -> GaugeConfiguration {
        return GaugeConfiguration(
            title: "AIR SCFM",
            unit: "",
            precision: 1,
            spaceBeforeUnit: false,
            minValue: 0,
            maxValue: 500,
            gamma: 1.0,
            ticks: GaugeTickConfig(
                minorStep: 10,
                majorStep: 50,
                minorTickWidth: 1,
                majorTickWidth: 2,
                minorTickLength: 5,
                majorTickLength: 10,
                maxMinorTick: 500
            ),
            needle: GaugeNeedleConfig(
                innerRadiusRatio: -0.1,
                outerRadiusRatio: 0.7,
                width: 4.0,
                ks: 1000.0,
                kd: 50.0,
                maxVelocity: 2.0
            ),
            bands: [],
            needleColor: .white,
            tickColor: .white
        )
    }

    // MARK: - Intake AFR

    /// Intake Air-Fuel Ratio gauge configuration
    static func intakeAfr() -> GaugeConfiguration {
        let shortenAngle = GaugeConfiguration.shortenAngle

        return GaugeConfiguration(
            title: "INTAKE AFR",
            unit: "",
            precision: 1,
            spaceBeforeUnit: false,
            minValue: 0,
            maxValue: 50,
            gamma: 1.0,
            ticks: GaugeTickConfig(
                minorStep: 1,
                majorStep: 5,
                minorTickWidth: 1,
                majorTickWidth: 2,
                minorTickLength: 5,
                majorTickLength: 10,
                maxMinorTick: 50
            ),
            needle: GaugeNeedleConfig(
                innerRadiusRatio: -0.1,
                outerRadiusRatio: 0.7,
                width: 4.0,
                ks: 1000.0,
                kd: 30.0,
                maxVelocity: 2.0
            ),
            bands: [
                // Rich zone (below stoich)
                GaugeBand(color: blue, start: 10, end: 14,
                         width: 3, radialOffset: 6,
                         shortenStart: shortenAngle, shortenEnd: shortenAngle),
                // Stoichiometric zone
                GaugeBand(color: green, start: 14, end: 15,
                         width: 3, radialOffset: 6,
                         shortenStart: shortenAngle, shortenEnd: shortenAngle),
                // Lean zone
                GaugeBand(color: orange, start: 15, end: 18,
                         width: 3, radialOffset: 6,
                         shortenStart: shortenAngle, shortenEnd: shortenAngle)
            ],
            needleColor: .white,
            tickColor: .white
        )
    }

    // MARK: - Exhaust O2

    /// Exhaust O2 percentage gauge configuration
    static func exhaustO2() -> GaugeConfiguration {
        // Real engines run with 0–5% residual O2 (rich/stoich) up to ~21%
        // for an engine breathing pure air (idling without combustion). 100%
        // is impossible. Cap the gauge at 25% so the needle actually has
        // room to move within the meaningful range.
        return GaugeConfiguration(
            title: "EXHAUST O2",
            unit: "%",
            precision: 1,
            spaceBeforeUnit: false,
            minValue: 0,
            maxValue: 25,
            gamma: 1.0,
            ticks: GaugeTickConfig(
                minorStep: 1,
                majorStep: 5,
                minorTickWidth: 1,
                majorTickWidth: 2,
                minorTickLength: 5,
                majorTickLength: 10,
                maxMinorTick: 25
            ),
            needle: GaugeNeedleConfig(
                innerRadiusRatio: -0.1,
                outerRadiusRatio: 0.7,
                width: 4.0,
                ks: 1000.0,
                kd: 30.0,
                maxVelocity: 2.0
            ),
            bands: [],
            needleColor: .white,
            tickColor: .white
        )
    }

    // MARK: - Cylinder Pressure

    /// Cylinder pressure gauge configuration
    /// Uses gamma = 0.5 for non-linear scale (compresses high values)
    static func cylinderPressure() -> GaugeConfiguration {
        let shortenAngle = GaugeConfiguration.shortenAngle

        return GaugeConfiguration(
            title: "CYL PRESSURE",
            unit: "PSI",
            precision: 0,
            spaceBeforeUnit: true,
            minValue: 0,
            maxValue: 1000,
            gamma: 0.5,  // Non-linear scale
            ticks: GaugeTickConfig(
                minorStep: 20,
                majorStep: 100,
                minorTickWidth: 1,
                majorTickWidth: 2,
                minorTickLength: 5,
                majorTickLength: 10,
                maxMinorTick: 1000
            ),
            needle: GaugeNeedleConfig(
                innerRadiusRatio: -0.1,
                outerRadiusRatio: 0.7,
                width: 4.0,
                ks: 1000.0,
                kd: 25.0,
                maxVelocity: 2.0
            ),
            bands: [
                // Atmospheric zone (0-14.7 PSI)
                GaugeBand(color: blue, start: 0, end: 14.7,
                         width: 3, radialOffset: 6,
                         shortenStart: -shortenAngle, shortenEnd: shortenAngle),
                // High pressure zone (400-1000 PSI)
                GaugeBand(color: foregroundColor, start: 400, end: 1000,
                         width: 3, radialOffset: 6,
                         shortenStart: shortenAngle, shortenEnd: -shortenAngle)
            ],
            needleColor: .cyan,
            tickColor: .white
        )
    }
}
