//
//  LampLens.swift
//  engine-simulator
//
//  Shared LED-style indicator for the instrument surfaces (the shift-light
//  strip and the per-cylinder damage matrix). It reads as a small coloured
//  lamp under a domed lens:
//
//    • a recessed dark socket so the lamp sits in the panel,
//    • a domed fill that, when lit, glows in its OWN colour — the colour does
//      the work, not a white wash,
//    • a small, dim specular hotspot near the top so a lit lamp catches a
//      point of light (kept deliberately faint — a bright white core read as
//      ugly),
//    • a soft top gloss and a thin rim, plus an outer colour bloom when lit.
//
//  Off, the dome stays dark but faintly tinted so you can read what colour it
//  would burn. One definition so every LED in the app matches.
//

import SwiftUI

// MARK: - Tuning

// Socket the lens recesses into.
private let socketTop = Color(white: 0.05)
private let socketBottom = Color.black

// Lit dome: pure lens colour, brightest at the bulb, fading to a darker rim of
// the same colour so the dome has body. No white in the base fill.
private let domeLitRimFade: Double = 0.55
private let domeRadiusRatio: CGFloat = 0.60
private let domeCenterY: CGFloat = 0.42

// The specular hotspot — a small, faint bright point. Screen-blended so it
// brightens the colour toward its own light rather than graying it, and kept
// low + small so the lamp never looks like a white blob.
private let hotspotColor = Color.white.opacity(0.35)
private let hotspotRadiusRatio: CGFloat = 0.40

// Off dome: a dim tint so the colour still reads when dark.
private let domeOffCenter: Double = 0.28
private let domeOffEdge: Double = 0.05

// Soft cover gloss along the top.
private let glossColor = Color.white
private let glossLitOpacity: Double = 0.30
private let glossOffOpacity: Double = 0.22
private let glossHeightRatio: CGFloat = 0.40
private let glossInsetRatio: CGFloat = 0.18
private let glossOffsetRatio: CGFloat = 0.06

private let rimColor = Color.white.opacity(0.14)
private let lampAutoCornerRatio: CGFloat = 0.35

// MARK: - LampLens

struct LampLens: View {
    let lit: Bool
    let color: Color
    /// Explicit lens corner radius; nil derives one from the lamp size.
    var cornerRadius: CGFloat? = nil
    var rimWidth: CGFloat = Theme.Stroke.hairline
    var bloomRadius: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minDim = min(w, h)
            let corner = cornerRadius ?? max(Theme.Radius.lamp, minDim * lampAutoCornerRatio)
            let lens = RoundedRectangle(cornerRadius: corner)
            let innerCorner = max(0.5, corner - 1)
            let inner = RoundedRectangle(cornerRadius: innerCorner)
            let center = UnitPoint(x: 0.5, y: domeCenterY)
            let domeR = max(w, h) * domeRadiusRatio

            ZStack {
                // 1. Recessed socket.
                lens.fill(LinearGradient(colors: [socketTop, socketBottom],
                                         startPoint: .top, endPoint: .bottom))

                // 2. Domed lens fill.
                if lit {
                    inner.fill(RadialGradient(
                        colors: [color, color, color.opacity(domeLitRimFade)],
                        center: center, startRadius: 0, endRadius: domeR))
                        .padding(0.5)

                    // Small, faint specular hotspot — screen-blended so it
                    // brightens the colour without washing it white.
                    inner.fill(RadialGradient(
                        colors: [hotspotColor, .clear],
                        center: center, startRadius: 0,
                        endRadius: minDim * hotspotRadiusRatio))
                        .blendMode(.screen)
                        .padding(0.5)
                } else {
                    inner.fill(RadialGradient(
                        colors: [color.opacity(domeOffCenter), color.opacity(domeOffEdge)],
                        center: center, startRadius: 0, endRadius: domeR))
                        .padding(0.5)
                }

                // 3. Soft cover gloss near the top.
                gloss(in: CGSize(width: w, height: h), corner: innerCorner)
                    .fill(LinearGradient(
                        colors: [glossColor.opacity(lit ? glossLitOpacity : glossOffOpacity), .clear],
                        startPoint: .top, endPoint: .bottom))
                    .blendMode(.screen)

                // 4. Thin rim — warms to the lens colour when lit.
                lens.stroke(lit ? color.opacity(0.5) : rimColor, lineWidth: rimWidth)
            }
            .clipShape(lens)
            .shadow(color: lit ? color.opacity(0.7) : .clear, radius: bloomRadius)
        }
    }

    /// The gloss cap: an inset rounded rectangle hugging the top of the lens.
    private func gloss(in size: CGSize, corner: CGFloat) -> Path {
        let inset = size.width * glossInsetRatio
        let rect = CGRect(x: inset,
                          y: size.height * glossOffsetRatio,
                          width: size.width - inset * 2,
                          height: size.height * glossHeightRatio)
        return Path(roundedRect: rect, cornerRadius: min(corner, rect.height / 2))
    }
}
