//
//  CommunityService.swift
//  engine-simulator
//
//  CloudKit access for the community engine browser. Engines are shared to the
//  PUBLIC database so everyone sees the same catalog. The full EngineSpec JSON
//  (with its embedded capturedStats) rides on each record so a shared engine
//  can be downloaded, previewed and re-raced; denormalized columns alongside it
//  let the browser sort/filter without decoding every spec.
//
//  Like the leaderboard, v1 trusts client-submitted numbers — CloudKit can't
//  re-run the sim. Ownership of a re-publish is enforced by a deterministic,
//  per-owner record ID (you can only ever overwrite your own engine's record);
//  publishing someone else's downloaded engine is blocked client-side via the
//  spec's CommunityOrigin.
//
//  ── Manual CloudKit Dashboard setup (one-time) ───────────────────────────
//  Record type `CommunityEngine` with these fields. Mark the sort columns
//  SORTABLE and the filter columns QUERYABLE (ownerId queryable powers the
//  per-owner "delete my data" wipe):
//    ownerId (String, queryable)         ownerUsername (String, queryable)
//    engineName (String)
//    engineClassRaw (String, queryable)  layoutRaw (String)
//    specJSON (String)                   appVersion (String)
//    buildCostTotal (Double, sortable)   displacementL (Double, sortable)
//    cylinderCount (Int64)
//    peakPowerHp (Double, sortable+queryable)
//    peakTorqueLbFt (Double, sortable+queryable)
//    zeroToSixtySec (Double)             topSpeedMph (Double)
//  Also enable QUERYABLE on the system `recordName` (powers "fetch all") and
//  SORTABLE on the system `createdTimestamp` (powers the "Newest" sort, which
//  sorts on the `creationDate` key).
//

import Foundation
import CloudKit
import CryptoKit

// MARK: - Errors

enum CommunityError: LocalizedError {
    case noUsername
    case notEligible(String)
    case decodeFailed
    case contentRejected(String)

    var errorDescription: String? {
        switch self {
        case .noUsername:               return "Set a community name before publishing."
        case .notEligible(let why):     return why
        case .decodeFailed:             return "This engine couldn't be read."
        case .contentRejected(let why): return why
        }
    }
}

// MARK: - Service

final class CommunityService {
    static let shared = CommunityService()

    /// Shared with the leaderboard — one iCloud container for the whole app.
    static let containerIdentifier = LeaderboardService.containerIdentifier
    static let recordType = "CommunityEngine"
    /// Page size. CloudKit pulls at most this many per request, so it doubles
    /// as the rate-limit on how much one fetch can pull down; "load more"
    /// continues from the returned cursor.
    static let pageLimit = 30

    private lazy var database: CKDatabase =
        CKContainer(identifier: Self.containerIdentifier).publicCloudDatabase

    private init() { }

    // A page of results plus the cursor to continue from (nil = end reached).
    struct Page {
        let engines: [CommunityEngine]
        let cursor: CKQueryOperation.Cursor?
    }

    // MARK: Publish

    /// Share `spec` to the community under `ownerUsername`. Re-publishing the
    /// same engine overwrites the owner's existing record rather than spawning
    /// duplicates. Throws `notEligible` if the engine was authored by someone
    /// else (a downloaded engine), `noUsername` if no name is set.
    @discardableResult
    func publish(spec: EngineSpec, ownerUsername: String, ownerId: String) async throws -> CommunityEngine {
        let trimmed = ownerUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CommunityError.noUsername }
        if let reason = Self.ineligibilityReason(for: spec, currentUserId: ownerId) {
            throw CommunityError.notEligible(reason)
        }
        // Safety net for the public name + description. The builder already
        // screens these on save, so this only catches engines saved before that
        // gate shipped — but it's the last checkpoint before text goes public.
        if let rejection = await EngineContentValidator.validate(
            name: spec.name, description: spec.engineDescription) {
            throw CommunityError.contentRejected(rejection.reason)
        }

        let record = makeRecord(from: spec, ownerUsername: trimmed, ownerId: ownerId)
        do {
            let (saveResults, _) = try await database.modifyRecords(
                saving: [record], deleting: [], savePolicy: .allKeys, atomically: true)
            let saved = try saveResults[record.recordID]?.get() ?? record
            guard let engine = Self.engine(from: saved) else { throw CommunityError.decodeFailed }
            ReviewRequest.registerHappyMoment()
            return engine
        } catch {
            reportFailure(error, op: "community_publish")
            throw error
        }
    }

    /// Remove a previously-published engine (only meaningful for one the player
    /// owns). Best-effort: logs and rethrows so the UI can report failure.
    func unpublish(recordName: String) async throws {
        do {
            _ = try await database.modifyRecords(
                saving: [], deleting: [CKRecord.ID(recordName: recordName)], atomically: true)
        } catch {
            print("CommunityService: unpublish failed for \(recordName): \(error)")
            reportFailure(error, op: "community_unpublish")
            throw error
        }
    }

    /// Why `spec` can't be published, or nil if it can. Built engines without a
    /// spec can't reach here; this guards the "no re-publishing others' work"
    /// rule using the spec's recorded origin.
    static func ineligibilityReason(for spec: EngineSpec, currentUserId: String) -> String? {
        if let origin = spec.communityOrigin, origin.authorId != currentUserId {
            return "This engine was built by \(origin.authorUsername). You can't republish someone else's engine."
        }
        return nil
    }

    // MARK: Fetch

    /// First page for the given sort/filter. The class filter narrows to one
    /// engine class; nil means everything.
    func fetchFirstPage(sort: CommunitySort,
                        engineClass: EngineClass?,
                        limit: Int = pageLimit) async throws -> Page {
        let query = CKQuery(recordType: Self.recordType, predicate: predicate(sort, engineClass))
        query.sortDescriptors = [NSSortDescriptor(key: sort.recordKey, ascending: sort.ascending)]
        let (matches, cursor) = try await database.records(matching: query, resultsLimit: limit)
        return Page(engines: Self.engines(from: matches), cursor: cursor)
    }

    /// Continue from a cursor returned by a previous page ("load more").
    func fetchNextPage(after cursor: CKQueryOperation.Cursor,
                       limit: Int = pageLimit) async throws -> Page {
        let (matches, next) = try await database.records(continuingMatchFrom: cursor,
                                                         resultsLimit: limit)
        return Page(engines: Self.engines(from: matches), cursor: next)
    }

    private func predicate(_ sort: CommunitySort, _ engineClass: EngineClass?) -> NSPredicate {
        var clauses: [NSPredicate] = []
        if let engineClass {
            clauses.append(NSPredicate(format: "engineClassRaw == %@", engineClass.rawValue))
        }
        // When ranking by a captured metric, exclude engines that never recorded
        // it — otherwise a power sort lists never-dyno'd engines (0 hp) at the
        // bottom, which the player has no reason to see on a power board.
        switch sort {
        case .power:  clauses.append(NSPredicate(format: "peakPowerHp > 0"))
        case .torque: clauses.append(NSPredicate(format: "peakTorqueLbFt > 0"))
        case .newest, .cheapest: break
        }
        guard !clauses.isEmpty else { return NSPredicate(value: true) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
    }

    // MARK: Record mapping

    private func makeRecord(from spec: EngineSpec, ownerUsername: String, ownerId: String) -> CKRecord {
        let breakdown = EnginePricing.price(for: spec)
        let stats = spec.capturedStats ?? .empty
        let recordID = CKRecord.ID(recordName: Self.recordName(ownerId: ownerId, specId: spec.id))
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)

        record["ownerId"] = ownerId as CKRecordValue
        record["ownerUsername"] = ownerUsername as CKRecordValue
        record["engineName"] = spec.name as CKRecordValue
        record["engineClassRaw"] = EngineClass.from(spec.layout).rawValue as CKRecordValue
        record["layoutRaw"] = spec.layout.rawValue as CKRecordValue
        record["specJSON"] = Self.encodeSpec(spec) as CKRecordValue
        record["appVersion"] = Self.appVersion as CKRecordValue

        record["buildCostTotal"] = breakdown.total as CKRecordValue
        record["displacementL"] = spec.displacementLitres as CKRecordValue
        record["cylinderCount"] = spec.layout.cylinderCount as CKRecordValue

        record["peakPowerHp"] = stats.peakPowerHp as CKRecordValue
        record["peakTorqueLbFt"] = stats.peakTorqueLbFt as CKRecordValue
        record["zeroToSixtySec"] = stats.zeroToSixtySec as CKRecordValue
        record["topSpeedMph"] = stats.topSpeedMph as CKRecordValue

        return record
    }

    /// Deterministic record name: the same owner (by stable id) + engine always
    /// map to the same record, so re-publishing overwrites in place. Keying on
    /// the stable id (not the username) means two players who happen to share a
    /// name can't collide on, or overwrite, each other's records.
    private static func recordName(ownerId: String, specId: UUID) -> String {
        let raw = "\(ownerId)|\(specId.uuidString)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return "engine-" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func engines(from matches: [(CKRecord.ID, Result<CKRecord, Error>)]) -> [CommunityEngine] {
        matches.compactMap { _, result in
            guard let record = try? result.get() else { return nil }
            return engine(from: record)
        }
    }

    private static func engine(from record: CKRecord) -> CommunityEngine? {
        guard let owner = record["ownerUsername"] as? String,
              let classRaw = record["engineClassRaw"] as? String,
              let engineClass = EngineClass(rawValue: classRaw),
              let specJSON = record["specJSON"] as? String else { return nil }

        return CommunityEngine(
            id: record.recordID.recordName,
            ownerId: record["ownerId"] as? String ?? "",
            ownerUsername: owner,
            engineName: record["engineName"] as? String ?? "Engine",
            engineClass: engineClass,
            layoutRaw: record["layoutRaw"] as? String ?? "",
            specJSON: specJSON,
            buildCostTotal: record["buildCostTotal"] as? Double ?? 0,
            displacementL: record["displacementL"] as? Double ?? 0,
            cylinderCount: record["cylinderCount"] as? Int ?? 0,
            appVersion: record["appVersion"] as? String ?? "",
            publishedAt: record.creationDate ?? Date()
        )
    }

    // MARK: Spec (de)serialization — reuse the leaderboard's encoders (DRY).

    static func encodeSpec(_ spec: EngineSpec) -> String { LeaderboardService.encodeSpec(spec) }
    static func decodeSpec(_ json: String) -> EngineSpec? { LeaderboardService.decodeSpec(json) }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
