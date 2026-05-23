//
//  CommunityTileView.swift
//  engine-simulator
//
//  The community engine browser tile. A publish strip for the player's
//  currently-selected engine, sort + engine-class filters, and a grid of
//  shared engines shown as cached still thumbnails (rendered once, never a
//  live 3D view per row). Each card surfaces the value of the active sort so
//  the list shows what it's ranked by at a glance. Tapping a card opens an
//  in-tile detail overlay (not a sheet — a sheet goes full-screen and clips on
//  iOS) with one live, slowly-rotating 3D preview and a Download button.
//
//  Only the player's own user-built engines can be published, and a downloaded
//  engine can never be re-published under a different name (enforced by the
//  spec's CommunityOrigin in CommunityService).
//

import SwiftUI

// MARK: - Layout constants

private let cOuterPadding: CGFloat = 12
private let cControlSpacing: CGFloat = 10
private let cCardSpacing: CGFloat = 10
private let cCardMinWidth: CGFloat = 220
private let cThumbHeight: CGFloat = 130
private let cChipRowInset: CGFloat = 4
private let cStateMinHeight: CGFloat = 200

#if os(macOS)
private let cHeaderFont: CGFloat = 14
private let cChipFont: CGFloat = 12
private let cButtonFont: CGFloat = 12
private let cCardTitleFont: CGFloat = 15
private let cCardSubFont: CGFloat = 12
private let cBadgeValueFont: CGFloat = 15
private let cBadgeCaptionFont: CGFloat = 9
private let cNoticeFont: CGFloat = 14
#else
private let cHeaderFont: CGFloat = 14
private let cChipFont: CGFloat = 14
private let cButtonFont: CGFloat = 13
private let cCardTitleFont: CGFloat = 16
private let cCardSubFont: CGFloat = 13
private let cBadgeValueFont: CGFloat = 15
private let cBadgeCaptionFont: CGFloat = 10
private let cNoticeFont: CGFloat = 15
#endif

// MARK: - Tile

struct CommunityTileView: View {
    @ObservedObject var engineVm: EngineViewModel
    @StateObject private var model = CommunityBrowserModel()
    @ObservedObject private var library = EngineLibrary.shared

    @State private var detailEngine: CommunityEngine?

    /// The active engine's spec, only if it's user-built (built-ins return nil).
    /// The live ECU tune is read straight from the engine VM and stamped on,
    /// rather than trusting the debounced-to-disk copy in the saved spec — so a
    /// publish right after tuning always ships the current tune.
    private var userSpec: EngineSpec? {
        guard var spec = library.selectedEntry?.spec else { return nil }
        spec.ecuTune = engineVm.ecu.export()
        return spec
    }

    var body: some View {
        ZStack {
            Color.appBackground
            platformBody
            detailOverlay
        }
        .task(id: model.filterKey) { await model.load() }
    }

    // MARK: Platform layout
    //
    // macOS keeps the controls pinned above a scrolling grid (plenty of window
    // height). iOS scrolls the controls along with the list so the small screen
    // frees vertical space for engines as you scroll down.

    @ViewBuilder private var platformBody: some View {
        #if os(macOS)
        VStack(spacing: cControlSpacing) {
            controls
            Divider().background(Color.strokeFaint)
            ScrollView { gridOrState }
                .refreshable { await model.load(force: true) }
        }
        .padding(cOuterPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #else
        ScrollView {
            VStack(spacing: cControlSpacing) {
                controls
                Divider().background(Color.strokeFaint)
                gridOrState
            }
            .padding(cOuterPadding)
        }
        .refreshable { await model.load(force: true) }
        #endif
    }

    private var controls: some View {
        VStack(spacing: cControlSpacing) {
            CommunityHeaderLabel()
            PublishStrip(model: model, userSpec: userSpec)
            SortFilterBar(model: model)
            ClassFilterBar(model: model)
        }
    }

    @ViewBuilder private var gridOrState: some View {
        if model.isLoading && model.engines.isEmpty {
            stateBox { DashLoader(diameter: 30, label: "Loading engines") }
        } else if let error = model.errorText {
            stateBox { CommunityNotice(symbol: "wifi.slash", text: error) }
        } else if model.engines.isEmpty {
            stateBox {
                CommunityNotice(symbol: "person.2",
                                text: "No engines shared yet\(model.engineClass.map { " for \($0.displayName)" } ?? ""). Publish one of yours.")
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        VStack(spacing: cCardSpacing) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cCardMinWidth), spacing: cCardSpacing)],
                      spacing: cCardSpacing) {
                ForEach(model.engines) { engine in
                    CommunityCard(engine: engine, sort: model.sort) {
                        withAnimation(.easeInOut(duration: 0.2)) { detailEngine = engine }
                    }
                }
            }
            if model.canLoadMore {
                LoadMoreButton(isLoading: model.isLoadingMore) { Task { await model.loadMore() } }
                    .padding(.top, 4)
            }
        }
    }

    private func stateBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, minHeight: cStateMinHeight)
    }

    // MARK: Detail overlay (in-tile, not a sheet)

    @ViewBuilder private var detailOverlay: some View {
        if let engine = detailEngine {
            CommunityDetailOverlay(engine: engine, model: model) {
                withAnimation(.easeInOut(duration: 0.2)) { detailEngine = nil }
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Header

private struct CommunityHeaderLabel: View {
    var body: some View {
        HStack {
            Text("COMMUNITY")
                .modifier(RetroFont(size: cHeaderFont, weight: .bold))
                .foregroundColor(.accentLive)
                .tracking(2)
            Spacer()
        }
    }
}

// MARK: - Publish strip

private struct PublishStrip: View {
    @ObservedObject var model: CommunityBrowserModel
    let userSpec: EngineSpec?

    @State private var publishing = false
    @State private var didPublish = false

    private var ineligibleReason: String? { model.eligibility(for: userSpec) }
    private var canPublish: Bool { ineligibleReason == nil && userSpec != nil }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(titleColor)
                    .lineLimit(2)
                Text(detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            trailingControl
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.panel).fill(bg))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel)
            .stroke(borderColor, lineWidth: Theme.Stroke.thin))
        .animation(.easeInOut(duration: 0.2), value: didPublish)
        .animation(.easeInOut(duration: 0.2), value: model.actionError)
        // A change of selected engine clears the last publish's result so the
        // strip reflects the engine now in front of the user.
        .onChange(of: userSpec?.id) { _, _ in
            didPublish = false
            model.clearActionError()
        }
    }

    @ViewBuilder private var trailingControl: some View {
        if didPublish && model.actionError == nil {
            publishedBadge
        } else if canPublish {
            publishButton
        }
    }

    private var publishButton: some View {
        Button(action: publish) {
            HStack(spacing: 5) {
                if publishing { DashLoader(diameter: 13, tint: .black) }
                Text(buttonLabel)
                    .font(.system(size: cButtonFont, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundColor(.black)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(model.actionError != nil ? Color.accentDanger : Color.accentLive))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(publishing)
    }

    private var publishedBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
            Text("PUBLISHED")
                .font(.system(size: cButtonFont, weight: .bold, design: .monospaced))
                .tracking(1)
        }
        .foregroundColor(.accentOk)
    }

    private var buttonLabel: String {
        if publishing { return "PUBLISHING" }
        if model.actionError != nil { return "RETRY" }
        return didPublish ? "RE-PUBLISH" : "PUBLISH"
    }

    private var title: String {
        if let error = model.actionError { return error }
        if didPublish { return "Shared “\(userSpec?.name ?? "engine")” to the community" }
        if let reason = ineligibleReason { return reason }
        return userSpec?.name ?? "No engine selected"
    }

    private var detail: String {
        if model.actionError != nil { return "Couldn’t publish — tap retry" }
        if didPublish { return "Live on the community board" }
        guard let spec = userSpec, canPublish else { return "Build your own engine to share it" }
        let stats = spec.capturedStats ?? .empty
        if stats.hasDyno { return "\(Int(stats.peakPowerHp)) hp · ready to share" }
        return "Share it now, or capture a dyno/0-60 first"
    }

    private var titleColor: Color {
        if model.actionError != nil { return .accentDanger }
        if didPublish { return .accentOk }
        return .white
    }

    private var bg: Color {
        if model.actionError != nil { return Color.accentDanger.opacity(0.10) }
        if didPublish { return Color.accentOk.opacity(0.10) }
        return Color.surfaceFaint
    }

    private var borderColor: Color {
        if model.actionError != nil { return Color.accentDanger.opacity(0.5) }
        if didPublish { return Color.accentOk.opacity(0.5) }
        return Color.strokeFaint
    }

    private func publish() {
        guard let spec = userSpec else { return }
        publishing = true
        didPublish = false
        Task {
            let ok = await model.publish(spec: spec)
            didPublish = ok
            publishing = false
        }
    }
}

// MARK: - Filters

private struct SortFilterBar: View {
    @ObservedObject var model: CommunityBrowserModel
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CommunitySort.allCases) { sort in
                    CommunityChip(label: sort.title.uppercased(),
                                  selected: model.sort == sort) { model.sort = sort }
                }
            }
            .padding(.horizontal, cChipRowInset).padding(.vertical, 1)
        }
    }
}

private struct ClassFilterBar: View {
    @ObservedObject var model: CommunityBrowserModel
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                CommunityChip(label: "ALL", selected: model.engineClass == nil) { model.engineClass = nil }
                ForEach(EngineClass.allCases) { cls in
                    CommunityChip(label: cls.shortLabel,
                                  selected: model.engineClass == cls) { model.engineClass = cls }
                }
            }
            .padding(.horizontal, cChipRowInset).padding(.vertical, 1)
        }
    }
}

private struct CommunityChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: cChipFont, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(selected ? .white : .textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(selected ? Color.accentLive.opacity(0.18) : Color.surfaceLow))
                .overlay(Capsule().stroke(selected ? Color.accentLive : Color.clear,
                                          lineWidth: Theme.Stroke.thin))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card

private struct CommunityCard: View {
    let engine: CommunityEngine
    let sort: CommunitySort
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.engineName)
                        .font(.system(size: cCardTitleFont, weight: .semibold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: cCardSubFont, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }
                BadgeRow(badges: Array(engine.badges.prefix(4)))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.panel).fill(Color.surfaceLow))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel)
                .stroke(Color.strokeFaint, lineWidth: Theme.Stroke.thin))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.panel))
        }
        .buttonStyle(.plain)
    }

    private var thumbnail: some View {
        EngineThumbnail(spec: engine.spec)
            .frame(height: cThumbHeight)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
            // Active-sort value, surfaced over the thumbnail so the list shows
            // what it's ranked by without opening each engine.
            .overlay(alignment: .topTrailing) { sortHighlight }
    }

    @ViewBuilder private var sortHighlight: some View {
        if let h = engine.sortHighlight(for: sort) {
            HStack(spacing: 3) {
                Text(h.value)
                    .font(.system(size: cBadgeValueFont, weight: .bold, design: .monospaced))
                Text(h.caption)
                    .font(.system(size: cBadgeCaptionFont, weight: .medium, design: .monospaced))
                    .opacity(0.8)
            }
            .foregroundColor(.black)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color.accentLive))
            .padding(6)
        }
    }

    /// Newest shows "by name · 3d ago"; ranked sorts show "by name".
    private var subtitle: String {
        if sort == .newest { return "by \(engine.ownerUsername) · \(engine.publishedRelative)" }
        return "by \(engine.ownerUsername)"
    }
}

private struct BadgeRow: View {
    let badges: [CommunityBadge]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(badges) { badge in BadgeChip(badge: badge) }
        }
    }
}

private struct BadgeChip: View {
    let badge: CommunityBadge
    var body: some View {
        VStack(spacing: 1) {
            Text(badge.value)
                .font(.system(size: cBadgeValueFont, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(badge.caption.uppercased())
                .font(.system(size: cBadgeCaptionFont, weight: .medium, design: .monospaced))
                .foregroundColor(.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Color.surfaceFaint))
    }
}

// MARK: - Thumbnail (cached still image, rendered once)

private struct EngineThumbnail: View {
    let spec: EngineSpec?
    @State private var image: PlatformImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.surfaceFaint
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if failed || spec == nil {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 30))
                    .foregroundColor(.textFaint)
            } else {
                DashLoader(diameter: 22)
            }
        }
        .task(id: spec?.id) { await loadImage() }
    }

    private func loadImage() async {
        guard let spec else { failed = true; return }
        let rendered = await EnginePreviewRenderer.shared.image(for: spec)
        if let rendered { image = rendered } else { failed = true }
    }
}

// MARK: - Load more

private struct LoadMoreButton: View {
    let isLoading: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading { DashLoader(diameter: 13, tint: .textSecondary) }
                Text(isLoading ? "LOADING" : "LOAD MORE")
                    .font(.system(size: cButtonFont, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(Color.surfaceLow))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Notice

private struct CommunityNotice: View {
    let symbol: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundColor(.textFaint)
            Text(text)
                .font(.system(size: cNoticeFont, design: .monospaced))
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Cross-platform Image init

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
