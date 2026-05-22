//
//  BuiltInLayouts.swift
//  engine-simulator
//
//  Layouts that ship with the app. They are constructed entirely in code so
//  they're guaranteed to be present on every install (no first-launch
//  seeding from a bundle resource needed), and they cannot be deleted —
//  the sidebar hides the trash for `isBuiltIn` layouts and `TileStore`
//  refuses to delete them.
//
//  Layout sizes are *initial* hints. `NSSplitView` rescales children to fit
//  the actual window on first load, so the ratios are what matter — not the
//  absolute pixel values. The reference frame used here is 1600 × 1000.
//

import Foundation
import SwiftUI

// MARK: - Stable IDs

/// Stable UUIDs so `activeLayoutId` round-trips correctly between launches.
/// Tile UUIDs inside `rootData` are generated fresh per build because
/// `TileData` is a value type — copying it into a new tree per load
/// produces independent view-model state.
private enum BuiltInLayoutId {
    static let `default` = UUID(uuidString: "0F1E1100-0000-0000-0000-000000000001")!
    static let cockpit   = UUID(uuidString: "0F1E1100-0000-0000-0000-000000000002")!
    static let tuner     = UUID(uuidString: "0F1E1100-0000-0000-0000-000000000003")!
    static let track     = UUID(uuidString: "0F1E1100-0000-0000-0000-000000000004")!
    // 0F1E1100-...-000000000005 was the retired "Diagnostics" layout; its
    // scopes were folded into Tuner. The new ID below is intentionally
    // different so persisted state pointing at the old layout still falls
    // back to Default instead of silently mapping into the new one.
    static let diagnostic = UUID(uuidString: "0F1E1100-0000-0000-0000-000000000006")!
}

// MARK: - Construction helpers

private enum BuiltInBuilder {
    /// A single-tile node (no children, no split direction).
    static func leaf(_ type: TileType, size: CGSize? = nil) -> TileData {
        var d = TileData(id: UUID(), type: type)
        d.persistantChildren = []
        d.size = size
        return d
    }

    /// A split node. The parent's `type` field is cosmetic (carried over
    /// from the first child to match what `TileStore.syncModelData` writes
    /// when the user saves a layout by hand).
    static func split(_ direction: SplitDirection,
                      _ children: [TileData],
                      size: CGSize? = nil) -> TileData {
        precondition(!children.isEmpty, "Split node needs at least one child")
        var d = TileData(id: UUID(), type: children[0].type)
        d.splitDirection = direction
        d.persistantChildren = children
        d.size = size
        return d
    }
}

// MARK: - The layouts

enum BuiltInLayouts {
    static let all: [TileLayout] = [
        defaultLayout,
        cockpit,
        tuner,
        track,
        diagnostic,
    ]

    /// Loads on app launch. Engine 3D dominates with a slim right column
    /// holding Engine Controls (where the user starts the engine) and a
    /// big RPM gauge.
    static let defaultLayout: TileLayout = TileLayout(
        id: BuiltInLayoutId.default,
        name: "Default",
        rootData: BuiltInBuilder.split(.horizontal, [
            BuiltInBuilder.leaf(.engine3DProcedural,
                                size: CGSize(width: 1080, height: 1000)),
            BuiltInBuilder.split(.vertical, [
                BuiltInBuilder.leaf(.engineControls,
                                    size: CGSize(width: 520, height: 620)),
                BuiltInBuilder.leaf(.rpmGauge,
                                    size: CGSize(width: 520, height: 380)),
            ], size: CGSize(width: 520, height: 1000)),
        ]),
        isBuiltIn: true
    )

    /// Engine 3D + Engine Controls stacked on the left, six gauges plus
    /// two key scopes (Dyno + Flow) in a 2×4 grid on the right. The two
    /// niche-while-driving gauges from the previous iteration (Exhaust O2,
    /// Cylinder Pressure) are dropped — their slots become a scope row at
    /// the bottom so the user gets both glance values *and* live curves.
    static let cockpit: TileLayout = TileLayout(
        id: BuiltInLayoutId.cockpit,
        name: "Cockpit",
        rootData: cockpitRoot,
        isBuiltIn: true
    )

    /// macOS Cockpit: the original 3D-over-controls + 8-gauge grid.
    /// iOS Cockpit: 3D engine takes the bulk of the left column (it's the
    /// star of the cockpit), shifter is shorter underneath. On the right
    /// the two intake/AFR gauges are replaced by the clutch + intake
    /// cross-section drawings so the user can see what their right thumb
    /// is doing on the throttle slider.
    private static var cockpitRoot: TileData {
        #if os(macOS)
        return BuiltInBuilder.split(.horizontal, [
            BuiltInBuilder.split(.vertical, [
                BuiltInBuilder.leaf(.engine3DProcedural,
                                    size: CGSize(width: 680, height: 400)),
                BuiltInBuilder.leaf(.engineControls,
                                    size: CGSize(width: 680, height: 600)),
            ], size: CGSize(width: 680, height: 1000)),
            BuiltInBuilder.split(.horizontal, [
                BuiltInBuilder.split(.vertical, [
                    BuiltInBuilder.leaf(.rpmGauge,                  size: CGSize(width: 460, height: 250)),
                    BuiltInBuilder.leaf(.manifoldPressureGauge,     size: CGSize(width: 460, height: 250)),
                    BuiltInBuilder.leaf(.intakeAfrGauge,            size: CGSize(width: 460, height: 250)),
                    BuiltInBuilder.leaf(.dynoOscilloscope,          size: CGSize(width: 460, height: 250)),
                ], size: CGSize(width: 460, height: 1000)),
                BuiltInBuilder.split(.vertical, [
                    BuiltInBuilder.leaf(.speedometerGauge,          size: CGSize(width: 460, height: 250)),
                    BuiltInBuilder.leaf(.volumetricEfficiencyGauge, size: CGSize(width: 460, height: 250)),
                    BuiltInBuilder.leaf(.airScfmGauge,              size: CGSize(width: 460, height: 250)),
                    BuiltInBuilder.leaf(.flowOscilloscope,          size: CGSize(width: 460, height: 250)),
                ], size: CGSize(width: 460, height: 1000)),
            ], size: CGSize(width: 920, height: 1000)),
        ])
        #else
        return BuiltInBuilder.split(.horizontal, [
            BuiltInBuilder.split(.vertical, [
                BuiltInBuilder.leaf(.engine3DProcedural,
                                    size: CGSize(width: 680, height: 580)),
                BuiltInBuilder.leaf(.engineControls,
                                    size: CGSize(width: 680, height: 420)),
            ], size: CGSize(width: 680, height: 1000)),
            BuiltInBuilder.split(.horizontal, [
                BuiltInBuilder.split(.vertical, [
                    BuiltInBuilder.leaf(.rpmGauge,                  size: CGSize(width: 460, height: 250)),
                    BuiltInBuilder.leaf(.manifoldPressureGauge,     size: CGSize(width: 460, height: 250)),
                    BuiltInBuilder.leaf(.clutchPanel,               size: CGSize(width: 460, height: 250)),
                    BuiltInBuilder.leaf(.dynoOscilloscope,          size: CGSize(width: 460, height: 250)),
                ], size: CGSize(width: 460, height: 1000)),
                BuiltInBuilder.split(.vertical, [
                    BuiltInBuilder.leaf(.speedometerGauge,          size: CGSize(width: 460, height: 250)),
                    BuiltInBuilder.leaf(.volumetricEfficiencyGauge, size: CGSize(width: 460, height: 250)),
                    BuiltInBuilder.leaf(.intakePanel,               size: CGSize(width: 460, height: 250)),
                    BuiltInBuilder.leaf(.flowOscilloscope,          size: CGSize(width: 460, height: 250)),
                ], size: CGSize(width: 460, height: 1000)),
            ], size: CGSize(width: 920, height: 1000)),
        ])
        #endif
    }

    /// The single tuning workbench. Left column = ECU Tuning + Engine 3D
    /// reference. Right column = three stacked rows of paired panels that
    /// progress top-to-bottom from "what the tune produces" → "how the
    /// burn looks" → "what the engine is doing right now":
    ///
    ///   • Dyno + Spark Advance   — torque/power result vs. timing curve
    ///   • Cyl Pressure + PV      — combustion shape & cycle efficiency
    ///   • Intake AFR + Manifold  — live driving response
    ///
    /// PV and Cylinder Pressure Scope folded in from the old standalone
    /// Diagnostics layout; the remaining niche scopes (Cyl Molecules,
    /// Valve Lift) weren't pulling enough weight to justify their own
    /// sidebar entry. Users who want them can still build a custom
    /// scope-grid workspace and save it from the top bar.
    static let tuner: TileLayout = TileLayout(
        id: BuiltInLayoutId.tuner,
        name: "Tuner",
        rootData: BuiltInBuilder.split(.horizontal, [
            tunerLeftColumn,
            BuiltInBuilder.split(.vertical, [
                BuiltInBuilder.split(.horizontal, [
                    BuiltInBuilder.leaf(.dynoOscilloscope,
                                        size: CGSize(width: 440, height: 333)),
                    BuiltInBuilder.leaf(.sparkAdvanceOscilloscope,
                                        size: CGSize(width: 440, height: 333)),
                ], size: CGSize(width: 880, height: 333)),
                BuiltInBuilder.split(.horizontal, [
                    BuiltInBuilder.leaf(.cylinderPressureOscilloscope,
                                        size: CGSize(width: 440, height: 334)),
                    BuiltInBuilder.leaf(.pvOscilloscope,
                                        size: CGSize(width: 440, height: 334)),
                ], size: CGSize(width: 880, height: 334)),
                BuiltInBuilder.split(.horizontal, [
                    BuiltInBuilder.leaf(.intakeAfrGauge,
                                        size: CGSize(width: 440, height: 333)),
                    BuiltInBuilder.leaf(.manifoldPressureGauge,
                                        size: CGSize(width: 440, height: 333)),
                ], size: CGSize(width: 880, height: 333)),
            ], size: CGSize(width: 880, height: 1000)),
        ]),
        isBuiltIn: true
    )

    /// Left column of the Tuner layout. macOS includes a small live 3D
    /// preview under the ECU map; iOS drops it so the ECU map gets the
    /// full column height (3D in a corner tile is too cramped on iPad).
    private static var tunerLeftColumn: TileData {
        #if os(macOS)
        BuiltInBuilder.split(.vertical, [
            BuiltInBuilder.leaf(.ecuTuning,
                                size: CGSize(width: 720, height: 720)),
            BuiltInBuilder.leaf(.engine3DProcedural,
                                size: CGSize(width: 720, height: 280)),
        ], size: CGSize(width: 720, height: 1000))
        #else
        // Wider on iOS so the heatmap + paint pills fit without clipping;
        // the scope grid on the right keeps its weight via the matching
        // 880 split, but the proportional sizing now favors the ECU side.
        BuiltInBuilder.leaf(.ecuTuning,
                            size: CGSize(width: 1100, height: 1000))
        #endif
    }

    /// Driver's seat. Shift light spans the top. Engine Controls take a
    /// narrow portrait column on the left (where it actually fits — the
    /// previous bottom-row placement squashed it horizontally). Engine 3D
    /// fills the middle; Speedometer / RPM / 0-60 Timer stack vertically
    /// on the right so the timer panel keeps room for its chips & buttons.
    static let track: TileLayout = TileLayout(
        id: BuiltInLayoutId.track,
        name: "Track",
        rootData: trackRoot,
        isBuiltIn: true
    )

    /// macOS keeps the engineControls (shifter + throttle/clutch combined)
    /// in the left column; iOS splits them so the throttle/clutch drawings
    /// can live under the 3D engine instead of crowding the shifter, and
    /// the 0-60 timer can sit directly under the shifter where the user
    /// actually looks for it on a track run.
    private static var trackRoot: TileData {
        #if os(macOS)
        return BuiltInBuilder.split(.vertical, [
            BuiltInBuilder.leaf(.shiftLight,
                                size: CGSize(width: 1600, height: 140)),
            BuiltInBuilder.split(.horizontal, [
                BuiltInBuilder.leaf(.engineControls,
                                    size: CGSize(width: 360, height: 860)),
                BuiltInBuilder.leaf(.engine3DProcedural,
                                    size: CGSize(width: 820, height: 860)),
                BuiltInBuilder.split(.vertical, [
                    BuiltInBuilder.leaf(.speedometerGauge,
                                        size: CGSize(width: 420, height: 280)),
                    BuiltInBuilder.leaf(.rpmGauge,
                                        size: CGSize(width: 420, height: 280)),
                    BuiltInBuilder.leaf(.zeroToSixtyTimer,
                                        size: CGSize(width: 420, height: 300)),
                ], size: CGSize(width: 420, height: 860)),
            ], size: CGSize(width: 1600, height: 860)),
        ])
        #else
        return BuiltInBuilder.split(.vertical, [
            BuiltInBuilder.leaf(.shiftLight,
                                size: CGSize(width: 1600, height: 140)),
            BuiltInBuilder.split(.horizontal, [
                // Left: 0-60 timer on top, H-shifter below. Timer first
                // because it was being clipped at the bottom by the home
                // indicator + bottom safe area when placed in the bottom
                // half; moving it above sidesteps that entirely.
                BuiltInBuilder.split(.vertical, [
                    BuiltInBuilder.leaf(.zeroToSixtyTimer,
                                        size: CGSize(width: 360, height: 420)),
                    BuiltInBuilder.leaf(.engineControls,
                                        size: CGSize(width: 360, height: 440)),
                ], size: CGSize(width: 360, height: 860)),
                // Middle: 3D engine on top, clutch + intake drawings under.
                BuiltInBuilder.split(.vertical, [
                    BuiltInBuilder.leaf(.engine3DProcedural,
                                        size: CGSize(width: 820, height: 560)),
                    BuiltInBuilder.leaf(.clutchIntake,
                                        size: CGSize(width: 820, height: 300)),
                ], size: CGSize(width: 820, height: 860)),
                // Right: speedo + rpm gauges, no timer (it moved left).
                BuiltInBuilder.split(.vertical, [
                    BuiltInBuilder.leaf(.speedometerGauge,
                                        size: CGSize(width: 420, height: 430)),
                    BuiltInBuilder.leaf(.rpmGauge,
                                        size: CGSize(width: 420, height: 430)),
                ], size: CGSize(width: 420, height: 860)),
            ], size: CGSize(width: 1600, height: 860)),
        ])
        #endif
    }

    /// Diagnostic bench. The wireframe engine is the visual reference for
    /// what's failing, alongside the component-level damage state, the
    /// per-cylinder ignition/fuel cut switches, and the live OBD-II codes.
    static let diagnostic: TileLayout = TileLayout(
        id: BuiltInLayoutId.diagnostic,
        name: "Diagnostic",
        rootData: diagnosticRoot,
        isBuiltIn: true
    )

    /// macOS: wireframe on the left; the right column stacks Engine Health,
    /// the Cylinder Control switch row, then the OBD-II scanner.
    /// iOS / iPad: wireframe on top with the short Cylinder Control row
    /// directly beneath it; Engine Health + OBD-II share the right column.
    private static var diagnosticRoot: TileData {
        #if os(macOS)
        return BuiltInBuilder.split(.horizontal, [
            BuiltInBuilder.leaf(.engine3DWireframe,
                                size: CGSize(width: 880, height: 1000)),
            BuiltInBuilder.split(.vertical, [
                BuiltInBuilder.leaf(.engineHealth,
                                    size: CGSize(width: 720, height: 560)),
                BuiltInBuilder.leaf(.cylinderControl,
                                    size: CGSize(width: 720, height: 150)),
                BuiltInBuilder.leaf(.obd2,
                                    size: CGSize(width: 720, height: 290)),
            ], size: CGSize(width: 720, height: 1000)),
        ])
        #else
        return BuiltInBuilder.split(.horizontal, [
            BuiltInBuilder.split(.vertical, [
                BuiltInBuilder.leaf(.engine3DWireframe,
                                    size: CGSize(width: 880, height: 780)),
                BuiltInBuilder.leaf(.cylinderControl,
                                    size: CGSize(width: 880, height: 220)),
            ], size: CGSize(width: 880, height: 1000)),
            BuiltInBuilder.split(.vertical, [
                BuiltInBuilder.leaf(.engineHealth,
                                    size: CGSize(width: 720, height: 600)),
                BuiltInBuilder.leaf(.obd2,
                                    size: CGSize(width: 720, height: 400)),
            ], size: CGSize(width: 720, height: 1000)),
        ])
        #endif
    }

}
