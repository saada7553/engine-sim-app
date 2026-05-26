//
//  OnboardingTutorialPages.swift
//  engine-simulator
//
//  Tutorial screens. Each renders the REAL thing it talks about: the start page
//  embeds the actual ignition switch / starter / clutch controls (interactive,
//  driven by local demo state so they never touch the live engine); the build
//  page shows a real ignition-timing heatmap and OBD-II readout miniature; the
//  closing page drops the player into the leaderboard preview by name.
//

import SwiftUI
import Combine

// MARK: - Layout constants

private let controlRowSpacing: CGFloat = 30
private let tutorialRowSpacing: CGFloat = 14
private let bodyTextSize: CGFloat = 13
private let previewStackSpacing = Theme.Space.lg

// iOS throttle demo width — keeps the reused top-bar slider from filling the
// whole preview panel.
private let throttleDemoWidth: CGFloat = 220

// ECU heatmap miniature — mirrors EcuTuningView.heatColor's blue→green→red ramp.
private let ecuCols = 8
private let ecuRows = 4
private let ecuCellSpacing: CGFloat = 3
private let ecuCellCorner: CGFloat = 2
private let ecuMapHeight: CGFloat = 92
private let ecuHeatBlueHue = 0.62
private let ecuHeatSaturation = 0.62
private let ecuHeatBrightness = 0.58

// macOS key legend chip
private let keyChipMinWidth: CGFloat = 30
private let keyLegendItemWidth: CGFloat = 132
private let keyLegendColumnSpacing: CGFloat = 14
private let keyLegendRowSpacing: CGFloat = 8

// MARK: - Onboarding demo state
//
// A throwaway stand-in for the engine while the first-launch tutorial is up.
// Both the on-screen demo controls and the macOS keyboard drive THIS object, so
// the ignition / starter / clutch respond on screen without ever touching the
// real EngineViewModel. Nothing here feeds the simulation.

final class OnboardingEngineDemo: ObservableObject {
    static let shared = OnboardingEngineDemo()

    @Published var ignitionOn = false
    @Published var cranking = false
    @Published var clutchEngaged = false

    // Everything is a plain toggle in the tutorial — press (or the key) flips it
    // on/off, in any order. Nothing here is gated or auto-resets.
    func toggleIgnition() { ignitionOn.toggle() }
    func toggleStarter() { cranking.toggle() }
    func toggleClutch() { clutchEngaged.toggle() }

    /// Wipe state so replaying the tutorial always starts cold.
    func reset() {
        ignitionOn = false
        cranking = false
        clutchEngaged = false
    }
}

// MARK: - Step 2: Start an engine

struct StartEngineDemo: View {
    @ObservedObject private var demo = OnboardingEngineDemo.shared
    #if os(iOS)
    @State private var throttle = 0.0
    #endif

    private let clutchStepText = "Tap the clutch to disengage, tap again to drive"

    var body: some View {
        OnboardingTwoColumn(
            text: { textColumn },
            preview: {
                OnboardingPreviewPanel(title: "START SEQUENCE") {
                    previewBody.padding(.vertical, Theme.Space.xl)
                }
            })
        .onAppear { demo.reset() }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Space.section) {
            OnboardingStepHeader(
                index: 2,
                title: "Bring it to life",
                subtitle: "Every engine starts the same way. These are the real switches from the dash, so go ahead and play with them.")

            VStack(alignment: .leading, spacing: tutorialRowSpacing) {
                OnboardingListRow(text: "Flip the ignition switch to RUN")
                OnboardingListRow(text: "Press the starter to crank it over")
                OnboardingListRow(text: clutchStepText)
            }

            #if os(iOS)
            OnboardingNote(text: "If it won't catch, feed in a little throttle and crank again.")
            #else
            MacKeyLegend()
            #endif
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        #if os(iOS)
        VStack(spacing: previewStackSpacing) {
            controlRow
            TopBarThrottleSlider(value: $throttle)
                .frame(width: throttleDemoWidth)
        }
        #else
        controlRow
        #endif
    }

    private var controlRow: some View {
        HStack(alignment: .top, spacing: controlRowSpacing) {
            ArmedIgnitionSwitch(isOn: demo.ignitionOn) { demo.toggleIgnition() }
            StarterButton(running: demo.cranking, action: demo.toggleStarter)
            // The same tappable clutch tile the dash uses, on both platforms.
            DashImageWarningTile(label: "CLUTCH",
                                 active: demo.clutchEngaged,
                                 accent: .accentClutch,
                                 imageName: "clutch",
                                 onTap: demo.toggleClutch)
        }
    }
}

// MARK: - Step 3: Build & tune

struct BuildTunePage: View {
    var body: some View {
        OnboardingTwoColumn(
            text: {
                VStack(alignment: .leading, spacing: Theme.Space.section) {
                    OnboardingStepHeader(
                        index: 3,
                        title: "Build it. Tune it.",
                        subtitle: "Design your own engine, or describe one and let the AI draft it for you. A fresh build rarely runs clean on the first crank, and sorting that out is the fun part.")

                    VStack(alignment: .leading, spacing: tutorialRowSpacing) {
                        OnboardingListRow(text: "Reshape the ignition and fuel maps in ECU Tuning until it idles smooth and pulls hard.")
                        OnboardingListRow(text: "Trouble codes in the OBD-II readout tell you what your tune is fighting.")
                    }
                }
            },
            preview: {
                OnboardingPreviewPanel(title: "TUNE & DIAGNOSE") {
                    VStack(spacing: previewStackSpacing) {
                        MiniMapPreview()
                        MiniObdPreview()
                    }
                }
            })
    }
}

// MARK: - Step 4: Ready

struct ReadyPage: View {
    let username: String

    private var greeting: String {
        username.isEmpty ? "You're on the board" : "Welcome aboard, \(username)"
    }

    var body: some View {
        OnboardingTwoColumn(
            text: {
                VStack(alignment: .leading, spacing: Theme.Space.section) {
                    OnboardingStepHeader(
                        index: 4,
                        title: greeting,
                        subtitle: "Fire up a built-in engine to get a feel for it, then make one your own. Clean, powerful builds climb the ranks.")

                    VStack(alignment: .leading, spacing: tutorialRowSpacing) {
                        OnboardingListRow(text: "Pick an engine from the sidebar")
                        OnboardingListRow(text: "Hit the starter and drive")
                        OnboardingListRow(text: "Build a new engine when you're ready")
                    }
                }
            },
            preview: {
                OnboardingPreviewPanel(title: "GLOBAL LEADERBOARD") {
                    MiniLeaderboard(youName: username)
                }
            })
    }
}

// MARK: - Shared tutorial list rows
//
// Every page lists its points the same way: a plain text line, no bullet glyph
// or icon, so the prose stays clean and consistent across the flow.

/// A plain, unmarked list line. Wraps freely so long lines never truncate.
struct OnboardingListRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: bodyTextSize))
            .foregroundColor(.textSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A quieter aside (tips, hints) — same family as the list rows but dimmer.
struct OnboardingNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: Theme.FontSize.callout))
            .foregroundColor(.textMuted)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - macOS keyboard legend
//
// macOS players can drive entirely from the keyboard, so the start page spells
// out the bindings and notes that the on-screen dash controls do the same job.
// Chip styling matches ControlsMenuView so the keys read identically wherever
// they appear.

#if os(macOS)
/// Two-column key reference. Rows are laid out explicitly (no ForEach) so they
/// slide in as one piece with the page transition — a ForEach gives its rows
/// their own insertion transition, which made the hints pop in after the rest
/// of the card had already moved.
private struct MacKeyLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("KEYBOARD")
                .modifier(RetroFont(size: Theme.FontSize.footnote))
                .tracking(2)
                .foregroundColor(.accentLive)

            VStack(alignment: .leading, spacing: keyLegendRowSpacing) {
                legendRow(("A", "Ignition"), ("S", "Starter"))
                legendRow(("⇧", "Clutch"), ("Space", "Throttle"))
                legendRow(("↑ ↓", "Shift gears"), ("D", "Dyno"))
                legendRow(("H", "Throttle hold"), ("B", "Brake"))
            }

            OnboardingNote(text: "Every key has a switch on the dash too, so you can point and click instead.")
        }
    }

    private func legendRow(_ left: (String, String), _ right: (String, String)?) -> some View {
        HStack(spacing: keyLegendColumnSpacing) {
            keyCell(left)
            if let right { keyCell(right) }
        }
    }

    private func keyCell(_ binding: (key: String, action: String)) -> some View {
        HStack(spacing: Theme.Space.md) {
            Text(binding.key)
                .font(.system(size: Theme.FontSize.footnote, weight: .semibold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .frame(minWidth: keyChipMinWidth)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, Theme.Space.xs)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .fill(Color.sidebarHighlight))
            Text(binding.action)
                .font(.system(size: Theme.FontSize.callout))
                .foregroundColor(.textSecondary)
                .lineLimit(1)
        }
        .frame(width: keyLegendItemWidth, alignment: .leading)
    }
}
#endif

// MARK: - ECU map miniature

/// A static ignition-timing heatmap that reads like the real EcuTuningView grid:
/// cold blue at low rpm / light load, reddening as advance climbs with rpm and
/// load. Same hue ramp as `EcuTuningView.heatColor`.
private struct MiniMapPreview: View {
    var body: some View {
        VStack(spacing: ecuCellSpacing) {
            ForEach(0..<ecuRows, id: \.self) { row in
                HStack(spacing: ecuCellSpacing) {
                    ForEach(0..<ecuCols, id: \.self) { col in
                        RoundedRectangle(cornerRadius: ecuCellCorner)
                            .fill(cellColor(row: row, col: col))
                    }
                }
            }
        }
        .frame(height: ecuMapHeight)
    }

    private func cellColor(row: Int, col: Int) -> Color {
        let rpmFrac = Double(col) / Double(ecuCols - 1)
        let loadFrac = Double(ecuRows - 1 - row) / Double(ecuRows - 1)
        let norm = min(1.0, 0.12 + 0.62 * rpmFrac + 0.26 * loadFrac)
        let hue = ecuHeatBlueHue - norm * ecuHeatBlueHue
        return Color(hue: hue, saturation: ecuHeatSaturation, brightness: ecuHeatBrightness)
    }
}

// MARK: - OBD-II miniature

private struct MiniObdPreview: View {
    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            MiniObdRow(code: "P0171", description: "System Too Lean", critical: false)
            MiniObdRow(code: "P0301", description: "Cyl 1 Misfire", critical: true)
        }
    }
}

/// Matches OBD2View.CodeRow: monospaced code + uppercased fault, amber for a
/// warning and red for a critical, with the same !/!! severity glyph.
private struct MiniObdRow: View {
    let code: String
    let description: String
    let critical: Bool

    private var color: Color { critical ? .accentDanger : .accentWarn }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.lg) {
            Text(code)
                .font(.system(size: Theme.FontSize.control, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(description.uppercased())
                .font(.system(size: Theme.FontSize.footnote, design: .monospaced))
                .foregroundColor(color.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: Theme.Space.sm)
            Text(critical ? "!!" : "!")
                .font(.system(size: Theme.FontSize.control, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small)
                .fill(color.opacity(0.08)))
    }
}
