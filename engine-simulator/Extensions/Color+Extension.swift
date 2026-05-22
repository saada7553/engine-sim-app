//
//  Color+Extension.swift
//  TileSurf
//
//  Created by Saad Ata on 12/2/25.
//

import Foundation
import SwiftUI

extension Color {
    public static let accentPrimary = Color(hue: 0.75, saturation: 0.7, brightness: 0.95)
    public static let accentSecondary = Color(hue: 0.55, saturation: 0.65, brightness: 0.9)
    public static let accentTertiary = Color(hue: 0.85, saturation: 0.6, brightness: 0.92)
    
    // Shared "full health" green — the bright green used by the diagnostic
    // wireframe and the Engine Health panel so both read identically.
    public static let healthGreen = Color(hue: 0.33, saturation: 0.9, brightness: 1.0)

    // App Concept Colors
    public static let appBackground = Color(white: 0.08)
    public static let sidebarHighlight = Color(white: 0.15)
    public static let sidebarAccent = Color(red: 0.9, green: 0.6, blue: 0.5)
    public static let sidebarTextSecondary = Color.gray

    // MARK: - Semantic accents
    //
    // Named by meaning, not hue, so a control's intent is clear at the call
    // site and a future palette change happens in one place. These alias the
    // system colors the dashboard already standardized on.
    // Primary brand accent — the cool blue from the app icon's blueprint
    // sheet. Active / armed / selected / primary action across the whole app.
    public static let accentLive = Color(red: 0.20, green: 0.56, blue: 0.96)
    // Warm "heat" cue — redline bands, the throttle blade, lean / clutch-slip.
    // This is the one place the old orange legitimately lives on (as heat),
    // never as the brand accent.
    public static let accentHeat = Color.orange
    public static let accentOk = Color.green        // healthy / neutral gear / pump on
    public static let accentDanger = Color.red      // critical fault / destructive
    public static let accentWarn = Color.yellow     // caution
    public static let accentInfo = Color.cyan       // coolant / airflow / info
    // Clutch — a violet/indigo kept distinct from the blue accent + cyan info.
    public static let accentClutch = Color(red: 0.58, green: 0.44, blue: 0.97)

    // MARK: - Dash red (ignition / starter glow)
    //
    // One bright red used by every red-accented control in the top bar so the
    // ignition switch and starter button never drift to different reds.
    public static let dashRed = Color(red: 1.00, green: 0.18, blue: 0.18)
    public static let dashRedDeep = Color(red: 0.45, green: 0.05, blue: 0.05)
    public static let dashRedDim = Color(red: 0.78, green: 0.10, blue: 0.10)
    public static let dashRedDimDeep = Color(red: 0.20, green: 0.02, blue: 0.02)

    // MARK: - Text ladder (white over the dark dash)
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.65)
    public static let textMuted = Color.white.opacity(0.45)
    public static let textFaint = Color.white.opacity(0.30)

    // MARK: - Surface fills (subtle white lifts over appBackground)
    public static let surfaceFaint = Color.white.opacity(0.03)
    public static let surfaceLow = Color.white.opacity(0.05)
    public static let surfaceRaised = Color.white.opacity(0.08)

    // MARK: - Hairline strokes
    public static let strokeFaint = Color.white.opacity(0.08)
    public static let strokeSubtle = Color.white.opacity(0.12)
    public static let strokeStrong = Color.white.opacity(0.18)

    // MARK: - Blueprint
    //
    // The app icon is a chrome piston drawn on a blue blueprint sheet with a
    // white grid and technical arcs. The "Build New Engine" CTA borrows that
    // language so the one creative action in the app echoes the brand mark.
    public static let blueprint = Color(red: 0.16, green: 0.52, blue: 0.85)
    public static let blueprintDeep = Color(red: 0.06, green: 0.20, blue: 0.40)
    public static let blueprintGrid = Color.white.opacity(0.16)
    public static let blueprintInk = Color(red: 0.82, green: 0.92, blue: 1.0)

    // MARK: - Oscilloscope trace palette
    //
    // A deliberately distinct multi-series set so overlaid signals stay legible
    // against each other; intentionally kept separate from the brand accent.
    public static let scopeWarm = Color.orange
    public static let scopeCool = Color(red: 0.2, green: 0.6, blue: 1.0)
    public static let scopePower = Color.pink
}
