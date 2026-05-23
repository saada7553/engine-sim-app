//
//  DashLoader.swift
//  engine-simulator
//
//  The one loading indicator for the whole app. A ring of short dash ticks
//  with a single bright tick that sweeps around the ring like a tachometer
//  needle, trailing a comet tail that fades back into the dim track. Pure
//  time-based motion (no gradients, no system spinner) so it reads as part of
//  the instrument aesthetic everywhere it appears — inline inside buttons or
//  centered in a tile with a caption.
//
//  Use `DashLoader(diameter:tint:)` inline (in a button row, beside a label),
//  and `DashLoader(diameter:label:)` for a centered panel state. Replaces every
//  ad-hoc `ProgressView().controlSize(.small)` in the codebase so loading reads
//  the same on the leaderboard, the community board, the 3D tile, and a button.
//

import SwiftUI

private enum DashLoaderMetrics {
    static let tickCount = 12
    static let revolutionsPerSecond = 0.85
    static let tickLengthFraction: CGFloat = 0.34   // of the radius
    static let tickWidthFraction: CGFloat = 0.16    // of the radius
    static let minTickWidth: CGFloat = 1.2
    static let dimOpacity = 0.12                     // unlit track tick
    static let tailFalloff = 2.2                     // higher = tighter comet tail
    static let labelGapFraction: CGFloat = 0.5       // of the diameter
}

struct DashLoader: View {
    /// Ring diameter in points. ~13 reads well inline in a button; ~30 for a
    /// centered panel state.
    var diameter: CGFloat = 16
    /// Tick colour. Defaults to the live accent; pass `.black` when the loader
    /// sits inside a filled accent button so it stays legible.
    var tint: Color = .accentLive
    /// Optional caption shown beneath the ring (panel state). Rendered in the
    /// dash monospaced style with an ellipsis appended.
    var label: String? = nil

    var body: some View {
        if let label {
            VStack(spacing: diameter * DashLoaderMetrics.labelGapFraction) {
                ring
                Text(label.uppercased() + "…")
                    .font(.system(size: Theme.FontSize.callout, weight: .medium, design: .monospaced))
                    .tracking(Theme.Tracking.wide)
                    .foregroundColor(.textMuted)
                    .multilineTextAlignment(.center)
            }
        } else {
            ring
        }
    }

    private var ring: some View {
        TimelineView(.animation) { timeline in
            TickRing(date: timeline.date, tint: tint)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(label ?? "Loading")
    }
}

// MARK: - Overlay modifier

private let loadingScrimColor = Color.black.opacity(0.35)
private let loadingPanelDiameter: CGFloat = 34
private let loadingFadeDuration: Double = 0.35

extension View {
    /// The one way any surface shows a loading state: a centered `DashLoader`
    /// over a faint scrim, sized to (and centered within) THIS view. Because it
    /// is an `.overlay`, it always lands dead-center in the host — a tile, a
    /// sheet, a button row — regardless of the host's shape, so loaders never
    /// drift off-center.
    ///
    /// Visibility is driven straight off `isLoading`: pass a real readiness
    /// signal (a network flag, an "assembly installed" flag) — never a timer or
    /// a hold — so the loader disappears the instant the work is actually done.
    /// It cross-fades in and out rather than popping.
    func loadingOverlay(_ isLoading: Bool, label: String? = nil) -> some View {
        overlay { LoadingOverlay(isLoading: isLoading, label: label) }
    }
}

/// Stable host for the loader so its opacity transition reliably animates: the
/// ZStack always exists and carries the `.animation`, while the scrim+spinner
/// fade in/out as `isLoading` flips.
private struct LoadingOverlay: View {
    let isLoading: Bool
    let label: String?

    var body: some View {
        ZStack {
            if isLoading {
                ZStack {
                    loadingScrimColor
                    DashLoader(diameter: loadingPanelDiameter, label: label)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Swallow taps so the half-loaded content behind can't be
                // interacted with mid-load.
                .contentShape(Rectangle())
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: loadingFadeDuration), value: isLoading)
    }
}

// MARK: - Ring canvas

private struct TickRing: View {
    let date: Date
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            let t = date.timeIntervalSinceReferenceDate
            let head = (t * DashLoaderMetrics.revolutionsPerSecond)
                .truncatingRemainder(dividingBy: 1.0)   // 0...1, the bright tick

            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerR = min(size.width, size.height) / 2
            let innerR = outerR * (1 - DashLoaderMetrics.tickLengthFraction)
            let width = max(DashLoaderMetrics.minTickWidth,
                            outerR * DashLoaderMetrics.tickWidthFraction)

            for i in 0..<DashLoaderMetrics.tickCount {
                let frac = Double(i) / Double(DashLoaderMetrics.tickCount)

                // Angular distance this tick sits *behind* the sweeping head,
                // wrapped to 0...1 so the brightest point trails into the track.
                var behind = head - frac
                if behind < 0 { behind += 1 }
                let brightness = pow(1 - behind, DashLoaderMetrics.tailFalloff)
                let opacity = DashLoaderMetrics.dimOpacity
                    + (1 - DashLoaderMetrics.dimOpacity) * brightness

                let angle = frac * 2 * .pi - .pi / 2   // 12 o'clock start
                let cosA = CGFloat(cos(angle)), sinA = CGFloat(sin(angle))
                var path = Path()
                path.move(to: CGPoint(x: center.x + cosA * innerR, y: center.y + sinA * innerR))
                path.addLine(to: CGPoint(x: center.x + cosA * outerR, y: center.y + sinA * outerR))

                ctx.stroke(path,
                           with: .color(tint.opacity(opacity)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }
}
