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

    // Driver tools
    case shiftLight = "Shift Light"
    case zeroToSixtyTimer = "0-60 Timer"

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
}
