//
//  IntentReconciler.swift
//  engine-simulator
//
//  Cross-field coherence the per-dimension AI calls can't see on their own.
//  Each focused call answers its ONE question well, but only here do we have the
//  whole picture — so this is where we fold the rev-character vibe into the build
//  and stop the axes from contradicting each other.
//
//  The key job is making "high revving" actually rev. The expander caps redline
//  by mean PISTON SPEED, which is set by the geometry (stroke) and the
//  performance/cam rank. A bare "+rpm" nudge gets clamped straight back down, so
//  a high-rev intent has to also push the geometry oversquare and earn a real
//  cam — that's what lets the cap rise. Explicit pins (a redline NUMBER the user
//  actually typed) are never overridden.
//
//  Framework-free / all-OS / unit-testable.
//

import Foundation

enum IntentReconciler {

    static func reconcile(_ intent: inout EngineIntent, revCharacter: RevCharacter) {
        applyRevCharacter(&intent, revCharacter)
        applyHighRevBuild(&intent)        // acts on the .highRedline tag from ANY source
        enforcePerformanceCoherence(&intent)
    }

    /// Fold the "how high does it rev" feeling into the build. Only matters when
    /// the user gave no explicit redline number. `high`/`screamer` set the
    /// `.highRedline` tag (the keyword pass also sets it for "high revving" etc.),
    /// which `applyHighRevBuild` then turns into a genuinely high-revving engine.
    private static func applyRevCharacter(_ intent: inout EngineIntent, _ rev: RevCharacter) {
        guard intent.redlineRpm == nil else { return }   // an explicit number wins
        switch rev {
        case .low:
            if intent.performance == .modest { intent.powerBand = .lowEnd }
        case .medium:
            break
        case .high:
            intent.features.insert(.highRedline)
        case .screamer:
            intent.features.insert(.highRedline)
            // A screamer is unambiguously aggressive: a race cam and at least a
            // strong power level on top of the high-rev geometry below.
            if intent.camProfile.rank < DesignCamProfile.race.rank { intent.camProfile = .race }
            if intent.performance.rank < DesignPerformance.strong.rank { intent.performance = .strong }
        }
    }

    /// Make a high-rev engine actually able to rev. Whatever set `.highRedline`
    /// (the rev call OR the keyword pass on "high revving"/"revvy"/…), the engine
    /// needs top-end-biased geometry and a real cam so the piston-speed cap lifts
    /// — and at least a modest power level so the derived redline base isn't
    /// dragged down by a misread "weak". This is the direct fix for "high revving
    /// one cylinder" landing at ~6.4k.
    private static func applyHighRevBuild(_ intent: inout EngineIntent) {
        guard intent.redlineRpm == nil, intent.has(.highRedline) else { return }
        intent.powerBand = .topEnd
        if intent.camProfile.rank < DesignCamProfile.sport.rank { intent.camProfile = .sport }
        if intent.performance.rank < DesignPerformance.modest.rank { intent.performance = .modest }
    }

    /// Keep character consistent with the intended power level. A weak/economy
    /// build shouldn't get a racy cam or lumpy idle from a per-axis misread; a
    /// monster build should always get a real cam.
    private static func enforcePerformanceCoherence(_ intent: inout EngineIntent) {
        switch intent.performance {
        case .weak:
            // Don't undo a high-rev cam: a high-revving economy engine is still
            // sporty up top. Only tame the cam when nothing asked for revs.
            if !intent.has(.highRedline) {
                if intent.camProfile.rank > DesignCamProfile.stock.rank { intent.camProfile = .stock }
                if intent.idle == .lumpy { intent.idle = .mild }
            }
        case .extreme:
            if intent.camProfile.rank < DesignCamProfile.sport.rank { intent.camProfile = .sport }
        default:
            break
        }
    }
}
