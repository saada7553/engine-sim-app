//
//  CustomTopBar.swift
//  engine-simulator
//
//  Top bar with engine controls + status lights. Visual language is a blend
//  of modern OEM dash cleanliness and race-car / dyno-cell instrumentation:
//  a covered toggle for ignition (arming behaviour) and a chunky illuminated
//  start/stop button that only lights up when ignition is "armed". The
//  warning lights on the right mimic real dashboard tiles with bezels,
//  recessed LEDs and properly drawn icons.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Top Bar

struct CustomTopBar: View {
    @ObservedObject var vm: EngineViewModel
    @Binding var browserMode: BrowserMode
    let isLayoutDirty: Bool
    let onToggleSplit: () -> Void
    let onToggleDelete: () -> Void
    let onSaveLayout: () -> Void

    var body: some View {
        barContent
            .frame(height: Theme.Bar.height)
            .background(topBarBackground)
            .border(Color.white.opacity(0.12), width: 1, edges: [.bottom])
    }

    #if os(macOS)
    private var barContent: some View {
        HStack(spacing: 0) {
            leftCluster
                .padding(.leading, 18)

            Spacer()

            rightCluster
                .padding(.trailing, 18)
        }
    }
    #else
    // iOS: prefer the full-width row (Spacer alive, so the throttle slider +
    // shift buttons hug the far right for right-thumb reach). Only when the
    // controls can't fit — a narrow iPhone — fall back to a horizontally
    // scrollable row so a packed bar scrolls instead of clipping. ViewThatFits
    // picks the first child whose ideal width fits; inside the ScrollView the
    // Spacer collapses to its minLength and the row overflows to scroll.
    private var barContent: some View {
        ViewThatFits(in: .horizontal) {
            iosRow
            ScrollView(.horizontal, showsIndicators: false) {
                iosRow
            }
        }
    }

    private var iosRow: some View {
        HStack(spacing: 0) {
            leftCluster
                .padding(.leading, 18)

            Spacer(minLength: Theme.Bar.clusterSpacing)

            iosQuickControls
                .padding(.trailing, 18)
        }
    }
    #endif

    #if !os(macOS)
    // MARK: iOS quick controls — gear readout + throttle slider + shift buttons.
    private var iosQuickControls: some View {
        HStack(spacing: Theme.Bar.itemSpacing) {
            TopBarGearReadout(gear: vm.gear, gearCount: vm.gearCount)
            TopBarThrottleSlider(value: vm.throttleInput)
                .frame(width: 200)
            TopBarShiftButton(direction: .up,   action: vm.shiftUp)
            TopBarShiftButton(direction: .down, action: vm.shiftDown)
        }
    }
    #endif

    // MARK: Left — controls
    //
    // The sidebar toggle button and the WorkspaceToolCluster (add tile /
    // remove tile / save layout) are macOS-only. On iOS the sidebar collapses
    // via NavigationSplitView's built-in toolbar control, and the custom
    // tiling system is intentionally not exposed — users get the built-in
    // layouts read-only.

    private var leftCluster: some View {
        HStack(spacing: Theme.Bar.clusterSpacing) {
            // Sidebar toggle now lives on both platforms — iOS needs a
            // way to reclaim the screen real estate the sidebar takes up.
            SidebarToggleButton {
                SidebarManager.shared.toggleSidebar()
            }

            #if os(macOS)
            WorkspaceToolCluster(
                browserMode: browserMode,
                isLayoutDirty: isLayoutDirty,
                onToggleSplit: onToggleSplit,
                onToggleDelete: onToggleDelete,
                onSaveLayout: onSaveLayout
            )
            #endif

            ArmedIgnitionSwitch(isOn: vm.isIgnitionOn) { vm.toggleIgnition() }

            StarterButton(running: vm.isStarterOn) {
                vm.toggleStarter()
            }

            #if !os(macOS)
            // iOS: tappable CLUTCH + DYNO sit next to the ignition + starter
            // so all the on/off controls live in one cluster on the left.
            // The right side stays reserved for the throttle slider + shift
            // buttons (right-thumb territory). The status warning lights ride
            // on the left here too, since iOS keeps the right side clear.
            DashImageWarningTile(label: "CLUTCH",
                                 active: vm.clutchPressed,
                                 accent: .accentClutch,
                                 imageName: "clutch",
                                 onTap: { vm.toggleClutch() })
            DashWarningTile(label: "DYNO",
                            active: vm.dynoEnabled,
                            accent: .accentLive,
                            onTap: { vm.toggleDyno() }) { DynoIcon() }
            warningLights
            #endif
        }
    }

    // MARK: Right — warning-light cluster

    private var rightCluster: some View {
        HStack(spacing: Theme.Bar.itemSpacing) {
            // macOS keeps CLUTCH / DYNO / HOLD as passive indicators on
            // the right side (the keyboard drives the toggles). On iOS
            // CLUTCH and DYNO moved into the left cluster as tappable
            // tiles next to the ignition + starter, and HOLD is gone
            // (the throttle slider auto-holds its position), so iOS has
            // nothing left to show here.
            #if os(macOS)
            DashWarningTile(label: "IGN",    active: vm.isIgnitionOn,  accent: .accentDanger,    onTap: { vm.toggleIgnition() }) { IgnitionIcon() }
            DashWarningTile(label: "CRANK",  active: vm.isStarterOn,   accent: .accentOk,  onTap: { vm.toggleStarter() })  { StarterIcon() }
            DashImageWarningTile(label: "CLUTCH", active: vm.clutchPressed, accent: .accentClutch, imageName: "clutch", onTap: { vm.toggleClutch() })
            DashWarningTile(label: "DYNO",   active: vm.dynoEnabled,   accent: .accentLive, onTap: { vm.toggleDyno() })     { DynoIcon() }
            DashWarningTile(label: "HOLD",   active: vm.throttleHeld,  accent: .accentWarn, onTap: { vm.toggleHold() })     { HoldIcon() }
            warningLights
            #else
            EmptyView()
            #endif
        }
    }

    // MARK: Status warning lights (check engine / oil / coolant)
    //
    // Driven straight off the OBD-II code list so the lights mirror exactly
    // what the diagnostic scanner reports — no second set of thresholds to
    // drift out of sync. Off normally; lit (in their accent colour) when a
    // matching fault is present; the check-engine light flashes on any
    // critical/catastrophic fault.

    @ViewBuilder
    private var warningLights: some View {
        let state = WarningLightState(codes: OBD2CodeService.codes(for: vm))
        DashImageWarningTile(label: "CHECK", active: state.checkEngine, accent: .accentWarn,
                             imageName: "car-indicator", flashing: state.catastrophic)
        #if os(macOS)
        DashImageWarningTile(label: "OIL", active: state.oil, accent: .accentDanger,
                             imageName: "oil-indicator")
        DashImageWarningTile(label: "TEMP", active: state.coolant, accent: .accentInfo,
                             imageName: "car-cooler")
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            DashImageWarningTile(label: "OIL", active: state.oil, accent: .accentDanger,
                                 imageName: "oil-indicator")
            DashImageWarningTile(label: "TEMP", active: state.coolant, accent: .accentInfo,
                                 imageName: "car-cooler")
        }
        #endif
    }

    private var topBarBackground: some View {
        // Flat fill — the gradient overlay competed with the dash chrome and
        // the user asked for it gone on both platforms.
        Color.appBackground
    }
}

// MARK: - Warning-light derivation

/// Maps the active OBD-II codes onto the three dashboard tell-tales. The code
/// ids come from `OBD2CodeService`; grouping them here keeps the top bar and
/// the scanner in agreement about what counts as "out of whack".
private struct WarningLightState {
    let checkEngine: Bool
    let catastrophic: Bool
    let oil: Bool
    let coolant: Bool

    init(codes: [OBD2Code]) {
        // Any active code trips the check-engine light; a critical one makes
        // it flash.
        checkEngine = !codes.isEmpty
        catastrophic = codes.contains { $0.severity == .critical }

        let oilCodeIds: Set<String> = ["P0196", "P0521", "P0524", "P0521-PUMP"]
        let coolantCodeIds: Set<String> = ["P0217", "P0480"]
        oil = codes.contains { oilCodeIds.contains($0.id) }
        coolant = codes.contains { coolantCodeIds.contains($0.id) }
    }
}

// MARK: - Sidebar toggle
//
// The panel toggle, built on the shared DashTileChrome so it matches the
// workspace tools and warning tiles beside it exactly — same bezel, same
// caption row, same footprint. Lights its accent on hover so it reads as a
// live control.

private struct SidebarToggleButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        DashTileChrome(label: "PANEL", active: hovering, accent: .accentLive,
                       onTap: action, style: .button) {
            Image(systemName: "sidebar.left")
                .font(.system(size: Theme.Bar.bezel * 0.36, weight: .regular))
                .foregroundColor(hovering ? .white : .white.opacity(0.7))
        }
        .onHover { hovering = $0 }
        .help("Toggle Sidebar")
    }
}

// MARK: - Workspace tool cluster
//
// Add / remove / save tiles. Each button doubles as its own state indicator:
// when a mode is armed the icon swaps to its active variant, the caption flips
// to a "PICK …" prompt and the bezel lights its accent ring so the user knows
// the next click acts on the workspace. Tooltips spell out the full action.

private struct WorkspaceToolCluster: View {
    let browserMode: BrowserMode
    let isLayoutDirty: Bool
    let onToggleSplit: () -> Void
    let onToggleDelete: () -> Void
    let onSaveLayout: () -> Void

    var body: some View {
        HStack(spacing: Theme.Bar.itemSpacing) {
            WorkspaceToolButton(
                idleIcon: "rectangle.split.2x1",
                activeIcon: "plus.rectangle.on.rectangle",
                idleLabel: "ADD TILE",
                activeLabel: "PICK AN EDGE",
                tooltip: "Add Tile  (⌘T)\nClick an edge of any tile — a new tile spawns on that side.",
                isArmed: browserMode == .split,
                accent: .accentLive,
                dirty: false,
                action: onToggleSplit
            )

            WorkspaceToolButton(
                idleIcon: "minus.rectangle",
                activeIcon: "rectangle.badge.minus",
                idleLabel: "REMOVE",
                activeLabel: "PICK A TILE",
                tooltip: "Remove Tile  (⌘D)\nClick a tile — it disappears and its sibling expands to fill the space.",
                isArmed: browserMode == .delete,
                accent: .accentDanger,
                dirty: false,
                action: onToggleDelete
            )

            WorkspaceToolButton(
                idleIcon: "square.and.arrow.down",
                activeIcon: "square.and.arrow.down",
                idleLabel: "SAVE",
                activeLabel: "SAVE",
                tooltip: "Save Workspace  (⌘S)\nName this tile arrangement to keep it in your Layouts list.",
                isArmed: false,
                accent: .accentLive,
                dirty: isLayoutDirty,
                action: onSaveLayout
            )
        }
    }
}

// Built on the shared DashTileChrome so the workspace tools are the same
// bezel + caption footprint as the sidebar toggle and the warning tiles. When
// armed the icon swaps to its active variant, the caption flips to the
// "PICK …" prompt and an accent ring lights the bezel; the SAVE tool carries
// an unsaved-changes dot. A little wider than square to hold the longer caps.
private struct WorkspaceToolButton: View {
    let idleIcon: String
    let activeIcon: String
    let idleLabel: String
    let activeLabel: String
    let tooltip: String
    let isArmed: Bool
    let accent: Color
    let dirty: Bool
    let action: () -> Void

    @State private var hovering = false

    private var displayIcon: String { isArmed ? activeIcon : idleIcon }
    private var displayLabel: String { isArmed ? activeLabel : idleLabel }

    var body: some View {
        DashTileChrome(label: displayLabel,
                       active: isArmed || hovering,
                       accent: accent,
                       onTap: action,
                       width: Theme.Bar.bezel * 1.7,
                       style: .button,
                       armed: isArmed,
                       dirtyDot: dirty) {
            Image(systemName: displayIcon)
                .font(.system(size: Theme.Bar.bezel * 0.32, weight: .medium))
                .foregroundColor(isArmed ? accent : .white.opacity(hovering ? 0.95 : 0.7))
        }
        .onHover { hovering = $0 }
        .help(tooltip)
        .animation(.easeInOut(duration: 0.2), value: isArmed)
    }
}

// MARK: - Ignition switch
//
// Chrome bezel labelled OFF / RUN with a paddle that travels between the
// two positions. A small LED at the base lights red when ignition is on.

// Shared "dash red" used by every red-accented control in the top bar
// (ignition switch lit RUN, starter button face, LED dots). One source of
// truth so the ignition and starter never drift to slightly different reds.
private let dashRed = Color.dashRed
private let dashRedDeep = Color.dashRedDeep
private let dashRedDim = Color.dashRedDim
private let dashRedDimDeep = Color.dashRedDimDeep

// Hand-built dashboard rocker switch: stacked top / bottom readouts with the
// active label lit in an accent colour, separated by a thin "detent" rule,
// with a small LED dot at the bottom. Drawn entirely from SwiftUI primitives
// — no SF Symbol — so the typography and proportions match the rest of the
// hand-built dash chrome. Reused by the ignition switch and the Engine Health
// pump toggles. Font sizes derive from `height` so it scales cleanly between
// the full-size top-bar instance and the smaller health-tile instances.
struct DashRockerSwitch: View {
    let topLabel: String
    let bottomLabel: String
    let isOn: Bool
    var accent: Color = dashRed
    var width: CGFloat = 52
    var height: CGFloat = 54
    let toggle: () -> Void

    private var topFontSize: CGFloat { height * 0.19 }
    private var bottomFontSize: CGFloat { height * 0.17 }

    var body: some View {
        Button(action: toggle) {
            ZStack {
                bezel
                rockerFace
            }
            .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isOn)
    }

    private var bezel: some View {
        DashBezel(cornerRadius: 7)
    }

    private var rockerFace: some View {
        VStack(spacing: 0) {
            // Top row — tinted accent + glowing when on.
            ZStack {
                if isOn {
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .fill(accent.opacity(0.18))
                        .padding(.horizontal, 5)
                        .blur(radius: 1)
                }
                Text(topLabel)
                    .modifier(RetroFont(size: topFontSize, weight: .bold))
                    .foregroundColor(isOn ? accent : .white.opacity(0.35))
                    .tracking(1.0)
                    .shadow(color: isOn ? accent.opacity(0.55) : .clear, radius: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Detent rule between the two positions.
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 0.5)
                .padding(.horizontal, 6)

            // Bottom row — lit white when off.
            Text(bottomLabel)
                .modifier(RetroFont(size: bottomFontSize, weight: .bold))
                .foregroundColor(!isOn ? .white.opacity(0.85) : .white.opacity(0.25))
                .tracking(1.0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // LED dot.
            Circle()
                .fill(isOn ? accent : accent.opacity(0.15))
                .frame(width: 4, height: 4)
                .shadow(color: isOn ? accent.opacity(0.9) : .clear, radius: 2.5)
                .padding(.bottom, 4)
        }
        .padding(.vertical, 3)
    }
}

// Internal (not private) so the onboarding tutorial can render the real
// ignition switch the user will actually use, rather than a lookalike.
struct ArmedIgnitionSwitch: View {
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        // Caption below (not above) so the rocker's bezel lines up with every
        // other control's bezel across the bar, and the captions form one row.
        VStack(spacing: Theme.Bar.captionGap) {
            DashRockerSwitch(topLabel: "RUN",
                             bottomLabel: "OFF",
                             isOn: isOn,
                             accent: dashRed,
                             width: Theme.Bar.bezel * 1.15,
                             height: Theme.Bar.bezel,
                             toggle: toggle)
            DashCaption(text: "IGNITION", active: isOn)
        }
    }
}

// MARK: - Starter button
//
// Chunky illuminated push button labelled STARTER. Always pressable — works
// independently of the ignition switch (you can crank the engine over with
// ignition off; it just won't fire). Lights up red whenever the starter is
// engaged, with a pulsing halo to communicate the cranking motor.

// Internal so the onboarding tutorial reuses the real starter button.
struct StarterButton: View {
    let running: Bool
    let action: () -> Void

    @State private var pressing = false

    // Round button sized to the shared bezel so it stands the same height as
    // the rocker and the tiles. Inner rings derive from that diameter.
    private var diameter: CGFloat { Theme.Bar.bezel }
    private var faceDiameter: CGFloat { diameter - 10 }

    var body: some View {
        // Caption below to match the rest of the bar; the CRANK text on the
        // face still identifies the button at a glance.
        VStack(spacing: Theme.Bar.captionGap) {
            Button(action: { HapticManager.shared.tap(.firm); action() }) {
                ZStack {
                    bezel

                    // Inset shadow ring (subtle, not a dark moat).
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: diameter - 8, height: diameter - 8)

                    // Illuminated face — calmer palette + thin rim ring
                    // instead of the heavy halo blur.
                    Circle()
                        .fill(faceGradient)
                        .frame(width: faceDiameter, height: faceDiameter)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                .padding(4)
                        )
                        .overlay(
                            Circle()
                                .stroke(dashRed.opacity(running ? 0.55 : 0.30),
                                        lineWidth: 1)
                        )

                    Text("CRANK")
                        .font(.system(size: Theme.FontSize.micro, weight: .black))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                }
                .frame(width: diameter, height: diameter)
                // Soft cast shadow only — no animated halo pulse. The
                // CRANK dash light + running starter audio already
                // communicate cranking state; the big red glow was
                // visually dominating the whole top bar.
                .shadow(color: dashRed.opacity(running ? 0.30 : 0.0),
                        radius: running ? 3 : 0, x: 0, y: pressing ? 0 : 2)
                .scaleEffect(pressing ? 0.94 : 1.0)
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { p in
                pressing = p
            }, perform: {})
            .animation(.interactiveSpring(), value: pressing)

            DashCaption(text: "STARTER", active: running)
        }
    }

    private var bezel: some View {
        // The DashBezel chrome in circular form so the starter and the rocker
        // read as a matched pair — same metal, same bevel.
        Circle()
            .fill(LinearGradient(colors: [dashBezelTopGray, dashBezelBottomGray],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle().stroke(
                    LinearGradient(colors: [dashBezelStrokeLight, dashBezelStrokeDark],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 2)
    }

    private var faceGradient: RadialGradient {
        // Always lit — dimmer at rest, brighter when cranking. Uses the
        // shared dashRed palette so the starter and the ignition switch
        // glow in the exact same red.
        let warmCore = running ? dashRed : dashRedDim
        let darkRim  = running ? dashRedDeep : dashRedDimDeep
        return RadialGradient(colors: [warmCore, darkRim],
                              center: .center, startRadius: 0, endRadius: faceDiameter / 2)
    }
}

// MARK: - Shared control caption
//
// The tracked-caps legend under every top-bar control. One definition so the
// caption row is identical height and style whether it sits under a warning
// tile, the sidebar toggle, the ignition rocker or the starter — which is what
// keeps the whole bar aligned.

struct DashCaption: View {
    let text: String
    var active: Bool = true
    var accentColor: Color = .textPrimary

    var body: some View {
        Text(text)
            .modifier(RetroFont(size: Theme.FontSize.micro))
            .foregroundColor(active ? accentColor : .textFaint)
            .tracking(0.5)
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Dash tile chrome
//
// One flat tile used by every small top-bar control — no chrome metal bezel.
// Two styles:
//   • .lamp   — a status warning light. The frame is the light's OWN colour
//               (dim when off, bright + glowing when active), so a check-engine
//               tile reads as a yellow-rimmed lamp rather than a chrome box.
//   • .button — an action button (sidebar toggle, workspace tools, shift). A
//               flat dark face with a quiet neutral hairline; the active /
//               armed state shows through the glyph + caption colour and a soft
//               accent fill, never a coloured outline.

enum DashTileStyle { case lamp, button }

private struct DashTileChrome<Glyph: View>: View {
    let label: String
    let active: Bool
    let accent: Color
    /// Non-nil makes the tile a button (e.g. CLUTCH / DYNO toggles on iOS).
    let onTap: (() -> Void)?
    /// Haptic flavor for the tap. Toggles use a light tap; gear shifts pass
    /// `.firm` for a more consequential feel.
    var hapticKind: HapticTap = .light
    /// Bezel width. Defaults to a square footprint so every control in the bar
    /// shares the same size; callers can widen without changing the height.
    var width: CGFloat = Theme.Bar.bezel
    var style: DashTileStyle = .lamp
    /// An armed workspace tool — tints the face + caption in the accent.
    var armed: Bool = false
    /// A small unsaved-changes dot in the corner (the SAVE tool).
    var dirtyDot: Bool = false
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        Group {
            if let onTap = onTap {
                Button(action: { HapticManager.shared.tap(hapticKind); onTap() }) { tileContent }
                    .buttonStyle(.plain)
            } else {
                tileContent
            }
        }
        .contentShape(Rectangle())
    }

    private var tileContent: some View {
        VStack(spacing: Theme.Bar.captionGap) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(faceFill)

                // Lit lamp: a soft colour wash behind the glyph.
                if style == .lamp && active {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .fill(accent.opacity(0.16))
                        .blur(radius: 4)
                }

                glyph()
                    .frame(width: glyphSize, height: glyphSize)
                    .shadow(color: (style == .lamp && active) ? accent.opacity(0.7) : .clear,
                            radius: 5)

                if dirtyDot {
                    Circle()
                        .fill(Color.accentLive)
                        .frame(width: 5, height: 5)
                        .shadow(color: Color.accentLive.opacity(0.7), radius: 3)
                        .offset(x: width / 2 - 8, y: -Theme.Bar.bezel / 2 + 8)
                }
            }
            .frame(width: width, height: Theme.Bar.bezel)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .stroke(borderColor, lineWidth: borderWidth)
            )

            DashCaption(text: label, active: active || armed, accentColor: captionColor)
        }
    }

    private var glyphSize: CGFloat { Theme.Bar.bezel * 0.46 }
    private var isClickable: Bool { onTap != nil }

    private var faceFill: Color {
        switch style {
        case .lamp:
            // A passive gauge-cluster light has no housing — just the backlit
            // glyph. A tappable lamp gets a dark recessed face so it reads as
            // a pressable control.
            guard isClickable else { return .clear }
            return Color.black.opacity(active ? 0.25 : 0.5)
        case .button:
            // Armed → soft accent fill; otherwise a quiet raised face that
            // lifts a touch when active (hover / pressed).
            if armed { return accent.opacity(0.16) }
            return Color.white.opacity(active ? 0.10 : 0.05)
        }
    }

    // Tappable lamps wear their own colour as a frame so they read as pressable.
    // Passive cluster lights have no frame at all; buttons get a quiet neutral
    // hairline, never a coloured outline.
    private var borderColor: Color {
        switch style {
        case .lamp:
            guard isClickable else { return .clear }
            return accent.opacity(active ? 0.9 : 0.4)
        case .button:
            return Color.white.opacity(0.10)
        }
    }

    private var borderWidth: CGFloat {
        style == .lamp && isClickable && active ? Theme.Stroke.medium : Theme.Stroke.thin
    }

    private var captionColor: Color {
        armed ? accent : .textPrimary
    }
}

/// Shape-glyph dash light (battery, gear, lock, etc.).
private struct DashWarningTile<Icon: Shape>: View {
    let label: String
    let active: Bool
    let accent: Color
    let icon: Icon
    let onTap: (() -> Void)?

    init(label: String,
         active: Bool,
         accent: Color,
         onTap: (() -> Void)? = nil,
         @ViewBuilder icon: () -> Icon) {
        self.label = label
        self.active = active
        self.accent = accent
        self.onTap = onTap
        self.icon = icon()
    }

    var body: some View {
        DashTileChrome(label: label, active: active, accent: accent, onTap: onTap) {
            icon
                .stroke(iconColor, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                .background(icon.fill(iconColor.opacity(active ? 0.25 : 0.06)))
        }
    }

    private var iconColor: Color { active ? accent : accent.opacity(0.25) }
}

/// PNG-glyph dash light. Renders an asset-catalog image as a tintable
/// template so the warning icons (check engine, oil, coolant, clutch) match
/// the hand-drawn lights' on/off colour behaviour. `flashing` pulses the
/// glyph while active — used for catastrophic check-engine faults.
// Internal so the onboarding tutorial reuses the real CLUTCH dash tile.
struct DashImageWarningTile: View {
    let label: String
    let active: Bool
    let accent: Color
    let imageName: String
    let flashing: Bool
    let onTap: (() -> Void)?

    @State private var flashDimmed = false

    init(label: String,
         active: Bool,
         accent: Color,
         imageName: String,
         flashing: Bool = false,
         onTap: (() -> Void)? = nil) {
        self.label = label
        self.active = active
        self.accent = accent
        self.imageName = imageName
        self.flashing = flashing
        self.onTap = onTap
    }

    var body: some View {
        DashTileChrome(label: label, active: active, accent: accent, onTap: onTap) {
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(iconColor)
                .opacity(active && flashing && flashDimmed ? 0.2 : 1.0)
        }
        .onChange(of: shouldFlash) { _, flash in updateFlash(flash) }
        .onAppear { updateFlash(shouldFlash) }
    }

    private var iconColor: Color { active ? accent : accent.opacity(0.25) }
    private var shouldFlash: Bool { active && flashing }

    private func updateFlash(_ flash: Bool) {
        if flash {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                flashDimmed = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { flashDimmed = false }
        }
    }
}

// MARK: - iOS quick controls
//
// Pulled into the top bar on iOS so users always have throttle + shifting
// reachable without a hardware keyboard. Styling stays in the same family
// as the rest of the dash chrome.

#if !os(macOS)

private let topBarSliderHeight: CGFloat = 28
private let topBarSliderHandleWidth: CGFloat = 18
private let topBarSliderTrackColor = Color.white.opacity(0.07)
private let topBarSliderTrackBorder = Color.strokeStrong
private let topBarSliderFillColor = Color.accentLive.opacity(0.4)
private let topBarSliderHandleFill = Color(white: 0.20)
private let topBarSliderHandleBorder = Color.white.opacity(0.45)
private let topBarSliderLabelColor = Color.white.opacity(0.55)
private let topBarSliderValueColor = Color.accentLive

// Internal so the onboarding tutorial reuses the real throttle slider rather
// than a lookalike.
struct TopBarThrottleSlider: View {
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text("THROTTLE")
                    .modifier(RetroFont(size: Theme.FontSize.caption, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(topBarSliderLabelColor)
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .modifier(RetroFont(size: Theme.FontSize.footnote, weight: .bold))
                    .foregroundColor(topBarSliderValueColor)
            }

            GeometryReader { geo in
                let trackWidth = geo.size.width - topBarSliderHandleWidth
                let x = trackWidth * CGFloat(value)

                ZStack(alignment: .leading) {
                    Rectangle().fill(topBarSliderTrackColor)
                    Rectangle()
                        .fill(topBarSliderFillColor)
                        .frame(width: x + topBarSliderHandleWidth / 2)
                    Rectangle()
                        .fill(topBarSliderHandleFill)
                        .frame(width: topBarSliderHandleWidth)
                        .overlay(Rectangle().stroke(topBarSliderHandleBorder, lineWidth: 1))
                        .offset(x: x)
                }
                .overlay(Rectangle().stroke(topBarSliderTrackBorder, lineWidth: 1))
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let pct = (drag.location.x - topBarSliderHandleWidth / 2) / trackWidth
                    value = min(max(0, Double(pct)), 1)
                })
            }
            .frame(height: topBarSliderHeight)
        }
    }
}

private let topBarGearReadoutWidth: CGFloat = 56

private struct TopBarGearReadout: View {
    let gear: Int
    let gearCount: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("GEAR")
                .modifier(RetroFont(size: Theme.FontSize.caption, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.55))
            Text(gear == -1 ? "N" : "\(gear + 1)")
                .modifier(RetroFont(size: Theme.FontSize.readout, weight: .black))
                .foregroundColor(gear == -1 ? .accentOk : .accentLive)
                .shadow(color: (gear == -1 ? Color.accentOk : Color.accentLive).opacity(0.5), radius: 3)
            Text("\(gearCount)-SPD")
                .modifier(RetroFont(size: Theme.FontSize.micro, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(width: topBarGearReadoutWidth)
    }
}

private enum TopBarShiftDirection {
    case up, down

    var symbol: String {
        switch self {
        case .up:   return "arrow.up"
        case .down: return "arrow.down"
        }
    }

    var label: String {
        switch self {
        case .up:   return "SHIFT UP"
        case .down: return "SHIFT DN"
        }
    }
}

// Shift up / down on iOS, built on the shared DashTileChrome so they're the
// same bezel + caption as the ignition, starter and warning tiles instead of
// the flat rounded rectangles they used to be. A brief press lights the
// accent so the shift registers.
private struct TopBarShiftButton: View {
    let direction: TopBarShiftDirection
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        DashTileChrome(label: direction.label,
                       active: pressed,
                       accent: .accentLive,
                       onTap: action,
                       hapticKind: .firm,
                       style: .button) {
            Image(systemName: direction.symbol)
                .font(.system(size: Theme.Bar.bezel * 0.34, weight: .bold))
                .foregroundColor(pressed ? .accentLive : .white.opacity(0.8))
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

#endif
