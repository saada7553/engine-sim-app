//
//  LeaderboardTileView.swift
//  engine-simulator
//
//  The global leaderboard tile. Top: board picker + engine-class filter and a
//  submit strip that posts the active engine's captured dyno/launch result.
//  Below: the ranked rows, each of which can be downloaded and re-raced.
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
private let lbHeaderFont: CGFloat = 11
private let lbChipFont: CGFloat = 11
private let lbStatusTitleFont: CGFloat = 12
private let lbStatusDetailFont: CGFloat = 10
private let lbButtonFont: CGFloat = 10
private let lbRankFont: CGFloat = 13
private let lbNameFont: CGFloat = 13
private let lbRowDetailFont: CGFloat = 10
private let lbMetricFont: CGFloat = 16
private let lbMetricUnitFont: CGFloat = 8
private let lbNoticeFont: CGFloat = 12
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
    @Published private(set) var lastSubmitMessage: String?

    /// Reload key — any change reruns the fetch via `.task(id:)`.
    var filterKey: String { "\(metric.rawValue)|\(engineClass?.rawValue ?? "global")" }

    /// Whether CloudKit is actually wired up in this build. Drives a distinct
    /// "not set up" state instead of a misleading empty board.
    var isConfigured: Bool { LeaderboardService.shared.isConfigured }

    func load() async {
        guard isConfigured else { entries = []; errorText = nil; return }
        isLoading = true
        errorText = nil
        do {
            entries = try await LeaderboardService.shared.fetch(metric: metric, engineClass: engineClass)
        } catch {
            entries = []
            errorText = "Leaderboard unavailable. Check your connection and iCloud sign-in."
        }
        isLoading = false
    }

    func submit(spec: EngineSpec, results: RunResultsStore) async {
        let submission = LeaderboardSubmission(
            spec: spec,
            peakPowerHp: results.peakPowerHp,
            peakPowerRpm: results.peakPowerRpm,
            peakTorqueLbFt: results.peakTorqueLbFt,
            peakTorqueRpm: results.peakTorqueRpm,
            zeroToSixtySec: results.bestLaunch("0-60") ?? 0
        )
        do {
            try await LeaderboardService.shared.submit(submission)
            lastSubmitMessage = "Posted \(Int(results.peakPowerHp)) hp to the board."
            await load()
        } catch {
            lastSubmitMessage = error.localizedDescription
        }
    }

    /// Copy a board engine into the local library as a fresh user engine so it
    /// can be inspected, tuned and re-raced.
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
        if !model.isConfigured {
            centered {
                LeaderboardNotice(symbol: "icloud.slash",
                                  text: "Leaderboard isn't set up in this build yet. The rest of the loop still works — drive, dyno and time your engine.")
            }
        } else if model.isLoading && model.entries.isEmpty {
            centered { ProgressView().controlSize(.small) }
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
                                       isMe: entry.username == PlayerIdentity.shared.username,
                                       onDownload: { model.downloadAndRace(entry) })
                    }
                }
            }
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
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(statusDetail)
                    .font(.system(size: lbStatusDetailFont, design: .monospaced))
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            if canSubmit {
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
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.panel).fill(Color.surfaceFaint))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel)
            .stroke(Color.strokeFaint, lineWidth: Theme.Stroke.thin))
    }

    private var canSubmit: Bool { model.isConfigured && userSpec != nil && results.hasDynoResult }

    private var statusTitle: String {
        if let message = model.lastSubmitMessage { return message }
        guard userSpec != nil else { return "This is a prebuilt engine" }
        guard results.hasDynoResult else { return "No dyno result yet" }
        return "\(Int(results.peakPowerHp)) hp · \(Int(results.peakTorqueLbFt)) lb-ft"
    }

    private var statusDetail: String {
        guard userSpec != nil else { return "Make your own engine to compete" }
        guard results.hasDynoResult else { return "Run the dyno to capture a peak" }
        let cost = EnginePricing.formatted(EnginePricing.buildCost(for: userSpec!))
        guard model.isConfigured else { return "Build \(cost) — leaderboard not set up yet" }
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
    let onDownload: () -> Void

    @State private var confirmingDownload = false

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: lbRankFont, weight: .bold, design: .monospaced))
                .foregroundColor(rankColor)
                .frame(width: lbRankColumnWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.username)
                    .font(.system(size: lbNameFont, weight: .semibold, design: .monospaced))
                    .foregroundColor(isMe ? .accentLive : .white)
                    .lineLimit(1)
                Text("\(entry.engineName) · \(entry.engineClass.shortLabel) · \(EnginePricing.formatted(entry.buildCostTotal))")
                    .font(.system(size: lbRowDetailFont, design: .monospaced))
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(metric.formatted(entry.metricValue(for: metric)))
                    .font(.system(size: lbMetricFont, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(metric.unit)
                    .font(.system(size: lbMetricUnitFont, design: .monospaced))
                    .foregroundColor(.textFaint)
            }

            Button(action: { confirmingDownload = true }) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Download & race this engine")
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.control)
            .fill(isMe ? Color.accentLive.opacity(0.10) : Color.surfaceLow))
        .confirmationDialog("Download \(entry.engineName)?",
                            isPresented: $confirmingDownload, titleVisibility: .visible) {
            Button("Add to my engines") { onDownload() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Copies this build into your library so you can tune and race it.")
        }
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
