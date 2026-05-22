//
//  AIEngineGenerator.swift
//  engine-simulator
//
//  Multi-stage, on-device engine generation via Apple's Foundation Models.
//  A 3B model is unreliable when asked to pull many fields at once (it would
//  drop an explicit "inline six" while juggling displacement, fuel, etc.), so
//  each stage asks ONE narrow question with an explicit "unspecified" answer:
//
//    1. Layout      — the cylinder configuration, or unspecified.
//    2. Size        — displacement in litres, or "not stated".
//    3. Induction   — aspiration + fuel, each or unspecified.
//    4. Tune        — redline + compression, each or "not stated".
//    5. Features    — specific parts the user named (tags).
//    6. Vibe        — the feel (cam/power band/idle/class/sound/gearing) + name.
//
//  Stages 1-5 are pure extraction (resilient: a failed/empty stage just means
//  "user didn't say"). The results merge into an EngineIntent and
//  EngineDesignExpander does all the heavy procedural work. The model never
//  fills coupled numbers, so it can't make duds.
//
//  Foundation Models requires macOS 26 / iOS 26; all framework use is gated.
//

import Foundation
import FoundationModels

// MARK: - Public facade

enum EngineGeneratorAvailability: Equatable {
    case available
    case unavailable(String)
    var isAvailable: Bool { self == .available }
}

enum EngineGenerationError: LocalizedError {
    case unsupportedOS
    case modelUnavailable(String)
    case emptyDescription

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:           return "AI generation requires macOS 26 or iOS 26."
        case .modelUnavailable(let r): return r
        case .emptyDescription:        return "Describe the engine you want first."
        }
    }
}

enum AIEngineGeneration {
    static let maxPromptLength = 200

    static var availability: EngineGeneratorAvailability {
        if #available(macOS 26.0, iOS 26.0, *) { return AIEngineGenerator.availability }
        return .unavailable("Requires macOS 26 or iOS 26.")
    }

    static func generate(from description: String) async throws -> EngineSpec {
        let trimmed = String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxPromptLength))
        guard !trimmed.isEmpty else { throw EngineGenerationError.emptyDescription }

        if #available(macOS 26.0, iOS 26.0, *) {
            return try await AIEngineGenerator().generate(from: trimmed)
        }
        throw EngineGenerationError.unsupportedOS
    }
}

// MARK: - Stage 1: Layout

@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenLayoutChoice: String {
    case unspecified
    case inline3, inline4, inline5, inline6
    case v6_60, v6_90, v8_90, v10_72, v12_60, v12_75
    case flat4, flat6

    var engineLayout: EngineLayout? {
        switch self {
        case .unspecified: return nil
        case .inline3: return .inline3;  case .inline4: return .inline4
        case .inline5: return .inline5;  case .inline6: return .inline6
        case .v6_60: return .v6_60;      case .v6_90: return .v6_90
        case .v8_90: return .v8_90;      case .v10_72: return .v10_72
        case .v12_60: return .v12_60;    case .v12_75: return .v12_75
        case .flat4: return .flat4;      case .flat6: return .flat6
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
struct GenLayoutStage {
    @Guide(description: "The cylinder layout the user explicitly asked for. 'inline six'/'straight six'/'I6'/'six-cylinder' = inline6; 'inline four'/'I4' = inline4; 'straight five'/'I5' = inline5; 'V6' = v6_60; 'V8' = v8_90; 'V10' = v10_72; 'V12' = v12_60; 'boxer'/'flat four' = flat4; 'flat six' = flat6. If the user did NOT name a cylinder layout, answer unspecified.")
    var layout: GenLayoutChoice
}

// MARK: - Stage 2: Size

@available(macOS 26.0, iOS 26.0, *)
@Generable
struct GenSizeStage {
    @Guide(description: "true only if the user stated a displacement or named an engine that fixes it (e.g. 2JZ, LS, Coyote); false otherwise.")
    var stated: Bool
    @Guide(description: "Displacement in litres (used only when stated is true). 2JZ=3.0, LS=5.7, Coyote=5.0, Hayabusa=1.3.", .range(0.5...30.0))
    var litres: Double
}

// MARK: - Stage 3: Induction (aspiration + fuel)

@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenAspirationChoice: String {
    case unspecified, naturallyAspirated, turbocharged, supercharged
    var design: DesignAspiration? {
        switch self {
        case .unspecified: return nil
        case .naturallyAspirated: return .naturallyAspirated
        case .turbocharged: return .turbocharged
        case .supercharged: return .supercharged
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenFuelChoice: String {
    case unspecified, gasoline, e85, methanol, diesel
    var preset: FuelPreset? {
        switch self {
        case .unspecified: return nil
        case .gasoline: return .gasoline; case .e85: return .e85
        case .methanol: return .methanol; case .diesel: return .diesel
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
struct GenInductionStage {
    @Guide(description: "Aspiration only if the user mentions it (turbo, supercharger, or naturally aspirated/NA); else unspecified.")
    var aspiration: GenAspirationChoice
    @Guide(description: "Fuel only if the user mentions E85, methanol, or diesel; else unspecified.")
    var fuel: GenFuelChoice
}

// MARK: - Stage 4: Tune (redline + compression)

@available(macOS 26.0, iOS 26.0, *)
@Generable
struct GenTuneStage {
    @Guide(description: "true only if the user gave an explicit redline / max RPM; false otherwise.")
    var redlineStated: Bool
    @Guide(description: "Redline RPM (used only when redlineStated is true).", .range(3000.0...12000.0))
    var redlineRpm: Double
    @Guide(description: "true only if the user gave an explicit compression ratio; false otherwise.")
    var compressionStated: Bool
    @Guide(description: "Compression ratio (used only when compressionStated is true).", .range(7.0...14.0))
    var compressionRatio: Double
}

// MARK: - Stage 5: Features

@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenFeature: String {
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

    var design: DesignFeature {
        switch self {
        case .highCompression: return .highCompression; case .lowCompression: return .lowCompression
        case .heavyFlywheel: return .heavyFlywheel;      case .lightFlywheel: return .lightFlywheel
        case .bigCam: return .bigCam;                    case .mildCam: return .mildCam
        case .tightLSA: return .tightLSA;                case .wideLSA: return .wideLSA
        case .longHeaders: return .longHeaders;          case .shortHeaders: return .shortHeaders
        case .longRunners: return .longRunners;          case .shortRunners: return .shortRunners
        case .bigPlenum: return .bigPlenum;              case .smallPlenum: return .smallPlenum
        case .shortGears: return .shortGears;            case .tallGears: return .tallGears
        case .bigBore: return .bigBore;                  case .longStroke: return .longStroke
        case .highRedline: return .highRedline
        case .lightweightInternals: return .lightweightInternals
        case .highBoost: return .highBoost
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
struct GenFeatureStage {
    @Guide(description: "Tags for specific parts the user explicitly mentions (e.g. 'lightweight flywheel'->lightFlywheel, 'long-tube headers'->longHeaders, 'stroker'->longStroke, 'big turbo'->highBoost). Empty list if none mentioned.")
    var features: [GenFeature]
}

// MARK: - Stage 6: Vibe

@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenCamProfile: String {
    case economy, stock, sport, race
    var design: DesignCamProfile {
        switch self {
        case .economy: return .economy; case .stock: return .stock
        case .sport: return .sport;     case .race: return .race
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenPowerBand: String {
    case lowEnd, broad, topEnd
    var design: DesignPowerBand {
        switch self { case .lowEnd: return .lowEnd; case .broad: return .broad; case .topEnd: return .topEnd }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenIdle: String {
    case smooth, mild, lumpy
    var design: DesignIdle {
        switch self { case .smooth: return .smooth; case .mild: return .mild; case .lumpy: return .lumpy }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenGearing: String {
    case short, balanced, tall
    var design: DesignGearing {
        switch self { case .short: return .short; case .balanced: return .balanced; case .tall: return .tall }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenVehicleClass: String {
    case lightweight, sportsCar, sedan, muscle, supercar, truck, raceCar, motorcycle
    var design: DesignVehicleClass {
        switch self {
        case .lightweight: return .lightweight; case .sportsCar: return .sportsCar
        case .sedan: return .sedan;             case .muscle: return .muscle
        case .supercar: return .supercar;       case .truck: return .truck
        case .raceCar: return .raceCar;         case .motorcycle: return .motorcycle
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenSound: String {
    case smooth, stock, aggressive, raw
    var design: DesignSound {
        switch self {
        case .smooth: return .smooth; case .stock: return .stock
        case .aggressive: return .aggressive; case .raw: return .raw
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
struct GenVibeStage {
    @Guide(description: "Short evocative engine name fitting the description.")
    var name: String
    @Guide(description: "Cam character: economy(smooth daily), stock, sport, race(lumpy aggressive).")
    var camProfile: GenCamProfile
    @Guide(description: "Where power lives: lowEnd(torquey), broad, topEnd(peaky high-rpm).")
    var powerBand: GenPowerBand
    @Guide(description: "Idle feel: smooth, mild, lumpy.")
    var idle: GenIdle
    @Guide(description: "Vehicle archetype this engine belongs in.")
    var vehicleClass: GenVehicleClass
    @Guide(description: "Exhaust tone.")
    var sound: GenSound
    @Guide(description: "Gearing feel: short(acceleration), balanced, tall(cruising).")
    var gearing: GenGearing
}

// MARK: - Generator

@available(macOS 26.0, iOS 26.0, *)
struct AIEngineGenerator {

    private static let extractTemp = 0.0
    private static let vibeTemp = 0.3

    static var availability: EngineGeneratorAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(let reason): return .unavailable(describe(reason))
        @unknown default: return .unavailable("On-device model is unavailable.")
        }
    }

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:           return "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in Settings to use AI generation."
        case .modelNotReady:               return "The on-device model is still downloading. Try again shortly."
        @unknown default:                  return "The on-device model is unavailable."
        }
    }

    func generate(from description: String) async throws -> EngineSpec {
        guard case .available = Self.availability else {
            let reason: String = { if case .unavailable(let r) = Self.availability { return r }; return "Unavailable." }()
            throw EngineGenerationError.modelUnavailable(reason)
        }

        // Extraction stages are resilient: if one fails, treat it as "unspecified".
        let layout = (try? await extract(description,
            "Your only job: identify the engine cylinder layout the user asked for. Do not infer it from the car's vibe — only from explicit words. If no layout is named, answer unspecified.",
            GenLayoutStage.self))?.layout.engineLayout

        let size = try? await extract(description,
            "Your only job: find the engine displacement in litres if the user stated it or named a specific engine. Otherwise set stated=false.",
            GenSizeStage.self)

        let induction = try? await extract(description,
            "Your only job: detect forced induction and fuel type, but ONLY if the user mentions them. Otherwise unspecified.",
            GenInductionStage.self)

        let tune = try? await extract(description,
            "Your only job: find an explicit redline RPM and/or compression ratio if the user gave them. Otherwise set the matching stated flag false.",
            GenTuneStage.self)

        let features = (try? await extract(description,
            "Your only job: list specific mechanical parts the user explicitly mentions, as tags. Empty list if none.",
            GenFeatureStage.self))?.features ?? []

        // Vibe is required — it supplies the name and character.
        let vibe = try await extractVibe(description)

        let intent = EngineIntent(
            name: vibe.name,
            layout: layout,
            displacementL: (size?.stated == true) ? size?.litres : nil,
            redlineRpm: (tune?.redlineStated == true) ? tune?.redlineRpm : nil,
            compressionRatio: (tune?.compressionStated == true) ? tune?.compressionRatio : nil,
            aspiration: induction?.aspiration.design,
            fuel: induction?.fuel.preset,
            camProfile: vibe.camProfile.design,
            powerBand: vibe.powerBand.design,
            idle: vibe.idle.design,
            vehicleClass: vibe.vehicleClass.design,
            sound: vibe.sound.design,
            gearing: vibe.gearing.design,
            features: Set(features.map { $0.design })
        )

        return EngineDesignExpander.expand(intent)
    }

    // MARK: Stage helpers

    private func extract<T: Generable>(_ description: String, _ instructions: String, _ type: T.Type) async throws -> T {
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(
            to: description, generating: type,
            options: GenerationOptions(temperature: Self.extractTemp)
        ).content
    }

    private func extractVibe(_ description: String) async throws -> GenVibeStage {
        let session = LanguageModelSession(instructions:
            "Read the overall feel of the engine description and classify it: what car it belongs in, how it behaves. Pick the closest option for every field and invent a fitting name.")
        return try await session.respond(
            to: description, generating: GenVibeStage.self,
            options: GenerationOptions(temperature: Self.vibeTemp)
        ).content
    }
}
