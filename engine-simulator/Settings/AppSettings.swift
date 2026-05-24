//
//  AppSettings.swift
//  engine-simulator
//
//  User-facing app preferences, UserDefaults-backed and observable so the
//  Settings screen edits a single source of truth that the rest of the app
//  reacts to live. Player identity (name / onboarding) lives separately in
//  PlayerIdentity — this is for behavioural toggles.
//

import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// The single UI refresh rate (Hz). Drives BOTH how often the simulator
    /// state is polled and how often the 2D gauges / driver tools redraw — one
    /// knob, no scattered timers. Lower = less CPU/battery but steppier
    /// animation; higher = smoother. The 3D engine view interpolates on its own
    /// render loop and is unaffected. This is deliberately NOT the physics/audio
    /// frame rate (kPhysicsFrameRateHz in EngineWrapper.m), which stays steady
    /// so the sim and audio don't glitch when the UI rate is lowered.
    ///
    /// Ceiling is 30 because the physics thread only produces a new frame 30×/s
    /// (kPhysicsFrameRateHz) — polling faster just re-reads identical state and
    /// burns battery for no visible gain.
    static let minUIFrameRate: Double = 10
    static let maxUIFrameRate: Double = 30
    /// At or above this rate, redraw cost is high enough to be worth flagging
    /// for battery — the UI surfaces a gentle warning.
    static let highBatteryFrameRate: Double = 25

    private enum Keys {
        static let engineDamage = "settings.engineDamageEnabled"
        static let haptics      = "settings.hapticsEnabled"
        static let uiFrameRate  = "settings.uiFrameRate"
        static let autoFrameRate = "settings.autoFrameRate"
    }

    /// When false, the engine can't be damaged — money-shifts, over-rev, and
    /// wear are all suppressed and any existing damage heals. "Drive freely".
    @Published var engineDamageEnabled: Bool {
        didSet { defaults.set(engineDamageEnabled, forKey: Keys.engineDamage) }
    }

    /// Master switch for haptic feedback (UI taps + the money-shift crash
    /// rumble). Only meaningful on devices with haptics; a no-op elsewhere.
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }

    /// The effective UI frame rate, clamped to [min, max] on set so a stray
    /// value can't stall or thrash the UI clock. Persisted; EngineViewModel
    /// observes it and rebuilds its poll timer live, so changes apply without a
    /// relaunch. Set it through `selectFrameRate(_:)` / `enableAutoFrameRate()`
    /// rather than directly so Auto mode stays consistent.
    @Published var uiFrameRate: Double {
        didSet {
            let clamped = min(max(uiFrameRate, Self.minUIFrameRate), Self.maxUIFrameRate)
            if clamped != uiFrameRate { uiFrameRate = clamped; return }
            defaults.set(uiFrameRate, forKey: Keys.uiFrameRate)
        }
    }

    /// When true, the rate is chosen for the device automatically (and re-chosen
    /// when Low Power Mode toggles) rather than pinned by the user.
    @Published private(set) var autoFrameRate: Bool {
        didSet { defaults.set(autoFrameRate, forKey: Keys.autoFrameRate) }
    }

    /// Whether the current rate is high enough to meaningfully cost battery.
    var usesHighBatteryRate: Bool { uiFrameRate >= Self.highBatteryFrameRate }

    /// Mirror of the OS Low Power Mode flag, so the UI can explain an auto
    /// downgrade. (Always false on macOS.)
    var lowPowerModeEnabled: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default ON when never set (object(forKey:) is nil on first launch).
        self.engineDamageEnabled = defaults.object(forKey: Keys.engineDamage) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true

        // First launch defaults to Auto so a weak device starts gentle without
        // the user having to know to lower it.
        let auto = defaults.object(forKey: Keys.autoFrameRate) as? Bool ?? true
        self.autoFrameRate = auto
        if auto {
            self.uiFrameRate = Self.recommendedFrameRate()
        } else {
            let saved = defaults.object(forKey: Keys.uiFrameRate) as? Double ?? Self.maxUIFrameRate
            self.uiFrameRate = min(max(saved, Self.minUIFrameRate), Self.maxUIFrameRate)
        }

        // Re-evaluate the auto pick whenever Low Power Mode flips.
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.objectWillChange.send()   // refresh lowPowerModeEnabled-derived UI
                if self.autoFrameRate { self.uiFrameRate = Self.recommendedFrameRate() }
            }
            .store(in: &cancellables)
    }

    /// Pin the rate to a specific value (turns Auto off).
    func selectFrameRate(_ rate: Double) {
        autoFrameRate = false
        uiFrameRate = rate
    }

    /// Hand rate selection back to the device-capability heuristic.
    func enableAutoFrameRate() {
        autoFrameRate = true
        uiFrameRate = Self.recommendedFrameRate()
    }

    /// A sensible default rate for this device. Low Power Mode → floor; weak
    /// CPU/RAM → reduced; otherwise the platform target. Kept crude on purpose —
    /// it only sets the *starting* point; the user can always override.
    ///
    /// Mobile biases lower than desktop: a phone is battery- and thermally
    /// constrained and held close to the face, so a strong phone targets 20 fps
    /// while a Mac (mains/large battery, Apple Silicon headroom) targets the
    /// full 30.
    static func recommendedFrameRate() -> Double {
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled { return minUIFrameRate }
        let cores = info.activeProcessorCount
        let memGB = Double(info.physicalMemory) / 1_073_741_824.0
        #if os(iOS)
        if cores <= 2 || memGB < 3 { return minUIFrameRate }   // 10
        if cores <= 4 || memGB < 4 { return 15 }
        return 20
        #else
        if cores <= 2 || memGB < 3 { return 15 }
        if cores <= 4 || memGB < 6 { return 20 }
        return maxUIFrameRate                                  // 30
        #endif
    }
}
