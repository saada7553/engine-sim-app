//
//  OBD2CodeService.swift
//  engine-simulator
//
//  Derives the active diagnostic-trouble-code list from the current
//  engine state. Pure / live-status semantics: at every redraw the
//  service inspects EngineViewModel's published health & thermal
//  fields and returns the codes that *would* be active right now if a
//  real scanner were plugged in. No persistence, no historical
//  log — when a fault condition resolves, its code drops off the list.
//
//  Code numbers are curated for plausibility, not full SAE J2012
//  fidelity. They map cleanly to the underlying damage model so a user
//  who knows what a P0301 means will see the expected code when a
//  cylinder starts misfiring. Manufacturer-specific P13xx ranges are
//  used for damage modes that don't have a clean SAE equivalent
//  (piston wear, rod wear, etc.).
//

import Foundation
import SwiftUI

// MARK: - Models

enum OBD2Severity {
    case warning
    case critical
}

struct OBD2Code: Identifiable, Equatable {
    let id: String          // dedup key — same id never appears twice in one snapshot
    let code: String        // e.g. "P0301"
    let description: String
    let severity: OBD2Severity
}

// MARK: - Service

/// Stateless code-derivation. Called from `OBD2View`'s body so each
/// engine-state update re-derives the active code list.
enum OBD2CodeService {

    static func codes(for vm: EngineViewModel) -> [OBD2Code] {
        var codes: [OBD2Code] = []

        codes.append(contentsOf: thermalCodes(vm: vm))
        codes.append(contentsOf: perCylinderCodes(vm: vm))
        codes.append(contentsOf: engineWideCodes(vm: vm))
        codes.append(contentsOf: knockCodes(vm: vm))

        // Severity then code ordering: critical first, then alphanumeric.
        return codes.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return severityRank(lhs.severity) > severityRank(rhs.severity)
            }
            return lhs.code < rhs.code
        }
    }

    // MARK: - Thermals

    private static func thermalCodes(vm: EngineViewModel) -> [OBD2Code] {
        var out: [OBD2Code] = []

        // Coolant: P0217
        if vm.coolantTempC > 115 {
            out.append(.init(id: "P0217",
                             code: "P0217",
                             description: "Engine Coolant Over Temperature Condition",
                             severity: .critical))
        } else if vm.coolantTempC > 105 {
            out.append(.init(id: "P0217",
                             code: "P0217",
                             description: "Coolant Temperature High",
                             severity: .warning))
        }

        // Oil temp: P0196
        if vm.oilTempC > 120 {
            out.append(.init(id: "P0196",
                             code: "P0196",
                             description: "Engine Oil Temperature High",
                             severity: .critical))
        } else if vm.oilTempC > 105 {
            out.append(.init(id: "P0196",
                             code: "P0196",
                             description: "Engine Oil Temperature Elevated",
                             severity: .warning))
        }

        // Oil pressure: P0521 (warn) / P0524 (critical)
        if vm.oilPressurePsi < 15 {
            out.append(.init(id: "P0524",
                             code: "P0524",
                             description: "Engine Oil Pressure Too Low",
                             severity: .critical))
        } else if vm.oilPressurePsi < 25 {
            out.append(.init(id: "P0521",
                             code: "P0521",
                             description: "Engine Oil Pressure Sensor Performance",
                             severity: .warning))
        }

        return out
    }

    // MARK: - Per-cylinder

    private static func perCylinderCodes(vm: EngineViewModel) -> [OBD2Code] {
        var out: [OBD2Code] = []
        let warn = 0.70
        let crit = 0.30

        for (idx, c) in vm.cylinderHealths.enumerated() {
            let cylNum = idx + 1
            // Cap at 8 because P030X / P130X only go up to 8 cleanly
            // before bumping into other ranges. For high-cyl engines the
            // hex digit (9, A, B, C) still reads as "cylinder X" in
            // scanner UIs.
            let cylDigit = hexDigit(for: cylNum)

            if c.seized {
                out.append(.init(id: "P130\(cylDigit)-SEIZED",
                                 code: "P130\(cylDigit)",
                                 description: "Cylinder \(cylNum) Mechanical Failure / Seized",
                                 severity: .critical))
                continue
            }

            // Misfire family — head gasket, rings, intake valve, exhaust
            // valve all manifest as a misfire on real scanners. Collapse
            // any combination into a single P030X for that cylinder.
            let misfireSources: [(Double, String)] = [
                (c.headGasket,   "Head Gasket"),
                (c.pistonRings,  "Compression Loss"),
                (c.intakeValve,  "Intake Valve"),
                (c.exhaustValve, "Exhaust Valve")
            ]
            let triggered = misfireSources.filter { $0.0 < warn }
            if !triggered.isEmpty {
                let worst = triggered.map { $0.0 }.min() ?? 1.0
                let primaryCause = triggered.min(by: { $0.0 < $1.0 })?.1 ?? "Misfire"
                let severity: OBD2Severity = worst < crit ? .critical : .warning
                out.append(.init(id: "P030\(cylDigit)",
                                 code: "P030\(cylDigit)",
                                 description: "Cylinder \(cylNum) Misfire (\(primaryCause))",
                                 severity: severity))
            }

            // Component-specific codes (separate from misfire group)
            if c.piston < warn {
                out.append(.init(id: "P131\(cylDigit)",
                                 code: "P131\(cylDigit)",
                                 description: "Cylinder \(cylNum) Piston Damage",
                                 severity: c.piston < crit ? .critical : .warning))
            }
            if c.rodBearing < warn {
                out.append(.init(id: "P132\(cylDigit)",
                                 code: "P132\(cylDigit)",
                                 description: "Cylinder \(cylNum) Rod Bearing Wear",
                                 severity: c.rodBearing < crit ? .critical : .warning))
            }
            if c.rod < warn {
                out.append(.init(id: "P133\(cylDigit)",
                                 code: "P133\(cylDigit)",
                                 description: "Cylinder \(cylNum) Connecting Rod Wear",
                                 severity: c.rod < crit ? .critical : .warning))
            }
        }

        return out
    }

    // MARK: - Engine-wide

    private static func engineWideCodes(vm: EngineViewModel) -> [OBD2Code] {
        var out: [OBD2Code] = []
        let warn = 0.70
        let crit = 0.30
        let wide = vm.engineWideHealth

        if wide.cylinderHead < warn {
            out.append(.init(id: "P1100",
                             code: "P1100",
                             description: "Cylinder Head Mechanical Wear",
                             severity: wide.cylinderHead < crit ? .critical : .warning))
        }
        if wide.camshaft < warn {
            out.append(.init(id: "P0340",
                             code: "P0340",
                             description: "Camshaft Position Sensor Circuit Malfunction",
                             severity: wide.camshaft < crit ? .critical : .warning))
        }
        if wide.crankshaft < warn {
            out.append(.init(id: "P0335",
                             code: "P0335",
                             description: "Crankshaft Position Sensor Circuit Malfunction",
                             severity: wide.crankshaft < crit ? .critical : .warning))
        }
        if wide.mainBearing < warn {
            out.append(.init(id: "P1335",
                             code: "P1335",
                             description: "Main Bearing Wear",
                             severity: wide.mainBearing < crit ? .critical : .warning))
        }
        if wide.waterPump < warn {
            out.append(.init(id: "P0480",
                             code: "P0480",
                             description: "Cooling Fan / Pump Circuit Malfunction",
                             severity: wide.waterPump < crit ? .critical : .warning))
        }
        if wide.oilPump < warn {
            out.append(.init(id: "P0521-PUMP",
                             code: "P0521",
                             description: "Oil Pump Performance",
                             severity: wide.oilPump < crit ? .critical : .warning))
        }

        return out
    }

    // MARK: - Knock

    private static func knockCodes(vm: EngineViewModel) -> [OBD2Code] {
        guard vm.rodKnocking else { return [] }
        return [.init(id: "P0327",
                      code: "P0327",
                      description: "Knock Sensor Circuit Low Input",
                      severity: .warning)]
    }

    // MARK: - Helpers

    private static func severityRank(_ s: OBD2Severity) -> Int {
        switch s {
        case .critical: return 2
        case .warning:  return 1
        }
    }

    /// Cylinder 1-8 → "1"-"8", 9-12 → "9","A","B","C". Real scanners
    /// don't use this convention but it keeps the code short.
    private static func hexDigit(for cyl: Int) -> String {
        let table = ["0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F"]
        if cyl >= 0 && cyl < table.count {
            return table[cyl]
        }
        return "X"
    }
}
