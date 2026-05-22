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
// default it ships with in the Track layout. iOS caps maxScale at 1.0
// because the iOS base font sizes already account for the global 0.7
// scaleEffect — letting scale grow past 1.0 made the readouts overflow
// the tile height (clipping the bottom labels).
private let referenceHeight: CGFloat = 140
private let minScale: CGFloat = 0.35
#if os(macOS)
private let maxScale: CGFloat = 1.4
#else
private let maxScale: CGFloat = 1.0
#endif

private let baseLedSpacing: CGFloat = 6
private let baseLedHeight: CGFloat = 22
private let baseLedCornerRadius: CGFloat = 3
private let basePanelCornerRadius: CGFloat = 8
private let basePadding: CGFloat = 16
private let basePanelPadding: CGFloat = 12
private let baseVStackSpacing: CGFloat = 14
private let baseReadoutSpacing: CGFloat = 18
private let baseGlowRadius: CGFloat = 8
// Base font sizes are tuned for macOS, then the global 0.7 iOS scaleEffect
// shrinks every rendered pixel by 30% on iOS. Originally these numbers
// matched a much taller mac window so the readouts read at glance distance;
// at modern tile sizes they end up tiny. Both platforms get a generous
// bump, with iOS pushed further to absorb the global scale.
#if os(macOS)
private let baseHeaderFontSize: CGFloat = 14
private let baseBadgeFontSize: CGFloat = 13
private let baseReadoutLabelFontSize: CGFloat = 11
private let baseReadoutValueFontSize: CGFloat = 32
#else
// iOS sizes are calibrated against a maxScale=1.0 ceiling + the global
// 0.7 scaleEffect, so they end up readable without overflowing the tile.
private let baseHeaderFontSize: CGFloat = 26
private let baseBadgeFontSize: CGFloat = 24
private let baseReadoutLabelFontSize: CGFloat = 22
private let baseReadoutValueFontSize: CGFloat = 56
#endif
private let textShrinkFloor: CGFloat = 0.5

private let panelStrokeColor = Color.strokeSubtle
private let panelFill = Color.surfaceFaint
private let ledGreenColor = Color.accentOk
private let ledYellowColor = Color.accentWarn
private let ledRedColor = Color.accentDanger

// MARK: - View

struct ShiftLightView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        GeometryReader { geo in
            let scale = layoutScale(for: geo.size)
            VStack(spacing: baseVStackSpacing * scale) {
                unifiedHeader(scale: scale)
                ledBar(scale: scale)
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

    /// Single top bar holding the "SHIFT LIGHT" label, the RPM / OPTIMAL /
    /// GEAR readouts, and the BUILD / SHIFT NOW status badge. Replaces the
    /// separate header + readouts row so the component is just a bar over
    /// the LED strip and doesn't risk clipping its bottom labels.
    private func unifiedHeader(scale: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: baseReadoutSpacing * scale) {
            Text("SHIFT LIGHT")
                .modifier(RetroFont(size: baseHeaderFontSize * scale))
                .foregroundColor(.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
                .fixedSize()

            Spacer(minLength: baseReadoutSpacing * scale)

            inlineReadout(label: "RPM",
                          value: "\(Int(vm.rpm))",
                          color: .white,
                          scale: scale)
            inlineReadout(label: "OPTIMAL",
                          value: "\(Int(shiftRpm))",
                          color: .accentLive,
                          scale: scale)
            inlineReadout(label: "GEAR",
                          value: vm.gear == -1 ? "N" : "\(vm.gear + 1)",
                          color: vm.gear == -1 ? .accentOk : .accentLive,
                          scale: scale)

            Spacer(minLength: baseReadoutSpacing * scale)

            statusBadge(scale: scale)
        }
    }

    /// Compact inline readout for the top bar — label and value share a
    /// baseline so the bar reads as a single typographic line.
    private func inlineReadout(label: String, value: String, color: Color, scale: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .modifier(RetroFont(size: baseReadoutLabelFontSize * scale, weight: .bold))
                .foregroundColor(.white.opacity(0.45))
                .tracking(1.0)
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
                .fixedSize()
            Text(value)
                .modifier(RetroFont(size: baseHeaderFontSize * scale, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(textShrinkFloor)
                .fixedSize()
        }
    }

    private func statusBadge(scale: CGFloat) -> some View {
        let progress = currentProgress
        let (label, color) = statusFor(progress: progress)
        // Pin the badge to a fixed width so the BUILD ↔ SHIFT NOW flicker
        // at the rev limiter doesn't change the row's layout — without
        // this the trailing Spacer absorbs the width delta and the inline
        // RPM/OPTIMAL/GEAR readouts visibly jitter.
        return Text(label)
            .modifier(RetroFont(size: baseBadgeFontSize * scale, weight: .bold))
            .foregroundColor(color)
            .tracking(1.2)
            .lineLimit(1)
            .minimumScaleFactor(textShrinkFloor)
            .frame(width: baseBadgeFontSize * scale * 8, alignment: .trailing)
    }

    private func statusFor(progress: Double) -> (String, Color) {
        if progress < preShiftBlankFraction { return ("STANDBY", Color.white.opacity(0.4)) }
        if progress < 1.0                   { return ("BUILD", .accentOk) }
        if progress < 1.15                  { return ("SHIFT NOW", .accentDanger) }
        return ("OVER REV", .accentDanger)
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
        // Same glass-lensed lamp the damage matrix uses, so every indicator
        // in the app glows from one shared treatment.
        return LampLens(lit: lit, color: color, cornerRadius: corner,
                        rimWidth: 1, bloomRadius: baseGlowRadius * scale)
            .frame(height: baseLedHeight * scale)
            .frame(maxWidth: .infinity)
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
