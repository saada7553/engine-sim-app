//
//  ReportService.swift
//  engine-simulator
//
//  Sends a user's report of objectionable content to CloudKit so it can be
//  reviewed and acted on. Reports land in the PUBLIC database as `ContentReport`
//  records the developer can inspect in the CloudKit Dashboard — the actionable
//  half of the App Store UGC requirements (the other halves being the on-publish
//  content filter and the per-user block).
//
//  Reporting is best-effort: a failed write never blocks the user, because the
//  UI always blocks the offending author locally at the same time, so the
//  content disappears regardless of whether the report reached the cloud.
//
//  ── Manual CloudKit Dashboard setup (one-time) ───────────────────────────
//  Record type `ContentReport` with these fields (none need to be queryable for
//  the app — they're for the developer to read):
//    reporterId (String)         reportedOwnerId (String)
//    reportedUsername (String)   reportedRecordName (String)
//    reportedContentName (String)  contentType (String)
//    appVersion (String)
//

import Foundation
import CloudKit

enum ReportedContentType: String {
    case communityEngine
    case leaderboardEntry
}

/// Everything needed to file a report, gathered from the row/card the user
/// flagged.
struct ContentReport {
    let reportedOwnerId: String
    let reportedUsername: String
    let reportedRecordName: String
    let reportedContentName: String   // engine name shown publicly
    let contentType: ReportedContentType
}

enum ReportService {
    private static let containerIdentifier = LeaderboardService.containerIdentifier
    private static let recordType = "ContentReport"

    private static var database: CKDatabase {
        CKContainer(identifier: containerIdentifier).publicCloudDatabase
    }

    /// File a report. Returns true if the record reached CloudKit; the caller
    /// treats false as a soft failure (the author is blocked locally either way).
    @discardableResult
    static func submit(_ report: ContentReport) async -> Bool {
        let record = CKRecord(recordType: recordType)
        record["reporterId"] = PlayerIdentity.shared.playerId as CKRecordValue
        record["reportedOwnerId"] = report.reportedOwnerId as CKRecordValue
        record["reportedUsername"] = report.reportedUsername as CKRecordValue
        record["reportedRecordName"] = report.reportedRecordName as CKRecordValue
        record["reportedContentName"] = report.reportedContentName as CKRecordValue
        record["contentType"] = report.contentType.rawValue as CKRecordValue
        record["appVersion"] = appVersion as CKRecordValue

        do {
            _ = try await database.save(record)
            return true
        } catch {
            print("ReportService: report submit failed: \(error)")
            return false
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
