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

// MARK: - Tune-fault thresholds

// Below this rpm (engine off / cranking) the AFR and timing aren't
// meaningful, so tune codes are suppressed.
private let runningRpmFloor: Double = 400.0
// Oil pressure lags engine speed at start-up — the pump needs a moment to
// build pressure after the engine catches. Suppress oil-pressure codes until
// the engine has been running at least this long so a normal start doesn't
// throw a false low-pressure fault.
private let oilPressureGraceSeconds: TimeInterval = 4.0
// Lean/rich limits on the commanded target AFR. The factory tune spans
// 14.7 (cruise) → 12.8 (WOT), so these sit clear of a stock map and only
// fire once the user dials the mixture past a safe window.
private let leanWarnAfr: Double = 15.5
private let leanCriticalAfr: Double = 17.0
private let richWarnAfr: Double = 12.0
private let richCriticalAfr: Double = 10.8
// Spark advance offset from the engine's own base curve. Big positive
// offsets are detonation territory; big negative offsets (timing pulled way
// out) kill power and dump heat into the exhaust.
private let overAdvanceWarnDeg: Double = 8.0
private let overAdvanceCriticalDeg: Double = 16.0
private let overRetardWarnDeg: Double = -8.0
private let overRetardCriticalDeg: Double = -16.0

// MARK: - Start-assist thresholds
//
// These only matter while the user is actively cranking (ignition + starter on)
// and the engine hasn't caught yet. They turn a frustrating "it just won't
// start" into concrete things to try: spin it faster, or feed it throttle.

// Above this rpm the engine has fired and is running — no longer a start fault.
private let crankCatchRpm: Double = 450.0
// Fraction of the starter's target cranking speed below which it's clearly
// bogging down (can't overcome the engine it's bolted to).
private let crankBoggingFraction: Double = 0.55
// Assumed healthy cranking target for built-in engines with no editable spec.
private let assumedCrankTargetRpm: Double = 220.0
// A starter geared this slow can't build enough speed to fire most engines.
private let starterSpeedFloorRpm: Double = 180.0
// Throttle while cranking: wide-open floods it; near-closed may be starving a
// big-cam engine that needs a little air to catch.
private let floodingThrottle: Double = 0.95
private let starvedThrottle: Double = 0.04

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
    /// Optional remediation hint shown under the description — what the user
    /// should actually do about it. Populated for user-tunable faults (fuel /
    /// spark); damage codes leave it nil since there's no in-app fix.
    var action: String? = nil
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
        codes.append(contentsOf: ignitionCutCodes(vm: vm))
        codes.append(contentsOf: tuneCodes(vm: vm))
        codes.append(contentsOf: startingCodes(vm: vm))

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

        // Oil temp: P0196. Normal full-load oil runs ~100-105°C across engine
        // types (the thermal model is engine-normalized), so the warning sits
        // above that band and only genuine oil overheating trips a code.
        if vm.oilTempC > 135 {
            out.append(.init(id: "P0196",
                             code: "P0196",
                             description: "Engine Oil Temperature High",
                             severity: .critical))
        } else if vm.oilTempC > 120 {
            out.append(.init(id: "P0196",
                             code: "P0196",
                             description: "Engine Oil Temperature Elevated",
                             severity: .warning))
        }

        // Oil pressure: P0521 (warn) / P0524 (critical). Idle oil pressure is
        // ~25 psi, so the warning sits below idle to avoid false-tripping when
        // the engine is just ticking over. Only evaluated once the engine has
        // been running past the start-up grace — a stopped engine reads zero
        // pressure, and a fresh start needs a moment for the pump to spin up,
        // neither of which is a real fault.
        if engineRunningPastGrace(vm: vm) {
            if vm.oilPressurePsi < 10 {
                out.append(.init(id: "P0524",
                                 code: "P0524",
                                 description: "Engine Oil Pressure Too Low",
                                 severity: .critical))
            } else if vm.oilPressurePsi < 12 {
                out.append(.init(id: "P0521",
                                 code: "P0521",
                                 description: "Engine Oil Pressure Sensor Performance",
                                 severity: .warning))
            }
        }

        return out
    }

    /// True once the engine has been continuously running longer than the
    /// oil-pressure start-up grace. False while stopped or just-started.
    private static func engineRunningPastGrace(vm: EngineViewModel) -> Bool {
        guard let runningSince = vm.runningSince else { return false }
        return Date().timeIntervalSince(runningSince) >= oilPressureGraceSeconds
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
                                 description: "Cylinder \(cylNum) Mechanical Failure",
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

    // MARK: - Ignition cut

    /// A user-driven fault, not a damage one: while a cylinder's spark is cut
    /// from the Cylinder Control tile its plug never fires, which a real
    /// scanner reads as an open ignition-coil circuit (P035X). The code drops
    /// off as soon as ignition is restored.
    private static func ignitionCutCodes(vm: EngineViewModel) -> [OBD2Code] {
        var out: [OBD2Code] = []

        for (idx, enabled) in vm.cylinderIgnitionEnabled.enumerated() where !enabled {
            let cylNum = idx + 1
            let cylDigit = hexDigit(for: cylNum)
            out.append(.init(id: "P035\(cylDigit)-CUT",
                             code: "P035\(cylDigit)",
                             description: "Cylinder \(cylNum) Ignition Coil Disabled",
                             severity: .warning))
        }

        return out
    }

    // MARK: - Tune faults

    /// Codes driven by the user's ECU tune rather than mechanical damage. The
    /// commanded target AFR (fuel map) and the commanded spark advance above
    /// the engine's base curve are both things the user can push out of a safe
    /// window, and a real scanner would flag them as lean/rich/knock faults.
    /// Only evaluated while the engine is actually running.
    private static func tuneCodes(vm: EngineViewModel) -> [OBD2Code] {
        guard vm.isIgnitionOn, vm.rpm > runningRpmFloor else { return [] }
        var out: [OBD2Code] = []

        let targetAfr = vm.ecu.targetAfr(rpm: vm.ecu.currentRpm,
                                         loadKpa: vm.ecu.currentLoadKpa)
        if targetAfr >= leanCriticalAfr {
            out.append(.init(id: "P0171",
                             code: "P0171",
                             description: "System Too Lean — Detonation / Burn Risk",
                             severity: .critical,
                             action: "Add fuel now: lower the FUEL map target AFR"))
        } else if targetAfr >= leanWarnAfr {
            out.append(.init(id: "P0171",
                             code: "P0171",
                             description: "System Too Lean (Bank 1)",
                             severity: .warning,
                             action: "Richen the tune: lower the FUEL map target AFR"))
        } else if targetAfr <= richCriticalAfr {
            out.append(.init(id: "P0172",
                             code: "P0172",
                             description: "System Too Rich — Plug Fouling Risk",
                             severity: .critical,
                             action: "Lean it out: raise the FUEL map target AFR"))
        } else if targetAfr <= richWarnAfr {
            out.append(.init(id: "P0172",
                             code: "P0172",
                             description: "System Too Rich (Bank 1)",
                             severity: .warning,
                             action: "Lean the tune: raise the FUEL map target AFR"))
        }

        let advance = vm.ignitionOffset
        if advance >= overAdvanceCriticalDeg {
            out.append(.init(id: "P0325",
                             code: "P0325",
                             description: "Ignition Over-Advanced — Detonation Risk",
                             severity: .critical,
                             action: "Pull timing now: lower the IGNITION map"))
        } else if advance >= overAdvanceWarnDeg {
            out.append(.init(id: "P0325",
                             code: "P0325",
                             description: "Ignition Timing Over-Advanced",
                             severity: .warning,
                             action: "Reduce advance: lower the IGNITION map"))
        } else if advance <= overRetardCriticalDeg {
            out.append(.init(id: "P1325",
                             code: "P1325",
                             description: "Ignition Over-Retarded — Power Loss / High EGT",
                             severity: .critical,
                             action: "Add timing: raise the IGNITION map"))
        } else if advance <= overRetardWarnDeg {
            out.append(.init(id: "P1325",
                             code: "P1325",
                             description: "Ignition Timing Over-Retarded",
                             severity: .warning,
                             action: "Add advance: raise the IGNITION map"))
        }

        return out
    }

    // MARK: - Start assist
    //
    // Only active while cranking (ignition + starter on) and the engine hasn't
    // caught. Diagnoses the two most common reasons a hand-built engine won't
    // fire — a starter too weak/slow to spin it, or the wrong throttle — and
    // hands the user a concrete fix instead of leaving them stabbing the starter.

    private static func startingCodes(vm: EngineViewModel) -> [OBD2Code] {
        guard vm.isIgnitionOn, vm.isStarterOn, vm.rpm < crankCatchRpm else { return [] }
        var out: [OBD2Code] = []
        let crankRpm = vm.rpm

        let spec = vm.engineId.flatMap { EngineLibrary.shared.entry(for: $0)?.spec }
        let target = spec?.starterSpeedRpm ?? assumedCrankTargetRpm
        let bogging = crankRpm < target * crankBoggingFraction

        // 1. Starter can't spin the engine fast enough to fire.
        if bogging {
            let (desc, action) = starterDiagnosis(spec: spec)
            out.append(.init(id: "P0616-START", code: "P0616",
                             description: desc, severity: .warning, action: action))
        } else {
            // The starter is doing its job, so if it still won't catch the
            // throttle is the likely culprit — too much (flooding) or too little.
            if vm.throttlePosition >= floodingThrottle {
                out.append(.init(id: "P0172-START", code: "P0172",
                                 description: "Flooded — Too Much Throttle While Cranking",
                                 severity: .warning,
                                 action: "Ease off the throttle, then crank"))
            } else if vm.throttlePosition <= starvedThrottle {
                out.append(.init(id: "P050A-START", code: "P050A",
                                 description: "Engine Cranks But Won't Catch",
                                 severity: .warning,
                                 action: "Feed it some throttle while cranking"))
            }
        }

        return out
    }

    /// Separate "geared too slow" from "not enough torque" when the engine has
    /// an editable spec; fall back to a generic hint for built-ins.
    private static func starterDiagnosis(spec: EngineSpec?) -> (String, String) {
        guard let spec else {
            return ("Cranking Speed Too Low", "Starter too weak to spin this engine")
        }
        if spec.starterSpeedRpm < starterSpeedFloorRpm {
            return ("Starter Geared Too Slow to Fire", "Raise starter speed in the builder")
        }
        return ("Starter Torque Too Low for This Engine", "Raise starter torque in the builder")
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
