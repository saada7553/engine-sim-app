//
//  HapticManager.swift
//  engine-simulator
//
//  Central haptic feedback for the app. Two responsibilities:
//   1. Light UI feedback for buttons / toggles / selections / the H-shifter.
//   2. The money-shift CRASH haptic that follows the catastrophe sound in
//      real time — a violent randomized initial BANG scaled by over-rev
//      severity, then a continuous rumble + sharp per-impact PUNCHES whose
//      strength and timing track the LIVE crash-audio peaks streamed up from
//      the C++ synthesizer (EngineState.catastropheHapticLevel / Peak). Because
//      the booms and clanks fire at random pitches and times in the audio, the
//      crash haptic surges loud-soft-hard and feels different every time — it
//      is NOT a smooth exponential decay.
//
//  Capability differs sharply by device: iPhone has the full Taptic Engine +
//  Core Haptics (rich, modulated patterns); iPad has NO haptics; Mac exposes
//  only discrete trackpad feedback (no custom patterns). Each path degrades
//  gracefully — unsupported devices simply no-op.
//

import Foundation

#if os(iOS)
import CoreHaptics
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Light, discrete UI feedback flavors, mapped to the closest primitive each
/// platform offers.
enum HapticTap {
    case light      // routine button press
    case firm       // a more consequential action (gear engaged, starter)
    case selection  // value / segment changed, shifter detent
    case success    // confirmation (repair complete, etc.)
    case warning    // something went wrong (bad tune, fault)
}

final class HapticManager {
    static let shared = HapticManager()

#if os(iOS)
    // --- Money-shift onset BANG (randomized transient cluster) ---
    // A lead hit plus a random burst of follow-ups makes the initial detonation
    // punchy and different every time. Over-rev severity (~0..0.4+) is
    // normalised by kSeverityFullScale to scale the bang + how long it rings.
    private let kBangLeadSharpness: Float = 0.9
    private let kBangMinFollowups = 3
    private let kBangMaxFollowups = 7
    private let kBangMaxSpread: TimeInterval = 0.30
    private let kBangFollowupIntensityMin: Float = 0.7
    private let kBangFollowupIntensityMax: Float = 1.0
    private let kSeverityFullScale: Double = 0.4

    // --- Continuous crash rumble (follows the live crash audio) ---
    private let kRumbleSharpness: Float = 0.45
    // Strong even in the quiet gaps so the whole event reads as violent.
    private let kRumbleIntensityFloor: Float = 0.4
    // <1 boosts low envelope values so faint tails still drive a firm rumble.
    private let kRumbleCurve: Float = 0.55
    // Random ± wobble added each poll so the rumble surges and dips instead of
    // gliding — part of the loud-soft texture.
    private let kRumbleJitter: Float = 0.2
    private let kRumbleStopThreshold: Double = 0.02
    // The continuous event is created open-ended; safe upper bound so a missed
    // stop can't buzz forever.
    private let kRumbleMaxDuration: TimeInterval = 30.0
    // Randomised minimum hold so the crash always lasts a beat and varies in
    // length; bigger over-revs ring out toward the upper bound.
    private let kHoldMinSec: TimeInterval = 1.2
    private let kHoldMaxSec: TimeInterval = 2.6

    // --- Per-impact PUNCHES (the hard hits riding the rumble) ---
    // A fresh peak above kHitThreshold that jumped at least kHitRiseFactor over
    // the last poll fires a sharp transient — these are the random booms/clanks.
    private let kHitThreshold: Double = 0.16
    private let kHitRiseFactor: Double = 1.2
    private let kHitIntensityMin: Float = 0.6
    private let kHitSharpnessMin: Float = 0.3
    private let kHitSharpnessMax: Float = 1.0

    private var engine: CHHapticEngine?
    private var rumblePlayer: CHHapticAdvancedPatternPlayer?
    private var rumbleActive = false
    // Monotonic uptime until which the rumble is force-held even if the audio
    // envelope has briefly dipped. Guarantees a minimum (and variable) length.
    private var rumbleHoldUntil: TimeInterval = 0
    private var lastPeak: Double = 0
    private let supportsHaptics =
        CHHapticEngine.capabilitiesForHardware().supportsHaptics

    // Cached UI generators (kept prepared for low latency).
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let firmImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()
#endif

    private init() {
#if os(iOS)
        prepareEngine()
#endif
    }

    // MARK: - UI feedback

    func tap(_ kind: HapticTap) {
        guard AppSettings.shared.hapticsEnabled else { return }
#if os(iOS)
        switch kind {
        case .light:     lightImpact.impactOccurred()
        case .firm:      firmImpact.impactOccurred()
        case .selection: selectionGenerator.selectionChanged()
        case .success:   notificationGenerator.notificationOccurred(.success)
        case .warning:   notificationGenerator.notificationOccurred(.warning)
        }
#elseif os(macOS)
        // The trackpad performer only has a few discrete patterns.
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch kind {
        case .selection: performer.perform(.alignment, performanceTime: .now)
        default:         performer.perform(.levelChange, performanceTime: .now)
        }
#endif
    }

    /// Prime the platform generators so an imminent tap has minimal latency.
    func prepareForTaps() {
#if os(iOS)
        lightImpact.prepare()
        firmImpact.prepare()
        selectionGenerator.prepare()
#endif
    }

    // MARK: - Money-shift crash haptic

    /// Fire the initial CRASH bang. `severity` is the over-rev excess reported
    /// by the simulator; bigger over-revs hit harder and ring out longer.
    func beginMoneyshift(severity: Double) {
        guard AppSettings.shared.hapticsEnabled else { return }
#if os(iOS)
        guard supportsHaptics else { return }
        let strength = Float(min(1.0, max(0.0, severity / kSeverityFullScale)))
        playRandomBang(strength: strength)
        ensureRumbleStarted()
        let hold = kHoldMinSec + (kHoldMaxSec - kHoldMinSec) * Double(strength)
        rumbleHoldUntil = max(rumbleHoldUntil,
                              ProcessInfo.processInfo.systemUptime + hold)
        // The bang already delivered the first big hits; don't immediately
        // double-punch on the next poll's peak.
        lastPeak = 1.0
#elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange,
                                                         performanceTime: .now)
#endif
    }

    /// Drive the crash rumble + punches from the LIVE crash audio: `level` is
    /// the smoothed envelope, `peak` the loudest impact since the last poll.
    /// Call every poll. Stays alive while the sound is audible or the minimum
    /// hold hasn't elapsed, then stops. No-op where unsupported.
    func updateMoneyshift(level: Double, peak: Double) {
        guard AppSettings.shared.hapticsEnabled else { return }
#if os(iOS)
        guard supportsHaptics else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let audible = max(level, peak) > kRumbleStopThreshold
        guard audible || now < rumbleHoldUntil else {
            stopRumble()
            lastPeak = 0
            return
        }
        ensureRumbleStarted()

        // Continuous intensity: boosted envelope + random wobble so it surges
        // and dips (loud-soft) rather than gliding down smoothly.
        let drive = Float(min(1.0, max(0.0, max(level, peak))))
        let boosted = pow(drive, kRumbleCurve)
        let wobble = Float.random(in: -kRumbleJitter...kRumbleJitter)
        let intensity = min(1.0, max(kRumbleIntensityFloor, boosted + wobble))
        sendRumbleIntensity(intensity)

        // Hard PUNCH on a fresh loud impact — the random booms/clanks. Random
        // sharpness makes each hit feel distinct.
        if peak > kHitThreshold && peak > lastPeak * kHitRiseFactor {
            let hitIntensity = max(kHitIntensityMin, Float(min(1.0, sqrt(peak))))
            let hitSharpness = Float.random(in: kHitSharpnessMin...kHitSharpnessMax)
            playTransient(intensity: hitIntensity, sharpness: hitSharpness)
        }
        lastPeak = peak
#endif
    }

    // MARK: - Core Haptics internals (iOS only)

#if os(iOS)
    private func prepareEngine() {
        guard supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            // Restart transparently if the system stops or resets the engine
            // (e.g. after an interruption); clear rumble state either way.
            engine.stoppedHandler = { [weak self] _ in
                self?.rumbleActive = false
            }
            engine.resetHandler = { [weak self] in
                self?.rumbleActive = false
                try? self?.engine?.start()
            }
            self.engine = engine
        } catch {
            self.engine = nil
        }
    }

    /// Returns the engine, starting it on demand. Starting an already-running
    /// engine is a no-op, so this is cheap to call before playback.
    private func runningEngine() -> CHHapticEngine? {
        guard let engine = engine else { return nil }
        do { try engine.start() } catch { return nil }
        return engine
    }

    private func transientEvent(intensity: Float, sharpness: Float,
                                at relativeTime: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        ], relativeTime: relativeTime)
    }

    private func play(_ events: [CHHapticEvent]) {
        guard let engine = runningEngine() else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch { }
    }

    private func playTransient(intensity: Float, sharpness: Float) {
        play([transientEvent(intensity: intensity, sharpness: sharpness, at: 0)])
    }

    /// A lead hit plus a random burst of follow-up transients — the initial
    /// detonation. `strength` (0..1) scales the follow-up loudness.
    private func playRandomBang(strength: Float) {
        var events = [transientEvent(intensity: 1.0,
                                     sharpness: kBangLeadSharpness, at: 0)]
        let count = Int.random(in: kBangMinFollowups...kBangMaxFollowups)
        for _ in 0..<count {
            let when = TimeInterval.random(in: 0.01...kBangMaxSpread)
            let base = Float.random(in: kBangFollowupIntensityMin...kBangFollowupIntensityMax)
            let intensity = min(1.0, base * (0.6 + 0.4 * strength))
            let sharpness = Float.random(in: 0.3...1.0)
            events.append(transientEvent(intensity: intensity,
                                         sharpness: sharpness, at: when))
        }
        play(events)
    }

    private func ensureRumbleStarted() {
        guard !rumbleActive, let engine = runningEngine() else { return }
        // Base intensity 1.0; the live envelope scales it down via the dynamic
        // intensity-control parameter, so the rumble can swing the full range.
        let params = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
            CHHapticEventParameter(parameterID: .hapticSharpness,
                                   value: kRumbleSharpness)
        ]
        let event = CHHapticEvent(eventType: .hapticContinuous,
                                  parameters: params,
                                  relativeTime: 0,
                                  duration: kRumbleMaxDuration)
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.completionHandler = { [weak self] _ in
                self?.rumbleActive = false
            }
            try player.start(atTime: CHHapticTimeImmediate)
            rumblePlayer = player
            rumbleActive = true
        } catch {
            rumbleActive = false
        }
    }

    private func sendRumbleIntensity(_ intensity: Float) {
        guard let player = rumblePlayer else { return }
        let param = CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                             value: intensity, relativeTime: 0)
        try? player.sendParameters([param], atTime: CHHapticTimeImmediate)
    }

    private func stopRumble() {
        guard rumbleActive else { return }
        try? rumblePlayer?.stop(atTime: CHHapticTimeImmediate)
        rumblePlayer = nil
        rumbleActive = false
        rumbleHoldUntil = 0
    }
#endif
}
