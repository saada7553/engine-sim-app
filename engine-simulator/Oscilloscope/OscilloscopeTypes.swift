//
//  OscilloscopeTypes.swift
//  engine-simulator
//

import SwiftUI

extension EngineScopeType: CaseIterable, Identifiable {
    public var id: Int { Int(self.rawValue) }
    
    public static var allCases: [EngineScopeType] {
        return [
            .torque,
            .power,
            .sparkAdvance,
            .totalExhaustFlow,
            .exhaustFlow,
            .intakeFlow,
            .exhaustValveLift,
            .intakeValveLift,
            .cylinderPressure,
            .cylinderMolecules,
            .PV
        ]
    }

    var displayName: String {
        switch self {
        case .torque: return "Torque"
        case .power: return "Power"
        case .sparkAdvance: return "Spark Advance"
        case .totalExhaustFlow: return "Total Exhaust Flow"
        case .exhaustFlow: return "Exhaust Flow"
        case .intakeFlow: return "Intake Flow"
        case .exhaustValveLift: return "Exhaust Valve Lift"
        case .intakeValveLift: return "Intake Valve Lift"
        case .cylinderPressure: return "Cylinder Pressure"
        case .cylinderMolecules: return "Cylinder Molecules"
        case .PV: return "P-V Diagram"
        @unknown default: return "Unknown"
        }
    }

    /// Whether this oscilloscope uses cycle angle as X-axis (creates standing wave)
    var isCycleSynced: Bool {
        switch self {
        case .totalExhaustFlow, .exhaustFlow, .intakeFlow,
             .exhaustValveLift, .intakeValveLift,
             .cylinderPressure, .cylinderMolecules:
            return true
        case .torque, .power, .sparkAdvance, .PV:
            return false
        @unknown default: return false
        }
    }

    /// Whether this oscilloscope uses RPM as X-axis
    var isRPMBased: Bool {
        switch self {
        case .torque, .power, .sparkAdvance:
            return true
        default:
            return false
        }
    }
}

/// Configuration for an oscilloscope display
struct OscilloscopeConfig {
    let type: EngineScopeType
    let bufferSize: Int
    let xMin: Double
    let xMax: Double
    let yMin: Double
    let yMax: Double
    let dynamicallyResizeX: Bool
    let dynamicallyResizeY: Bool
    let drawReverse: Bool
    let color: Color
    let lineWidth: CGFloat
    let xAxisLabel: String
    let yAxisLabel: String
    /// Time-series traces fade older samples toward transparent so the
    /// freshest data pops. Static curves (e.g. the spark advance map,
    /// which is re-sampled in whole each tick) should render every point
    /// at full strength — turn this off in that case.
    var fadeWithAge: Bool = true

    /// Standard configurations matching C++ oscilloscope_cluster
    static func standard(for type: EngineScopeType) -> OscilloscopeConfig {
        switch type {
        case .torque:
            return OscilloscopeConfig(
                type: type,
                bufferSize: 100,
                xMin: 0, xMax: 10000,  // RPM
                yMin: 0, yMax: 100,     // Will auto-resize
                dynamicallyResizeX: true,
                dynamicallyResizeY: true,
                drawReverse: false,
                color: .scopeWarm,
                lineWidth: 2.0,
                xAxisLabel: "RPM",
                yAxisLabel: "Nm"
            )

        case .power:
            return OscilloscopeConfig(
                type: type,
                bufferSize: 100,
                xMin: 0, xMax: 10000,  // RPM
                yMin: 0, yMax: 100,     // Will auto-resize
                dynamicallyResizeX: true,
                dynamicallyResizeY: true,
                drawReverse: false,
                color: .scopePower,
                lineWidth: 2.0,
                xAxisLabel: "RPM",
                yAxisLabel: "kW"
            )

        case .sparkAdvance:
            return OscilloscopeConfig(
                type: type,
                bufferSize: 1024,
                xMin: 0, xMax: 10000,  // RPM
                yMin: -30, yMax: 60,    // Degrees — fallback before first sample
                dynamicallyResizeX: false,
                dynamicallyResizeY: true,  // Tunes (e.g. VTEC) run past the static range
                drawReverse: false,
                color: .scopeWarm,
                lineWidth: 1.5,
                xAxisLabel: "RPM",
                yAxisLabel: "deg",
                fadeWithAge: false
            )

        case .totalExhaustFlow:
            return OscilloscopeConfig(
                type: type,
                bufferSize: 1024,
                xMin: 0, xMax: 4 * .pi,  // Cycle angle (0 to 4pi)
                yMin: -10, yMax: 10,      // SCFM
                dynamicallyResizeX: false,
                dynamicallyResizeY: true,
                drawReverse: false,
                color: .scopeWarm,
                lineWidth: 1.0,
                xAxisLabel: "Cycle",
                yAxisLabel: "SCFM"
            )

        case .exhaustFlow:
            return OscilloscopeConfig(
                type: type,
                bufferSize: 1024,
                xMin: 0, xMax: 4 * .pi,
                yMin: -10, yMax: 10,
                dynamicallyResizeX: false,
                dynamicallyResizeY: false,
                drawReverse: false,
                color: .scopeWarm,
                lineWidth: 1.0,
                xAxisLabel: "Cycle",
                yAxisLabel: "SCFM"
            )

        case .intakeFlow:
            return OscilloscopeConfig(
                type: type,
                bufferSize: 1024,
                xMin: 0, xMax: 4 * .pi,
                yMin: -10, yMax: 10,
                dynamicallyResizeX: false,
                dynamicallyResizeY: true,  // Auto-scales to match exhaust
                drawReverse: false,
                color: .scopeCool,
                lineWidth: 1.0,
                xAxisLabel: "Cycle",
                yAxisLabel: "SCFM"
            )

        case .exhaustValveLift:
            return OscilloscopeConfig(
                type: type,
                bufferSize: 1024,
                xMin: 0, xMax: 4 * .pi,
                yMin: -10, yMax: 10,  // Thousandths of inch
                dynamicallyResizeX: false,
                dynamicallyResizeY: true,
                drawReverse: false,
                color: .scopeWarm,
                lineWidth: 1.0,
                xAxisLabel: "Cycle",
                yAxisLabel: "thou"
            )

        case .intakeValveLift:
            return OscilloscopeConfig(
                type: type,
                bufferSize: 1024,
                xMin: 0, xMax: 4 * .pi,
                yMin: -10, yMax: 10,
                dynamicallyResizeX: false,
                dynamicallyResizeY: true,
                drawReverse: false,
                color: .scopeCool,
                lineWidth: 1.0,
                xAxisLabel: "Cycle",
                yAxisLabel: "thou"
            )

        case .cylinderPressure:
            return OscilloscopeConfig(
                type: type,
                bufferSize: 1024,
                xMin: 0, xMax: 4 * .pi,
                yMin: 0, yMax: 50,  // sqrt(PSI)
                dynamicallyResizeX: false,
                dynamicallyResizeY: true,
                drawReverse: false,
                color: .scopeWarm,
                lineWidth: 1.0,
                xAxisLabel: "Cycle",
                yAxisLabel: "sqrt(PSI)"
            )

        case .cylinderMolecules:
            return OscilloscopeConfig(
                type: type,
                bufferSize: 1024,
                xMin: 0, xMax: 4 * .pi,
                yMin: -0.05, yMax: 0.2,  // Moles
                dynamicallyResizeX: false,
                dynamicallyResizeY: false,
                drawReverse: false,
                color: .white,
                lineWidth: 1.0,
                xAxisLabel: "Cycle",
                yAxisLabel: "mol"
            )

        case .PV:
            return OscilloscopeConfig(
                type: type,
                bufferSize: 1024,
                xMin: 0, xMax: 0.1,      // Volume in liters
                yMin: 0, yMax: 50,        // sqrt(PSI)
                dynamicallyResizeX: true,
                dynamicallyResizeY: true,
                drawReverse: true,        // Draws loop in correct direction
                color: .scopeWarm,
                lineWidth: 1.0,
                xAxisLabel: "L",
                yAxisLabel: "sqrt(PSI)"
            )
        }
    }
}
