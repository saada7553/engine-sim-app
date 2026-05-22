//
//  GeneratingIndicator.swift
//  engine-simulator
//
//  The "AI is thinking" state for engine generation. A fluid wave of light
//  travels across a row of dash segments while build-step status lines fade
//  in and out. Everything is driven by a single TimelineView clock — pure
//  time-based motion and opacity, no gradients — so it stays on-brand with the
//  instrument aesthetic while reading as a live, generative process.
//

import SwiftUI

private enum IndicatorMetrics {
    static let segmentCount = 13
    static let segmentWidth: CGFloat = 6
    static let segmentHeight: CGFloat = 16
    static let segmentSpacing: CGFloat = 5
    static let waveSpeed = 2.0           // radians/sec the pulse travels
    static let waveSpacing = 0.55        // phase offset between adjacent segments
    static let minBrightness = 0.16
    static let phraseInterval = 1.6      // seconds each status line is shown
    static let phraseFadeFraction = 0.2  // fraction of the window spent fading in/out
    static let stackSpacing: CGFloat = 22
}

private let buildPhrases: [String] = [
    "Reading your description",
    "Choosing the cylinder layout",
    "Sizing the displacement",
    "Reading forced induction",
    "Grinding the camshaft",
    "Balancing the crankshaft",
    "Porting the cylinder heads",
    "Tuning the intake tract",
    "Routing the headers",
    "Mapping the ignition",
    "Selecting the transmission",
    "Setting the gear ratios",
    "Torquing it all down",
]

struct GeneratingIndicator: View {
    private let start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            VStack(alignment: .leading, spacing: IndicatorMetrics.stackSpacing) {
                segments(at: t)
                phrase(at: t)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Travelling wave of dash segments

    private func segments(at t: TimeInterval) -> some View {
        HStack(spacing: IndicatorMetrics.segmentSpacing) {
            ForEach(0..<IndicatorMetrics.segmentCount, id: \.self) { i in
                let phase = t * IndicatorMetrics.waveSpeed - Double(i) * IndicatorMetrics.waveSpacing
                let pulse = pow(max(0, sin(phase)), 2)        // 0...1, sharp travelling crest
                let brightness = IndicatorMetrics.minBrightness
                    + (1 - IndicatorMetrics.minBrightness) * pulse

                RoundedRectangle(cornerRadius: Theme.Radius.lamp)
                    .fill(Color.accentLive.opacity(brightness))
                    .frame(width: IndicatorMetrics.segmentWidth,
                           height: IndicatorMetrics.segmentHeight)
                    .shadow(color: Color.accentLive.opacity(brightness * 0.7),
                            radius: brightness * 4)
            }
        }
    }

    // MARK: - Cycling status line

    private func phrase(at t: TimeInterval) -> some View {
        let window = t / IndicatorMetrics.phraseInterval
        let index = Int(window) % buildPhrases.count
        let local = window - window.rounded(.down)            // 0...1 within this phrase
        let fade = IndicatorMetrics.phraseFadeFraction
        let alpha = min(min(local / fade, 1.0), min((1 - local) / fade, 1.0))

        return Text(buildPhrases[index] + "…")
            .font(.system(size: Theme.FontSize.headline, weight: .regular, design: .monospaced))
            .tracking(1)
            .foregroundColor(.textSecondary)
            .opacity(alpha)
            // Reserve a stable line height so the layout doesn't jump as text changes.
            .frame(height: Theme.FontSize.headline + 6)
    }
}
