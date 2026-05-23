//
//  CommunityDetailSheet.swift
//  engine-simulator
//
//  Detail view for a single community engine. Like the paywall, the layout
//  differs by platform:
//    • macOS: a bounded card floating over a dimmed scrim, sized to its content
//      (capped at the tile height) so a short engine doesn't leave a tall empty
//      card and a long one scrolls.
//    • iOS: a full-page view (the community tile is the whole screen there), so
//      there's room for the live 3D preview, the description, badges, the full
//      spec sheet and the read-only tune without anything clipping.
//
//  Both share the same scrolling content and actions (download / unpublish).
//

import SwiftUI

private let detailScrim = Color.black.opacity(0.72)
private let detailCardMaxWidth: CGFloat = 460
private let detailPreviewHeight: CGFloat = 220
private let detailBadgeMinWidth: CGFloat = 88

/// Measures the natural height of the macOS card's content so it can hug it.
private struct DetailContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct CommunityDetailOverlay: View {
    let engine: CommunityEngine
    @ObservedObject var model: CommunityBrowserModel
    let onClose: () -> Void

    @State private var downloading = false
    @State private var downloaded = false
    @State private var unpublishing = false
    // Seeded non-zero so the macOS card always renders its content on the first
    // pass (a 0 seed collapsed the scroll view to nothing); it settles to the
    // measured height after layout.
    @State private var contentHeight: CGFloat = 600

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iosBody
        #endif
    }

    // MARK: - macOS: floating card over a scrim

    #if os(macOS)
    private var macOSBody: some View {
        GeometryReader { geo in
            ZStack {
                detailScrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)

                VStack(spacing: 0) {
                    headerBar
                    ScrollView {
                        scrollContent
                            .padding(16)
                            .background(GeometryReader { g in
                                Color.clear.preference(key: DetailContentHeightKey.self,
                                                       value: g.size.height)
                            })
                    }
                    .frame(height: min(contentHeight, max(220, geo.size.height - 120)))
                    // Ignore the PreferenceKey's transient 0 default — accepting
                    // it collapsed the scroll view to nothing (only the header
                    // showed). Only a real, positive measurement updates the
                    // height, so the non-zero seed always renders content.
                    .onPreferenceChange(DetailContentHeightKey.self) { measured in
                        if measured > 0 { contentHeight = measured }
                    }
                }
                .frame(maxWidth: detailCardMaxWidth)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.window).fill(Color.appBackground))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.window)
                    .stroke(Color.strokeSubtle, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.55), radius: 24, y: 10)
                .padding(16)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onDisappear { model.clearActionError() }
    }
    #endif

    // MARK: - iOS: full page (the community tile is the whole screen)

    #if !os(macOS)
    private var iosBody: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                headerBar
                ScrollView {
                    scrollContent.padding(16)
                }
            }
        }
        .onDisappear { model.clearActionError() }
    }
    #endif

    // MARK: - Shared content

    private var headerBar: some View {
        HStack {
            Text("ENGINE")
                .modifier(RetroFont(size: 13, weight: .bold))
                .foregroundColor(.accentLive)
                .tracking(2)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.textMuted)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview
            heading
            if let blurb = engine.engineDescription { description(blurb) }
            badges
            if let spec = engine.spec {
                SectionDivider(title: "TUNE")
                EngineTunePreview(spec: spec)
                SectionDivider(title: "SPECS")
                EngineSpecList(spec: spec)
            }
            if let error = model.actionError { errorRow(error) }
            actions
        }
    }

    @ViewBuilder private var preview: some View {
        if let spec = engine.spec {
            EnginePreview3DView(spec: spec)
                .frame(height: detailPreviewHeight)
                .frame(maxWidth: .infinity)
                .background(Color.surfaceLow)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel)
                    .stroke(Color.strokeFaint, lineWidth: Theme.Stroke.thin))
        } else {
            unreadablePreview
        }
    }

    private var unreadablePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.panel).fill(Color.surfaceLow)
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26)).foregroundColor(.textFaint)
                Text("This engine couldn't be read.")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.textMuted)
            }
        }
        .frame(height: detailPreviewHeight)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(engine.engineName)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(engine.engineClass.displayName) · by \(engine.ownerUsername) · \(engine.publishedRelative)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func description(_ blurb: String) -> some View {
        Text(blurb)
            .font(.system(size: 14, design: .monospaced))
            .foregroundColor(.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Color.surfaceFaint))
    }

    private var badges: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: detailBadgeMinWidth), spacing: 8)], spacing: 8) {
            ForEach(engine.badges) { badge in DetailBadge(badge: badge) }
        }
    }

    private func errorRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(.accentDanger)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            downloadButton
            if model.isMine(engine) { unpublishButton }
        }
        .padding(.top, 4)
    }

    private var downloadButton: some View {
        Button(action: download) {
            HStack(spacing: 6) {
                if downloading { ProgressView().controlSize(.small) }
                Image(systemName: downloaded ? "checkmark.circle.fill" : "square.and.arrow.down")
                Text(downloaded ? "ADDED TO GARAGE" : "DOWNLOAD")
                    .font(.system(size: 14, weight: .bold, design: .monospaced)).tracking(1)
            }
            .foregroundColor(downloaded ? .accentOk : .black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(downloaded ? Color.surfaceLow : Color.accentLive))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(downloading || downloaded || engine.spec == nil)
    }

    private var unpublishButton: some View {
        Button(action: unpublish) {
            HStack(spacing: 6) {
                if unpublishing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "trash").font(.system(size: 12, weight: .semibold))
                }
                Text(unpublishing ? "REMOVING" : "UNPUBLISH")
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(1)
            }
            .foregroundColor(.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color.surfaceLow))
            .overlay(Capsule().stroke(Color.strokeStrong, lineWidth: Theme.Stroke.thin))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(unpublishing)
    }

    // MARK: - Actions

    private func dismiss() { onClose() }

    private func download() {
        downloading = true
        let ok = model.download(engine)
        downloading = false
        if ok { downloaded = true }
    }

    private func unpublish() {
        unpublishing = true
        Task {
            let ok = await model.unpublish(engine)
            unpublishing = false
            if ok { onClose() }
        }
    }
}

// MARK: - Section divider

private struct SectionDivider: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.textMuted)
            Rectangle().fill(Color.strokeFaint).frame(height: 1)
        }
        .padding(.top, 2)
    }
}

// MARK: - Detail badge

private struct DetailBadge: View {
    let badge: CommunityBadge
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: badge.icon)
                .font(.system(size: 13))
                .foregroundColor(.accentLive.opacity(0.85))
            Text(badge.value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(badge.caption.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Color.surfaceFaint))
    }
}
