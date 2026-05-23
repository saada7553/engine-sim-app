//
//  CommunityBrowserModel.swift
//  engine-simulator
//
//  View model for the community engine browser. Owns the fetched page, the
//  sort/class filters, pagination, and the publish/download/unpublish actions.
//  Mirrors LeaderboardViewModel's short-lived per-filter cache so flipping
//  between sorts (or away and back) doesn't refire a CloudKit query for results
//  just pulled — the cache is the client-side half of the rate-limiting; the
//  page size is the server-side half.
//

import Foundation
import CloudKit
import Combine

@MainActor
final class CommunityBrowserModel: ObservableObject {
    @Published var sort: CommunitySort = .newest
    @Published var engineClass: EngineClass? = nil      // nil = all classes

    @Published private(set) var engines: [CommunityEngine] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorText: String?
    /// Set on a failed publish/download/unpublish; surfaced in the action UI.
    @Published private(set) var actionError: String?

    private var cursor: CKQueryOperation.Cursor?
    var canLoadMore: Bool { cursor != nil }

    /// Per-filter cache so toggling sorts doesn't refetch within the TTL.
    private var cache: [String: (engines: [CommunityEngine], at: Date)] = [:]
    private let cacheTTL: TimeInterval = 60

    /// Reload key — any change reruns the fetch via `.task(id:)`.
    var filterKey: String { "\(sort.rawValue)|\(engineClass?.rawValue ?? "all")" }

    func clearActionError() { actionError = nil }

    // MARK: Load

    /// `force` skips the cache (pull-to-refresh, or right after a publish).
    func load(force: Bool = false) async {
        let key = filterKey
        if !force, let cached = cache[key], Date().timeIntervalSince(cached.at) < cacheTTL {
            engines = cached.engines
            errorText = nil
            return
        }
        isLoading = true
        errorText = nil
        do {
            let page = try await CommunityService.shared.fetchFirstPage(sort: sort, engineClass: engineClass)
            engines = page.engines
            cursor = page.cursor
            cache[key] = (page.engines, Date())
        } catch {
            print("Community fetch error: \(error)")
            engines = []
            cursor = nil
            errorText = "Community unavailable. Check your connection and iCloud sign-in."
        }
        isLoading = false
    }

    /// Pull the next page and append it, de-duplicating by record id.
    func loadMore() async {
        guard let cursor, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let page = try await CommunityService.shared.fetchNextPage(after: cursor)
            let known = Set(engines.map(\.id))
            engines.append(contentsOf: page.engines.filter { !known.contains($0.id) })
            self.cursor = page.cursor
            cache[filterKey] = (engines, Date())
        } catch {
            print("Community load-more error: \(error)")
            // Stop paginating on error rather than spinning; the existing list
            // stays put and the user can pull-to-refresh.
            self.cursor = nil
        }
        isLoadingMore = false
    }

    // MARK: Actions

    /// Whether `spec` is publishable by the current player (user-built and not
    /// authored by someone else). Built-ins (nil spec) are never publishable.
    func eligibility(for spec: EngineSpec?) -> String? {
        guard let spec else { return "Select one of your own engines to publish." }
        if PlayerIdentity.shared.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Set a community name to publish."
        }
        return CommunityService.ineligibilityReason(for: spec,
                                                    currentUserId: PlayerIdentity.shared.playerId)
    }

    /// Publish `spec`. Returns true on success. On failure sets `actionError`.
    func publish(spec: EngineSpec) async -> Bool {
        actionError = nil
        do {
            let saved = try await CommunityService.shared.publish(
                spec: spec,
                ownerUsername: PlayerIdentity.shared.username,
                ownerId: PlayerIdentity.shared.playerId)
            await load(force: true)   // refetch so the board reflects the post
            // CloudKit's query index lags a few seconds behind a save, so the
            // refetch often won't include the just-published engine yet. Merge
            // it in locally so the player sees it immediately.
            mergeOptimistic(saved)
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    /// Insert a freshly-published engine into the current board if it belongs
    /// there, keeping the list ordered by the active sort. Reconciled by the
    /// next real fetch once CloudKit has indexed the record.
    private func mergeOptimistic(_ engine: CommunityEngine) {
        guard qualifies(engine) else { return }
        var list = engines.filter { $0.id != engine.id }
        list.append(engine)
        list.sort(by: orderedBefore)
        engines = list
        cache[filterKey] = (engines, Date())
    }

    /// Whether an engine passes the active sort/class filters (matches the
    /// server-side predicate so the optimistic insert can't show something the
    /// real query would have excluded).
    private func qualifies(_ engine: CommunityEngine) -> Bool {
        if let engineClass, engine.engineClass != engineClass { return false }
        switch sort {
        case .power, .torque: return engine.stats.hasDyno
        case .newest, .cheapest: return true
        }
    }

    /// Ordering for the active sort, matching the CloudKit sort descriptor.
    private func orderedBefore(_ a: CommunityEngine, _ b: CommunityEngine) -> Bool {
        switch sort {
        case .newest:   return a.publishedAt > b.publishedAt
        case .power:    return a.stats.peakPowerHp > b.stats.peakPowerHp
        case .torque:   return a.stats.peakTorqueLbFt > b.stats.peakTorqueLbFt
        case .cheapest: return a.buildCostTotal < b.buildCostTotal
        }
    }

    /// Copy a community engine into the local garage. Returns true on success.
    func download(_ engine: CommunityEngine) -> Bool {
        actionError = nil
        guard let spec = engine.spec else {
            actionError = CommunityError.decodeFailed.localizedDescription
            return false
        }
        let origin = CommunityOrigin(authorId: engine.ownerId,
                                     authorUsername: engine.ownerUsername,
                                     sourceRecordName: engine.id)
        EngineLibrary.shared.downloadCommunityEngine(spec: spec, origin: origin)
        return true
    }

    /// Whether the given engine was published by the current player (so it can
    /// be unpublished). Matched on the stable id, never the (non-unique) name.
    func isMine(_ engine: CommunityEngine) -> Bool {
        !engine.ownerId.isEmpty && engine.ownerId == PlayerIdentity.shared.playerId
    }

    /// Remove one of the player's own published engines. Returns true on success.
    func unpublish(_ engine: CommunityEngine) async -> Bool {
        actionError = nil
        do {
            try await CommunityService.shared.unpublish(recordName: engine.id)
            engines.removeAll { $0.id == engine.id }
            cache[filterKey] = (engines, Date())
            return true
        } catch {
            actionError = "Couldn't remove the engine. Try again."
            return false
        }
    }
}
