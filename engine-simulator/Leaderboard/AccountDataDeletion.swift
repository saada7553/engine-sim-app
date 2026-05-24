//
//  AccountDataDeletion.swift
//  engine-simulator
//
//  Backs the Settings "Delete my data" control. There's no account/login here —
//  a player is just a chosen username plus an anonymous, device-generated
//  `playerId` — so "delete my data" means: remove every public record stamped
//  with that id (community engines + leaderboard runs), then reset the local
//  identity so the next post starts a clean, unlinked player.
//
//  Cloud records are deleted FIRST, while the owning id is still known; the local
//  wipe only runs if that succeeds, so a failed delete leaves the player able to
//  retry rather than orphaning cloud data under an id they can no longer produce.
//
//  The local wipe is a full factory reset: identity, block list, preferences,
//  and every engine the player built, then onboarding is flagged incomplete so
//  the app drops back into the first-launch tutorial.
//
//  Left untouched on purpose: any moderation reports the player filed against
//  others (kept for moderation integrity — these carry the reporter's id, not
//  their content), and their Pro purchase (an Apple entitlement, not our data).
//

import Foundation
import CloudKit

enum AccountDataDeletion {
    enum Outcome {
        case success(deleted: Int)
        case failure(String)
    }

    /// Erase the player's published footprint, then reset their local identity
    /// and clear their block list. Safe to call when nothing was ever published
    /// (it just resets the identity).
    @MainActor
    static func deleteEverything() async -> Outcome {
        let ownerId = PlayerIdentity.shared.playerId
        let database = CKContainer(identifier: LeaderboardService.containerIdentifier).publicCloudDatabase

        let deleted: Int
        do {
            let engines = try await CloudKitOwnership.deleteAll(
                ownerId: ownerId, recordType: CommunityService.recordType, in: database)
            let runs = try await CloudKitOwnership.deleteAll(
                ownerId: ownerId, recordType: LeaderboardService.recordType, in: database)
            deleted = engines + runs
        } catch {
            print("AccountDataDeletion: cloud delete failed: \(error)")
            reportFailure(error, op: "account_delete")
            return .failure("Couldn't reach iCloud to delete your published content. "
                          + "Check your connection and iCloud sign-in, then try again.")
        }

        PlayerIdentity.shared.resetIdentity()
        BlockStore.shared.clearAll()
        AppSettings.shared.resetToDefaults()
        EngineLibrary.shared.deleteAllUserEngines()
        // Last: drop back to the first-launch tutorial so the reset is obvious.
        PlayerIdentity.shared.resetOnboarding()
        return .success(deleted: deleted)
    }
}
