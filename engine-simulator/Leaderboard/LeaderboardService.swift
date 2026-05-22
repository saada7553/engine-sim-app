//
//  LeaderboardService.swift
//  engine-simulator
//
//  CloudKit access for the global leaderboard. Submissions and board queries
//  hit the PUBLIC database so everyone shares one ranking. The full EngineSpec
//  JSON rides along on each record so a board engine can be downloaded and
//  re-raced, and so a future server-side pass could re-validate the numbers.
//
//  v1 trusts the client-submitted metrics — CloudKit can't re-run the sim.
//
//  ── Manual CloudKit Dashboard setup (one-time) ───────────────────────────
//  Record type `EngineLeaderboardEntry` with these fields. Mark the sort
//  fields SORTABLE and `engineClassRaw` + `username` QUERYABLE:
//    username (String, queryable)        engineName (String)
//    engineClassRaw (String, queryable)  layoutRaw (String)
//    specJSON (String)                   appVersion (String)
//    buildCostTotal (Double)             buildCostEngine (Double)
//    displacementL (Double)              peakPowerHp (Double, sortable)
//    peakPowerRpm (Double)               peakTorqueLbFt (Double, sortable)
//    peakTorqueRpm (Double)              valueHpPerThousand (Double, sortable)
//    specificOutputHpPerL (Double, sortable)
//    zeroToSixtySec (Double, sortable)
//  Also enable QUERYABLE on the system `recordName` so "fetch all" works.
//

import Foundation
import CloudKit
import Security

// MARK: - Submission input

/// Everything needed to post a run, gathered by the submission UI from the
/// active engine's spec and its RunResultsStore.
struct LeaderboardSubmission {
    let spec: EngineSpec
    let peakPowerHp: Double
    let peakPowerRpm: Double
    let peakTorqueLbFt: Double
    let peakTorqueRpm: Double
    let zeroToSixtySec: Double   // 0 when the player hasn't run a launch
}

// MARK: - Errors

enum LeaderboardError: LocalizedError {
    case notConfigured
    case noUsername
    case noPowerResult

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "The leaderboard isn't set up in this build yet."
        case .noUsername:    return "Set a leaderboard name before posting."
        case .noPowerResult: return "Do a dyno run first — there's no peak power to post."
        }
    }
}

// MARK: - Service

final class LeaderboardService {
    static let shared = LeaderboardService()

    /// Rename to match the container you create in Xcode's iCloud capability.
    static let containerIdentifier = "iCloud.com.simulation.engine-simulator"
    private static let recordType = "EngineLeaderboardEntry"
    private static let defaultFetchLimit = 100

    /// True only when the app actually carries the CloudKit entitlement.
    /// Touching ANY CloudKit API (even creating the container) crashes the
    /// process when it's missing, so this is checked before every CloudKit
    /// call and the container is created lazily — never when unconfigured.
    let isConfigured: Bool

    private lazy var database: CKDatabase =
        CKContainer(identifier: Self.containerIdentifier).publicCloudDatabase

    private init() {
        isConfigured = Self.hasCloudKitEntitlement()
    }

    private static let entitlementKey = "com.apple.developer.icloud-services"

    /// Whether the binary carries the CloudKit entitlement, determined WITHOUT
    /// touching CloudKit (which crashes when it's absent). macOS reads its own
    /// entitlements via the Security framework; iOS reads the embedded
    /// provisioning profile (SecTask is macOS-only).
    private static func hasCloudKitEntitlement() -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let raw = SecTaskCopyValueForEntitlement(task, entitlementKey as CFString, nil)
        else { return false }
        return entitlementGrantsCloudKit(raw)
        #elseif targetEnvironment(simulator)
        // The simulator has no signed entitlements, so any CloudKit call would
        // crash — treat it as unconfigured (the board shows its "not set up"
        // state). Test CloudKit on a real device or on macOS.
        return false
        #else
        // Device builds: dev / ad-hoc / TestFlight embed a provisioning profile
        // we can read. An App Store build has none — in that case the iCloud
        // capability was necessarily configured to ship, so trust it.
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let open = text.range(of: "<plist"),
              let close = text.range(of: "</plist>"),
              let plistData = String(text[open.lowerBound..<close.upperBound]).data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [],
                                                                      format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return true }
        return entitlementGrantsCloudKit(entitlements[entitlementKey])
        #endif
    }

    private static func entitlementGrantsCloudKit(_ value: Any?) -> Bool {
        if let services = value as? [String] {
            return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
        }
        if let single = value as? String {
            return single == "CloudKit" || single == "CloudKit-Anonymous"
        }
        return false
    }

    // MARK: Submit

    /// Post a run to the leaderboard, returning the stored entry. The caller is
    /// responsible for ensuring the engine is user-built (no prebuilts).
    @discardableResult
    func submit(_ submission: LeaderboardSubmission) async throws -> LeaderboardEntry {
        guard isConfigured else { throw LeaderboardError.notConfigured }
        let username = PlayerIdentity.shared.username
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LeaderboardError.noUsername
        }
        guard submission.peakPowerHp > 0 else { throw LeaderboardError.noPowerResult }

        let record = makeRecord(from: submission, username: username)
        let saved = try await database.save(record)
        return Self.entry(from: saved) ?? Self.fallbackEntry(from: record, username: username,
                                                              submission: submission)
    }

    // MARK: Fetch

    /// Fetch a board ranked by `metric`, optionally filtered to one engine
    /// class. The zero-to-sixty board excludes entries with no launch time.
    func fetch(metric: LeaderboardMetric,
               engineClass: EngineClass? = nil,
               limit: Int = defaultFetchLimit) async throws -> [LeaderboardEntry] {
        guard isConfigured else { return [] }
        let query = CKQuery(recordType: Self.recordType, predicate: predicate(metric, engineClass))
        query.sortDescriptors = [NSSortDescriptor(key: metric.recordKey, ascending: !metric.descending)]

        let (matches, _) = try await database.records(matching: query, resultsLimit: limit)
        return matches.compactMap { _, result in
            guard let record = try? result.get() else { return nil }
            return Self.entry(from: record)
        }
    }

    private func predicate(_ metric: LeaderboardMetric, _ engineClass: EngineClass?) -> NSPredicate {
        var clauses: [NSPredicate] = []
        if let engineClass {
            clauses.append(NSPredicate(format: "engineClassRaw == %@", engineClass.rawValue))
        }
        // A 0-60 board only ranks entries that actually posted a launch time.
        if metric == .zeroToSixty {
            clauses.append(NSPredicate(format: "zeroToSixtySec > 0"))
        }
        guard !clauses.isEmpty else { return NSPredicate(value: true) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
    }

    // MARK: Record mapping

    private func makeRecord(from s: LeaderboardSubmission, username: String) -> CKRecord {
        let breakdown = EnginePricing.price(for: s.spec)
        let engineCost = breakdown.engineCost
        let displacement = s.spec.displacementLitres
        let record = CKRecord(recordType: Self.recordType)

        record["username"] = username as CKRecordValue
        record["engineName"] = s.spec.name as CKRecordValue
        record["engineClassRaw"] = EngineClass.from(s.spec.layout).rawValue as CKRecordValue
        record["layoutRaw"] = s.spec.layout.rawValue as CKRecordValue
        record["specJSON"] = Self.encodeSpec(s.spec) as CKRecordValue
        record["appVersion"] = Self.appVersion as CKRecordValue

        record["buildCostTotal"] = breakdown.total as CKRecordValue
        record["buildCostEngine"] = engineCost as CKRecordValue
        record["displacementL"] = displacement as CKRecordValue

        record["peakPowerHp"] = s.peakPowerHp as CKRecordValue
        record["peakPowerRpm"] = s.peakPowerRpm as CKRecordValue
        record["peakTorqueLbFt"] = s.peakTorqueLbFt as CKRecordValue
        record["peakTorqueRpm"] = s.peakTorqueRpm as CKRecordValue
        record["valueHpPerThousand"] =
            LeaderboardMath.valueHpPerThousand(powerHp: s.peakPowerHp, engineCost: engineCost) as CKRecordValue
        record["specificOutputHpPerL"] =
            LeaderboardMath.specificOutput(powerHp: s.peakPowerHp, displacementL: displacement) as CKRecordValue
        record["zeroToSixtySec"] = s.zeroToSixtySec as CKRecordValue

        return record
    }

    private static func entry(from record: CKRecord) -> LeaderboardEntry? {
        guard let username = record["username"] as? String,
              let classRaw = record["engineClassRaw"] as? String,
              let engineClass = EngineClass(rawValue: classRaw) else { return nil }

        return LeaderboardEntry(
            id: record.recordID.recordName,
            username: username,
            engineName: record["engineName"] as? String ?? "Engine",
            engineClass: engineClass,
            layoutRaw: record["layoutRaw"] as? String ?? "",
            specJSON: record["specJSON"] as? String ?? "",
            buildCostTotal: record["buildCostTotal"] as? Double ?? 0,
            buildCostEngine: record["buildCostEngine"] as? Double ?? 0,
            displacementL: record["displacementL"] as? Double ?? 0,
            peakPowerHp: record["peakPowerHp"] as? Double ?? 0,
            peakPowerRpm: record["peakPowerRpm"] as? Double ?? 0,
            peakTorqueLbFt: record["peakTorqueLbFt"] as? Double ?? 0,
            peakTorqueRpm: record["peakTorqueRpm"] as? Double ?? 0,
            valueHpPerThousand: record["valueHpPerThousand"] as? Double ?? 0,
            specificOutputHpPerL: record["specificOutputHpPerL"] as? Double ?? 0,
            zeroToSixtySec: record["zeroToSixtySec"] as? Double ?? 0,
            appVersion: record["appVersion"] as? String ?? "",
            submittedAt: record.creationDate ?? Date()
        )
    }

    /// Used only if a freshly-saved record somehow can't be re-parsed — keeps
    /// submit() returning a usable entry rather than failing after a good save.
    private static func fallbackEntry(from record: CKRecord, username: String,
                                      submission s: LeaderboardSubmission) -> LeaderboardEntry {
        let breakdown = EnginePricing.price(for: s.spec)
        return LeaderboardEntry(
            id: record.recordID.recordName,
            username: username,
            engineName: s.spec.name,
            engineClass: EngineClass.from(s.spec.layout),
            layoutRaw: s.spec.layout.rawValue,
            specJSON: encodeSpec(s.spec),
            buildCostTotal: breakdown.total,
            buildCostEngine: breakdown.engineCost,
            displacementL: s.spec.displacementLitres,
            peakPowerHp: s.peakPowerHp,
            peakPowerRpm: s.peakPowerRpm,
            peakTorqueLbFt: s.peakTorqueLbFt,
            peakTorqueRpm: s.peakTorqueRpm,
            valueHpPerThousand: LeaderboardMath.valueHpPerThousand(powerHp: s.peakPowerHp,
                                                                  engineCost: breakdown.engineCost),
            specificOutputHpPerL: LeaderboardMath.specificOutput(powerHp: s.peakPowerHp,
                                                                 displacementL: s.spec.displacementLitres),
            zeroToSixtySec: s.zeroToSixtySec,
            appVersion: appVersion,
            submittedAt: Date()
        )
    }

    // MARK: Spec (de)serialization

    static func encodeSpec(_ spec: EngineSpec) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(spec) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decodeSpec(_ json: String) -> EngineSpec? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(EngineSpec.self, from: data)
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
