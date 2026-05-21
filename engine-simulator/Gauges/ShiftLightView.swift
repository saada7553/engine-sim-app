//
//  ShiftLightView.swift
//  engine-simulator
//
//  Race-car style shift-light tile. A row of LEDs climbs from green to red
//  as the engine approaches the optimal shift point, then strobes the whole
//  bar once the user has stayed in the rev zone too long.
//

import SwiftUI

// MARK: - Tunables

private let ledCount: Int = 12
private let greenLedCount: Int = 5
private let yellowLedCount: Int = 4
// The rest (ledCount - green - yellow) light red.

// Where peak power sits relative to redline. At full throttle the optimal
// shift point lands the engine back near this RPM in the next gear; at
// part throttle the target shifts toward peak-torque (closer to mid-range).
private let peakPowerFraction: Double = 0.92
private let peakTorqueFraction: Double = 0.72
// Top-gear fallback: no upshift available, so the bar just climbs to redline.
private let topGearShiftFraction: Double = 0.98
private let preShiftBlankFraction: Double = 0.65   // RPM below this leaves the bar dark
private let flashPeriodSeconds: Double = 0.10      // strobing cadence above shift point

// Reference dimensions for the layout. All sizes below are scaled by
// (actualHeight / referenceHeight), clamped to [minScale, maxScale], so the
// tile collapses cleanly when the user drags it shorter than the 140-px
// default it ships with in the Track layout.
private let referenceHeight: CGFloat = 140
private let minScale: CGFloat = 0.35
private let maxScale: CGFloat = 1.4

private let baseLedSpacing: CGFloat = 6
private let baseLedHeight: CGFloat = 22
private let baseLedCornerRadius: CGFloat = 3
private let basePanelCornerRadius: CGFloat = 8
private let basePadding: CGFloat = 16
private let basePanelPadding: CGFloat = 12
private let baseVStackSpacing: CGFloat = 14
private let baseReadoutSpacing: CGFloat = 18
private let baseGlowRadius: CGFloat = 8
private let baseHeaderFontSize: CGFloat = 10
private let baseBadgeFontSize: CGFloat = 9
private let baseReadoutLabelFontSize: CGFloat = 8
private let baseReadoutValueFontSize: CGFloat = 22
private let textShrinkFloor: CGFloat = 0.5

private let panelStrokeColor = Color.white.opacity(0.12)
private let panelFill = Color.white.opacity(0.03)
private let ledOffColor = Color.white.opacity(0.06)
private let ledOffStroke = Color.white.opacity(0.10)
private let ledGreenColor = Color.green
private let ledYellowColor = Color.yellow
private let ledRedColor = Color.red

// MARK: - View

struct ShiftLightView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        GeometryReader { geo in
            let scale = layoutScale(for: geo.size)
            VStack(spacing: baseVStackSpacing * scale) {
                header(scale: scale)
                ledBar(scale: scale)
                readouts(scale: scale)
            }
            .padding(basePadding * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.appBackground)
        }
    }

    private func layoutScale(for size: CGSize) -> CGFloat {
        let raw = size.height / referenceHeight
        return max(minScale, min(maxScale, raw))
    }

    private func header(scale: CGFloat) -> some View {
        HStack {
            Text("SHIFT LIGHT")
                .modifier(RetroFont(size: baseHeaderFontSize * scale))
                .foregroundColor(.gray)
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
            Spacer()
            statusBadge(scale: scale)
        }
    }

    private func statusBadge(scale: CGFloat) -> some View {
        let progress = currentProgress
        let (label, color) = statusFor(progress: progress)
        return Text(label)
            .modifier(RetroFont(size: baseBadgeFontSize * scale, weight: .bold))
            .foregroundColor(color)
            .tracking(1.2)
            .lineLimit(1)
            .minimumScaleFactor(textShrinkFloor)
    }

    private func statusFor(progress: Double) -> (String, Color) {
        if progress < preShiftBlankFraction { return ("STANDBY", Color.white.opacity(0.4)) }
        if progress < 1.0                   { return ("BUILD", .green) }
        if progress < 1.15                  { return ("SHIFT NOW", .red) }
        return ("OVER REV", .red)
    }

    private func ledBar(scale: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            HStack(spacing: baseLedSpacing * scale) {
                ForEach(0..<ledCount, id: \.self) { idx in
                    led(at: idx,
                        now: context.date.timeIntervalSinceReferenceDate,
                        scale: scale)
                }
            }
            .padding(basePanelPadding * scale)
            .background(
                RoundedRectangle(cornerRadius: basePanelCornerRadius * scale)
                    .fill(panelFill)
                    .overlay(RoundedRectangle(cornerRadius: basePanelCornerRadius * scale)
                                .stroke(panelStrokeColor, lineWidth: 1))
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func led(at idx: Int, now: TimeInterval, scale: CGFloat) -> some View {
        let lit = shouldLight(idx: idx, now: now)
        let color = ledColor(for: idx)
        let corner = baseLedCornerRadius * scale
        return RoundedRectangle(cornerRadius: corner)
            .fill(lit ? color : ledOffColor)
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .stroke(lit ? color.opacity(0.9) : ledOffStroke, lineWidth: 1)
            )
            .frame(height: baseLedHeight * scale)
            .frame(maxWidth: .infinity)
            .shadow(color: lit ? color.opacity(0.85) : .clear,
                    radius: baseGlowRadius * scale)
    }

    private func readouts(scale: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: baseReadoutSpacing * scale) {
            readout(label: "RPM",
                    value: "\(Int(vm.rpm))",
                    color: .white,
                    scale: scale)
            readout(label: "OPTIMAL",
                    value: "\(Int(shiftRpm))",
                    color: .orange,
                    scale: scale)
            readout(label: "GEAR",
                    value: vm.gear == -1 ? "N" : "\(vm.gear + 1)",
                    color: vm.gear == -1 ? .green : .orange,
                    scale: scale)
            Spacer()
        }
    }

    private func readout(label: String, value: String, color: Color, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .modifier(RetroFont(size: baseReadoutLabelFontSize * scale, weight: .bold))
                .foregroundColor(.white.opacity(0.45))
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
            Text(value)
                .modifier(RetroFont(size: baseReadoutValueFontSize * scale))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
        }
    }

    // MARK: - Light logic

    /// Optimal upshift RPM. Top gear (and any state where we don't have a
    /// usable gear-ratio pair) falls back to a near-redline cue. Otherwise:
    ///
    /// 1. Pick a target post-shift RPM somewhere between peak-torque and
    ///    peak-power based on throttle position. Driver lifting → torque,
    ///    driver buried → power.
    /// 2. Divide by the drop ratio between current gear and the next to
    ///    figure out the rpm we need to be at *before* shifting so we land
    ///    on that target after the shift drops us.
    /// 3. Clamp to redline so we never recommend bouncing off the limiter.
    private var shiftRpm: Double {
        let topGearFallback = vm.redline * topGearShiftFraction
        let ratios = vm.gearRatios
        let gear = vm.gear

        guard gear >= 0,
              gear + 1 < ratios.count,
              ratios[gear] > 0,
              ratios[gear + 1] > 0 else {
            return topGearFallback
        }

        let throttle = max(0.0, min(1.0, vm.throttlePosition))
        let target = vm.redline * (peakTorqueFraction
                                    + (peakPowerFraction - peakTorqueFraction) * throttle)
        let dropRatio = ratios[gear + 1] / ratios[gear]
        let computed = target / dropRatio
        return min(computed, vm.redline)
    }

    /// Normalised progress: 0 at idle, 1 at the shift point, > 1 once you're
    /// blowing past it. Anchored at 70% of the shift point so the bar starts
    /// to light a few hundred rpm before the action begins.
    private var currentProgress: Double {
        guard shiftRpm > 0 else { return 0 }
        return vm.rpm / shiftRpm
    }

    private func shouldLight(idx: Int, now: TimeInterval) -> Bool {
        let progress = currentProgress
        if progress >= 1.0 {
            // All LEDs strobe in lockstep.
            let phase = (now.truncatingRemainder(dividingBy: flashPeriodSeconds * 2))
                        < flashPeriodSeconds
            return phase
        }
        if progress < preShiftBlankFraction { return false }
        // Map [preShiftBlankFraction, 1.0] onto [0, ledCount].
        let span = 1.0 - preShiftBlankFraction
        let normalized = (progress - preShiftBlankFraction) / span
        let lit = Int(round(normalized * Double(ledCount)))
        return idx < lit
    }

    private func ledColor(for idx: Int) -> Color {
        if idx < greenLedCount { return ledGreenColor }
        if idx < greenLedCount + yellowLedCount { return ledYellowColor }
        return ledRedColor
    }
}
