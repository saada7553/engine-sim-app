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

// On iOS the slider's 0-distance drag gesture competes with the ScrollView for
// vertical swipes that land on it. Confining the slider controls to the left
// 2/3 of the row leaves the right 1/3 as a gesture-free strip the user can
// reliably grab to scroll. macOS has a cursor + scrollbar, so it uses the full
// width.
private let iosSliderWidthFraction: CGFloat = 2.0 / 3.0
// Fixed height for the slider controls row, needed because the GeometryReader
// that measures the 2/3 width doesn't size to its content. Covers the AUTO
// pill, which is the tallest element in the row.
private let sliderRowHeight: CGFloat = 34

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
                    .scrollIndicators(.hidden)
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

            SettingsSection(title: "PERFORMANCE") {
                FrameRateRow()
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

            SettingsSection(title: "LEGAL") {
                LegalLinksRow()
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

// MARK: - Performance: UI frame rate

/// The single UI-clock knob. The slider / Auto pill rewrite AppSettings, which
/// EngineViewModel observes and applies live — the poll timer and every 2D
/// gauge/tool immediately move to the new rate, so it's easy to compare. Capped
/// at 30 (the physics frame rate); a battery caution shows at the high end.
private struct FrameRateRow: View {
    @ObservedObject private var settings = AppSettings.shared

    private var rateBinding: Binding<Double> {
        Binding(get: { settings.uiFrameRate },
                set: { settings.selectFrameRate($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("UI frame rate")
                        .font(.system(size: rowTitleFont, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("How often the gauges and 2D readouts redraw. Lower saves battery; higher is smoother. The 3D engine view is unaffected.")
                        .font(.system(size: rowSubtitleFont))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("\(Int(settings.uiFrameRate.rounded())) Hz")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentLive)
                    .monospacedDigit()
            }

            sliderControlsRow

            warningLine
        }
        .animation(.easeInOut(duration: 0.15), value: settings.uiFrameRate)
        .animation(.easeInOut(duration: 0.15), value: settings.autoFrameRate)
    }

    // Slider + AUTO pill. On iOS the interactive controls are pinned to the
    // left 2/3 so the right 1/3 stays free for scrolling (see
    // iosSliderWidthFraction); macOS uses the full width.
    private var sliderControlsRow: some View {
        let controls = HStack(spacing: 12) {
            DashSlider(value: rateBinding,
                       range: AppSettings.minUIFrameRate...AppSettings.maxUIFrameRate)
            autoPill
        }
        #if os(iOS)
        return GeometryReader { geo in
            controls.frame(width: geo.size.width * iosSliderWidthFraction,
                           alignment: .leading)
        }
        .frame(height: sliderRowHeight)
        #else
        return controls
        #endif
    }

    // Pill that hands rate selection back to the device heuristic.
    private var autoPill: some View {
        let on = settings.autoFrameRate
        return Button(action: { settings.enableAutoFrameRate() }) {
            Text("AUTO")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(on ? .black : .textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(on ? Color.accentLive : Color.surfaceLow))
                .overlay(Capsule().stroke(on ? Color.accentLive : Color.strokeFaint,
                                          lineWidth: Theme.Stroke.thin))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // Battery caution. Low Power Mode takes priority (and notes the auto
    // downgrade). The high-rate caution only fires when the user has manually
    // pushed the rate up — in Auto, the device was judged able to handle the
    // chosen rate, so warning there would just be noise.
    @ViewBuilder private var warningLine: some View {
        if settings.lowPowerModeEnabled {
            cautionRow(icon: "battery.25",
                       text: settings.autoFrameRate
                           ? "Low Power Mode is on — rate lowered automatically."
                           : "Low Power Mode is on — a lower rate will save battery.")
        } else if settings.usesHighBatteryRate && !settings.autoFrameRate {
            cautionRow(icon: "bolt.fill",
                       text: "Higher rates use more battery. Lower it to extend runtime.")
        }
    }

    private func cautionRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: rowSubtitleFont))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.accentWarn)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.control)
            .fill(Color.accentWarn.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control)
            .stroke(Color.accentWarn.opacity(0.4), lineWidth: Theme.Stroke.thin))
    }
}

// MARK: - Dash slider primitive

/// A themed horizontal slider (capsule track + accent fill + knob) that snaps to
/// whole steps. Built to match the dashboard rather than use the stock system
/// Slider, which reads as foreign here.
private struct DashSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    private let trackHeight: CGFloat = 6
    private let knob: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let frac = min(max((value - range.lowerBound) / span, 0), 1)
            let travel = max(geo.size.width - knob, 0)
            let knobX = CGFloat(frac) * travel

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.surfaceLow)
                    .overlay(Capsule().stroke(Color.strokeFaint, lineWidth: Theme.Stroke.thin))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(Color.accentLive)
                    .frame(width: knobX + knob / 2, height: trackHeight)
                Circle()
                    .fill(Color.accentLive)
                    .overlay(Circle().stroke(Color.appBackground, lineWidth: 2))
                    .frame(width: knob, height: knob)
                    .offset(x: knobX)
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = travel > 0 ? min(max((g.location.x - knob / 2) / travel, 0), 1) : 0
                        let raw = range.lowerBound + Double(f) * span
                        let snapped = (raw / step).rounded() * step
                        value = min(max(snapped, range.lowerBound), range.upperBound)
                    }
            )
        }
        .frame(height: knob)
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

// MARK: - Legal links

private struct LegalLinksRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            link("Privacy Policy", LegalLinks.privacyPolicy)
            link("Community Guidelines", LegalLinks.communityGuidelines)
            link("Terms of Use", LegalLinks.termsOfUse)
        }
    }

    private func link(_ title: String, _ url: URL) -> some View {
        Button { openURL(url) } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: rowTitleFont, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

            CommunityAgreementNote(fontSize: rowSubtitleFont)
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
