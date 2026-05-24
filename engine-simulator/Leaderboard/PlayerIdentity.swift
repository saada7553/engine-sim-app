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
        static let playerId = "player.stableId"
    }

    /// The current leaderboard name. Empty until the player sets one.
    @Published private(set) var username: String

    /// Whether the player has finished the first-launch tutorial.
    @Published private(set) var hasCompletedOnboarding: Bool

    /// Stable, opaque identity for this player — the real key for "is this
    /// mine" on the leaderboard and community board. Usernames are NOT unique
    /// (two people can pick "Bob"), so matching on the name wrongly highlighted
    /// rows and let a same-named player target someone else's engine. This id
    /// is generated once and mirrored into iCloud key-value storage, so it's
    /// the same across the player's own devices but distinct between people.
    /// Settable only by ``resetIdentity()`` (the "delete my data" path), which
    /// rolls a fresh id so a wiped player can't be re-linked to deleted content.
    private(set) var playerId: String

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.username = defaults.string(forKey: Keys.username) ?? ""
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
        self.playerId = Self.resolvePlayerId(defaults: defaults)
    }

    /// Read the stable id, preferring an iCloud-synced value so a second device
    /// on the same Apple ID inherits the same identity. Falls back to a local
    /// value, generating and persisting one (locally + iCloud) on first launch.
    private static func resolvePlayerId(defaults: UserDefaults) -> String {
        let cloud = NSUbiquitousKeyValueStore.default
        if let synced = cloud.string(forKey: Keys.playerId), !synced.isEmpty {
            defaults.set(synced, forKey: Keys.playerId)
            return synced
        }
        if let local = defaults.string(forKey: Keys.playerId), !local.isEmpty {
            cloud.set(local, forKey: Keys.playerId)
            cloud.synchronize()
            return local
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: Keys.playerId)
        cloud.set(fresh, forKey: Keys.playerId)
        cloud.synchronize()
        return fresh
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

    /// Clear the username and roll a brand-new stable id, locally and in iCloud.
    /// The "delete my data" path calls this after the player's cloud content is
    /// gone, so future posts start as a fresh, unlinked player. (Onboarding is
    /// reset separately by that same path so the app returns to the tutorial.)
    @MainActor
    func resetIdentity() {
        let cloud = NSUbiquitousKeyValueStore.default

        username = ""
        defaults.removeObject(forKey: Keys.username)

        let fresh = UUID().uuidString
        playerId = fresh
        defaults.set(fresh, forKey: Keys.playerId)
        cloud.set(fresh, forKey: Keys.playerId)
        cloud.synchronize()
    }

    /// Re-show the first-launch flow. Wired to a DEBUG-only button in the
    /// profile popover so the tutorial can be replayed without wiping defaults.
    func resetOnboarding() {
        hasCompletedOnboarding = false
        defaults.set(false, forKey: Keys.onboarded)
    }
}
