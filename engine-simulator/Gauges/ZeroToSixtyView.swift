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
private let displayCornerRadius: CGFloat = 8
private let buttonHeight: CGFloat = 44
private let chipHeight: CGFloat = 34
private let displayPanelFill = Color.white.opacity(0.04)
private let displayPanelStroke = Color.white.opacity(0.12)
private let chipCornerRadius: CGFloat = 6

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
        VStack(spacing: 18) {
            header
            targetSelector
            timeDisplay
            statusLine
            buttonRow
            speedRow
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onChange(of: vm.vehicleSpeed) { _, newSpeed in
            handleSpeed(newSpeed)
        }
        .onChange(of: target) { _, _ in
            // Switching the target while armed/mid-run is confusing — reset.
            phase = .idle
        }
    }

    // MARK: Sub-views

    private var header: some View {
        HStack {
            Text("LAUNCH TIMER")
                .modifier(RetroFont(size: 10))
                .foregroundColor(.gray)
            Spacer()
            Text(phaseHeaderLabel)
                .modifier(RetroFont(size: 10, weight: .bold))
                .foregroundColor(phaseAccentColor)
                .tracking(1.2)
        }
    }

    private var targetSelector: some View {
        HStack(spacing: 8) {
            ForEach(availableTargets) { entry in
                TargetChip(
                    label: entry.label,
                    selected: target.id == entry.id,
                    action: { target = entry }
                )
            }
        }
    }

    /// Big monospaced clock face. Dropped the "0 → 60 · SECONDS" subtext
    /// — the target chip already says which run is selected and "seconds"
    /// is obvious from the digit layout.
    private var timeDisplay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            Text(displayTimeString(at: context.date.timeIntervalSinceReferenceDate))
                .font(.system(size: 64, weight: .regular, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: displayCornerRadius)
                        .fill(displayPanelFill)
                        .overlay(RoundedRectangle(cornerRadius: displayCornerRadius)
                                    .stroke(displayPanelStroke, lineWidth: 1))
                )
        }
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(phaseAccentColor)
            Text(statusMessage)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 10) {
            TimerButton(
                label: armButtonLabel,
                style: .primary,
                action: handleArm
            )
            TimerButton(
                label: "RESET",
                style: .secondary,
                action: reset
            )
        }
    }

    private var speedRow: some View {
        HStack(spacing: 6) {
            Text("CURRENT")
                .modifier(RetroFont(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.45))
                .tracking(1.2)
            Spacer()
            Text(String(format: "%.1f", vm.vehicleSpeed))
                .modifier(RetroFont(size: 15))
                .foregroundColor(.white)
            Text("mph")
                .modifier(RetroFont(size: 10))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.horizontal, 4)
    }

    // MARK: Phase-driven labels & colors

    /// Single accent color across all non-idle states so the panel stays
    /// in the orange/white palette of the rest of the app. Phase is read
    /// from the status text / icon, not from a rainbow of colors.
    private var phaseAccentColor: Color {
        switch phase {
        case .idle:     return .white.opacity(0.45)
        default:        return .orange
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
                phase = .complete(elapsed: Date().timeIntervalSinceReferenceDate - start)
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
    let action: () -> Void
    @State private var hovered = false

    private var accent: Color {
        switch style {
        case .primary:   return .orange
        case .secondary: return .white.opacity(0.55)
        }
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .modifier(RetroFont(size: 13, weight: .bold))
                .tracking(2)
                .foregroundColor(hovered ? .white : accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: chipCornerRadius)
                        .fill(hovered ? accent.opacity(0.18) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: chipCornerRadius)
                        .stroke(accent.opacity(hovered ? 0.85 : 0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(height: buttonHeight)
        .onHover { hovered = $0 }
    }
}

private struct TargetChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .modifier(RetroFont(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundColor(selected ? .orange : (hovered ? .white : .white.opacity(0.55)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: chipCornerRadius)
                        .fill(selected ? Color.orange.opacity(0.18)
                                       : (hovered ? Color.white.opacity(0.05) : Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: chipCornerRadius)
                        .stroke(selected ? Color.orange.opacity(0.7) : Color.white.opacity(0.18),
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(height: chipHeight)
        .onHover { hovered = $0 }
    }
}
