//
//  OscilloscopeManager.swift
//  engine-simulator
//
//  Matches C++ oscilloscope.cpp implementation:
//  - Fetches full buffer state from EngineWrapper (C++)
//  - Manages dynamic bounds for UI

import SwiftUI
import Combine

/// Manages oscilloscope data by fetching from C++ engine
class OscilloscopeManager: ObservableObject {

    // MARK: - Data Buffers (fetched from C++)

    @Published var torque: [CGPoint] = []
    @Published var power: [CGPoint] = []
    @Published var sparkAdvance: [CGPoint] = []
    @Published var totalExhaustFlow: [CGPoint] = []
    @Published var exhaustFlow: [CGPoint] = []
    @Published var intakeFlow: [CGPoint] = []
    @Published var exhaustValveLift: [CGPoint] = []
    @Published var intakeValveLift: [CGPoint] = []
    @Published var cylinderPressure: [CGPoint] = []
    @Published var cylinderMolecules: [CGPoint] = []
    @Published var pv: [CGPoint] = []

    // MARK: - Dynamic Bounds (from C++)

    private var dynamicBounds: [EngineScopeType: (xMin: Double, xMax: Double, yMin: Double, yMax: Double)] = [:]

    /// Published update trigger for views
    @Published private(set) var lastUpdateTime: TimeInterval = 0

    // MARK: - Initialization

    init() {
        // Buffers start empty
    }

    // MARK: - Sampling

    func sample(from engine: EngineWrapper) {
        // Update all buffers by fetching from C++ engine
        // Using the aliased Enum directly
        updateBuffer(for: .torque, from: engine)
        updateBuffer(for: .power, from: engine)
        updateBuffer(for: .sparkAdvance, from: engine)
        updateBuffer(for: .totalExhaustFlow, from: engine)
        updateBuffer(for: .exhaustFlow, from: engine)
        updateBuffer(for: .intakeFlow, from: engine)
        updateBuffer(for: .exhaustValveLift, from: engine)
        updateBuffer(for: .intakeValveLift, from: engine)
        updateBuffer(for: .cylinderPressure, from: engine)
        updateBuffer(for: .cylinderMolecules, from: engine)
        updateBuffer(for: .PV, from: engine)
        
        lastUpdateTime = ProcessInfo.processInfo.systemUptime
    }

    private func updateBuffer(for type: EngineScopeType, from engine: EngineWrapper) {
        // Directly pass the type since OscilloscopeType is now EngineScopeType
        guard let data = engine.getScopeData(type) else { return }
        
        // Convert ScopePoint (Obj-C) to CGPoint
        // data.points is [ScopePoint]
        let points = data.points.compactMap { point -> CGPoint? in
            let p = point as ScopePoint
            return CGPoint(x: p.x, y: p.y)
        }
        
        switch type {
        case .torque: torque = points
        case .power: power = points
        case .sparkAdvance: sparkAdvance = points
        case .totalExhaustFlow: totalExhaustFlow = points
        case .exhaustFlow: exhaustFlow = points
        case .intakeFlow: intakeFlow = points
        case .exhaustValveLift: exhaustValveLift = points
        case .intakeValveLift: intakeValveLift = points
        case .cylinderPressure: cylinderPressure = points
        case .cylinderMolecules: cylinderMolecules = points
        case .PV: pv = points
        @unknown default: break
        }
        
        dynamicBounds[type] = (xMin: data.xMin, xMax: data.xMax, yMin: data.yMin, yMax: data.yMax)
    }

    // MARK: - Data Access

    /// Get display points (already ordered by EngineWrapper)
    func getPoints(for type: EngineScopeType, config: OscilloscopeConfig) -> [CGPoint] {
        switch type {
        case .torque: return torque
        case .power: return power
        case .sparkAdvance: return sparkAdvance
        case .totalExhaustFlow: return totalExhaustFlow
        case .exhaustFlow: return exhaustFlow
        case .intakeFlow: return intakeFlow
        case .exhaustValveLift: return exhaustValveLift
        case .intakeValveLift: return intakeValveLift
        case .cylinderPressure: return cylinderPressure
        case .cylinderMolecules: return cylinderMolecules
        case .PV: return pv
        @unknown default: return []
        }
    }

    /// Get axis bounds for a type (uses stored dynamic bounds from C++)
    func getAxisBounds(for type: EngineScopeType, config: OscilloscopeConfig) -> (xMin: Double, xMax: Double, yMin: Double, yMax: Double) {
        // Start with config defaults
        var xMin = config.xMin
        var xMax = config.xMax
        var yMin = config.yMin
        var yMax = config.yMax

        // Apply dynamic bounds from C++ if enabled
        if let bounds = dynamicBounds[type] {
            if config.dynamicallyResizeX {
                xMin = bounds.xMin
                xMax = bounds.xMax
            }
            if config.dynamicallyResizeY {
                yMin = bounds.yMin
                yMax = bounds.yMax
            }
        }

        // Ensure valid range
        if xMax <= xMin { xMax = xMin + 1.0 }
        if yMax <= yMin { yMax = yMin + 1.0 }

        return (xMin, xMax, yMin, yMax)
    }

    /// Get the normalized position (0-1) of each point for opacity/width calculations
    func getPointAges(for type: EngineScopeType, config: OscilloscopeConfig) -> [CGFloat] {
        let count: Int
        switch type {
        case .torque: count = torque.count
        case .power: count = power.count
        case .sparkAdvance: count = sparkAdvance.count
        case .totalExhaustFlow: count = totalExhaustFlow.count
        case .exhaustFlow: count = exhaustFlow.count
        case .intakeFlow: count = intakeFlow.count
        case .exhaustValveLift: count = exhaustValveLift.count
        case .intakeValveLift: count = intakeValveLift.count
        case .cylinderPressure: count = cylinderPressure.count
        case .cylinderMolecules: count = cylinderMolecules.count
        case .PV: count = pv.count
        @unknown default: count = 0
        }
        
        guard count > 0 else { return [] }
        return (0..<count).map { CGFloat($0) / CGFloat(count) }
    }

    /// Reset all bounds (can be called if engine reloads)
    func reset() {
        dynamicBounds.removeAll()
        torque.removeAll()
        power.removeAll()
        sparkAdvance.removeAll()
        totalExhaustFlow.removeAll()
        exhaustFlow.removeAll()
        intakeFlow.removeAll()
        exhaustValveLift.removeAll()
        intakeValveLift.removeAll()
        cylinderPressure.removeAll()
        cylinderMolecules.removeAll()
        pv.removeAll()
    }
}

