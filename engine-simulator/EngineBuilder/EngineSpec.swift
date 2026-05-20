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
    case inline3
    case inline4
    case inline5
    case inline6
    case v6_60
    case v6_90
    case v8_90
    case v10_72
    case v12_60
    case flat4
    case flat6

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inline3: return "Inline 3"
        case .inline4: return "Inline 4"
        case .inline5: return "Inline 5"
        case .inline6: return "Inline 6"
        case .v6_60:   return "V6 (60°)"
        case .v6_90:   return "V6 (90°)"
        case .v8_90:   return "V8 (90°)"
        case .v10_72:  return "V10 (72°)"
        case .v12_60:  return "V12 (60°)"
        case .flat4:   return "Flat 4"
        case .flat6:   return "Flat 6"
        }
    }

    var shortLabel: String {
        switch self {
        case .inline3: return "I3"
        case .inline4: return "I4"
        case .inline5: return "I5"
        case .inline6: return "I6"
        case .v6_60, .v6_90:   return "V6"
        case .v8_90:           return "V8"
        case .v10_72:          return "V10"
        case .v12_60:          return "V12"
        case .flat4:           return "F4"
        case .flat6:           return "F6"
        }
    }

    var cylinderCount: Int {
        switch self {
        case .inline3:                  return 3
        case .inline4, .flat4:          return 4
        case .inline5:                  return 5
        case .inline6, .v6_60, .v6_90, .flat6: return 6
        case .v8_90:                    return 8
        case .v10_72:                   return 10
        case .v12_60:                   return 12
        }
    }

    var bankCount: Int {
        switch self {
        case .inline3, .inline4, .inline5, .inline6: return 1
        case .v6_60, .v6_90, .v8_90, .v10_72, .v12_60: return 2
        case .flat4, .flat6: return 2
        }
    }

    // Half-angle from vertical: bank0 sits at +angle, bank1 at -angle.
    var bankHalfAngleDeg: Double {
        switch self {
        case .inline3, .inline4, .inline5, .inline6: return 0
        case .v6_60, .v12_60: return 30
        case .v8_90, .v6_90:  return 45
        case .v10_72:         return 36
        case .flat4, .flat6:  return 90
        }
    }

    /// 1-indexed firing order across all cylinders (interpreted as bank0 cyl1..N then bank1 cyl1..N).
    var firingOrder: [Int] {
        switch self {
        case .inline3:  return [1, 2, 3]
        case .inline4:  return [1, 3, 4, 2]
        case .inline5:  return [1, 2, 4, 5, 3]
        case .inline6:  return [1, 5, 3, 6, 2, 4]
        case .v6_60, .v6_90: return [1, 4, 2, 5, 3, 6]
        case .v8_90:    return [1, 8, 4, 3, 6, 5, 7, 2]
        case .v10_72:   return [1, 6, 5, 10, 2, 7, 3, 8, 4, 9]
        case .v12_60:   return [1, 12, 5, 8, 3, 10, 6, 7, 2, 11, 4, 9]
        case .flat4:    return [1, 3, 2, 4]
        case .flat6:    return [1, 4, 3, 6, 2, 5]
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

    // Cam
    var camDurationDeg: Double         // duration_at_50_thou
    var camLiftMm: Double
    var camLobeSeparationDeg: Double
    var camAdvanceDeg: Double
    var camBaseRadiusIn: Double

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

    // Ignition
    var revLimitRpm: Double
    var ignitionTiming: [TimingPoint]    // ascending RPM
    var limiterDurationSec: Double

    // Fuel
    var fuel: FuelPreset

    // MARK: Derived

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
        EngineSpec(
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

            camDurationDeg: 220,
            camLiftMm: 9.5,
            camLobeSeparationDeg: 114,
            camAdvanceDeg: 0,
            camBaseRadiusIn: 0.67,

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

            revLimitRpm: 7000,
            ignitionTiming: defaultTimingCurve(),
            limiterDurationSec: 0.1,

            fuel: .gasoline
        )
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
