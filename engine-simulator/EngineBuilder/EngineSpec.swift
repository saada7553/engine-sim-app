//
//  EngineSpec.swift
//  engine-simulator
//
//  User-editable description of an engine. Serializable to JSON for
//  persistence and to a .mr script via MRWriter for the C++ simulator.
//

import Foundation

// MARK: - Layout

enum EngineLayout: String, Codable, CaseIterable, Identifiable {
    case inline1
    case inline2
    case inline3
    case inline4
    case inline5
    case inline6
    case inline7
    case v6_60
    case v6_90
    case v8_90
    case v10_72
    case v12_60
    case v12_75
    case flat4
    case flat6

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inline1: return "Single"
        case .inline2: return "Inline 2 (Twin)"
        case .inline3: return "Inline 3"
        case .inline7: return "Inline 7"
        case .inline4: return "Inline 4"
        case .inline5: return "Inline 5"
        case .inline6: return "Inline 6"
        case .v6_60:   return "V6 (60°)"
        case .v6_90:   return "V6 (90°)"
        case .v8_90:   return "V8 (90°)"
        case .v10_72:  return "V10 (72°)"
        case .v12_60:  return "V12 (60°)"
        case .v12_75:  return "V12 (75°)"
        case .flat4:   return "Flat 4"
        case .flat6:   return "Flat 6"
        }
    }

    var shortLabel: String {
        switch self {
        case .inline1: return "1"
        case .inline2: return "I2"
        case .inline7: return "I7"
        case .inline3: return "I3"
        case .inline4: return "I4"
        case .inline5: return "I5"
        case .inline6: return "I6"
        case .v6_60, .v6_90:   return "V6"
        case .v8_90:           return "V8"
        case .v10_72:          return "V10"
        case .v12_60, .v12_75: return "V12"
        case .flat4:           return "F4"
        case .flat6:           return "F6"
        }
    }

    var cylinderCount: Int {
        switch self {
        case .inline1:                  return 1
        case .inline2:                  return 2
        case .inline3:                  return 3
        case .inline4, .flat4:          return 4
        case .inline5:                  return 5
        case .inline6, .v6_60, .v6_90, .flat6: return 6
        case .inline7:                  return 7
        case .v8_90:                    return 8
        case .v10_72:                   return 10
        case .v12_60, .v12_75:          return 12
        }
    }

    var bankCount: Int {
        switch self {
        case .inline1, .inline2, .inline3, .inline4, .inline5, .inline6, .inline7: return 1
        case .v6_60, .v6_90, .v8_90, .v10_72, .v12_60, .v12_75: return 2
        case .flat4, .flat6: return 2
        }
    }

    // Half-angle from vertical: bank0 sits at +angle, bank1 at -angle.
    var bankHalfAngleDeg: Double {
        switch self {
        case .inline1, .inline2, .inline3, .inline4, .inline5, .inline6, .inline7: return 0
        case .v6_60, .v12_60: return 30
        case .v8_90, .v6_90:  return 45
        case .v10_72:         return 36
        case .v12_75:         return 37.5
        case .flat4, .flat6:  return 90
        }
    }

    /// 1-indexed firing order across all cylinders (interpreted as bank0 cyl1..N then bank1 cyl1..N).
    var firingOrder: [Int] {
        switch self {
        case .inline1:  return [1]
        case .inline2:  return [1, 2]
        case .inline3:  return [1, 2, 3]
        case .inline7:  return [1, 3, 5, 7, 2, 4, 6]
        case .inline4:  return [1, 3, 4, 2]
        case .inline5:  return [1, 2, 4, 5, 3]
        case .inline6:  return [1, 5, 3, 6, 2, 4]
        case .v6_60, .v6_90: return [1, 4, 2, 5, 3, 6]
        case .v8_90:    return [1, 8, 4, 3, 6, 5, 7, 2]
        case .v10_72:   return [1, 6, 5, 10, 2, 7, 3, 8, 4, 9]
        case .v12_60, .v12_75: return [1, 12, 5, 8, 3, 10, 6, 7, 2, 11, 4, 9]
        case .flat4:    return [1, 3, 2, 4]
        // For a boxer-6 (bank0 = odd, bank1 = even), each bank must contain
        // one cylinder at each crank-pin angle (0°, 120°, 240°). With the
        // previous default [1, 4, 3, 6, 2, 5] cylinders 4 & 2 landed on the
        // same pin within bank1 (and 3 & 5 on the same pin within bank0),
        // creating a physically-impossible journal layout that crashed the
        // sim. This order keeps every bank pin-angle unique.
        case .flat6:    return [1, 4, 3, 6, 5, 2]
        }
    }
}

// MARK: - Fuel + Exhaust

enum FuelPreset: String, Codable, CaseIterable, Identifiable {
    case gasoline
    case e85
    case methanol
    case diesel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gasoline: return "Gasoline"
        case .e85:      return "E85"
        case .methanol: return "Methanol"
        case .diesel:   return "Diesel"
        }
    }
}

enum ImpulseResponseChoice: String, Codable, CaseIterable, Identifiable {
    case mildExhaustReverb
    case mildExhaust
    case minimalMuffling01
    case minimalMuffling02
    case minimalMuffling03
    case sharp
    case defaultIR

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mildExhaustReverb: return "Mild Exhaust (Reverb)"
        case .mildExhaust:       return "Mild Exhaust"
        case .minimalMuffling01: return "Minimal Muffling A"
        case .minimalMuffling02: return "Minimal Muffling B"
        case .minimalMuffling03: return "Minimal Muffling C"
        case .sharp:             return "Sharp"
        case .defaultIR:         return "Default"
        }
    }

    /// Matches identifier in es/sound-library/impulse_responses.mr (ir_lib.<name>).
    var irLibField: String {
        switch self {
        case .mildExhaustReverb: return "mild_exhaust_0_reverb"
        case .mildExhaust:       return "mild_exhaust_0"
        case .minimalMuffling01: return "minimal_muffling_01"
        case .minimalMuffling02: return "minimal_muffling_02"
        case .minimalMuffling03: return "minimal_muffling_03"
        case .sharp:             return "sharp_0"
        case .defaultIR:         return "default_0"
        }
    }
}

// MARK: - Ignition timing curve

struct TimingPoint: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var rpm: Double
    var advanceDeg: Double

    enum CodingKeys: String, CodingKey { case rpm, advanceDeg }
}

// MARK: - Captured run stats

/// Best measured results for an engine, persisted inside the spec so they
/// travel with it (to disk and, when published, to the cloud). Every field is
/// 0 until the player actually captures it on a dyno sweep / launch / top-speed
/// run, so callers must treat 0 as "not recorded yet", not a real result.
struct CapturedStats: Codable, Equatable {
    var peakPowerHp: Double
    var peakPowerRpm: Double
    var peakTorqueLbFt: Double
    var peakTorqueRpm: Double
    var zeroToSixtySec: Double   // 0 = no launch captured
    var topSpeedMph: Double      // 0 = no top-speed captured

    static let empty = CapturedStats(peakPowerHp: 0, peakPowerRpm: 0,
                                     peakTorqueLbFt: 0, peakTorqueRpm: 0,
                                     zeroToSixtySec: 0, topSpeedMph: 0)

    var hasDyno: Bool { peakPowerHp > 0 }
    var hasLaunch: Bool { zeroToSixtySec > 0 }
    var hasTopSpeed: Bool { topSpeedMph > 0 }

    /// Combine two captures keeping the best of each field: highest power /
    /// torque / top speed, and the quickest (lowest non-zero) 0-60. Used when
    /// merging a fresh run into whatever was already persisted for the engine.
    static func merge(_ a: CapturedStats?, _ b: CapturedStats) -> CapturedStats {
        guard let a = a else { return b }
        var out = a
        if b.peakPowerHp > out.peakPowerHp {
            out.peakPowerHp = b.peakPowerHp; out.peakPowerRpm = b.peakPowerRpm
        }
        if b.peakTorqueLbFt > out.peakTorqueLbFt {
            out.peakTorqueLbFt = b.peakTorqueLbFt; out.peakTorqueRpm = b.peakTorqueRpm
        }
        if b.topSpeedMph > out.topSpeedMph { out.topSpeedMph = b.topSpeedMph }
        if b.zeroToSixtySec > 0,
           out.zeroToSixtySec == 0 || b.zeroToSixtySec < out.zeroToSixtySec {
            out.zeroToSixtySec = b.zeroToSixtySec
        }
        return out
    }
}

// MARK: - ECU tune

/// A saved ECU tune: the user-edited ignition (absolute deg BTDC) and fuel
/// (target AFR) maps, plus the grid axes they were built on. Persisted inside
/// the spec so a tuned engine keeps its tune across swaps/relaunches and
/// carries it when shared to the community. The axes let a restore validate the
/// grid still matches before applying (it always will for the same engine,
/// since the rpm axis derives deterministically from the redline).
struct EcuTune: Codable, Equatable {
    var rpmBins: [Double]
    var loadBins: [Double]
    var ignitionMap: [[Double]]   // [loadIdx][rpmIdx] absolute deg BTDC
    var fuelMap: [[Double]]       // [loadIdx][rpmIdx] target AFR
}

// MARK: - Community provenance

/// Stamped onto an engine that was downloaded from the community browser, so
/// the app can show who built it and — critically — refuse to let a different
/// player re-publish someone else's engine as their own.
struct CommunityOrigin: Codable, Equatable {
    /// Stable id of the author (see PlayerIdentity.playerId) — the real owner
    /// check. `authorUsername` is kept only for display.
    var authorId: String
    var authorUsername: String
    var sourceRecordName: String
}

// MARK: - EngineSpec

struct EngineSpec: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var redlineRpm: Double
    var layout: EngineLayout

    // Bottom end (mm)
    var boreMm: Double
    var strokeMm: Double
    var rodLengthMm: Double
    var compressionHeightMm: Double

    // Masses
    var pistonMassG: Double
    var rodMassG: Double
    var crankMassKg: Double
    var flywheelMassKg: Double
    var flywheelRadiusIn: Double
    var crankFrictionLbFt: Double

    // Starter motor + cylinder sealing
    var starterTorqueLbFt: Double
    var starterSpeedRpm: Double
    var blowby: Double                 // k_28inH2O value; 0 = perfect seal, higher = worn

    // Cam
    var camDurationDeg: Double         // duration_at_50_thou
    var camLiftMm: Double
    var camLobeSeparationDeg: Double
    var camAdvanceDeg: Double
    var camBaseRadiusIn: Double

    // VTEC / variable valvetrain — a second, high-lift cam profile that engages
    // above the crossover RPM. Only emitted when vtecEnabled.
    var vtecEnabled: Bool
    var vtecCrossoverRpm: Double
    var vtecCamDurationDeg: Double
    var vtecCamLiftMm: Double
    var vtecCamLobeSeparationDeg: Double

    // Head
    var chamberVolumeCc: Double
    var intakeRunnerVolumeCc: Double
    var intakeRunnerAreaInSq: Double
    var exhaustRunnerVolumeCc: Double
    var exhaustRunnerAreaInSq: Double
    var portFlowScale: Double

    // Intake
    var intakePlenumVolumeL: Double
    var intakePlenumAreaCm2: Double
    var intakeCfm: Double
    var runnerCfm: Double
    var idleCfm: Double
    var idleThrottlePosition: Double
    var intakeRunnerLengthIn: Double

    // Exhaust
    var exhaustPrimaryLengthIn: Double
    var exhaustCollectorBoreIn: Double   // diameter, fed into circle_area()
    var exhaustLengthIn: Double
    var exhaustAudioVolume: Double
    var impulseResponse: ImpulseResponseChoice

    // Ignition. revLimit is no longer a separate field — it derives from redlineRpm.
    var ignitionTiming: [TimingPoint]    // ascending RPM
    var limiterDurationSec: Double

    // Firing order: 1-indexed cylinder numbers in firing sequence.
    // Always has layout.cylinderCount entries; reset to layout default when layout changes.
    var firingOrder: [Int]

    // Fuel
    var fuel: FuelPreset

    // Transmission
    var clutchTorqueLbFt: Double
    var gearRatios: [Double]   // ordered: 1st → top

    // Vehicle
    var vehicleMassLb: Double
    var dragCoefficient: Double
    var frontalAreaWidthIn: Double
    var frontalAreaHeightIn: Double
    var diffRatio: Double
    var tireRadiusIn: Double
    var rollingResistanceN: Double

    // Best results the player has captured for this engine, and (for downloaded
    // engines) who originally built it. Both are optional and trailing so old
    // saved specs decode unchanged and the memberwise initializer keeps working
    // without these arguments.
    var capturedStats: CapturedStats? = nil
    var communityOrigin: CommunityOrigin? = nil
    var ecuTune: EcuTune? = nil
    /// Optional free-text blurb the builder can fill out; shown when the engine
    /// is shared to the community. Distinct from `name` (the short title).
    var engineDescription: String? = nil

    // MARK: Derived

    /// Rev limit derives from redline — single source of truth for "max RPM".
    /// The hardware limiter and the displayed redline are intentionally the same value.
    var revLimitRpm: Double { redlineRpm }

    /// Total displacement in cubic centimeters.
    var displacementCc: Double {
        let boreCm = boreMm / 10.0
        let strokeCm = strokeMm / 10.0
        let cylVol = .pi * pow(boreCm / 2.0, 2) * strokeCm
        return cylVol * Double(layout.cylinderCount)
    }

    var displacementLitres: Double { displacementCc / 1000.0 }

    // MARK: Defaults

    static func defaultSpec(name: String = "New Engine",
                            layout: EngineLayout = .inline4) -> EngineSpec {
        var spec = EngineSpec(
            id: UUID(),
            name: name,
            redlineRpm: 7000,
            layout: layout,

            boreMm: 86.0,
            strokeMm: 86.0,
            rodLengthMm: 142.0,
            compressionHeightMm: 32.8,

            pistonMassG: 250,
            rodMassG: 500,
            crankMassKg: 15,
            flywheelMassKg: 10,
            flywheelRadiusIn: 7,
            crankFrictionLbFt: 5,

            starterTorqueLbFt: 200,
            starterSpeedRpm: 200,
            blowby: 0.1,

            camDurationDeg: 220,
            camLiftMm: 9.5,
            camLobeSeparationDeg: 114,
            camAdvanceDeg: 0,
            camBaseRadiusIn: 0.67,

            vtecEnabled: false,
            vtecCrossoverRpm: 5800,
            vtecCamDurationDeg: 248,
            vtecCamLiftMm: 11.5,
            vtecCamLobeSeparationDeg: 105,

            chamberVolumeCc: 50,
            intakeRunnerVolumeCc: 150,
            intakeRunnerAreaInSq: 3.6,
            exhaustRunnerVolumeCc: 50,
            exhaustRunnerAreaInSq: 1.56,
            portFlowScale: 1.0,

            intakePlenumVolumeL: 1.0,
            intakePlenumAreaCm2: 10,
            intakeCfm: 500,
            runnerCfm: 200,
            idleCfm: 0.0,
            idleThrottlePosition: 0.9965,
            intakeRunnerLengthIn: 12,

            exhaustPrimaryLengthIn: 25,
            exhaustCollectorBoreIn: 2.0,
            exhaustLengthIn: 100,
            exhaustAudioVolume: 0.2,
            impulseResponse: .mildExhaustReverb,

            ignitionTiming: defaultTimingCurve(),
            limiterDurationSec: 0.1,
            firingOrder: layout.firingOrder,

            fuel: .gasoline,

            clutchTorqueLbFt: 500,
            gearRatios: [5.25, 3.36, 2.17, 1.72, 1.32, 1.0],

            vehicleMassLb: 3400,
            dragCoefficient: 0.4,
            frontalAreaWidthIn: 66,
            frontalAreaHeightIn: 50,
            diffRatio: 3.15,
            tireRadiusIn: 10,
            rollingResistanceN: 500
        )
        // Size-appropriate starter (the literal 200/200 above is a placeholder).
        spec.resyncStarterForLayout()
        return spec
    }

    /// True when firingOrder is a valid permutation of 1...cylinderCount.
    var firingOrderIsValid: Bool {
        let expected = Set(1...layout.cylinderCount)
        return Set(firingOrder) == expected && firingOrder.count == layout.cylinderCount
    }

    /// Reset firingOrder to the layout's default. Call when layout changes.
    mutating func resyncFiringOrderForLayout() {
        firingOrder = layout.firingOrder
    }

    /// Cranking effort matched to engine size + cylinder count: bigger engines
    /// need more starter torque and spin over more slowly. Clamped to sane
    /// ranges so it never produces a runaway/absurd starter.
    var recommendedStarterTorqueLbFt: Double {
        min(600, max(120, 60 + displacementLitres * 55 + Double(layout.cylinderCount) * 8))
    }
    var recommendedStarterSpeedRpm: Double {
        // Be generous on big engines: a gentle displacement/cylinder penalty and
        // a healthy floor so a large V8/V12 still cranks at a decent speed.
        min(300, max(180, 260 - displacementLitres * 5 - Double(layout.cylinderCount)))
    }
    /// Reset the starter to the size-appropriate recommendation. Call on layout change.
    mutating func resyncStarterForLayout() {
        starterTorqueLbFt = recommendedStarterTorqueLbFt
        starterSpeedRpm = recommendedStarterSpeedRpm
    }

    static func defaultTimingCurve() -> [TimingPoint] {
        [
            TimingPoint(rpm: 0,    advanceDeg: 12),
            TimingPoint(rpm: 1000, advanceDeg: 12),
            TimingPoint(rpm: 2000, advanceDeg: 20),
            TimingPoint(rpm: 3000, advanceDeg: 26),
            TimingPoint(rpm: 4000, advanceDeg: 30),
            TimingPoint(rpm: 5000, advanceDeg: 34),
            TimingPoint(rpm: 6000, advanceDeg: 38),
            TimingPoint(rpm: 7000, advanceDeg: 38),
        ]
    }
}
