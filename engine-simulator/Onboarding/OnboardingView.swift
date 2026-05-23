//
//  OnboardingView.swift
//  engine-simulator
//
//  First-launch flow: pick a leaderboard username, then a short tutorial. Every
//  page pairs a left text column with a framed live PREVIEW of the real thing
//  it describes — the actual dash controls, a real ignition-timing heatmap, an
//  OBD-II readout, the leaderboard with your name in it — so the visual
//  language matches the rest of the app instead of generic onboarding chrome.
//
//  Presented as a full-screen overlay from the app root while
//  `PlayerIdentity.hasCompletedOnboarding` is false.
//

import SwiftUI

// MARK: - Layout constants

let onboardingContentMaxWidth: CGFloat = 860
private let textColumnWidth: CGFloat = 312
private let columnSpacing: CGFloat = 36
private let pagePadding: CGFloat = 40
private let titleSize: CGFloat = 23
private let subtitleSize: CGFloat = 13
private let progressDotSize: CGFloat = 7
// Leaderboard preview rows are content, not dash chrome, so they read larger
// than the 7–12pt instrument labels. Touch (iOS) gets a touch more than the
// pointer-driven Mac.
#if os(macOS)
let onboardingLeaderboardFontSize: CGFloat = 15
#else
let onboardingLeaderboardFontSize: CGFloat = 18
#endif
private let ctaCorner = Theme.Radius.control
private let ctaHPadding: CGFloat = 30
private let ctaVPadding: CGFloat = 13
private let usernameFieldSize: CGFloat = 17

// Caps the preview column so a page never stretches into a tall empty
// rectangle (the previews are short; without a ceiling the framed RetroPanel
// grows to fill all the vertical space the page is offered).
private let onboardingPreviewMaxHeight: CGFloat = 300

// The whole tutorial is laid out once at this reference size and then scaled to
// fit whatever window or device it runs on (see OnboardingView.body). This way
// the proportions are identical on a Mac window and an iPhone in landscape
// without hardcoding per-screen numbers — the content just shrinks to fit.
private let onboardingCanvasWidth = onboardingContentMaxWidth + pagePadding * 2
private let onboardingCanvasHeight: CGFloat = 620
// Never enlarge past the reference size; only shrink to fit smaller screens.
private let onboardingMaxScale: CGFloat = 1.0

// MARK: - Steps

enum OnboardingStep: Int, CaseIterable {
    case username, startEngine, buildTune, ready

    var isFirst: Bool { self == .username }
    var isLast: Bool { self == .ready }
    var next: OnboardingStep { OnboardingStep(rawValue: rawValue + 1) ?? .ready }
    var previous: OnboardingStep { OnboardingStep(rawValue: rawValue - 1) ?? .username }
}

// MARK: - Container

struct OnboardingView: View {
    @ObservedObject var identity: PlayerIdentity

    @State private var step: OnboardingStep = .username
    @State private var draftUsername = ""
    @State private var isChecking = false
    @State private var usernameError: String?
    // Drives the page slide direction. Forward pages enter from the right and
    // leave to the left; going back reverses both so the motion matches the
    // BACK button rather than always sliding forward.
    @State private var goingBack = false

    var body: some View {
        GeometryReader { geo in
            // Aspect-fit the reference canvas into the available space so the
            // tutorial never clips, on any screen size or platform.
            let scale = min(geo.size.width / onboardingCanvasWidth,
                            geo.size.height / onboardingCanvasHeight,
                            onboardingMaxScale)
            ZStack {
                Color.appBackground.ignoresSafeArea()

                pageCanvas
                    .frame(width: onboardingCanvasWidth, height: onboardingCanvasHeight)
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
    }

    private var pageCanvas: some View {
        VStack(spacing: 0) {
            wordmarkHeader

            Spacer(minLength: pagePadding)

            pageContent
                .frame(maxWidth: onboardingContentMaxWidth)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: goingBack ? .leading : .trailing)
                        .combined(with: .opacity),
                    removal: .move(edge: goingBack ? .trailing : .leading)
                        .combined(with: .opacity)))

            Spacer(minLength: pagePadding)

            footer
                .frame(maxWidth: onboardingContentMaxWidth)
        }
        .padding(pagePadding)
    }

    // MARK: Header

    private var wordmarkHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "engine.combustion.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.accentHeat)
                Text("ENGINE SIM")
                    .modifier(RetroFont(size: Theme.FontSize.headline))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.92))
                Spacer()
                progressDots
            }
            .frame(maxWidth: onboardingContentMaxWidth)
            .padding(.bottom, Theme.Space.xl)

            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                .frame(maxWidth: onboardingContentMaxWidth)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s == step ? Color.accentLive : Color.strokeStrong)
                    .frame(width: s == step ? progressDotSize * 2.6 : progressDotSize,
                           height: progressDotSize)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }

    // MARK: Pages

    @ViewBuilder
    private var pageContent: some View {
        switch step {
        case .username:
            OnboardingUsernamePage(username: $draftUsername,
                                   errorText: usernameError,
                                   onSubmit: advance)
        case .startEngine:
            StartEngineDemo()
        case .buildTune:
            BuildTunePage()
        case .ready:
            ReadyPage(username: resolvedUsername)
        }
    }

    private var resolvedUsername: String {
        identity.username.isEmpty ? draftUsername : identity.username
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if !step.isFirst {
                Button(action: { goingBack = true; withAnimation { step = step.previous } }) {
                    Text("BACK")
                        .modifier(RetroFont(size: Theme.FontSize.control))
                        .tracking(1)
                        .foregroundColor(.textMuted)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            continueButton
        }
    }

    private var continueButton: some View {
        Button(action: advance) {
            HStack(spacing: 8) {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(continueLabel)
                    .modifier(RetroFont(size: Theme.FontSize.control))
                    .tracking(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, ctaHPadding)
            .padding(.vertical, ctaVPadding)
            .background(
                RoundedRectangle(cornerRadius: ctaCorner)
                    .fill(continueEnabled ? Color.accentLive : Color.accentLive.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .disabled(!continueEnabled)
    }

    private var continueLabel: String {
        if step == .username && isChecking { return "CHECKING…" }
        return step.isLast ? "START DRIVING" : "CONTINUE"
    }

    private var continueEnabled: Bool {
        if isChecking { return false }
        if step == .username {
            return !draftUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    // MARK: Navigation

    private func advance() {
        goingBack = false
        switch step {
        case .username: validateUsername()
        case .ready:    identity.completeOnboarding()
        default:        withAnimation { step = step.next }
        }
    }

    private func validateUsername() {
        let name = draftUsername
        isChecking = true
        usernameError = nil
        Task {
            let result = await UsernameValidator.validate(name)
            await MainActor.run {
                isChecking = false
                switch result {
                case .valid:
                    identity.setUsername(name)
                    withAnimation { step = .startEngine }
                case .invalid(let reason):
                    usernameError = reason
                }
            }
        }
    }
}

// MARK: - Username page

struct OnboardingUsernamePage: View {
    @Binding var username: String
    let errorText: String?
    let onSubmit: () -> Void

    @FocusState private var fieldFocused: Bool

    private var trimmed: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        OnboardingTwoColumn(
            text: {
                VStack(alignment: .leading, spacing: Theme.Space.section) {
                    OnboardingStepHeader(
                        index: 1,
                        title: "Claim your name",
                        subtitle: "This is how you show up on the global leaderboard. You can rename it later from the sidebar.")
                    usernameField
                }
            },
            preview: {
                OnboardingPreviewPanel(title: "GLOBAL LEADERBOARD") {
                    MiniLeaderboard(youName: trimmed)
                }
            })
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            ZStack(alignment: .leading) {
                // SwiftUI's built-in placeholder is nearly invisible on the dark
                // field, so draw our own in a legible muted tone instead.
                if username.isEmpty {
                    Text("Username")
                        .font(.system(size: usernameFieldSize, weight: .bold, design: .monospaced))
                        .foregroundColor(.textMuted)
                }
                TextField("", text: $username)
                    .textFieldStyle(.plain)
                    .font(.system(size: usernameFieldSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .focused($fieldFocused)
                    .onSubmit(handleReturn)
                    #if os(iOS)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
            }
            .padding(.horizontal, Theme.Space.xxl)
            .padding(.vertical, Theme.Space.xl)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.panel)
                    .fill(Color.surfaceLow)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel)
                        .stroke(errorText == nil ? Color.strokeStrong : Color.accentDanger,
                                lineWidth: Theme.Stroke.thin)))

            Text(errorText ?? "\(UsernameRules.minLength) to \(UsernameRules.maxLength) characters · letters, numbers, _ or -")
                .font(.system(size: Theme.FontSize.callout))
                .foregroundColor(errorText == nil ? .textMuted : .accentDanger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// On macOS, Return advances to the next page. On iOS the keyboard's Done
    /// key should only dismiss the keyboard so the player can review the field
    /// and tap CONTINUE deliberately.
    private func handleReturn() {
        #if os(macOS)
        onSubmit()
        #else
        fieldFocused = false
        #endif
    }
}

// MARK: - Shared scaffold

/// The standard onboarding page shape: a fixed-width text column on the left,
/// a flexible preview panel on the right, vertically centred.
struct OnboardingTwoColumn<TextContent: View, Preview: View>: View {
    @ViewBuilder let text: () -> TextContent
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        HStack(alignment: .center, spacing: columnSpacing) {
            text()
                .frame(width: textColumnWidth, alignment: .leading)
            preview()
                .frame(maxWidth: .infinity)
        }
    }
}

struct OnboardingStepHeader: View {
    let index: Int
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("STEP \(index) / \(OnboardingStep.allCases.count)")
                .modifier(RetroFont(size: Theme.FontSize.footnote))
                .tracking(2)
                .foregroundColor(.accentLive)
            Text(title)
                .modifier(RetroFont(size: titleSize))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: subtitleSize))
                .foregroundColor(.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A RetroPanel sized to fill the preview column, with its content vertically
/// centred so short previews don't crowd the title bar.
struct OnboardingPreviewPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        RetroPanel(title) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                content()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: onboardingPreviewMaxHeight)
    }
}

// MARK: - Leaderboard preview

private struct LeaderboardPreviewEntry: Identifiable {
    let id = UUID()
    let rank: Int
    let name: String
    let hp: Int
    let isYou: Bool
}

/// A three-row leaderboard miniature with the player's row highlighted and its
/// name bound live to whatever they're typing.
struct MiniLeaderboard: View {
    let youName: String

    private var rows: [LeaderboardPreviewEntry] {
        let you = youName.isEmpty ? "YOUR NAME" : youName.uppercased()
        return [
            .init(rank: 1, name: "APEXHUNTER", hp: 812, isYou: false),
            .init(rank: 2, name: you,         hp: 640, isYou: true),
            .init(rank: 3, name: "REVCOUNTER", hp: 598, isYou: false)
        ]
    }

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            ForEach(rows) { row in
                MiniLeaderboardRow(entry: row)
            }
        }
    }
}

private struct MiniLeaderboardRow: View {
    let entry: LeaderboardPreviewEntry

    var body: some View {
        HStack(spacing: Theme.Space.xl) {
            Text(String(format: "%02d", entry.rank))
                .modifier(RetroFont(size: onboardingLeaderboardFontSize))
                .foregroundColor(entry.isYou ? .accentLive : .textFaint)
            Text(entry.name)
                .modifier(RetroFont(size: onboardingLeaderboardFontSize))
                .foregroundColor(entry.isYou ? .textPrimary : .textSecondary)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.md)
            Text("\(entry.hp) HP")
                .modifier(RetroFont(size: onboardingLeaderboardFontSize))
                .foregroundColor(entry.isYou ? .accentLive : .textMuted)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small)
                .fill(entry.isYou ? Color.accentLive.opacity(0.12) : Color.surfaceLow))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.small)
                .stroke(entry.isYou ? Color.accentLive.opacity(0.55) : Color.clear,
                        lineWidth: Theme.Stroke.thin))
    }
}
