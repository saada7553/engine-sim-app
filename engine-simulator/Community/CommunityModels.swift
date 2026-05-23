//
//  CommunityModels.swift
//  engine-simulator
//
//  CloudKit-agnostic model types for the community engine browser: a published
//  engine, the ways the browser can sort, and the spec "badges" shown on a
//  card. CloudKit record mapping lives in CommunityService so these stay
//  testable on their own — mirroring the split used for the leaderboard.
//

import Foundation

// MARK: - Published engine

/// One engine someone shared to the community. The full EngineSpec rides along
/// as JSON (carrying its embedded `capturedStats`), so the engine can be
/// downloaded, previewed and re-raced; the denormalized columns alongside it
/// let the browser sort/filter without decoding every spec.
struct CommunityEngine: Identifiable, Equatable {
    let id: String              // CKRecord.ID.recordName
    let ownerId: String         // stable PlayerIdentity.playerId of the author
    let ownerUsername: String
    let engineName: String      // also serves as the description
    let engineClass: EngineClass
    let layoutRaw: String
    let specJSON: String

    let buildCostTotal: Double
    let displacementL: Double
    let cylinderCount: Int

    let appVersion: String
    let publishedAt: Date

    /// Full engine, decoded on demand. Nil if the stored JSON is unreadable
    /// (an older/corrupt record) — callers must handle that gracefully.
    var spec: EngineSpec? { CommunityService.decodeSpec(specJSON) }

    /// Author-recorded best results, pulled from the embedded spec. `.empty`
    /// (all zeros) when the spec can't be decoded or nothing was captured.
    var stats: CapturedStats { spec?.capturedStats ?? .empty }

    /// Author's free-text blurb, if they wrote one in the builder.
    var engineDescription: String? {
        let d = spec?.engineDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (d?.isEmpty ?? true) ? nil : d
    }

    static func == (lhs: CommunityEngine, rhs: CommunityEngine) -> Bool { lhs.id == rhs.id }
}

// MARK: - Sort highlight

extension CommunityEngine {
    /// The value to surface prominently on a card for the active sort, so the
    /// list shows what it's ranked by without opening each engine. Returns nil
    /// for "Newest" (the relative date is shown elsewhere) and an em dash when
    /// a metric wasn't captured.
    func sortHighlight(for sort: CommunitySort) -> (value: String, caption: String)? {
        let s = stats
        switch sort {
        case .newest:
            return nil
        case .power:
            return s.hasDyno ? ("\(Int(s.peakPowerHp))", "hp") : nil
        case .torque:
            return s.hasDyno ? ("\(Int(s.peakTorqueLbFt))", "lb-ft") : nil
        case .cheapest:
            return (EnginePricing.formatted(buildCostTotal), "build")
        }
    }

    /// Short relative "shared" label for the Newest sort / detail header.
    var publishedRelative: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: publishedAt, relativeTo: Date())
    }
}

// MARK: - Sort

/// How the browser orders results. Each maps to a single CloudKit field so the
/// server does the ranking; `recordKey` must match the columns CommunityService
/// writes. "Newest" uses the system creationDate.
enum CommunitySort: String, CaseIterable, Identifiable {
    case newest
    case power
    case torque
    case cheapest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:   return "Newest"
        case .power:    return "Most Power"
        case .torque:   return "Most Torque"
        case .cheapest: return "Cheapest"
        }
    }

    var recordKey: String {
        switch self {
        case .newest:   return "creationDate"
        case .power:    return "peakPowerHp"
        case .torque:   return "peakTorqueLbFt"
        case .cheapest: return "buildCostTotal"
        }
    }

    /// Cheapest ranks low-to-high; everything else high-to-low / newest-first.
    var ascending: Bool { self == .cheapest }
}

// MARK: - Badges

/// A single labelled spec chip shown on a card / in the detail sheet. `value`
/// is "—" when the stat wasn't captured, so the layout stays stable.
struct CommunityBadge: Identifiable {
    let id = UUID()
    let icon: String
    let value: String
    let caption: String
}

extension CommunityEngine {
    /// The headline spec chips for a card: class, displacement, cost, then any
    /// captured performance numbers (power / torque / 0-60 / top speed). Missing
    /// captures render as "—" rather than being dropped.
    var badges: [CommunityBadge] {
        let s = stats
        // Class / displacement / cost are intrinsic to the build and always
        // shown. Captured performance numbers are only shown when the author
        // actually recorded them — a missing dyno/launch is omitted, not "—".
        var out: [CommunityBadge] = [
            CommunityBadge(icon: "engine.combustion", value: engineClass.shortLabel,
                           caption: "\(cylinderCount) cyl"),
            CommunityBadge(icon: "drop", value: String(format: "%.1fL", displacementL),
                           caption: "displ"),
            CommunityBadge(icon: "dollarsign.circle", value: EnginePricing.formatted(buildCostTotal),
                           caption: "build"),
        ]
        if s.hasDyno {
            out.append(CommunityBadge(icon: "bolt.fill", value: "\(Int(s.peakPowerHp))", caption: "hp"))
            out.append(CommunityBadge(icon: "gauge.with.dots.needle.67percent",
                                      value: "\(Int(s.peakTorqueLbFt))", caption: "lb-ft"))
        }
        if s.hasLaunch {
            out.append(CommunityBadge(icon: "stopwatch",
                                      value: String(format: "%.2f", s.zeroToSixtySec), caption: "0-60"))
        }
        if s.hasTopSpeed {
            out.append(CommunityBadge(icon: "speedometer",
                                      value: "\(Int(s.topSpeedMph))", caption: "mph top"))
        }
        return out
    }
}
