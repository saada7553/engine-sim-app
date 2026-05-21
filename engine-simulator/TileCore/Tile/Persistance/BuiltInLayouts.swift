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
    // scopes were folded into Tuner. Any persisted activeLayoutId pointing
    // at it will fail the lookup and fall back to Default on next launch.
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
        rootData: BuiltInBuilder.split(.horizontal, [
            BuiltInBuilder.split(.vertical, [
                BuiltInBuilder.leaf(.engine3DProcedural,
                                    size: CGSize(width: 680, height: 520)),
                BuiltInBuilder.leaf(.engineControls,
                                    size: CGSize(width: 680, height: 480)),
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
        ]),
        isBuiltIn: true
    )

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
            BuiltInBuilder.split(.vertical, [
                BuiltInBuilder.leaf(.ecuTuning,
                                    size: CGSize(width: 720, height: 720)),
                BuiltInBuilder.leaf(.engine3DProcedural,
                                    size: CGSize(width: 720, height: 280)),
            ], size: CGSize(width: 720, height: 1000)),
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

    /// Driver's seat. Shift light spans the top. Engine Controls take a
    /// narrow portrait column on the left (where it actually fits — the
    /// previous bottom-row placement squashed it horizontally). Engine 3D
    /// fills the middle; Speedometer / RPM / 0-60 Timer stack vertically
    /// on the right so the timer panel keeps room for its chips & buttons.
    static let track: TileLayout = TileLayout(
        id: BuiltInLayoutId.track,
        name: "Track",
        rootData: BuiltInBuilder.split(.vertical, [
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
        ]),
        isBuiltIn: true
    )

}
