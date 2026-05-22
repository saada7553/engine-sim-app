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

// MARK: - Layout constants

private let controlRowSpacing: CGFloat = 30
private let checkRowSpacing: CGFloat = 16
private let stepNumberSize: CGFloat = 22
private let bodyTextSize: CGFloat = 13
private let keyCapSize = CGSize(width: 60, height: 46)
private let previewStackSpacing = Theme.Space.lg

// ECU heatmap miniature — mirrors EcuTuningView.heatColor's blue→green→red ramp.
private let ecuCols = 8
private let ecuRows = 4
private let ecuCellSpacing: CGFloat = 3
private let ecuCellCorner: CGFloat = 2
private let ecuMapHeight: CGFloat = 92
private let ecuHeatBlueHue = 0.62
private let ecuHeatSaturation = 0.62
private let ecuHeatBrightness = 0.58

// MARK: - Step 2: Start an engine

struct StartEngineDemo: View {
    @State private var ignitionOn = false
    @State private var cranking = false
    @State private var clutchWorked = false

    private var clutchStepText: String {
        #if os(macOS)
        return "Tap and release the Shift key to let the clutch out"
        #else
        return "Tap the CLUTCH pedal to disengage, release to drive"
        #endif
    }

    var body: some View {
        OnboardingTwoColumn(
            text: {
                VStack(alignment: .leading, spacing: Theme.Space.section) {
                    OnboardingStepHeader(
                        index: 2,
                        title: "Bring it to life",
                        subtitle: "Every engine starts the same way. Try the real controls, they're the exact switches on the dash.")

                    VStack(alignment: .leading, spacing: checkRowSpacing) {
                        TutorialStepRow(number: 1, text: "Flip the ignition to RUN", done: ignitionOn)
                        TutorialStepRow(number: 2, text: "Hold the starter to crank it over", done: cranking)
                        TutorialStepRow(number: 3, text: clutchStepText, done: clutchWorked)
                    }

                    if allDone {
                        Label("It fires, you're driving.", systemImage: "checkmark.seal.fill")
                            .modifier(RetroFont(size: Theme.FontSize.control))
                            .foregroundColor(.accentOk)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: allDone)
            },
            preview: {
                OnboardingPreviewPanel(title: "START SEQUENCE") {
                    controlRow.padding(.vertical, Theme.Space.xl)
                }
            })
    }

    private var allDone: Bool { ignitionOn && cranking && clutchWorked }

    private var controlRow: some View {
        HStack(alignment: .top, spacing: controlRowSpacing) {
            ArmedIgnitionSwitch(isOn: ignitionOn) { ignitionOn.toggle() }

            StarterButton(running: cranking) {
                if ignitionOn { cranking = true }
            }

            clutchControl
        }
    }

    @ViewBuilder
    private var clutchControl: some View {
        #if os(macOS)
        VStack(spacing: Theme.Bar.captionGap) {
            KeyCap(symbol: "⇧", label: "SHIFT", pressed: clutchWorked) { clutchWorked = true }
            DashCaption(text: "CLUTCH", active: clutchWorked)
        }
        #else
        DashImageWarningTile(label: "CLUTCH",
                             active: clutchWorked,
                             accent: .accentClutch,
                             imageName: "clutch",
                             onTap: { clutchWorked = true })
        #endif
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
                        subtitle: "Design your own engine, or describe one and let the AI draft it. A fresh build rarely runs clean on the first crank, but that's the fun part.")

                    VStack(alignment: .leading, spacing: checkRowSpacing) {
                        TutorialBullet(icon: "slider.horizontal.3",
                                       text: "Reshape the ignition & fuel maps in ECU Tuning until it idles smooth and pulls hard.")
                        TutorialBullet(icon: "exclamationmark.triangle.fill",
                                       text: "Trouble codes in the OBD-II readout tell you exactly what your tune is fighting.")
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

                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        NextStepLine(text: "Pick an engine from the sidebar")
                        NextStepLine(text: "Hit the starter and drive")
                        NextStepLine(text: "Build New Engine when you're ready")
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

// MARK: - Shared tutorial widgets

struct TutorialStepRow: View {
    let number: Int
    let text: String
    let done: Bool

    var body: some View {
        HStack(spacing: Theme.Space.xl) {
            ZStack {
                Circle()
                    .fill(done ? Color.accentOk : Color.surfaceRaised)
                    .frame(width: stepNumberSize, height: stepNumberSize)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .modifier(RetroFont(size: Theme.FontSize.footnote))
                        .foregroundColor(.textSecondary)
                }
            }
            Text(text)
                .font(.system(size: bodyTextSize))
                .foregroundColor(done ? .textPrimary : .textSecondary)
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.2), value: done)
    }
}

struct TutorialBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.xl) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentLive)
                .frame(width: stepNumberSize)
            Text(text)
                .font(.system(size: bodyTextSize))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct NextStepLine: View {
    let text: String

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Text("▸")
                .modifier(RetroFont(size: Theme.FontSize.control))
                .foregroundColor(.accentLive)
            Text(text)
                .font(.system(size: bodyTextSize))
                .foregroundColor(.textSecondary)
        }
    }
}

// MARK: - Keyboard key cap (macOS clutch = Shift)

struct KeyCap: View {
    let symbol: String
    let label: String
    let pressed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(symbol)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                Text(label)
                    .modifier(RetroFont(size: Theme.FontSize.micro))
                    .tracking(0.5)
            }
            .foregroundColor(pressed ? .accentClutch : .textPrimary)
            .frame(width: keyCapSize.width, height: keyCapSize.height)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(Color.sidebarHighlight)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .stroke(pressed ? Color.accentClutch : Color.strokeStrong,
                                lineWidth: Theme.Stroke.thin)))
            .offset(y: pressed ? 2 : 0)
            .shadow(color: .black.opacity(0.5), radius: pressed ? 1 : 3, y: pressed ? 1 : 2)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: pressed)
    }
}

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
