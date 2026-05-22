//
//  Theme.swift
//  engine-simulator
//
//  Single source of truth for the vintage-dash visual language. Every tile,
//  control and gauge draws its radii, spacing, type sizes and stroke widths
//  from here so values never drift between surfaces. Colors live alongside
//  these tokens in Color+Extension.swift.
//
//  Per CLAUDE.md: no magic numbers, no duplicated tokens. New UI should pull
//  from `Theme.*` rather than re-declaring local constants.
//

import SwiftUI

enum Theme {

    // MARK: - Corner radii
    //
    // Five steps, from the tiny LED segment up to a full modal window. The
    // scattered 1 / 1.5 / 3 / 4 / 5 / 6 / 7 / 8 / 10 / 12 values collapse onto
    // these so every bezel and card shares the same family of curves.

    enum Radius {
        static let lamp: CGFloat = 2       // LED segments / tiny indicators
        static let small: CGFloat = 4      // chips, pills, inner recesses
        static let control: CGFloat = 6    // buttons, rows, bezels, dash tiles
        static let panel: CGFloat = 10     // clusters, cards, grouped controls
        static let window: CGFloat = 12    // sheets, full overlays
    }

    // MARK: - Spacing
    //
    // The base rhythm shared by stacks, padding and gaps. Per-tile layouts that
    // scale with available space multiply these by their own `scale` factor.

    enum Space {
        static let hair: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 16
        static let section: CGFloat = 22
    }

    // MARK: - Type scale (point sizes)
    //
    // Pair with `RetroFont` for instrument / data surfaces (monospaced) or with
    // the system font for chrome and prose. Naming is by role, not by number,
    // so a "caption" reads the same size everywhere it appears.

    enum FontSize {
        static let micro: CGFloat = 7      // sub-tile captions under glyphs
        static let caption: CGFloat = 8    // dash labels
        static let footnote: CGFloat = 9
        static let body: CGFloat = 10
        static let callout: CGFloat = 11
        static let control: CGFloat = 12   // button / row text
        static let headline: CGFloat = 13
        static let title: CGFloat = 16
        static let readout: CGFloat = 22   // large numeric readouts
    }

    // MARK: - Stroke widths

    enum Stroke {
        static let hairline: CGFloat = 0.5
        static let thin: CGFloat = 1
        static let medium: CGFloat = 1.4
    }

    // MARK: - Top bar
    //
    // Every control in CustomTopBar — the sidebar toggle, the workspace tool
    // buttons, the ignition rocker, the starter, the warning tiles — sizes its
    // metal bezel to `bezel` and its caption row to `caption`, so the bar reads
    // as one row of matched instruments rather than a jumble of sizes. The
    // captionGap separates the two. Tune these once and the whole bar stays
    // uniform per platform.

    enum Bar {
        #if os(macOS)
        static let height: CGFloat = 86
        static let bezel: CGFloat = 46     // bezel height, shared by all controls
        static let captionGap: CGFloat = 3
        #else
        static let height: CGFloat = 86
        static let bezel: CGFloat = 50
        static let captionGap: CGFloat = 3
        #endif
        static let itemSpacing: CGFloat = 10
        static let clusterSpacing: CGFloat = 18
    }

    // MARK: - Letter spacing
    //
    // Uppercased dash labels get tracked out slightly; the wider value is for
    // small all-caps captions that need to read as deliberate signage.

    enum Tracking {
        static let label: CGFloat = 1.0
        static let wide: CGFloat = 1.2
    }
}

// MARK: - Text role modifiers
//
// Convenience wrappers around the most common dash text treatments so call
// sites read by intent. Built on the existing `RetroFont` monospaced modifier.

extension View {
    /// Uppercased instrument label — section headers, control captions.
    func dashLabel(size: CGFloat = Theme.FontSize.caption,
                   weight: Font.Weight = .bold,
                   color: Color = .textMuted) -> some View {
        modifier(RetroFont(size: size, weight: weight))
            .tracking(Theme.Tracking.label)
            .foregroundColor(color)
    }
}
