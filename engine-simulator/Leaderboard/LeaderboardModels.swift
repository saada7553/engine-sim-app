//
//  LeaderboardModels.swift
//  engine-simulator
//
//  Pure (CloudKit-agnostic) model types for the global leaderboard: the metrics
//  a board can rank by, the engine-class grouping used for the class filter, and
//  the entry that travels to/from the cloud. CloudKit record mapping lives in
//  LeaderboardService so these stay testable on their own.
//

import Foundation

// MARK: - Engine class (the class filter buckets)

/// Layout family used to segment boards. Coarser than EngineLayout — the two
/// V6 and two V12 bank angles collapse into one class so "best V6" means one
/// board, not two.
enum EngineClass: String, CaseIterable, Identifiable, Codable {
    case i1, i2, i3, i4, i5, i6, i7, v6, v8, v10, v12, flat4, flat6

    var id: String { rawValue }

    static func from(_ layout: EngineLayout) -> EngineClass {
        switch layout {
        case .inline1:          return .i1
        case .inline2:          return .i2
        case .inline3:          return .i3
        case .inline4:          return .i4
        case .inline5:          return .i5
        case .inline6:          return .i6
        case .inline7:          return .i7
        case .v6_60, .v6_90:    return .v6
        case .v8_90:            return .v8
        case .v10_72:           return .v10
        case .v12_60, .v12_75:  return .v12
        case .flat4:            return .flat4
        case .flat6:            return .flat6
        }
    }

    var displayName: String {
        switch self {
        case .i1:    return "Single"
        case .i2:    return "Inline 2"
        case .i3:    return "Inline 3"
        case .i4:    return "Inline 4"
        case .i5:    return "Inline 5"
        case .i6:    return "Inline 6"
        case .i7:    return "Inline 7"
        case .v6:    return "V6"
        case .v8:    return "V8"
        case .v10:   return "V10"
        case .v12:   return "V12"
        case .flat4: return "Flat 4"
        case .flat6: return "Flat 6"
        }
    }

    var shortLabel: String {
        switch self {
        case .i1: return "I1"
        case .i2: return "I2"
        case .i3: return "I3"
        case .i4: return "I4"
        case .i5: return "I5"
        case .i6: return "I6"
        case .i7: return "I7"
        case .v6: return "V6"
        case .v8: return "V8"
        case .v10: return "V10"
        case .v12: return "V12"
        case .flat4: return "F4"
        case .flat6: return "F6"
        }
    }
}

// MARK: - Metric (what a board ranks by)

/// The launch leaderboards. Each maps to a single sortable CloudKit field; the
/// `descending` flag is the sort direction (most power first; quickest 0-60
/// first). `recordKey` must match the field names written in LeaderboardService.
enum LeaderboardMetric: String, CaseIterable, Identifiable {
    case peakPower
    case peakTorque
    case value            // hp per $1,000 of engine cost
    case specificOutput   // hp per litre
    case zeroToSixty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .peakPower:      return "Peak Power"
        case .peakTorque:     return "Peak Torque"
        case .value:          return "Value King"
        case .specificOutput: return "Specific Output"
        case .zeroToSixty:    return "0–60 mph"
        }
    }

    var unit: String {
        switch self {
        case .peakPower:      return "hp"
        case .peakTorque:     return "lb-ft"
        case .value:          return "hp/$1k"
        case .specificOutput: return "hp/L"
        case .zeroToSixty:    return "sec"
        }
    }

    /// CloudKit field this board sorts on.
    var recordKey: String {
        switch self {
        case .peakPower:      return "peakPowerHp"
        case .peakTorque:     return "peakTorqueLbFt"
        case .value:          return "valueHpPerThousand"
        case .specificOutput: return "specificOutputHpPerL"
        case .zeroToSixty:    return "zeroToSixtySec"
        }
    }

    /// Sort direction. Power/value/output rank high-to-low; 0-60 ranks fastest
    /// (lowest) first.
    var descending: Bool { self != .zeroToSixty }

    /// Format a metric value for display in a leaderboard row.
    func formatted(_ value: Double) -> String {
        switch self {
        case .peakPower, .peakTorque:
            return String(format: "%.0f", value)
        case .value, .specificOutput:
            return String(format: "%.1f", value)
        case .zeroToSixty:
            return String(format: "%.2f", value)
        }
    }
}

// MARK: - Entry

/// One leaderboard row. Carries every board's metric plus the full EngineSpec
/// JSON so the engine can be downloaded and re-raced, and the build cost so
/// value/budget boards work without recomputation.
struct LeaderboardEntry: Identifiable, Equatable {
    let id: String              // CKRecord.ID.recordName
    let username: String
    let engineName: String
    let engineClass: EngineClass
    let layoutRaw: String
    let specJSON: String

    let buildCostTotal: Double
    let buildCostEngine: Double
    let displacementL: Double

    let peakPowerHp: Double
    let peakPowerRpm: Double
    let peakTorqueLbFt: Double
    let peakTorqueRpm: Double
    let valueHpPerThousand: Double
    let specificOutputHpPerL: Double
    let zeroToSixtySec: Double   // 0 when no launch run was submitted

    let appVersion: String
    let submittedAt: Date

    /// The value this entry shows on a board ranked by `metric`.
    func metricValue(for metric: LeaderboardMetric) -> Double {
        switch metric {
        case .peakPower:      return peakPowerHp
        case .peakTorque:     return peakTorqueLbFt
        case .value:          return valueHpPerThousand
        case .specificOutput: return specificOutputHpPerL
        case .zeroToSixty:    return zeroToSixtySec
        }
    }

    static func == (lhs: LeaderboardEntry, rhs: LeaderboardEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Derived metric helpers

enum LeaderboardMath {
    /// hp per $1,000 of engine cost — the "Value King" metric. Guards a zero
    /// or negative cost (a free build would be infinitely valuable).
    static func valueHpPerThousand(powerHp: Double, engineCost: Double) -> Double {
        guard engineCost > 0 else { return 0 }
        return powerHp / (engineCost / 1_000.0)
    }

    /// hp per litre of displacement.
    static func specificOutput(powerHp: Double, displacementL: Double) -> Double {
        guard displacementL > 0 else { return 0 }
        return powerHp / displacementL
    }
}
