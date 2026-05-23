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

    private enum Keys {
        static let engineDamage = "settings.engineDamageEnabled"
        static let haptics      = "settings.hapticsEnabled"
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

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default ON when never set (object(forKey:) is nil on first launch).
        self.engineDamageEnabled = defaults.object(forKey: Keys.engineDamage) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
    }
}
