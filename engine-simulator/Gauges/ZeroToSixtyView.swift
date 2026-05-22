//
//  ZeroToSixtyView.swift
//  engine-simulator
//
//  Arm-and-launch acceleration stopwatch. The user picks a target run
//  (0-60, 0-100, 60-130 rolling, etc.), arms it, and the clock starts the
//  moment the car crosses the run's *start* speed and stops the moment it
//  hits the *end* speed. Handles the awkward cases — armed while already
//  past the target, armed while still rolling — with clear status text.
//

import SwiftUI

// MARK: - Run definition

private struct LaunchTarget: Identifiable, Equatable {
    let id: String
    let label: String
    let startMph: Double
    let endMph: Double

    /// Some runs need the vehicle to be *at* the start speed (within a
    /// tolerance) before arming makes sense. The launch is detected once
    /// the speed crosses startMph upward; for stationary runs that means
    /// any forward motion.
    var requiresStop: Bool { startMph <= 1.0 }
}

private let availableTargets: [LaunchTarget] = [
    LaunchTarget(id: "0-60",    label: "0 → 60",    startMph: 0.0,  endMph: 60.0),
    LaunchTarget(id: "0-100",   label: "0 → 100",   startMph: 0.0,  endMph: 100.0),
    LaunchTarget(id: "60-130",  label: "60 → 130",  startMph: 60.0, endMph: 130.0),
]

// MARK: - Tunables

private let launchHysteresisMph: Double = 0.3   // forward-motion threshold for stop runs
private let rollingMatchToleranceMph: Double = 2.0

// Reference dimensions — everything below is multiplied by the smaller of
// (actualWidth / referenceWidth, actualHeight / referenceHeight) so the
// tile collapses gracefully when the user shrinks it in either axis. The
// 420×300 reference matches the default Track-layout slot.
private let referenceWidth: CGFloat = 420
private let referenceHeight: CGFloat = 300
private let minScale: CGFloat = 0.4
// iOS caps at 1.0 because the iOS base font sizes are already calibrated
// for a 1.0 scale + the global 0.7 scaleEffect. Letting scale grow past
// 1.0 pushed the timer's six stacked rows past the tile's bottom edge.
#if os(macOS)
private let maxScale: CGFloat = 1.4
#else
private let maxScale: CGFloat = 1.0
#endif

private let baseOuterPadding: CGFloat = 20
private let baseVStackSpacing: CGFloat = 18
private let baseTargetSelectorSpacing: CGFloat = 8
private let baseButtonRowSpacing: CGFloat = 10
private let baseStatusLineSpacing: CGFloat = 10
private let baseSpeedRowSpacing: CGFloat = 6
private let baseSpeedRowHorizontalPadding: CGFloat = 4

private let baseDisplayVerticalPadding: CGFloat = 18
#if os(macOS)
private let baseDisplayFontSize: CGFloat = 88
#else
// Was 130 — at maxScale 1.4 + the global 0.7 scale that's ~127pt visual
// for just the clock face, which pushed the buttons/speed rows below the
// tile's bottom edge. 92 + the new maxScale=1.0 ceiling lands at ~64pt
// visual: readable from across a desk, fits the tile.
private let baseDisplayFontSize: CGFloat = 92
#endif
private let baseButtonHeight: CGFloat = 44
private let baseChipHeight: CGFloat = 34
private let baseChipCornerRadius: CGFloat = 6
private let baseButtonHorizontalPadding: CGFloat = 14
private let baseChipHorizontalPadding: CGFloat = 12
// iOS bases sized for maxScale=1.0 + global 0.7 → text reads at ~10–18pt
// visual depending on element. Was tuned for maxScale=1.4 which was too
// aggressive and bumped content past the tile bottom.
#if os(macOS)
private let baseHeaderFontSize: CGFloat = 14
private let baseStatusIconFontSize: CGFloat = 18
private let baseStatusTextFontSize: CGFloat = 19
private let baseSpeedLabelFontSize: CGFloat = 13
private let baseSpeedValueFontSize: CGFloat = 22
private let baseButtonFontSize: CGFloat = 18
private let baseChipFontSize: CGFloat = 17
#else
private let baseHeaderFontSize: CGFloat = 17
private let baseStatusIconFontSize: CGFloat = 22
private let baseStatusTextFontSize: CGFloat = 23
private let baseSpeedLabelFontSize: CGFloat = 17
private let baseSpeedValueFontSize: CGFloat = 26
private let baseButtonFontSize: CGFloat = 22
private let baseChipFontSize: CGFloat = 20
#endif
private let textShrinkFloor: CGFloat = 0.5
private let displayShrinkFloor: CGFloat = 0.3

// MARK: - Phase model

private enum LaunchPhase: Equatable {
    case idle
    case armed
    case running(startedAt: TimeInterval)
    case complete(elapsed: TimeInterval)
    case aborted(reason: String)
}

// MARK: - View

struct ZeroToSixtyView: View {
    @ObservedObject var vm: EngineViewModel

    @State private var target: LaunchTarget = availableTargets[0]
    @State private var phase: LaunchPhase = .idle

    var body: some View {
        GeometryReader { geo in
            let scale = layoutScale(for: geo.size)
            VStack(spacing: baseVStackSpacing * scale) {
                header(scale: scale)
                targetSelector(scale: scale)
                timeDisplay(scale: scale)
                statusLine(scale: scale)
                buttonRow(scale: scale)
                // Speed readout row removed — speedometer tile + the
                // launch target chip already cover that info, and the
                // extra row was eating into the timer's tile height.
            }
            .padding(baseOuterPadding * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.appBackground)
            .onChange(of: vm.vehicleSpeed) { _, newSpeed in
                handleSpeed(newSpeed)
            }
            .onChange(of: target) { _, _ in
                // Switching the target while armed/mid-run is confusing — reset.
                phase = .idle
            }
        }
    }

    private func layoutScale(for size: CGSize) -> CGFloat {
        let raw = min(size.width / referenceWidth, size.height / referenceHeight)
        return max(minScale, min(maxScale, raw))
    }

    // MARK: Sub-views

    private func header(scale: CGFloat) -> some View {
        HStack {
            Text("LAUNCH TIMER")
                .modifier(RetroFont(size: baseHeaderFontSize * scale))
                .foregroundColor(.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
            Spacer()
            Text(phaseHeaderLabel)
                .modifier(RetroFont(size: baseHeaderFontSize * scale, weight: .bold))
                .foregroundColor(phaseAccentColor)
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
        }
    }

    private func targetSelector(scale: CGFloat) -> some View {
        HStack(spacing: baseTargetSelectorSpacing * scale) {
            ForEach(availableTargets) { entry in
                TargetChip(
                    label: entry.label,
                    selected: target.id == entry.id,
                    scale: scale,
                    action: { target = entry }
                )
            }
        }
    }

    /// Big monospaced clock face — the hero of the tile. No boxed panel; just
    /// large light-weight digits with a small unit, so it reads as a clean
    /// readout rather than a bordered widget. Font scales with tile size with a
    /// generous `minimumScaleFactor` so the digits never wrap or truncate.
    private func timeDisplay(scale: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            HStack(alignment: .lastTextBaseline, spacing: 4 * scale) {
                Text(displayTimeString(at: context.date.timeIntervalSinceReferenceDate))
                    .font(.system(size: baseDisplayFontSize * scale,
                                  weight: .light,
                                  design: .monospaced))
                    .foregroundColor(phase == .idle ? .white.opacity(0.85) : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(displayShrinkFloor)
                Text("s")
                    .font(.system(size: baseDisplayFontSize * scale * 0.32,
                                  weight: .regular,
                                  design: .monospaced))
                    .foregroundColor(.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, baseDisplayVerticalPadding * scale * 0.5)
        }
    }

    private func statusLine(scale: CGFloat) -> some View {
        HStack(spacing: baseStatusLineSpacing * scale) {
            Image(systemName: statusIcon)
                .font(.system(size: baseStatusIconFontSize * scale, weight: .semibold))
                .foregroundColor(phaseAccentColor)
            Text(statusMessage)
                .font(.system(size: baseStatusTextFontSize * scale))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(2)
                .minimumScaleFactor(textShrinkFloor)
            Spacer()
        }
    }

    private func buttonRow(scale: CGFloat) -> some View {
        HStack(spacing: baseButtonRowSpacing * scale) {
            TimerButton(
                label: armButtonLabel,
                style: .primary,
                scale: scale,
                action: handleArm
            )
            TimerButton(
                label: "RESET",
                style: .secondary,
                scale: scale,
                action: reset
            )
        }
    }

    private func speedRow(scale: CGFloat) -> some View {
        HStack(spacing: baseSpeedRowSpacing * scale) {
            Text("CURRENT")
                .modifier(RetroFont(size: baseSpeedLabelFontSize * scale, weight: .bold))
                .foregroundColor(.white.opacity(0.45))
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
            Spacer()
            Text(String(format: "%.1f", vm.vehicleSpeed))
                .modifier(RetroFont(size: baseSpeedValueFontSize * scale))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
            Text("mph")
                .modifier(RetroFont(size: baseSpeedLabelFontSize * scale))
                .foregroundColor(.white.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
        }
        .padding(.horizontal, baseSpeedRowHorizontalPadding * scale)
    }

    // MARK: Phase-driven labels & colors

    /// Single accent color across all non-idle states so the panel stays
    /// in the orange/white palette of the rest of the app. Phase is read
    /// from the status text / icon, not from a rainbow of colors.
    private var phaseAccentColor: Color {
        switch phase {
        case .idle:     return .white.opacity(0.45)
        default:        return .accentLive
        }
    }

    private var phaseHeaderLabel: String {
        switch phase {
        case .idle:     return "READY"
        case .armed:    return "ARMED"
        case .running:  return "TIMING"
        case .complete: return "FINISHED"
        case .aborted:  return "ABORTED"
        }
    }

    private var statusIcon: String {
        switch phase {
        case .idle:     return "stopwatch"
        case .armed:    return "scope"
        case .running:  return "speedometer"
        case .complete: return "checkmark.seal.fill"
        case .aborted:  return "exclamationmark.triangle.fill"
        }
    }

    private var statusMessage: String {
        switch phase {
        case .idle:
            return "Pick a target, then ARM."
        case .armed:
            return armedMessage()
        case .running:
            return "Hold throttle to \(Int(target.endMph)) mph."
        case .complete(let elapsed):
            return String(format: "Crossed %d mph in %.2fs.",
                          Int(target.endMph), elapsed)
        case .aborted(let reason):
            return reason
        }
    }

    private func armedMessage() -> String {
        if target.requiresStop {
            return vm.vehicleSpeed > launchHysteresisMph
                ? "Bring the car to a stop to start."
                : "Floor it — clock starts at first movement."
        }
        let lower = target.startMph - rollingMatchToleranceMph
        let upper = target.startMph + rollingMatchToleranceMph
        if vm.vehicleSpeed < lower {
            return "Accelerate to \(Int(target.startMph)) mph to start."
        }
        if vm.vehicleSpeed > upper {
            return "Slow to \(Int(target.startMph)) mph (±\(Int(rollingMatchToleranceMph))) to start."
        }
        return "Steady at \(Int(target.startMph)) mph — clock starts on launch."
    }

    private func displayTimeString(at now: TimeInterval) -> String {
        let seconds: TimeInterval
        switch phase {
        case .idle, .armed, .aborted:
            seconds = 0
        case .running(let startedAt):
            seconds = max(now - startedAt, 0)
        case .complete(let elapsed):
            seconds = elapsed
        }
        return String(format: "%.2f", seconds)
    }

    // MARK: Arm button labels

    private var armButtonLabel: String {
        switch phase {
        case .idle, .complete, .aborted: return "ARM"
        case .armed:                     return "DISARM"
        case .running:                   return "ABORT"
        }
    }

    // MARK: Actions

    private func handleArm() {
        switch phase {
        case .idle, .complete, .aborted:
            // Pre-flight checks vary by target — runs that begin at zero
            // require the user to have actually come to a stop; rolling
            // runs require the car to be near the start speed (the timer
            // will wait if not).
            if target.requiresStop && vm.vehicleSpeed > launchHysteresisMph {
                phase = .aborted(reason: "Already moving — stop the car, then arm.")
                return
            }
            if !target.requiresStop && vm.vehicleSpeed > target.endMph {
                phase = .aborted(reason: "Above \(Int(target.endMph)) mph — slow down to arm.")
                return
            }
            phase = .armed
        case .armed:
            phase = .idle
        case .running:
            phase = .aborted(reason: "Run aborted.")
        }
    }

    private func reset() { phase = .idle }

    private func handleSpeed(_ mph: Double) {
        switch phase {
        case .armed:
            handleArmedSpeed(mph)
        case .running(let start):
            if mph >= target.endMph {
                let elapsed = Date().timeIntervalSinceReferenceDate - start
                phase = .complete(elapsed: elapsed)
                vm.runResults.recordLaunch(targetId: target.id, seconds: elapsed)
            }
        default:
            break
        }
    }

    /// Launch detection: a stop-launch fires the moment we move past the
    /// hysteresis threshold; a rolling launch needs the user to be in the
    /// matching band and then cross the start speed upward.
    private func handleArmedSpeed(_ mph: Double) {
        if target.requiresStop {
            if mph > launchHysteresisMph {
                phase = .running(startedAt: Date().timeIntervalSinceReferenceDate)
            }
            return
        }

        let lower = target.startMph - rollingMatchToleranceMph
        let upper = target.startMph + rollingMatchToleranceMph
        // For rolling runs we require the user to be within the band AND
        // have just crossed the start line going forward. We approximate the
        // crossing with a one-sided check: once they're past the start speed
        // we start (no rear-edge tracking needed — they're either in the
        // band already or accelerating through it from below).
        if mph >= target.startMph && mph <= upper {
            phase = .running(startedAt: Date().timeIntervalSinceReferenceDate)
            return
        }
        if mph < lower {
            // Out-of-band low; keep waiting.
            return
        }
        if mph > upper {
            phase = .aborted(reason: "Overshot — slow back to \(Int(target.startMph)) mph and rearm.")
        }
    }
}

// MARK: - Themed button + chip

private enum TimerButtonStyle {
    case primary    // orange-accented action (ARM / DISARM / ABORT)
    case secondary  // neutral (RESET)
}

private struct TimerButton: View {
    let label: String
    let style: TimerButtonStyle
    let scale: CGFloat
    let action: () -> Void
    @State private var hovered = false

    private var accent: Color {
        switch style {
        case .primary:   return .accentLive
        case .secondary: return .white.opacity(0.55)
        }
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .modifier(RetroFont(size: baseButtonFontSize * scale, weight: .bold))
                .tracking(2)
                .foregroundColor(hovered ? .white : accent)
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, baseButtonHorizontalPadding * scale)
                .background(
                    RoundedRectangle(cornerRadius: baseChipCornerRadius * scale)
                        .fill(hovered ? accent.opacity(0.18) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: baseChipCornerRadius * scale)
                        .stroke(accent.opacity(hovered ? 0.85 : 0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(height: baseButtonHeight * scale)
        .onHover { hovered = $0 }
    }
}

private struct TargetChip: View {
    let label: String
    let selected: Bool
    let scale: CGFloat
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .modifier(RetroFont(size: baseChipFontSize * scale, weight: .bold))
                .tracking(1.2)
                .foregroundColor(selected ? .accentLive : (hovered ? .white : .white.opacity(0.5)))
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, baseChipHorizontalPadding * scale)
                // Clean segmented look — the selected target gets a soft orange
                // fill, the rest are plain text. No borders.
                .background(
                    RoundedRectangle(cornerRadius: baseChipCornerRadius * scale)
                        .fill(selected ? Color.accentLive.opacity(0.16)
                                       : (hovered ? Color.white.opacity(0.05) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .frame(height: baseChipHeight * scale)
        .onHover { hovered = $0 }
    }
}
