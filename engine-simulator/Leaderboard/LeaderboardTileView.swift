//
//  LeaderboardTileView.swift
//  engine-simulator
//
//  The global leaderboard tile. Top: board picker + engine-class filter and a
//  submit strip that posts the active engine's captured dyno/launch result.
//  Below: the ranked rows.
//
//  Built-in engines can't compete — only user-built engines (those with a
//  spec) can submit, and a run needs a captured dyno peak first.
//

import SwiftUI
import Combine

// MARK: - Layout constants

private let lbOuterPadding: CGFloat = 12
private let lbRowSpacing: CGFloat = 6
private let lbControlSpacing: CGFloat = 10
private let lbRankColumnWidth: CGFloat = 30
// Slight inset inside the horizontal chip scrollers so the first pill's stroke
// isn't clipped against the scroll edge.
private let lbChipRowInset: CGFloat = 4

// Font sizes. This tile lives in the dashboard, which renders at a 0.7 global
// scale on iOS — the original 7–12pt instrument sizes were unreadable there,
// so iOS is sized up to compensate while macOS stays compact.
#if os(macOS)
private let lbHeaderFont: CGFloat = 14
private let lbChipFont: CGFloat = 12
private let lbStatusTitleFont: CGFloat = 14
private let lbStatusDetailFont: CGFloat = 12
private let lbButtonFont: CGFloat = 12
private let lbRankFont: CGFloat = 17
private let lbNameFont: CGFloat = 16
private let lbRowDetailFont: CGFloat = 13
private let lbMetricFont: CGFloat = 21
private let lbMetricUnitFont: CGFloat = 11
private let lbNoticeFont: CGFloat = 14
#else
private let lbHeaderFont: CGFloat = 14
private let lbChipFont: CGFloat = 14
private let lbStatusTitleFont: CGFloat = 15
private let lbStatusDetailFont: CGFloat = 13
private let lbButtonFont: CGFloat = 13
private let lbRankFont: CGFloat = 16
private let lbNameFont: CGFloat = 16
private let lbRowDetailFont: CGFloat = 13
private let lbMetricFont: CGFloat = 20
private let lbMetricUnitFont: CGFloat = 10
private let lbNoticeFont: CGFloat = 15
#endif

// MARK: - View model

@MainActor
final class LeaderboardViewModel: ObservableObject {
    @Published var metric: LeaderboardMetric = .peakPower
    @Published var engineClass: EngineClass? = nil      // nil = global

    @Published private(set) var entries: [LeaderboardEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    /// Set only when a post fails; cleared when a new run starts. Success is
    /// reflected by RunResultsStore.posted, never by a lingering message here.
    @Published private(set) var submitError: String?

    /// Short-lived per-category cache so toggling between boards (or away and
    /// back) doesn't refire a CloudKit query for results we just pulled.
    private var cache: [String: (entries: [LeaderboardEntry], at: Date)] = [:]
    private let cacheTTL: TimeInterval = 60

    /// Reload key — any change reruns the fetch via `.task(id:)`.
    var filterKey: String { "\(metric.rawValue)|\(engineClass?.rawValue ?? "global")" }

    func clearSubmitError() { submitError = nil }

    /// `force` skips the cache — used by pull-to-refresh and right after a post
    /// so a freshly submitted entry shows up immediately.
    func load(force: Bool = false) async {
        let key = filterKey
        if !force, let cached = cache[key], Date().timeIntervalSince(cached.at) < cacheTTL {
            entries = cached.entries
            errorText = nil
            return
        }
        isLoading = true
        errorText = nil
        do {
            let fetched = try await LeaderboardService.shared.fetch(metric: metric, engineClass: engineClass)
            entries = fetched
            cache[key] = (fetched, Date())
        } catch {
            print("Leaderboard Fetch Error: \(error)")
            entries = []
            errorText = "Leaderboard unavailable. Check your connection and iCloud sign-in."
        }
        isLoading = false
    }

    /// Returns true only if the run actually reached the backend. On success
    /// the run is marked posted so it can't be submitted again.
    func submit(spec: EngineSpec, results: RunResultsStore) async -> Bool {
        submitError = nil
        let submission = LeaderboardSubmission(
            spec: spec,
            peakPowerHp: results.peakPowerHp,
            peakPowerRpm: results.peakPowerRpm,
            peakTorqueLbFt: results.peakTorqueLbFt,
            peakTorqueRpm: results.peakTorqueRpm,
            zeroToSixtySec: results.bestLaunch("0-60") ?? 0
        )
        do {
            let saved = try await LeaderboardService.shared.submit(submission)
            results.markPosted()
            await load(force: true)   // skip cache so the new entry shows
            // CloudKit's query index lags a few seconds behind a save, so the
            // refetch above often won't include the just-posted run yet. Merge
            // it in locally so the player sees their entry immediately.
            mergeOptimistic(saved)
            return true
        } catch {
            submitError = error.localizedDescription
            return false
        }
    }

    /// Insert a freshly-posted entry into the current board if it belongs there,
    /// keeping the list sorted by the active metric. Reconciled by the next real
    /// fetch once CloudKit has indexed the record.
    private func mergeOptimistic(_ entry: LeaderboardEntry) {
        guard qualifies(entry) else { return }
        var list = entries.filter { $0.id != entry.id }
        list.append(entry)
        list.sort { lhs, rhs in
            let a = lhs.metricValue(for: metric), b = rhs.metricValue(for: metric)
            return metric.descending ? a > b : a < b
        }
        entries = list
        cache[filterKey] = (list, Date())
    }

    /// Whether an entry passes the board's current metric/class filters.
    private func qualifies(_ entry: LeaderboardEntry) -> Bool {
        if let engineClass, entry.engineClass != engineClass { return false }
        if metric == .zeroToSixty, entry.zeroToSixtySec <= 0 { return false }
        return true
    }

    /// Copy a board engine into the local library as a fresh user engine so it
    /// can be inspected, tuned and re-raced. Retained for future use — the
    /// download button was removed from the row UI but the backend path stays.
    func downloadAndRace(_ entry: LeaderboardEntry) {
        guard var spec = LeaderboardService.decodeSpec(entry.specJSON) else { return }
        spec.id = UUID()    // a new local engine, independent of the author's
        EngineLibrary.shared.saveUserEngine(spec)
    }
}

// MARK: - Tile

struct LeaderboardTileView: View {
    @ObservedObject var engineVm: EngineViewModel
    @StateObject private var model = LeaderboardViewModel()
    @ObservedObject private var library = EngineLibrary.shared

    /// The active engine's spec, only if it's user-built (built-ins return nil
    /// and therefore can't compete).
    private var userSpec: EngineSpec? { library.selectedEntry?.spec }

    var body: some View {
        ZStack {
            Color.appBackground
            VStack(spacing: lbControlSpacing) {
                BoardHeaderLabel()
                MetricFilterBar(model: model)
                ClassFilterBar(model: model)
                SubmitStrip(model: model, results: engineVm.runResults, userSpec: userSpec)
                Divider().background(Color.strokeFaint)
                rankings
            }
            .padding(lbOuterPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task(id: model.filterKey) { await model.load() }
    }

    @ViewBuilder private var rankings: some View {
        if model.isLoading && model.entries.isEmpty {
            centered { ProgressView().controlSize(.small).tint(.accentLive) }
        } else if let error = model.errorText {
            centered { LeaderboardNotice(symbol: "wifi.slash", text: error) }
        } else if model.entries.isEmpty {
            centered {
                LeaderboardNotice(symbol: "trophy",
                                  text: "No entries yet for \(model.metric.title)\(model.engineClass.map { " · \($0.displayName)" } ?? ""). Be the first.")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: lbRowSpacing) {
                    ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                        LeaderboardRow(rank: index + 1, entry: entry, metric: model.metric,
                                       isMe: !entry.ownerId.isEmpty && entry.ownerId == PlayerIdentity.shared.playerId)
                    }
                }
            }
            .tint(.accentLive)
            .refreshable { await model.load(force: true) }
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Header

private struct BoardHeaderLabel: View {
    var body: some View {
        HStack {
            Text("LEADERBOARD")
                .modifier(RetroFont(size: lbHeaderFont, weight: .bold))
                .foregroundColor(.accentLive)
                .tracking(2)
            Spacer()
        }
    }
}

// MARK: - Filter chip (shared, fully themed — no native menu chrome)

private struct FilterChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: lbChipFont, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(selected ? .white : .textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? Color.accentLive.opacity(0.18) : Color.surfaceLow)
                )
                .overlay(
                    Capsule().stroke(selected ? Color.accentLive : Color.clear,
                                     lineWidth: Theme.Stroke.thin)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Metric selector (board picker)

private struct MetricFilterBar: View {
    @ObservedObject var model: LeaderboardViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LeaderboardMetric.allCases) { metric in
                    FilterChip(label: metric.title.uppercased(),
                               selected: model.metric == metric) { model.metric = metric }
                }
            }
            .padding(.horizontal, lbChipRowInset)
            .padding(.vertical, 1)
        }
    }
}

// MARK: - Class filter

private struct ClassFilterBar: View {
    @ObservedObject var model: LeaderboardViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(label: "GLOBAL", selected: model.engineClass == nil) { model.engineClass = nil }
                ForEach(EngineClass.allCases) { cls in
                    FilterChip(label: cls.shortLabel, selected: model.engineClass == cls) { model.engineClass = cls }
                }
            }
            .padding(.horizontal, lbChipRowInset)
            .padding(.vertical, 1)
        }
    }
}

// MARK: - Submit strip

private struct SubmitStrip: View {
    @ObservedObject var model: LeaderboardViewModel
    @ObservedObject var results: RunResultsStore
    let userSpec: EngineSpec?

    @State private var submitting = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: lbStatusTitleFont, weight: .semibold, design: .monospaced))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                Text(statusDetail)
                    .font(.system(size: lbStatusDetailFont, design: .monospaced))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if results.posted {
                postedBadge
            } else if canSubmit {
                postButton
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.panel).fill(Color.surfaceFaint))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel)
            .stroke(Color.strokeFaint, lineWidth: Theme.Stroke.thin))
        // A fresh dyno sweep clears the posted flag in RunResultsStore; clear
        // any stale error here at the same moment so the strip resets cleanly.
        .onChange(of: results.dynoRecording) { _, recording in
            if recording { model.clearSubmitError() }
        }
    }

    private var postButton: some View {
        Button(action: submit) {
            HStack(spacing: 5) {
                if submitting { ProgressView().controlSize(.small) }
                Text(submitting ? "POSTING" : "POST RUN")
                    .font(.system(size: lbButtonFont, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundColor(.black)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Color.accentLive))
        }
        .buttonStyle(.plain)
        .disabled(submitting)
    }

    private var postedBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
            Text("POSTED")
                .font(.system(size: lbButtonFont, weight: .bold, design: .monospaced))
                .tracking(1)
        }
        .foregroundColor(.accentOk)
    }

    private var canSubmit: Bool { userSpec != nil && results.hasPostableResult }

    private var titleColor: Color { model.submitError != nil ? .accentDanger : .white }

    /// "480 hp · 320 lb-ft", "5.20s 0-60", or both joined — whatever's captured.
    private var resultSummary: String {
        var parts: [String] = []
        if results.hasDynoResult {
            parts.append("\(Int(results.peakPowerHp)) hp · \(Int(results.peakTorqueLbFt)) lb-ft")
        }
        if let launch = results.bestLaunch("0-60"), launch > 0 {
            parts.append(String(format: "%.2fs 0-60", launch))
        }
        return parts.joined(separator: " · ")
    }

    private var statusTitle: String {
        if results.posted { return "Posted to the board" }
        if let error = model.submitError { return error }
        guard userSpec != nil else { return "You've selected a prebuilt engine" }
        guard results.hasPostableResult else { return "No result captured yet" }
        return resultSummary
    }

    private var statusDetail: String {
        if results.posted { return "Run the dyno or a 0-60 again to post a new result" }
        guard userSpec != nil else { return "Make your own engine to compete" }
        guard results.hasPostableResult else { return "Run the dyno or a 0-60 to capture a result" }
        let cost = EnginePricing.formatted(EnginePricing.buildCost(for: userSpec!))
        return "Build \(cost) — ready to post"
    }

    private func submit() {
        guard let spec = userSpec else { return }
        submitting = true
        Task {
            await model.submit(spec: spec, results: results)
            submitting = false
        }
    }
}

// MARK: - Row

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let metric: LeaderboardMetric
    let isMe: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: lbRankFont, weight: .bold, design: .monospaced))
                .foregroundColor(rankColor)
                .frame(width: lbRankColumnWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.username)
                    .font(.system(size: lbNameFont, weight: .semibold, design: .monospaced))
                    .foregroundColor(isMe ? .accentLive : .textPrimary)
                    .lineLimit(1)
                Text("\(entry.engineName) · \(entry.engineClass.shortLabel) · \(EnginePricing.formatted(entry.buildCostTotal))")
                    .font(.system(size: lbRowDetailFont, design: .monospaced))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(metric.formatted(entry.metricValue(for: metric)))
                    .font(.system(size: lbMetricFont, weight: .bold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                Text(metric.unit)
                    .font(.system(size: lbMetricUnitFont, weight: .medium, design: .monospaced))
                    .foregroundColor(.textMuted)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.control)
            .fill(isMe ? Color.accentLive.opacity(0.10) : Color.surfaceLow))
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .accentWarn
        case 2, 3: return .textSecondary
        default: return .textMuted
        }
    }
}

// MARK: - Notice

private struct LeaderboardNotice: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundColor(.textFaint)
            Text(text)
                .font(.system(size: lbNoticeFont, design: .monospaced))
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }
}
