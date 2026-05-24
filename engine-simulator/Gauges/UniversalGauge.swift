//
//  UniversalGauge.swift
//  engine-simulator
//
//  Created by Claude on 1/7/26.
//

import SwiftUI
import CoreGraphics
import Combine

// MARK: - Needle Animation State

/// Class to manage needle physics state across the per-tick re-renders driven
/// by the shared UI clock.
///
/// Uses spring-damper physics with two stability tweaks:
///
/// 1. **Substepping** — semi-implicit Euler is stable only while
///    `dt × √ks < 2`. With ks values up to 1000 that's ~63 ms; at a low UI
///    frame rate the per-tick dt is easily larger than that. Each call slices
///    the elapsed time into fixed `physicsStepSeconds` chunks so the inner step
///    never sees an unstable dt — which is what lets the needle stay smooth
///    even when the clock ticks slowly.
///
/// 2. **Damping floor** — many of the gauge presets ship with kd well below
///    `2√ks` (critical damping). That's a recipe for visible oscillation on
///    a steady target — exactly the "RPM bouncing 3-5K on idle" the user
///    reported. We always run with at least critical damping so the needle
///    asymptotes to the target instead of ringing.
class NeedleAnimationState: ObservableObject {
    var position: Double = 0.0
    private var velocity: Double = 0.0
    private var lastUpdateTime: Date?

    private static let physicsStepSeconds: Double = 1.0 / 240.0
    /// Hard cap on the elapsed time we'll catch up on in one update. If the
    /// app goes background for several seconds we don't want to spin in a
    /// substep loop — just snap the integrator forward.
    private static let maxCatchUpSeconds: Double = 0.25

    @discardableResult
    func update(targetPosition: Double, currentTime: Date, config: GaugeNeedleConfig) -> Bool {
        guard let lastTime = lastUpdateTime else {
            lastUpdateTime = currentTime
            return true
        }

        let dt = currentTime.timeIntervalSince(lastTime)
        lastUpdateTime = currentTime
        if dt <= 0 { return true }

        let cappedDt = min(dt, Self.maxCatchUpSeconds)
        let stepDt = Self.physicsStepSeconds
        let ks = config.ks
        // Damping below critical (kd_c = 2√ks) lets the needle ring on a
        // steady target. Treat the preset's kd as a floor: we never damp
        // less than critical.
        let kdMin = 2.0 * sqrt(max(ks, 0))
        let kd = max(config.kd, kdMin)

        var remaining = cappedDt
        while remaining > 0 {
            let step = min(stepDt, remaining)
            remaining -= step

            let springForce = ks * (targetPosition - position)
            let dampingForce = kd * velocity
            let acceleration = springForce - dampingForce

            velocity += acceleration * step
            velocity = max(-config.maxVelocity, min(config.maxVelocity, velocity))

            position += velocity * step
            position = max(0.0, min(1.0, position))
        }

        return true
    }

    func reset(to initialPosition: Double = 0.0) {
        position = initialPosition
        velocity = 0.0
        lastUpdateTime = nil
    }
}

/// A highly configurable gauge view that supports:
/// - Colored bands with configurable positions
/// - Major and minor tick marks
/// - Smooth needle animation using spring-damper physics
/// - Non-linear gamma scaling
/// - Adaptive text/tick density based on gauge size
/// - Maintains circular aspect ratio while filling available space
struct UniversalGauge: View {
    /// Plain reference, NOT @ObservedObject. UniversalGauge itself doesn't
    /// observe the VM, so its body (and the text-heavy static dial Canvas) only
    /// re-runs on resize / engine swap — not on every poll. The live parts live
    /// in `GaugeNeedleLayer`, which observes the VM and re-renders once per
    /// UI-clock tick. Engine swaps recreate the gauge via `.id(engineResetId)`
    /// in TileView, so a stale reference is never a concern.
    let engineVm: EngineViewModel
    let config: GaugeConfiguration
    let valueKeyPath: KeyPath<EngineViewModel, Double>

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            // Inset scales with the gauge: a 400pt gauge gets ~14pt of
            // padding for tick labels, smaller gauges proportionally
            // less. Cap so very large gauges don't waste space either.
            let labelInset = min(size * 0.035, 14)
            let outerRadius = size / 2 - labelInset

            // Determine if we should use compact mode (K abbreviation, fewer labels).
            // iOS thresholds are lower because the global 0.7 scaleEffect
            // shrinks every gauge by 30% visually — we want minor ticks
            // to keep drawing at smaller virtual sizes so they don't
            // vanish as soon as a gauge gets a modest tile.
            #if os(macOS)
            let isCompact = size < 180
            let isVeryCompact = size < 120
            #else
            let isCompact = size < 110
            let isVeryCompact = size < 70
            #endif

            ZStack {
                // Background
                config.backgroundColor

                // Static dial — bands, ticks and labels. UniversalGauge does NOT
                // observe the engine VM, so this body re-runs only when the tile
                // resizes or the engine swaps; the (text-heavy) dial Canvas is
                // drawn once per layout, never per frame.
                Canvas { context, canvasSize in
                    let canvasCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    GaugeDialRenderer.drawDial(context: context, config: config,
                                               center: canvasCenter, outerRadius: outerRadius,
                                               gaugeSize: size, isCompact: isCompact,
                                               isVeryCompact: isVeryCompact)
                }

                // Live layer — needle + numeric readout. This child observes the
                // VM and re-renders once per UI-clock tick (AppSettings
                // .uiFrameRate), advancing the needle spring off vm.frameDate.
                // One clock drives both the digits and the needle, so they can't
                // desync the way two separate TimelineViews did.
                GaugeNeedleLayer(engineVm: engineVm, config: config, valueKeyPath: valueKeyPath,
                                 size: size, center: center, outerRadius: outerRadius,
                                 isCompact: isCompact)

                // Title label — static, hidden on iOS in very-compact mode
                // since the value alone is enough info at that size.
                if shouldShowTitle(isVeryCompact: isVeryCompact) {
                    Text(config.title)
                        .font(.system(size: max(8, size * 0.05), weight: .medium, design: .monospaced))
                        .foregroundColor(config.labelColor)
                        .position(x: center.x, y: center.y + outerRadius * 0.65)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Adaptive text density

    /// Whether to render the bottom title label. iOS hides it in
    /// very-compact mode — the gauge's overall placement on the dash
    /// already communicates what it measures.
    private func shouldShowTitle(isVeryCompact: Bool) -> Bool {
        #if os(macOS)
        return true
        #else
        return !isVeryCompact
        #endif
    }

}

// MARK: - Needle Layer

/// The moving parts of a gauge: the needle and the numeric readout. Split out
/// from UniversalGauge so it can observe the engine VM (re-rendering once per
/// UI-clock tick) while the static dial in the parent stays cached. The needle
/// spring is advanced off `engineVm.frameDate` — the shared UI clock — so the
/// needle and the digits always step together at the configured frame rate.
private struct GaugeNeedleLayer: View {
    @ObservedObject var engineVm: EngineViewModel
    let config: GaugeConfiguration
    let valueKeyPath: KeyPath<EngineViewModel, Double>
    let size: CGFloat
    let center: CGPoint
    let outerRadius: CGFloat
    let isCompact: Bool

    // Spring-damper state persists across the per-tick re-renders.
    @StateObject private var needleState = NeedleAnimationState()

    // A diverged engine can briefly report a non-finite or absurdly large value.
    // Int(inf/NaN) — and Int() of anything past Int.max — is a hard Swift trap,
    // and a non-finite value also poisons the needle spring. Clamp the live
    // reading to a finite, displayable magnitude so the gauge degrades to a
    // pegged needle instead of taking the whole app down.
    private static let maxGaugeMagnitude: Double = 1e9

    private var targetValue: Double {
        let raw = engineVm[keyPath: valueKeyPath]
        guard raw.isFinite else { return 0 }
        return min(Self.maxGaugeMagnitude, max(-Self.maxGaugeMagnitude, raw))
    }

    var body: some View {
        // Advance the needle toward the live value, using the shared UI clock
        // as the time base. This re-runs every poll because we observe the VM
        // (frameDate changes each tick), so the needle tracks the same beat as
        // the readout below.
        let _ = needleState.update(
            targetPosition: config.normalizedPosition(for: targetValue),
            currentTime: engineVm.frameDate,
            config: config.needle
        )

        return ZStack {
            Canvas { context, canvasSize in
                let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                GaugeDialRenderer.drawNeedle(context: context, config: config, center: c,
                                             normalizedPosition: needleState.position,
                                             outerRadius: outerRadius, gaugeSize: size)
            }

            VStack(spacing: 2) {
                Text(formattedDisplayValue(compact: isCompact))
                    .font(.system(size: size * 0.12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                if !config.unit.isEmpty && shouldShowUnit(isCompact: isCompact) {
                    Text(config.unit)
                        .font(.system(size: size * 0.05, weight: .medium, design: .monospaced))
                        .foregroundColor(config.needleColor)
                }
            }
            .position(x: center.x, y: center.y + outerRadius * 0.25)
        }
    }

    /// Whether to render the small unit subtitle below the value. On iOS the
    /// global 0.7 scaleEffect makes compact gauges very small visually, so we
    /// drop the subtitle to give the value digits more room.
    private func shouldShowUnit(isCompact: Bool) -> Bool {
        #if os(macOS)
        return true
        #else
        return !isCompact
        #endif
    }

    private func formattedDisplayValue(compact: Bool) -> String {
        let intValue = Int(targetValue)
        if compact && abs(intValue) >= 1000 {
            let kValue = Double(intValue) / 1000.0
            if kValue == kValue.rounded() { return "\(Int(kValue))K" }
            return String(format: "%.1fK", kValue)
        }
        return "\(intValue)"
    }
}

// MARK: - Preview

#Preview {
    let oscilloscopeManager = OscilloscopeManager()
    let vm = EngineViewModel(oscillioscopeManager: oscilloscopeManager)

    return VStack {
        UniversalGauge(
            engineVm: vm,
            config: GaugePresets.tachometer(redline: 6500),
            valueKeyPath: \.rpm
        )
        .frame(width: 300, height: 300)

        UniversalGauge(
            engineVm: vm,
            config: GaugePresets.speedometer(),
            valueKeyPath: \.vehicleSpeed
        )
        .frame(width: 300, height: 300)
    }
    .background(Color.appBackground)
}
