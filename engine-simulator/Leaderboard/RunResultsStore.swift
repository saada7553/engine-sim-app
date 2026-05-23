//
//  RunResultsStore.swift
//  engine-simulator
//
//  Captures the current engine's best measured results so they can be posted
//  to the leaderboard: peak power/torque from a dyno sweep and best launch
//  times from the launch timer. Owned by EngineViewModel; reset on every
//  engine swap so one engine's numbers never bleed onto another.
//
//  The dyno scopes report SI (kW / Nm); the leaderboard speaks HP / lb-ft, so
//  conversions happen here at the single point the values are recorded.
//

import Foundation
import Combine
import CoreGraphics

// Scope-unit → display-unit conversions. Engine-sim's base units are SI
// (units.h: N = m = sec = kg = 1), so the power scope is kW and the torque
// scope is Nm. (kW × this) = hp; (Nm ÷ this) = lb-ft.
private let hpPerKilowatt: Double = 1.341022
private let nmPerPoundFoot: Double = 1.355818

final class RunResultsStore: ObservableObject {

    // MARK: Dyno peaks (best seen during the current sweep)

    @Published private(set) var peakPowerHp: Double = 0
    @Published private(set) var peakPowerRpm: Double = 0
    @Published private(set) var peakTorqueLbFt: Double = 0
    @Published private(set) var peakTorqueRpm: Double = 0

    /// True while a dyno sweep is actively being recorded.
    @Published private(set) var dynoRecording: Bool = false

    /// Best top speed (mph) observed for the current engine. Persisted with the
    /// engine so the community browser can show it; 0 until the car has moved.
    @Published private(set) var topSpeedMph: Double = 0

    /// A dyno sweep has produced a usable peak that can be submitted.
    var hasDynoResult: Bool { peakPowerHp > 0 }

    /// A 0-60 launch has been captured — postable on its own, even with no dyno.
    var hasLaunchResult: Bool { (bestLaunchSec["0-60"] ?? 0) > 0 }

    /// Any postable result exists (dyno peak or launch time).
    var hasPostableResult: Bool { hasDynoResult || hasLaunchResult }

    /// Fired whenever a best result is finalized (a sweep freezes, a launch
    /// completes, or a new top speed is set) so the owner can persist these
    /// numbers onto the engine. Carries the full current best-of snapshot.
    var onStatsCommitted: ((CapturedStats) -> Void)?

    /// The current best-of snapshot, suitable for persisting onto the engine.
    var snapshot: CapturedStats {
        CapturedStats(peakPowerHp: peakPowerHp, peakPowerRpm: peakPowerRpm,
                      peakTorqueLbFt: peakTorqueLbFt, peakTorqueRpm: peakTorqueRpm,
                      zeroToSixtySec: bestLaunchSec["0-60"] ?? 0,
                      topSpeedMph: topSpeedMph)
    }

    private func commitStats() { onStatsCommitted?(snapshot) }

    /// Whether the current captured result has already been posted to the
    /// leaderboard. Cleared the instant a new sweep begins so each unique run
    /// can be posted at most once (no spamming the post button).
    @Published private(set) var posted: Bool = false

    func markPosted() { posted = true }

    // MARK: Launch times (best per target id; lower is better)

    @Published private(set) var bestLaunchSec: [String: Double] = [:]

    func bestLaunch(_ targetId: String) -> Double? { bestLaunchSec[targetId] }

    // MARK: Lifecycle

    /// Called on engine swap — the recorded numbers belong to the engine that
    /// produced them, so a new engine starts from a clean slate.
    func resetForEngineChange() {
        clearDynoPeaks()
        dynoRecording = false
        topSpeedMph = 0
        bestLaunchSec.removeAll()
    }

    // MARK: Top speed ingestion

    /// Minimum gap between top-speed persistence commits. The live max climbs
    /// continuously during a pull; without this it would fire a disk write
    /// every poll. The displayed value still updates immediately — only the
    /// persistence callback is throttled.
    private let topSpeedCommitInterval: TimeInterval = 1.5
    private var lastTopSpeedCommit: Date = .distantPast

    /// Feed the live vehicle speed (mph) each poll, keeping the running max.
    /// Updates the published value immediately; throttles the persistence
    /// commit so a sustained pull doesn't hammer the disk.
    func recordTopSpeed(mph: Double) {
        guard mph > topSpeedMph else { return }
        topSpeedMph = mph
        let now = Date()
        guard now.timeIntervalSince(lastTopSpeedCommit) >= topSpeedCommitInterval else { return }
        lastTopSpeedCommit = now
        commitStats()
    }

    // MARK: Dyno ingestion

    /// Feed the live dyno scope buffers each poll. A sweep is bracketed by the
    /// dyno toggling on→off; peaks reset when a new sweep begins and persist
    /// (frozen) once it ends so the result stays available to submit.
    func ingestDyno(power: [CGPoint], torque: [CGPoint], dynoActive: Bool) {
        if dynoActive && !dynoRecording {
            clearDynoPeaks()      // new sweep — start fresh
            dynoRecording = true
        } else if !dynoActive && dynoRecording {
            dynoRecording = false // sweep ended — freeze the captured peak
            commitStats()         // persist the frozen peak onto the engine
        }
        guard dynoRecording else { return }
        absorbPeak(from: power, kilowatts: true)
        absorbPeak(from: torque, kilowatts: false)
    }

    /// Track the running maximum across the whole sweep rather than trusting
    /// the rolling 100-point scope buffer to still hold the peak.
    private func absorbPeak(from points: [CGPoint], kilowatts: Bool) {
        guard let best = points.max(by: { $0.y < $1.y }), best.y > 0 else { return }
        let rpm = Double(best.x)
        if kilowatts {
            let hp = Double(best.y) * hpPerKilowatt
            if hp > peakPowerHp { peakPowerHp = hp; peakPowerRpm = rpm }
        } else {
            let lbFt = Double(best.y) / nmPerPoundFoot
            if lbFt > peakTorqueLbFt { peakTorqueLbFt = lbFt; peakTorqueRpm = rpm }
        }
    }

    private func clearDynoPeaks() {
        peakPowerHp = 0; peakPowerRpm = 0
        peakTorqueLbFt = 0; peakTorqueRpm = 0
        posted = false
    }

    // MARK: Launch ingestion

    /// Record a completed launch run, keeping only the best (lowest) time for
    /// the given target. Called by the launch timer when a run finishes.
    func recordLaunch(targetId: String, seconds: Double) {
        guard seconds > 0 else { return }
        if let existing = bestLaunchSec[targetId], existing <= seconds { return }
        bestLaunchSec[targetId] = seconds
        if targetId == "0-60" {
            // A fresh best is a new postable result — re-arm the post button
            // (mirrors how a new dyno sweep clears `posted`).
            posted = false
            commitStats()
        }
    }
}
