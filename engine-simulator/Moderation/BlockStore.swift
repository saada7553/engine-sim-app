//
//  BlockStore.swift
//  engine-simulator
//
//  The set of other players the user has blocked. One app-wide store keyed on
//  the stable `ownerId` (PlayerIdentity.playerId), so a single block hides that
//  person's content everywhere it surfaces — the community board AND the
//  leaderboard, which both stamp `ownerId` on every record. The feeds observe
//  this and filter blocked owners out after each fetch (CloudKit can't do a
//  server-side "not in this set" cleanly, so it's a client-side filter).
//
//  Persisted to UserDefaults and mirrored into iCloud key-value storage so a
//  block follows the user across their own devices — same pattern as the stable
//  player id in PlayerIdentity.
//

import Foundation
import Combine

@MainActor
final class BlockStore: ObservableObject {
    static let shared = BlockStore()

    private enum Keys {
        static let blocked = "moderation.blockedOwnerIds"
    }

    /// Stable owner ids the user has blocked. Published so any feed observing it
    /// re-filters the instant a block changes, no refetch needed.
    @Published private(set) var blockedIds: Set<String>

    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore

    init(defaults: UserDefaults = .standard,
         cloud: NSUbiquitousKeyValueStore = .default) {
        self.defaults = defaults
        self.cloud = cloud
        // Prefer the iCloud-synced list (a block made on another device), else
        // the local copy.
        let synced = cloud.array(forKey: Keys.blocked) as? [String]
        let local = defaults.stringArray(forKey: Keys.blocked)
        self.blockedIds = Set(synced ?? local ?? [])
    }

    func isBlocked(_ ownerId: String) -> Bool {
        !ownerId.isEmpty && blockedIds.contains(ownerId)
    }

    /// Block a player by stable id. Returns whether the player is now blocked —
    /// false only when there's no id to key on (an empty id, e.g. a legacy
    /// record with no owner tag) or it's your own id (you can't block yourself).
    /// The caller uses this to confirm honestly rather than claim a block that
    /// didn't take.
    @discardableResult
    func block(ownerId: String) -> Bool {
        guard !ownerId.isEmpty, ownerId != PlayerIdentity.shared.playerId else { return false }
        if blockedIds.contains(ownerId) { return true }
        blockedIds.insert(ownerId)
        persist()
        return true
    }

    func unblock(ownerId: String) {
        guard blockedIds.contains(ownerId) else { return }
        blockedIds.remove(ownerId)
        persist()
    }

    /// Drop every block. Part of the "delete my data" reset — a wiped player
    /// starts with a clean slate locally and across their devices.
    func clearAll() {
        guard !blockedIds.isEmpty else { return }
        blockedIds.removeAll()
        persist()
    }

    private func persist() {
        let list = Array(blockedIds)
        defaults.set(list, forKey: Keys.blocked)
        cloud.set(list, forKey: Keys.blocked)
        cloud.synchronize()
    }
}
