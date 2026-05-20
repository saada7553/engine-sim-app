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

// MARK: - Top Bar

struct CustomTopBar: View {
    @ObservedObject var vm: EngineViewModel
    @Binding var browserMode: BrowserMode
    let isLayoutDirty: Bool
    let onToggleSplit: () -> Void
    let onToggleDelete: () -> Void
    let onSaveLayout: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            leftCluster
                .padding(.leading, 18)

            Spacer()

            rightCluster
                .padding(.trailing, 18)
        }
        .frame(height: 86)
        .background(topBarBackground)
        .border(Color.white.opacity(0.12), width: 1, edges: [.bottom])
    }

    // MARK: Left — controls

    private var leftCluster: some View {
        HStack(spacing: 22) {
            Button(action: { SidebarManager.shared.toggleSidebar() }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 17, weight: .light))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.05))
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle Sidebar")

            WorkspaceToolCluster(
                browserMode: browserMode,
                isLayoutDirty: isLayoutDirty,
                onToggleSplit: onToggleSplit,
                onToggleDelete: onToggleDelete,
                onSaveLayout: onSaveLayout
            )

            ArmedIgnitionSwitch(isOn: vm.isIgnitionOn) { vm.toggleIgnition() }

            StarterButton(running: vm.isStarterOn) {
                vm.toggleStarter()
            }
        }
    }

    // MARK: Right — warning-light cluster

    private var rightCluster: some View {
        HStack(spacing: 8) {
            DashWarningTile(label: "IGN",   active: vm.isIgnitionOn,    accent: .red)    { IgnitionIcon() }
            DashWarningTile(label: "CRANK", active: vm.isStarterOn,     accent: .green)  { StarterIcon() }
            DashWarningTile(label: "CLUTCH", active: vm.clutchPressed,  accent: .blue)   { ClutchIcon() }
            DashWarningTile(label: "DYNO",  active: vm.dynoEnabled,     accent: .orange) { DynoIcon() }
            DashWarningTile(label: "HOLD",  active: vm.throttleHeld,    accent: .yellow) { HoldIcon() }
        }
    }

    private var topBarBackground: some View {
        ZStack {
            Color.appBackground
            LinearGradient(colors: [Color.white.opacity(0.04), Color.clear],
                           startPoint: .top, endPoint: .bottom)
            // Faint scan lines for instrument-panel texture.
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Color.white.opacity(0.015).frame(height: 1)
                    Spacer().frame(height: 28)
                }
            }
        }
    }
}

// MARK: - Workspace tool cluster
//
// Pill icons for adding / removing / saving tiles. Each button doubles as
// its own state indicator: when a mode is active the icon swaps for an
// "armed" variant, the label flips to "ARMED · CLICK A TILE", and the
// border pulses softly so the user knows the next click acts on the
// workspace. Tooltips spell out the full action on hover.

private struct WorkspaceToolCluster: View {
    let browserMode: BrowserMode
    let isLayoutDirty: Bool
    let onToggleSplit: () -> Void
    let onToggleDelete: () -> Void
    let onSaveLayout: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            WorkspaceToolButton(
                idleIcon: "rectangle.split.2x1",
                activeIcon: "plus.rectangle.on.rectangle",
                idleLabel: "ADD TILE",
                activeLabel: "PICK AN EDGE",
                tooltip: "Add Tile  (⌘T)\nClick an edge of any tile — a new tile spawns on that side.",
                isArmed: browserMode == .split,
                accent: .orange,
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
                accent: .red,
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
                accent: .orange,
                dirty: isLayoutDirty,
                action: onSaveLayout
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        )
    }
}

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
    @State private var armedPulse = false

    private var displayIcon: String { isArmed ? activeIcon : idleIcon }
    private var displayLabel: String { isArmed ? activeLabel : idleLabel }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack {
                    Image(systemName: displayIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isArmed ? accent : .white.opacity(hovering ? 0.95 : 0.7))
                        .scaleEffect(isArmed && armedPulse ? 1.08 : 1.0)

                    if dirty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                            .offset(x: 8, y: -8)
                            .shadow(color: Color.orange.opacity(0.7), radius: 3)
                    }
                }
                .frame(width: 26, height: 26)

                Text(displayLabel)
                    .modifier(RetroFont(size: 7))
                    .foregroundColor(isArmed ? accent : .white.opacity(0.45))
                    .tracking(0.6)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(minWidth: 70)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isArmed ? accent.opacity(armedPulse ? 0.28 : 0.18) : (hovering ? Color.white.opacity(0.06) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isArmed ? accent.opacity(armedPulse ? 0.85 : 0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tooltip)
        .onChange(of: isArmed) { _, armed in
            if armed {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    armedPulse = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { armedPulse = false }
            }
        }
    }

}

// MARK: - Ignition switch
//
// Chrome bezel labelled OFF / RUN with a paddle that travels between the
// two positions. A small LED at the base lights red when ignition is on.

private struct ArmedIgnitionSwitch: View {
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text("IGNITION")
                .modifier(RetroFont(size: 8))
                .foregroundColor(.gray)

            Button(action: toggle) {
                ZStack {
                    bezel

                    // OFF / RUN side labels.
                    VStack(spacing: 0) {
                        Text("RUN").modifier(RetroFont(size: 6))
                            .foregroundColor(isOn ? .red.opacity(0.95) : .white.opacity(0.35))
                            .frame(maxHeight: .infinity)
                        Text("OFF").modifier(RetroFont(size: 6))
                            .foregroundColor(!isOn ? .white.opacity(0.85) : .white.opacity(0.25))
                            .frame(maxHeight: .infinity)
                    }
                    .padding(.vertical, 2)
                    .frame(width: 22)
                    .offset(x: -18)

                    paddle
                        .offset(y: isOn ? -10 : 10)

                    // Armed LED at the bottom of the bezel.
                    Circle()
                        .fill(isOn ? Color.red : Color.red.opacity(0.18))
                        .frame(width: 4, height: 4)
                        .shadow(color: isOn ? .red.opacity(0.9) : .clear, radius: 3)
                        .offset(x: 14, y: 22)
                }
                .frame(width: 64, height: 54)
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.32, dampingFraction: 0.55), value: isOn)
        }
    }

    private var bezel: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.45), Color.black.opacity(0.7)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1)
            )
            .overlay(
                // Inset recess where the paddle travels.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 18, height: 38)
            )
            .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 2)
    }

    private var paddle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.22)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 14, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.55), Color.clear],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.7), radius: 1.5,
                        x: 0, y: isOn ? -1 : 1)

            // Pivot dimple at the centre of the paddle.
            Circle()
                .fill(isOn ? Color.red : Color.gray.opacity(0.5))
                .frame(width: 3.5, height: 3.5)
                .shadow(color: isOn ? .red.opacity(0.9) : .clear, radius: 2)
        }
    }
}

// MARK: - Starter button
//
// Chunky illuminated push button labelled STARTER. Always pressable — works
// independently of the ignition switch (you can crank the engine over with
// ignition off; it just won't fire). Lights up red whenever the starter is
// engaged, with a pulsing halo to communicate the cranking motor.

private struct StarterButton: View {
    let running: Bool
    let action: () -> Void

    @State private var pressing = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 4) {
            Text("STARTER")
                .modifier(RetroFont(size: 8))
                .foregroundColor(.gray)

            Button(action: action) {
                ZStack {
                    bezel

                    // Inset shadow ring.
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 44, height: 44)

                    // Illuminated face.
                    Circle()
                        .fill(faceGradient)
                        .frame(width: 42, height: 42)
                        .overlay(
                            // Fine concentric machining ring.
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                .padding(4)
                        )
                        .overlay(haloRing)

                    Text("CRANK")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                }
                .frame(width: 56, height: 56)
                .shadow(color: Color.red.opacity(running ? 0.6 : 0.30),
                        radius: running ? 10 : 4, x: 0, y: pressing ? 0 : 3)
                .scaleEffect(pressing ? 0.94 : 1.0)
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { p in
                pressing = p
            }, perform: {})
            .animation(.interactiveSpring(), value: pressing)
            .onAppear {
                // Pulsing glow while cranking.
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse.toggle()
                }
            }
        }
    }

    private var bezel: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.14)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 52, height: 52)
            .overlay(
                Circle().stroke(
                    LinearGradient(colors: [Color.white.opacity(0.55), Color.black.opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
            )
    }

    private var faceGradient: RadialGradient {
        // Always lit — dimmer at rest, brighter when cranking.
        let warmCore: Color
        let darkRim: Color
        if running {
            warmCore = Color(red: 1.00, green: 0.18, blue: 0.18)
            darkRim = Color(red: 0.45, green: 0.05, blue: 0.05)
        } else {
            warmCore = Color(red: 0.78, green: 0.10, blue: 0.10)
            darkRim = Color(red: 0.20, green: 0.02, blue: 0.02)
        }
        return RadialGradient(colors: [warmCore, darkRim],
                              center: .center, startRadius: 0, endRadius: 22)
    }

    @ViewBuilder private var haloRing: some View {
        Circle()
            .stroke(Color.red.opacity(running ? (pulse ? 0.95 : 0.55) : 0.55),
                    lineWidth: running ? 2.2 : 1.4)
            .blur(radius: running ? 3 : 1.5)
    }
}

// MARK: - Dashboard warning tile

private struct DashWarningTile<Icon: Shape>: View {
    let label: String
    let active: Bool
    let accent: Color
    let icon: Icon

    init(label: String, active: Bool, accent: Color, @ViewBuilder icon: () -> Icon) {
        self.label = label
        self.active = active
        self.accent = accent
        self.icon = icon()
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                // Bezel.
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.06)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 1.5, x: 0, y: 1)

                // Inner recessed face.
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(active ? 0.35 : 0.55))
                    .padding(3)

                // Active halo.
                if active {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accent.opacity(0.18))
                        .padding(3)
                        .blur(radius: 4)
                }

                icon
                    .stroke(iconColor, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                    .background(icon.fill(iconColor.opacity(active ? 0.25 : 0.06)))
                    .frame(width: 22, height: 22)
                    .shadow(color: active ? accent.opacity(0.7) : .clear, radius: 5)
            }
            .frame(width: 40, height: 36)

            Text(label)
                .modifier(RetroFont(size: 7))
                .foregroundColor(active ? .white : .white.opacity(0.35))
                .tracking(0.5)
        }
        .frame(width: 44)
    }

    private var iconColor: Color {
        active ? accent : accent.opacity(0.25)
    }
}
