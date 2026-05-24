//
//  ReportBlockButton.swift
//  engine-simulator
//
//  The small flag affordance shown on every piece of another player's public
//  content — a leaderboard row and a community card. Tapping it opens a popup
//  to report the engine or block its author. Reporting also blocks (so the
//  content disappears immediately, which is what a reporting user expects); the
//  report itself is fired best-effort to CloudKit for the developer to review.
//
//  Hidden for the user's own content by the call sites (you don't report
//  yourself), so this view always assumes it's pointed at someone else.
//

import SwiftUI

struct ReportBlockButton: View {
    let ownerId: String
    let username: String
    let recordName: String
    let contentName: String
    let contentType: ReportedContentType

    var iconSize: CGFloat = 13
    var tint: Color = .textMuted

    @State private var showDialog = false
    @State private var confirmation: String?
    @ObservedObject private var blockStore = BlockStore.shared

    private var displayName: String { username.isEmpty ? "this player" : username }

    var body: some View {
        Button {
            showDialog = true
        } label: {
            Image(systemName: "flag")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(tint)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .confirmationDialog("Report or block \(displayName)?",
                            isPresented: $showDialog,
                            titleVisibility: .visible) {
            Button("Report engine", role: .destructive) { report() }
            Button("Block \(displayName)", role: .destructive) { block() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Report sends “\(contentName)” for review and hides it. Block hides everything from \(displayName).")
        }
        .alert("Done", isPresented: Binding(get: { confirmation != nil },
                                            set: { if !$0 { confirmation = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(confirmation ?? "")
        }
    }

    private func report() {
        let report = ContentReport(reportedOwnerId: ownerId,
                                   reportedUsername: username,
                                   reportedRecordName: recordName,
                                   reportedContentName: contentName,
                                   contentType: contentType)
        Task { await ReportService.submit(report) }
        // Reporting also hides the author's content locally — the report is for
        // the developer to act on later; the user shouldn't keep seeing it now.
        let hid = blockStore.block(ownerId: ownerId)
        confirmation = hid
            ? "Thanks. “\(contentName)” was reported for review and \(displayName)'s content is now hidden."
            : "Thanks. “\(contentName)” was reported for review."
    }

    private func block() {
        confirmation = blockStore.block(ownerId: ownerId)
            ? "Blocked \(displayName). You won't see their content anymore."
            : "Couldn't block \(displayName). Please try again."
    }
}
