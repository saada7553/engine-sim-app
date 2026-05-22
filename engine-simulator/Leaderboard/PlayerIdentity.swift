//
//  PlayerIdentity.swift
//  engine-simulator
//
//  The local player's identity — the username shown on the global leaderboard
//  and a one-time onboarding flag. UserDefaults-backed and observable so the
//  app root can gate first-launch onboarding and any future leaderboard
//  submission can read a single source of truth.
//

import Foundation
import Combine

/// Bounds shared by the store and the validator so "what counts as a valid
/// username" is defined in exactly one place.
enum UsernameRules {
    static let minLength = 3
    static let maxLength = 18
    /// Letters, numbers, single spaces, underscore and hyphen. No emoji or
    /// punctuation — keeps the leaderboard column clean and unambiguous.
    static let allowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-")
}

final class PlayerIdentity: ObservableObject {
    static let shared = PlayerIdentity()

    private enum Keys {
        static let username = "player.username"
        static let onboarded = "player.hasCompletedOnboarding"
    }

    /// The current leaderboard name. Empty until the player sets one.
    @Published private(set) var username: String

    /// Whether the player has finished the first-launch tutorial.
    @Published private(set) var hasCompletedOnboarding: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.username = defaults.string(forKey: Keys.username) ?? ""
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
    }

    /// Persist a validated, trimmed username. Callers must validate first via
    /// ``UsernameValidator`` — this only stores.
    func setUsername(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        username = trimmed
        defaults.set(trimmed, forKey: Keys.username)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Keys.onboarded)
    }

    /// Re-show the first-launch flow. Wired to a DEBUG-only button in the
    /// profile popover so the tutorial can be replayed without wiping defaults.
    func resetOnboarding() {
        hasCompletedOnboarding = false
        defaults.set(false, forKey: Keys.onboarded)
    }
}
