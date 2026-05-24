//
//  LaunchSplashView.swift
//  engine-simulator
//
//  The branded launch splash. It renders the SAME tachometer the dashboard
//  uses — GaugePresets.tachometer through GaugeDialRenderer, with the real
//  NeedleAnimationState spring physics — so it's visually identical to the
//  in-app gauge, not a lookalike. The needle is driven through a scripted
//  "key-on" rev: crank, sweep to the top, chatter against the rev limiter, a
//  parting throttle blip, then settle into a live idle. TileSurfApp holds it
//  for launchSplashHold, then crossfades to the dashboard.
//
//  It picks up from the OS static launch screen (the same dark appBackground),
//  and is purely a brand beat — the first engine is already built in
//  TileSurfApp.init before any frame renders, so this gates on nothing.
//

import SwiftUI

private let gaugeDiameter: CGFloat = 240
private let splashRedline: Double = 6500     // shapes the dial range/bands
private let idleRpm: Double = 850
private let readoutStep: Double = 50         // digits snap to this, like a real cluster

private let wordmarkSize: CGFloat = 16
private let wordmarkTracking: CGFloat = 5
private let wordmarkToGauge: CGFloat = 24
private let entranceDuration: Double = 0.35

// Scripted key-on sweep as (elapsed, fractionOfFullScale) anchor points. The
// needle position is smoothstep-interpolated *between* these — a continuous
// curve, not step targets — so the motion is smooth: a small stir as it
// catches, a graceful sweep to the top, a hold at the stop, then an easy
// settle to idle. `idleSentinel` resolves to wherever idle sits for the range.
// (smoothstep has zero velocity at each anchor, so the needle eases in and out
// of every phase instead of snapping.)
private let idleSentinel: Double = -1
private let revKeyframes: [(t: Double, frac: Double)] = [
    (0.00, 0.00),
    (0.20, 0.05),          // gentle stir as it catches
    (0.38, 0.03),
    (1.30, 1.00),          // smooth sweep to the top (~0.9s)
    (1.62, 1.00),          // hold at the stop
    (2.45, idleSentinel),  // ease back down to idle (~0.8s)
]
// After the sweep: a calm live idle that just breathes so the gauge looks alive.
private let idleFlutterRate: Double = 5
private let idleFlutterAmp: Double = 0.005   // fraction of full scale

struct LaunchSplashView: View {
    @State private var start = Date()
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: wordmarkToGauge) {
                Text("ENGINE SIMULATOR")
                    .font(.system(size: wordmarkSize, weight: .bold, design: .monospaced))
                    .tracking(wordmarkTracking)
                    .foregroundColor(.white.opacity(0.92))

                TimelineView(.animation) { timeline in
                    SplashTach(start: start, now: timeline.date)
                        .frame(width: gaugeDiameter, height: gaugeDiameter)
                }
            }
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            start = Date()
            withAnimation(.easeOut(duration: entranceDuration)) { appeared = true }
        }
    }
}

// MARK: - The real tach, scripted

/// Renders the in-app tachometer (dial + needle), with the needle position
/// taken from a smoothstep-interpolated key-on curve (see `revKeyframes`).
/// Recreated each frame by the parent TimelineView.
private struct SplashTach: View {
    let start: Date
    let now: Date

    private let config = GaugePresets.tachometer(redline: splashRedline)

    var body: some View {
        let elapsed = now.timeIntervalSince(start)
        let pos = needleFraction(at: elapsed)
        let displayRpm = Int((pos * config.maxValue / readoutStep).rounded() * readoutStep)

        return GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let labelInset = min(size * 0.035, 14)
            let outerRadius = size / 2 - labelInset

            ZStack {
                Canvas { ctx, cs in
                    let c = CGPoint(x: cs.width / 2, y: cs.height / 2)
                    GaugeDialRenderer.drawDial(context: ctx, config: config, center: c,
                                               outerRadius: outerRadius, gaugeSize: size,
                                               isCompact: false, isVeryCompact: false)
                    GaugeDialRenderer.drawNeedle(context: ctx, config: config, center: c,
                                                 normalizedPosition: pos,
                                                 outerRadius: outerRadius, gaugeSize: size)
                }

                // Numeric readout + title, positioned exactly as the live gauge.
                VStack(spacing: 2) {
                    Text("\(displayRpm)")
                        .font(.system(size: size * 0.12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(config.unit)
                        .font(.system(size: size * 0.05, weight: .medium, design: .monospaced))
                        .foregroundColor(config.needleColor)
                }
                .position(x: center.x, y: center.y + outerRadius * 0.25)

                Text(config.title)
                    .font(.system(size: max(8, size * 0.05), weight: .medium, design: .monospaced))
                    .foregroundColor(config.labelColor)
                    .position(x: center.x, y: center.y + outerRadius * 0.65)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Needle position (0…1 of full scale) at `elapsed` seconds: a continuous
    /// smoothstep interpolation across `revKeyframes`, then a breathing idle.
    private func needleFraction(at elapsed: Double) -> Double {
        let idleFrac = idleRpm / config.maxValue
        func resolve(_ frac: Double) -> Double { frac == idleSentinel ? idleFrac : frac }

        if elapsed <= revKeyframes[0].t { return resolve(revKeyframes[0].frac) }
        for i in 0 ..< (revKeyframes.count - 1) {
            let a = revKeyframes[i], b = revKeyframes[i + 1]
            if elapsed < b.t {
                let t = (elapsed - a.t) / (b.t - a.t)
                return resolve(a.frac) + (resolve(b.frac) - resolve(a.frac)) * smoothstep(t)
            }
        }
        return idleFrac + sin(elapsed * idleFlutterRate) * idleFlutterAmp
    }

    /// Hermite smoothstep: eases in and out (zero velocity at 0 and 1).
    private func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
