//
//  SettingsView.swift
//  engine-simulator
//
//  The app's settings surface. Presented like the community engine detail:
//    • macOS: a bounded card floating over a dimmed scrim (a popup).
//    • iOS: a full page that takes over the content area.
//  Both share the same scrolling sections. Player name lives in PlayerIdentity;
//  behavioural toggles live in AppSettings; purchases in PurchaseManager.
//

import SwiftUI

private let settingsCardWidth: CGFloat = 480
private let settingsCardHeight: CGFloat = 560

// Sizes. macOS gets comfortable, readable text (no sub-13pt body); iOS matches
// the community detail so it reads the same inside the scaled dashboard.
private let titleFont: CGFloat = 13
private let sectionFont: CGFloat = 12
private let rowTitleFont: CGFloat = 15
private let rowSubtitleFont: CGFloat = 12
private let buttonFont: CGFloat = 14

struct SettingsView: View {
    let onClose: () -> Void

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iosBody
        #endif
    }

    // MARK: - macOS: floating card over a scrim

    // The .sheet supplies the floating window + backdrop, so the card just
    // needs a fixed size. (A GeometryReader here collapses to zero height
    // inside a sheet, which is what left the popup showing only its header.)
    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(Color.strokeFaint)
            ScrollView { sections.padding(16) }
        }
        .frame(width: settingsCardWidth, height: settingsCardHeight)
        .background(Color.appBackground)
    }
    #endif

    // MARK: - iOS: full page

    #if !os(macOS)
    private var iosBody: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                headerBar
                Divider().background(Color.strokeFaint)
                ScrollView { sections.padding(16) }
            }
        }
    }
    #endif

    // MARK: - Header

    // Title centered on the page; the close button floats at the trailing edge
    // (a ZStack so the title's centering ignores the button's width).
    private var headerBar: some View {
        ZStack {
            Text("SETTINGS")
                .modifier(RetroFont(size: titleFont, weight: .bold))
                .foregroundColor(.accentLive)
                .tracking(2)
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.textMuted)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Sections

    private var sections: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSection(title: "PROFILE") {
                NameEditorRow()
            }

            SettingsSection(title: "SIMULATION") {
                DamageToggleRow()
            }

            #if os(iOS)
            SettingsSection(title: "FEEDBACK") {
                HapticsToggleRow()
            }
            #endif

            SettingsSection(title: "ACCOUNT") {
                PurchasesRow()
            }

            SettingsSection(title: "HELP") {
                ReplayTutorialRow(onClose: onClose)
            }

            #if DEBUG
            SettingsSection(title: "DEBUG") {
                DebugRows(onClose: onClose)
            }
            #endif
        }
    }
}

// MARK: - Section container

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: sectionFont, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(.textMuted)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.panel).fill(Color.surfaceFaint))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel)
                .stroke(Color.strokeFaint, lineWidth: Theme.Stroke.thin))
        }
    }
}

// MARK: - Toggle row primitive

private struct SettingsToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    // A dash-style switch (capsule track + knob), matching BuilderToggle —
    // not the stock system Toggle, which reads as foreign in the dashboard.
    private let trackWidth: CGFloat = 44
    private let trackHeight: CGFloat = 24
    private let knob: CGFloat = 18

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: rowTitleFont, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(subtitle)
                        .font(.system(size: rowSubtitleFont))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                dashSwitch
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }

    private var dashSwitch: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.accentLive.opacity(0.22) : Color.surfaceLow)
                .overlay(Capsule().stroke(isOn ? Color.accentLive.opacity(0.7) : Color.strokeStrong,
                                          lineWidth: Theme.Stroke.thin))
                .frame(width: trackWidth, height: trackHeight)
            Circle()
                .fill(isOn ? Color.accentLive : Color.textMuted)
                .frame(width: knob, height: knob)
                .padding(.horizontal, (trackHeight - knob) / 2)
        }
    }
}

// MARK: - Simulation: engine damage

private struct DamageToggleRow: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsToggle(
            title: "Engine damage",
            subtitle: "Money shifts, over revving and wear can break the engine. Turn this off to drive however you like and nothing breaks.",
            isOn: $settings.engineDamageEnabled
        )
    }
}

// MARK: - Feedback: haptics

#if os(iOS)
private struct HapticsToggleRow: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsToggle(
            title: "Haptics",
            subtitle: "Vibration for controls and the money-shift crash. No effect on devices without a Taptic Engine.",
            isOn: $settings.hapticsEnabled
        )
    }
}
#endif

// MARK: - Account / purchases

private struct PurchasesRow: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var restoring = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pro access")
                        .font(.system(size: rowTitleFont, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(purchaseManager.isPro ? "Unlocked. Every engine is yours."
                                               : "The free engine only. Unlock all engines with Pro.")
                        .font(.system(size: rowSubtitleFont))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(purchaseManager.isPro ? "ACTIVE" : "FREE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(purchaseManager.isPro ? .accentLive : .textMuted)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.surfaceLow))
                    .overlay(Capsule().stroke(purchaseManager.isPro ? Color.accentLive.opacity(0.5)
                                                                     : Color.strokeFaint,
                                              lineWidth: Theme.Stroke.thin))
            }

            if !purchaseManager.isPro {
                SettingsButton(label: "Restore Purchases", busy: restoring) {
                    restoring = true
                    Task { await purchaseManager.restorePurchases(); restoring = false }
                }
            }
        }
    }
}

// MARK: - Help: replay tutorial

private struct ReplayTutorialRow: View {
    let onClose: () -> Void
    @ObservedObject private var identity = PlayerIdentity.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Walk through the first-launch tutorial again.")
                .font(.system(size: rowSubtitleFont))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsButton(label: "Replay tutorial", icon: "arrow.counterclockwise") {
                identity.resetOnboarding()
                onClose()
            }
        }
    }
}

// MARK: - Debug

#if DEBUG
private struct DebugRows: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dev only. Gated to DEBUG builds.")
                .font(.system(size: rowSubtitleFont))
                .foregroundColor(.textSecondary)
            SettingsButton(label: "Forget purchase (show paywall)",
                           icon: "lock.open.trianglebadge.exclamationmark") {
                Task { await PurchaseManager.shared.resetPurchasesForDebug() }
                onClose()
            }
        }
    }
}
#endif

// MARK: - Button primitive

private struct SettingsButton: View {
    let label: String
    var icon: String? = nil
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    DashLoader(diameter: 13, tint: .accentLive)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: buttonFont, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundColor(.accentLive)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            // Quiet surface capsule (the app's secondary-button language —
            // Load More / Unpublish), not a tinted-border "blue bar".
            .background(Capsule().fill(Color.surfaceLow))
            .overlay(Capsule().stroke(Color.strokeFaint, lineWidth: Theme.Stroke.thin))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

// MARK: - Name editor

private struct NameEditorRow: View {
    @ObservedObject private var identity = PlayerIdentity.shared

    @State private var draft = ""
    @State private var isChecking = false
    @State private var errorText: String?
    @State private var savedFlash = false

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        !isChecking && !trimmed.isEmpty && trimmed != identity.username
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your name on the global leaderboard and shared engines.")
                .font(.system(size: rowSubtitleFont))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField("Username", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: rowTitleFont, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Color.surfaceLow)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .stroke(errorText == nil ? Color.strokeStrong : Color.accentDanger,
                                    lineWidth: Theme.Stroke.thin)))
                    .onSubmit(save)
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif

                Button(action: save) {
                    HStack(spacing: 5) {
                        if isChecking { DashLoader(diameter: 13, tint: .black) }
                        Text(savedFlash ? "SAVED" : "SAVE")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(canSave ? Color.accentLive : Color.accentLive.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: rowSubtitleFont))
                    .foregroundColor(.accentDanger)
            }
        }
        .onAppear { draft = identity.username }
        .onChange(of: draft) { _, _ in
            if errorText != nil { errorText = nil }
            if savedFlash { savedFlash = false }
        }
    }

    private func save() {
        let name = draft
        isChecking = true
        errorText = nil
        Task {
            let result = await UsernameValidator.validate(name)
            await MainActor.run {
                isChecking = false
                switch result {
                case .valid:
                    identity.setUsername(name)
                    draft = identity.username
                    savedFlash = true
                case .invalid(let reason):
                    errorText = reason
                }
            }
        }
    }
}
