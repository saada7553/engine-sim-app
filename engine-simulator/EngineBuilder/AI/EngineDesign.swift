//
//  EngineDesign.swift
//  engine-simulator
//
//  The intent model the AI pipeline produces and the procedural expander
//  consumes. Two small model passes fill an EngineIntent: an extraction pass
//  (anything the user explicitly named + feature tags) and a vibe pass (the
//  feel). EngineDesignExpander then builds a complete, runnable EngineSpec —
//  all ~50 fields — from this intent.
//
//  Explicit pins (the optionals) always win; everything else is derived from
//  character + feature tags so the model never has to fill coupled numbers and
//  the result always fires up.
//
//  Framework-free / all-OS so the expander is unit-testable without a model.
//

import Foundation

// MARK: - Character axes (always present, from the vibe pass)

enum DesignAspiration: String, CaseIterable {
    case naturallyAspirated, turbocharged, supercharged
    var isForced: Bool { self != .naturallyAspirated }
}

enum DesignCamProfile: String, CaseIterable {
    case economy, stock, sport, race

    var rank: Int {
        switch self { case .economy: return 0; case .stock: return 1; case .sport: return 2; case .race: return 3 }
    }
    static func from(rank: Int) -> DesignCamProfile {
        [.economy, .stock, .sport, .race][max(0, min(3, rank))]
    }
}

enum DesignPowerBand: String, CaseIterable {
    case lowEnd      // torquey, long runners/headers
    case broad
    case topEnd      // peaky, short runners/headers
}

enum DesignIdle: String, CaseIterable {
    case smooth      // heavier flywheel
    case mild
    case lumpy       // lighter flywheel, racy
}

enum DesignGearing: String, CaseIterable {
    case short, balanced, tall
}

enum DesignVehicleClass: String, CaseIterable {
    case lightweight, sportsCar, sedan, muscle, supercar, truck, raceCar, motorcycle
}

enum DesignSound: String, CaseIterable {
    case smooth, stock, aggressive, raw
}

/// Overall intended power level — the AI reads this from the prompt's sentiment
/// ("slow"/"gutless" → weak, "high horsepower"/"monster" → extreme). Drives
/// redline, breathing and cam aggressiveness so the engine matches the ask.
enum DesignPerformance: String, CaseIterable {
    case weak, modest, strong, extreme

    var rank: Int {
        switch self { case .weak: return 0; case .modest: return 1; case .strong: return 2; case .extreme: return 3 }
    }
}

/// Mechanical condition / age — drives blowby (ring seal).
enum DesignCondition: String, CaseIterable {
    case fresh, normal, worn
}

/// How high the engine wants to rev, as a feeling. Used only when the user gave
/// no explicit redline number; the reconciler folds it into the build.
enum RevCharacter: String, CaseIterable {
    case low, medium, high, screamer
}

// MARK: - Feature tags (specific mechanical things the user called out)

enum DesignFeature: String, CaseIterable {
    case highCompression, lowCompression
    case heavyFlywheel, lightFlywheel
    case bigCam, mildCam
    case tightLSA, wideLSA
    case longHeaders, shortHeaders
    case longRunners, shortRunners
    case bigPlenum, smallPlenum
    case shortGears, tallGears
    case bigBore, longStroke
    case highRedline
    case lightweightInternals
    case highBoost
    case worn          // tired/high-mileage -> more blowby
    case freshBuild    // freshly built -> perfect ring seal
}

// MARK: - EngineIntent

struct EngineIntent {
    var name: String

    // Explicit pins — nil means "user didn't specify", so the expander derives it.
    var layout: EngineLayout?
    var displacementL: Double?
    var redlineRpm: Double?
    var compressionRatio: Double?
    var aspiration: DesignAspiration?
    var fuel: FuelPreset?
    var vtec: Bool?              // nil = not requested; true/false = explicit or brand-inferred

    // Character / sentiment (the AI passes always supply these)
    var performance: DesignPerformance
    var condition: DesignCondition
    var camProfile: DesignCamProfile
    var powerBand: DesignPowerBand
    var idle: DesignIdle
    var vehicleClass: DesignVehicleClass
    var sound: DesignSound
    var gearing: DesignGearing

    // Specific features the user mentioned
    var features: Set<DesignFeature>

    func has(_ f: DesignFeature) -> Bool { features.contains(f) }

    static func neutral(name: String = "AI Engine") -> EngineIntent {
        EngineIntent(
            name: name,
            layout: nil, displacementL: nil, redlineRpm: nil,
            compressionRatio: nil, aspiration: nil, fuel: nil, vtec: nil,
            performance: .modest, condition: .normal,
            camProfile: .stock, powerBand: .broad, idle: .mild,
            vehicleClass: .sportsCar, sound: .stock, gearing: .balanced,
            features: []
        )
    }
}
