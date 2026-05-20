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
private let ledSpacing: CGFloat = 6
private let ledHeight: CGFloat = 22
private let ledCornerRadius: CGFloat = 3
private let panelCornerRadius: CGFloat = 8
private let panelStrokeColor = Color.white.opacity(0.12)
private let panelFill = Color.white.opacity(0.03)
private let ledOffColor = Color.white.opacity(0.06)
private let ledOffStroke = Color.white.opacity(0.10)
private let ledGreenColor = Color.green
private let ledYellowColor = Color.yellow
private let ledRedColor = Color.red
private let glowRadius: CGFloat = 8

// MARK: - View

struct ShiftLightView: View {
    @ObservedObject var vm: EngineViewModel

    var body: some View {
        VStack(spacing: 14) {
            header
            ledBar
            readouts
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    private var header: some View {
        HStack {
            Text("SHIFT LIGHT")
                .modifier(RetroFont(size: 10))
                .foregroundColor(.gray)
            Spacer()
            statusBadge
        }
    }

    private var statusBadge: some View {
        let progress = currentProgress
        let (label, color) = statusFor(progress: progress)
        return Text(label)
            .modifier(RetroFont(size: 9, weight: .bold))
            .foregroundColor(color)
            .tracking(1.2)
    }

    private func statusFor(progress: Double) -> (String, Color) {
        if progress < preShiftBlankFraction { return ("STANDBY", Color.white.opacity(0.4)) }
        if progress < 1.0                   { return ("BUILD", .green) }
        if progress < 1.15                  { return ("SHIFT NOW", .red) }
        return ("OVER REV", .red)
    }

    private var ledBar: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            HStack(spacing: ledSpacing) {
                ForEach(0..<ledCount, id: \.self) { idx in
                    led(at: idx, now: context.date.timeIntervalSinceReferenceDate)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: panelCornerRadius)
                    .fill(panelFill)
                    .overlay(RoundedRectangle(cornerRadius: panelCornerRadius)
                                .stroke(panelStrokeColor, lineWidth: 1))
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func led(at idx: Int, now: TimeInterval) -> some View {
        let lit = shouldLight(idx: idx, now: now)
        let color = ledColor(for: idx)
        return RoundedRectangle(cornerRadius: ledCornerRadius)
            .fill(lit ? color : ledOffColor)
            .overlay(
                RoundedRectangle(cornerRadius: ledCornerRadius)
                    .stroke(lit ? color.opacity(0.9) : ledOffStroke, lineWidth: 1)
            )
            .frame(height: ledHeight)
            .frame(maxWidth: .infinity)
            .shadow(color: lit ? color.opacity(0.85) : .clear, radius: glowRadius)
    }

    private var readouts: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            readout(label: "RPM",
                    value: "\(Int(vm.rpm))",
                    color: .white)
            readout(label: "OPTIMAL",
                    value: "\(Int(shiftRpm))",
                    color: .orange)
            readout(label: "GEAR",
                    value: vm.gear == -1 ? "N" : "\(vm.gear + 1)",
                    color: vm.gear == -1 ? .green : .orange)
            Spacer()
        }
    }

    private func readout(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .modifier(RetroFont(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.45))
                .tracking(1.2)
            Text(value)
                .modifier(RetroFont(size: 22))
                .foregroundColor(color)
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
