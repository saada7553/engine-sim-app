//
//  CloudKitOwnership.swift
//  engine-simulator
//
//  Shared helper for bulk-deleting every public record a given player owns — the
//  cloud half of the Settings "Delete my data" control. Both the community board
//  (CommunityEngine) and the leaderboard (EngineLeaderboardEntry) stamp an
//  `ownerId` on every record, so one query-and-delete by ownerId clears a
//  player's footprint from either record type.
//
//  Requires `ownerId` to be marked QUERYABLE on the record type in the CloudKit
//  Dashboard (the same one-time setup the service files document).
//

import Foundation
import CloudKit

enum CloudKitOwnership {
    /// CloudKit caps a single modify to a few hundred records; stay well under so
    /// a heavy poster's wipe still goes through in clean batches.
    private static let deleteBatchSize = 200

    /// Delete every record of `recordType` whose `ownerId` equals `ownerId`.
    /// Returns the number deleted. Throws on the first CloudKit error (network,
    /// auth, or a missing queryable index) so the caller can stop and report.
    static func deleteAll(ownerId: String,
                          recordType: String,
                          in database: CKDatabase) async throws -> Int {
        let ids = try await ownedRecordIDs(ownerId: ownerId, recordType: recordType, in: database)
        for chunk in ids.chunked(into: deleteBatchSize) {
            _ = try await database.modifyRecords(saving: [], deleting: chunk, atomically: false)
        }
        return ids.count
    }

    /// Page through every record the player owns, collecting only the record IDs
    /// (`desiredKeys: []` so no field data — specJSON et al. — is pulled down).
    private static func ownedRecordIDs(ownerId: String,
                                       recordType: String,
                                       in database: CKDatabase) async throws -> [CKRecord.ID] {
        let query = CKQuery(recordType: recordType,
                            predicate: NSPredicate(format: "ownerId == %@", ownerId))
        var ids: [CKRecord.ID] = []
        var result = try await database.records(matching: query, desiredKeys: [],
                                                resultsLimit: CKQueryOperation.maximumResults)
        ids.append(contentsOf: result.matchResults.map(\.0))
        while let cursor = result.queryCursor {
            result = try await database.records(continuingMatchFrom: cursor, desiredKeys: [],
                                                resultsLimit: CKQueryOperation.maximumResults)
            ids.append(contentsOf: result.matchResults.map(\.0))
        }
        return ids
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
