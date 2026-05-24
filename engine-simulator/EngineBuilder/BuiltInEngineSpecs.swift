//
//  BuiltInEngineSpecs.swift
//  engine-simulator
//
//  Built-in engines ship as authored .mr files without an EngineSpec attached.
//  The procedural 3D viewer needs geometry (bore, stroke, rod length, layout,
//  firing order) for every selectable engine, so we mirror the relevant values
//  from each built-in .mr here. Numbers below were read directly from the
//  corresponding file under assets/engines/atg-video-2/.
//

import Foundation

private let inchToMm: Double = 25.4

enum BuiltInEngineSpecs {
    /// Returns a fully-populated EngineSpec for the given built-in engine entry,
    /// or nil if the entry is not a known built-in.
    static func spec(for entry: EngineEntry) -> EngineSpec? {
        specsByStableId[entry.id]
    }

    /// All built-in specs in display order. Used by the paywall hero to cycle
    /// through every shipped engine.
    static let orderedSpecs: [EngineSpec] = makeOrderedSpecs()

    private static func makeOrderedSpecs() -> [EngineSpec] {
        var specs: [EngineSpec] = [
            geoMetroG10,
            bmwM52B28,
            audiI5,
            hondaVtecF20C,
            suzukiHayabusa,
            subaruEJ25EH,
            subaruEJ25UH,
            toyota2jz,
            gmLsV8,
            chevy454,
            ferrariF136V8,
            lexusLFAV10,
        ]
        // TODO: Re-enable the Merlin V12 in production alongside its
        // EngineLibrary catalog entry once its simulation issues are sorted.
        #if DEBUG
        specs.append(merlinV12)
        #endif
        specs.append(ferrari412T2)
        return specs
    }

    private static let specsByStableId: [UUID: EngineSpec] = [
        BuiltInEngineIds.geoMetroG10:    geoMetroG10,
        BuiltInEngineIds.toyota2jz:      toyota2jz,
        BuiltInEngineIds.gmLsV8:         gmLsV8,
        BuiltInEngineIds.ferrariF136:    ferrariF136V8,
        BuiltInEngineIds.lexusLFA:       lexusLFAV10,
        BuiltInEngineIds.bmwM52B28:      bmwM52B28,
        BuiltInEngineIds.audiI5:         audiI5,
        BuiltInEngineIds.hondaVtecF20C:  hondaVtecF20C,
        BuiltInEngineIds.suzukiHayabusa: suzukiHayabusa,
        BuiltInEngineIds.subaruEJ25EH:   subaruEJ25EH,
        BuiltInEngineIds.subaruEJ25UH:   subaruEJ25UH,
        BuiltInEngineIds.chevy454:       chevy454,
        BuiltInEngineIds.merlinV12:      merlinV12,
        BuiltInEngineIds.ferrari412T2:   ferrari412T2,
    ]

    // MARK: - Specs

    // Source: assets/engines/atg-video-2/00_geo_metro_g10.mr
    private static let geoMetroG10: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Geo Metro G10", layout: .inline3)
        spec.id = BuiltInEngineIds.geoMetroG10
        spec.boreMm = 73.96
        spec.strokeMm = 77.0
        spec.rodLengthMm = 120.0
        spec.compressionHeightMm = 30.0
        spec.pistonMassG = 200
        spec.rodMassG = 400
        spec.crankMassKg = 9
        spec.flywheelMassKg = 5
        spec.flywheelRadiusIn = 5
        spec.crankFrictionLbFt = 4
        spec.redlineRpm = 6500
        spec.firingOrder = [1, 3, 2]
        spec.gearRatios = [3.78, 2.11, 1.40, 1.06, 0.81]
        spec.clutchTorqueLbFt = 120
        spec.vehicleMassLb = 1800
        spec.dragCoefficient = 0.31
        spec.frontalAreaWidthIn = 60
        spec.frontalAreaHeightIn = 54
        spec.diffRatio = 3.789
        spec.tireRadiusIn = 11
        spec.rollingResistanceN = 320 // ~0.018 × car_mass × 9.81
        spec.chamberVolumeCc = 39
        spec.intakeRunnerVolumeCc = 80
        spec.intakeRunnerAreaInSq = 1.44
        spec.exhaustRunnerVolumeCc = 35
        spec.exhaustRunnerAreaInSq = 1.0
        spec.intakePlenumVolumeL = 0.5
        spec.intakePlenumAreaCm2 = 6
        spec.intakeCfm = 150
        spec.runnerCfm = 70
        spec.intakeRunnerLengthIn = 8
        spec.idleThrottlePosition = 0.997
        spec.exhaustPrimaryLengthIn = 18
        spec.exhaustLengthIn = 70
        spec.exhaustCollectorBoreIn = 1.8
        spec.exhaustAudioVolume = 0.18
        spec.impulseResponse = .minimalMuffling02
        spec.camDurationDeg = 200
        spec.camLiftMm = 7.5
        spec.camLobeSeparationDeg = 110
        spec.camBaseRadiusIn = 0.55
        spec.ignitionTiming = [
            TimingPoint(rpm: 0,    advanceDeg: 10),
            TimingPoint(rpm: 1000, advanceDeg: 14),
            TimingPoint(rpm: 2000, advanceDeg: 22),
            TimingPoint(rpm: 3000, advanceDeg: 28),
            TimingPoint(rpm: 4000, advanceDeg: 30),
            TimingPoint(rpm: 5000, advanceDeg: 30),
            TimingPoint(rpm: 6000, advanceDeg: 28),
        ]
        spec.limiterDurationSec = 0.15
        return spec
    }()

    // Source: assets/engines/atg-video-2/03_2jz.mr
    private static let toyota2jz: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Toyota 2JZ", layout: .inline6)
        spec.id = BuiltInEngineIds.toyota2jz
        spec.boreMm = 86.0
        spec.strokeMm = 86.0
        spec.rodLengthMm = 142.0
        spec.compressionHeightMm = 32.8
        spec.redlineRpm = 6000
        spec.firingOrder = EngineLayout.inline6.firingOrder
        spec.gearRatios = [5.25, 3.36, 2.17, 1.72, 1.32, 1.0]
        spec.ignitionTiming = [
            TimingPoint(rpm: 0,    advanceDeg: 12),
            TimingPoint(rpm: 1000, advanceDeg: 12),
            TimingPoint(rpm: 2000, advanceDeg: 20),
            TimingPoint(rpm: 3000, advanceDeg: 26),
            TimingPoint(rpm: 4000, advanceDeg: 30),
            TimingPoint(rpm: 5000, advanceDeg: 34),
            TimingPoint(rpm: 6000, advanceDeg: 38),
        ]
        return spec
    }()

    // Source: assets/engines/atg-video-2/07_gm_ls.mr
    private static let gmLsV8: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "GM LS V8", layout: .v8_90)
        spec.id = BuiltInEngineIds.gmLsV8
        spec.boreMm = 3.78 * inchToMm
        spec.strokeMm = 3.622 * inchToMm
        spec.rodLengthMm = 160.0
        spec.compressionHeightMm = 1.0 * inchToMm
        spec.redlineRpm = 6500
        spec.firingOrder = EngineLayout.v8_90.firingOrder
        spec.gearRatios = [2.97, 2.07, 1.43, 1.00, 0.71, 0.57]
        spec.ignitionTiming = [
            TimingPoint(rpm: 0,    advanceDeg: 12),
            TimingPoint(rpm: 1000, advanceDeg: 12),
            TimingPoint(rpm: 2000, advanceDeg: 20),
            TimingPoint(rpm: 3000, advanceDeg: 30),
            TimingPoint(rpm: 4000, advanceDeg: 40),
            TimingPoint(rpm: 5000, advanceDeg: 40),
            TimingPoint(rpm: 6000, advanceDeg: 40),
        ]
        return spec
    }()

    // Source: assets/engines/atg-video-2/08_ferrari_f136_v8.mr
    private static let ferrariF136V8: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Ferrari F136 V8", layout: .v8_90)
        spec.id = BuiltInEngineIds.ferrariF136
        spec.boreMm = 94.0
        spec.strokeMm = 81.0
        spec.rodLengthMm = 160.0
        spec.compressionHeightMm = 1.0 * inchToMm
        spec.redlineRpm = 9000
        spec.firingOrder = EngineLayout.v8_90.firingOrder
        spec.gearRatios = [3.23, 2.19, 1.61, 1.23, 0.97, 0.8]
        spec.ignitionTiming = [
            TimingPoint(rpm: 0,    advanceDeg: 12),
            TimingPoint(rpm: 1000, advanceDeg: 12),
            TimingPoint(rpm: 2000, advanceDeg: 20),
            TimingPoint(rpm: 3000, advanceDeg: 30),
            TimingPoint(rpm: 4000, advanceDeg: 40),
            TimingPoint(rpm: 5000, advanceDeg: 40),
            TimingPoint(rpm: 6000, advanceDeg: 40),
        ]
        return spec
    }()

    // Source: assets/engines/atg-video-2/10_lfa_v10.mr
    private static let lexusLFAV10: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Lexus LFA V10", layout: .v10_72)
        spec.id = BuiltInEngineIds.lexusLFA
        spec.boreMm = 88.0
        spec.strokeMm = 79.0
        spec.rodLengthMm = 130.0
        spec.compressionHeightMm = 1.0 * inchToMm
        spec.redlineRpm = 9000
        spec.firingOrder = EngineLayout.v10_72.firingOrder
        spec.gearRatios = [3.23, 2.19, 1.61, 1.23, 0.97, 0.8]
        spec.ignitionTiming = [
            TimingPoint(rpm: 0,    advanceDeg: 12),
            TimingPoint(rpm: 4000, advanceDeg: 40),
            TimingPoint(rpm: 8000, advanceDeg: 40),
            TimingPoint(rpm: 9000, advanceDeg: 40),
        ]
        return spec
    }()

    // Source: assets/engines/bmw/M52B28.mr
    private static let bmwM52B28: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "BMW M52B28", layout: .inline6)
        spec.id = BuiltInEngineIds.bmwM52B28
        spec.boreMm = 84.0
        spec.strokeMm = 84.0
        spec.rodLengthMm = 135.0
        spec.compressionHeightMm = 31.82
        spec.chamberVolumeCc = 34.0
        spec.redlineRpm = 7000
        spec.firingOrder = EngineLayout.inline6.firingOrder
        spec.gearRatios = [4.21, 2.49, 1.66, 1.24, 1.0]
        return spec
    }()

    // Source: assets/engines/audi/i5.mr — Audi 2.2 inline-5 (NA, e.g. 80/100 KE/RT/JN).
    private static let audiI5: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Audi 2.2 I5", layout: .inline5)
        spec.id = BuiltInEngineIds.audiI5
        spec.boreMm = 81.0
        spec.strokeMm = 86.4
        // .mr derives rod_length from deck height (220mm) − throw − comp height.
        spec.rodLengthMm = 220.0 - (0.5 * 86.4) - 32.8
        spec.compressionHeightMm = 32.8
        spec.redlineRpm = 7500
        spec.firingOrder = EngineLayout.inline5.firingOrder
        spec.gearRatios = [3.50, 1.94, 1.32, 1.03, 0.84]
        return spec
    }()

    // Source: assets/engines/atg-video-1/05_honda_vtec.mr — F20C-spec (S2000).
    private static let hondaVtecF20C: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Honda F20C (VTEC)", layout: .inline4)
        spec.id = BuiltInEngineIds.hondaVtecF20C
        spec.boreMm = 81.0
        spec.strokeMm = 87.2
        spec.rodLengthMm = 5.430 * inchToMm
        spec.redlineRpm = 8400
        spec.firingOrder = EngineLayout.inline4.firingOrder
        spec.gearRatios = [3.13, 2.05, 1.48, 1.16, 0.97, 0.81]
        return spec
    }()

    // Source: assets/engines/atg-video-1/04_hayabusa.mr — Suzuki GSX1300R inline-4.
    private static let suzukiHayabusa: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Suzuki Hayabusa (Bike)", layout: .inline4)
        spec.id = BuiltInEngineIds.suzukiHayabusa
        spec.boreMm = 81.0
        spec.strokeMm = 65.0
        spec.rodLengthMm = 4.705 * inchToMm
        spec.redlineRpm = 11000
        spec.firingOrder = EngineLayout.inline4.firingOrder
        // Motorcycle 6-speed sequential; ratios approximate Hayabusa OEM box.
        spec.gearRatios = [2.61, 1.78, 1.41, 1.21, 1.10, 1.00]
        // Light bike chassis approximation so the speedometer reads sensibly.
        spec.vehicleMassLb = 580
        spec.tireRadiusIn = 12
        spec.diffRatio = 2.40
        spec.dragCoefficient = 0.55
        spec.frontalAreaWidthIn = 28
        spec.frontalAreaHeightIn = 44
        return spec
    }()

    // Source: assets/engines/atg-video-2/01_subaru_ej25_eh.mr — equal-length header.
    private static let subaruEJ25EH: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Subaru EJ25 (Equal-Length Headers)", layout: .flat4)
        spec.id = BuiltInEngineIds.subaruEJ25EH
        spec.boreMm = 99.5
        spec.strokeMm = 79.0
        spec.rodLengthMm = 5.142 * inchToMm
        spec.redlineRpm = 6500
        spec.firingOrder = EngineLayout.flat4.firingOrder
        spec.gearRatios = [3.45, 2.05, 1.46, 1.06, 0.78]
        return spec
    }()

    // Source: assets/engines/atg-video-2/02_subaru_ej25_uh.mr — unequal-length
    // header (the classic Subaru burble).
    private static let subaruEJ25UH: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Subaru EJ25 (Boxer Rumble)", layout: .flat4)
        spec.id = BuiltInEngineIds.subaruEJ25UH
        spec.boreMm = 99.5
        spec.strokeMm = 79.0
        spec.rodLengthMm = 5.142 * inchToMm
        spec.redlineRpm = 6500
        spec.firingOrder = EngineLayout.flat4.firingOrder
        spec.gearRatios = [3.45, 2.05, 1.46, 1.06, 0.78]
        return spec
    }()

    // Source: assets/engines/chevrolet/chev_truck_454.mr — GM big-block 454.
    private static let chevy454: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Chevy 454 Big Block", layout: .v8_90)
        spec.id = BuiltInEngineIds.chevy454
        spec.boreMm = 4.25 * inchToMm
        spec.strokeMm = 4.0 * inchToMm
        spec.rodLengthMm = 6.135 * inchToMm
        spec.compressionHeightMm = 1.640 * inchToMm
        spec.rodMassG = 785
        spec.redlineRpm = 5500
        spec.firingOrder = EngineLayout.v8_90.firingOrder
        // 4-speed TH400-style ratios — 454 truck box.
        spec.gearRatios = [2.48, 1.48, 1.0, 0.75]
        spec.vehicleMassLb = 5500
        spec.tireRadiusIn = 15
        return spec
    }()

    // Source: assets/engines/atg-video-2/11_merlin_v12.mr — Rolls-Royce Merlin
    // (Spitfire / P-51). 27L aero V12.
    private static let merlinV12: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Rolls-Royce Merlin V12", layout: .v12_60)
        spec.id = BuiltInEngineIds.merlinV12
        spec.boreMm = 5.4 * inchToMm
        spec.strokeMm = 6.0 * inchToMm
        spec.rodLengthMm = 14.0 * inchToMm
        spec.redlineRpm = 3000
        spec.firingOrder = EngineLayout.v12_60.firingOrder
        // Aero engine — no road gearbox. Default ratios stay in place; the
        // user can clear them in the builder if simulating a propeller drive.
        return spec
    }()

    // Source: assets/engines/atg-video-2/12_ferrari_412_t2.mr — 1995 F1 V12
    // (75° bank, 3.0L, screams to 18000 rpm).
    private static let ferrari412T2: EngineSpec = {
        var spec = EngineSpec.defaultSpec(name: "Ferrari 412 T2 (F1)", layout: .v12_75)
        spec.id = BuiltInEngineIds.ferrari412T2
        spec.boreMm = 86.0
        spec.strokeMm = 43.0
        spec.rodLengthMm = 120.0
        spec.redlineRpm = 18000
        spec.firingOrder = EngineLayout.v12_75.firingOrder
        // 7-speed sequential gearbox approximation.
        spec.gearRatios = [3.0, 2.18, 1.66, 1.30, 1.04, 0.86, 0.76]
        spec.vehicleMassLb = 1320
        spec.dragCoefficient = 0.8
        return spec
    }()
}

extension EngineEntry {
    /// Returns the editable user spec if present, otherwise the canned built-in spec.
    /// Used by views (e.g. procedural 3D) that need geometry for any selected engine.
    var effectiveSpec: EngineSpec? {
        spec ?? BuiltInEngineSpecs.spec(for: self)
    }
}
