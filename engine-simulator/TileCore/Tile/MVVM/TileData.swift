//
//  Tile.swift
//  TileSurf
//
//  Created by Saad Ata on 11/25/25.
//

import Foundation
import SwiftUI

struct TileData: Codable, Identifiable, Equatable {
    var id: UUID
    var splitDirection: SplitDirection?
    var size: CGSize?
    var type: TileType
    
    /// Only used for saving / retriving tile structure to / from disk.
    var persistantChildren: [TileData]?
    
    static func == (lhs: TileData, rhs: TileData) -> Bool {
        lhs.id == rhs.id
    }
    
    init(id: UUID, type: TileType) {
        self.id = id
        self.type = type
    }
}

enum SplitDirection: Codable {
    case horizontal
    case vertical
}

enum TileType: String, Codable, CaseIterable, Identifiable {
    /// Legacy raw value preserved so layouts saved before the CAD renderer
    /// was removed still decode. Renders the procedural engine view now —
    /// SelectView no longer exposes this option for new tiles.
    case engine3DView = "Engine 3D"
    case engine3DProcedural = "Engine 3D (Procedural)"
    /// Diagnostic presentation of the procedural engine: hidden shells, a
    /// colour-cycling wireframe and a slow turntable. Same renderer as
    /// `engine3DProcedural`, just driven in wireframe mode.
    case engine3DWireframe = "Engine Wireframe"

    /// Hide the deprecated legacy 3D view from the type picker.
    static var pickerCases: [TileType] {
        allCases.filter { $0 != .engine3DView }
    }

    // Gauges
    case speedometerGauge = "Speedometer"
    case rpmGauge = "RPM Gauge"
    case manifoldPressureGauge = "Manifold Pressure"
    case volumetricEfficiencyGauge = "Volumetric Efficiency"
    case airScfmGauge = "Air SCFM"
    case intakeAfrGauge = "Intake AFR"
    case exhaustO2Gauge = "Exhaust O2"
    case cylinderPressureGauge = "Cylinder Pressure"

    // Controls
    case engineControls = "Engine Controls"
    case ecuTuning = "ECU Tuning"
    case cylinderControl = "Cylinder Ignition Control"
    case engineHealth = "Engine Health"
    case obd2 = "OBD-II"
    /// iOS-only: the clutch + intake cross-section drawings, split out of
    /// engineControls so the Track layout can place the shifter and the
    /// drawings in different cells.
    case clutchIntake = "Clutch & Intake"
    /// iOS Cockpit-only: just the clutch cross-section, on its own tile.
    case clutchPanel = "Clutch"
    /// iOS Cockpit-only: just the intake manifold cross-section.
    case intakePanel = "Intake Manifold"

    // Driver tools
    case shiftLight = "Shift Light"
    case zeroToSixtyTimer = "0-60 Timer"

    // Compete
    case leaderboard = "Leaderboard"
    case community = "Community"

    // Oscilloscopes
    case torqueOscilloscope = "Torque Scope"
    case powerOscilloscope = "Power Scope"
    case dynoOscilloscope = "Dyno Scope"
    case sparkAdvanceOscilloscope = "Spark Advance Scope"
    case totalExhaustFlowOscilloscope = "Total Exhaust Flow Scope"
    case exhaustFlowOscilloscope = "Exhaust Flow Scope"
    case intakeFlowOscilloscope = "Intake Flow Scope"
    case flowOscilloscope = "Flow Scope"
    case exhaustValveLiftOscilloscope = "Exhaust Valve Lift Scope"
    case intakeValveLiftOscilloscope = "Intake Valve Lift Scope"
    case valveLiftOscilloscope = "Valve Lift Scope"
    case cylinderPressureOscilloscope = "Cylinder Pressure Scope"
    case cylinderMoleculesOscilloscope = "Cylinder Molecules Scope"
    case pvOscilloscope = "PV Scope"
    
    case select = "Select View"
    
    var id: String { rawValue }

    /// User-facing name. Defaults to the raw value, which doubles as the
    /// Codable persistence key — override here when the displayed label
    /// should differ from the stored value.
    var displayName: String {
        switch self {
        case .engine3DProcedural: return "Engine 3D"
        case .engine3DWireframe: return "Diagnostic 3D"
        default: return rawValue
        }
    }
}
