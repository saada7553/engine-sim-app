//
//  AIEngineGenerator.swift
//  engine-simulator
//
//  Many-stage, on-device engine generation via Apple's Foundation Models.
//  A 3B model is unreliable when asked to pull several fields at once, so each
//  subsystem gets its OWN focused call with a single, narrow job and an
//  explicit "unspecified" answer. Stages run concurrently and merge into an
//  EngineIntent; EngineDesignExpander does all the heavy procedural work.
//
//  Stages: layout, displacement, aspiration, fuel, redline, compression, cam
//  character, power band, idle character, vehicle class, sound, gearing,
//  feature tags, and name. Extraction stages are resilient — a failed/empty
//  stage just means "the user didn't say", and the expander fills it.
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

// MARK: - Extraction enums (each generated directly; "unspecified" = not stated)

@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenLayoutChoice: String {
    case unspecified
    case single, inline2, inline3, inline4, inline5, inline6, inline7
    case v6_60, v6_90, v8_90, v10_72, v12_60, v12_75
    case flat4, flat6

    var engineLayout: EngineLayout? {
        switch self {
        case .unspecified: return nil
        case .single: return .inline1;  case .inline2: return .inline2
        case .inline3: return .inline3;  case .inline4: return .inline4
        case .inline5: return .inline5;  case .inline6: return .inline6
        case .inline7: return .inline7
        case .v6_60: return .v6_60;      case .v6_90: return .v6_90
        case .v8_90: return .v8_90;      case .v10_72: return .v10_72
        case .v12_60: return .v12_60;    case .v12_75: return .v12_75
        case .flat4: return .flat4;      case .flat6: return .flat6
        }
    }
}

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
struct GenSizeStage {
    @Guide(description: "true only if the user stated a displacement or named an engine that fixes it; false otherwise.")
    var stated: Bool
    @Guide(description: "Displacement in litres (used only when stated). 2JZ=3.0, LS=5.7, Coyote=5.0, Hayabusa=1.3.", .range(0.5...30.0))
    var litres: Double
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
struct GenRedlineStage {
    @Guide(description: "true only if the user gave an explicit redline / max RPM; false otherwise.")
    var stated: Bool
    @Guide(description: "Redline RPM (used only when stated).", .range(3000.0...18000.0))
    var rpm: Double
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
struct GenCompressionStage {
    @Guide(description: "true only if the user gave an explicit compression ratio; false otherwise.")
    var stated: Bool
    @Guide(description: "Compression ratio (used only when stated).", .range(7.0...14.0))
    var ratio: Double
}

// MARK: - Character enums (always answered; generated directly)

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
enum GenPerformance: String {
    case weak, modest, strong, extreme
    var design: DesignPerformance {
        switch self {
        case .weak: return .weak; case .modest: return .modest
        case .strong: return .strong; case .extreme: return .extreme
        }
    }
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenCondition: String {
    case fresh, normal, worn
    var design: DesignCondition {
        switch self {
        case .fresh: return .fresh; case .normal: return .normal; case .worn: return .worn
        }
    }
}

// MARK: - Features + name

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
    case worn
    case freshBuild

    var design: DesignFeature {
        switch self {
        case .worn: return .worn
        case .freshBuild: return .freshBuild
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
    @Guide(description: "Tags for specific parts the user explicitly mentions (e.g. 'lightweight flywheel'->lightFlywheel, 'long-tube headers'->longHeaders, 'stroker'->longStroke, 'big turbo'->highBoost). Empty if none.")
    var features: [GenFeature]
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
struct GenNameStage {
    @Guide(description: "A short, evocative engine name (2-4 words) that fits the description. No quotes, no explanation.")
    var name: String
}

// MARK: - Generator

// MARK: - Holistic design draft (one coherent reasoning pass)

@available(macOS 26.0, iOS 26.0, *)
@Generable
struct EngineDesignDraft {
    @Guide(description: "First think: in one sentence, identify what this engine/car is and its character (e.g. 'a worn-out economy commuter four', 'a Toyota 2JZ turbo inline-six', 'a supercharged Mad Max muscle V8').")
    var analysis: String

    @Guide(description: "Cylinder layout that matches the description and analysis.")
    var layout: GenLayoutChoice

    @Guide(description: "Total displacement in litres, realistic for THIS engine. economy I4 ~1.6, S2000 ~2.0, 2JZ ~3.0, inline-six ~3.0, LS V8 ~5.7, muscle/monster V8 ~6.2-7.0, road V12 ~6.0, F1/prototype race engine 1.6-3.0 (small but high-revving), sportbike ~1.0, single thumper ~0.5, diesel truck ~6.5.", .range(0.3...30.0))
    var displacementLitres: Double

    @Guide(description: "Redline RPM. Diesel/truck 4500-5500, economy/worn 5500-6500, daily 6500-7000, sporty NA 7500-8500, supercar 8500-9500, sportbike 12000-15000, F1/prototype race 15000-18000. A SLOW or WORN engine MUST be low; a race screamer very high.", .range(3000.0...18000.0))
    var redlineRpm: Double

    @Guide(description: "Intended power level. weak=slow/gutless/economy/worn; modest=ordinary daily; strong=fast/sporty; extreme=high-horsepower/race/monster.")
    var performance: GenPerformance

    @Guide(description: "Condition. fresh=new/rebuilt/blueprinted; normal=ordinary; worn=old/tired/high-mileage/beat-up/smoky. Use normal unless age/wear is implied.")
    var condition: GenCondition

    @Guide(description: "Aspiration: naturallyAspirated unless a turbo or supercharger is implied.")
    var aspiration: GenAspirationChoice

    @Guide(description: "Fuel: gasoline unless diesel / E85 / methanol is implied.")
    var fuel: GenFuelChoice

    @Guide(description: "Cam character: economy (smooth daily), stock, sport (lively), race (lumpy aggressive).")
    var camProfile: GenCamProfile

    @Guide(description: "Where power lives: lowEnd (torque, trucks/cruisers), broad, topEnd (peaky high-rpm, race/bike).")
    var powerBand: GenPowerBand

    @Guide(description: "Idle: smooth (refined), mild, lumpy (racy/choppy).")
    var idle: GenIdle

    @Guide(description: "Exhaust tone: smooth, stock, aggressive, raw.")
    var sound: GenSound

    @Guide(description: "Gearing: short (acceleration/drag), balanced, tall (cruising/highway/top speed).")
    var gearing: GenGearing

    @Guide(description: "Vehicle this engine belongs in: lightweight, sportsCar, sedan, muscle, supercar, truck, raceCar, motorcycle.")
    var vehicleClass: GenVehicleClass

    @Guide(description: "true only for a Honda VTEC-style variable valvetrain (Honda engines, or if VTEC/variable valve is mentioned).")
    var vtec: Bool

    @Guide(description: "A short, evocative engine name (2-4 words).")
    var name: String
}

// MARK: - Generator

@available(macOS 26.0, iOS 26.0, *)
struct AIEngineGenerator {

    private static let extractTemp = 0.0
    private static let creativeTemp = 0.4
    private static let designTemp = 0.0

    private static let designInstructions = """
    Design ONE coherent engine for the description (a named engine, a car, a \
    movie/character vehicle, or a vibe). Every field must agree:
    slow/economy/worn -> small, LOW redline, mild cam, tall gears, weak; \
    race/high-horsepower/monster -> large, aggressive cam, high redline, extreme.

    Use your knowledge to match real engines/cars (examples): 2JZ/Supra=turbo \
    inline-6 ~3.0L; RB26=turbo I6 ~2.6L; LS=V8 ~5.7L; Coyote=V8 ~5.0L; \
    Hellcat=supercharged V8 ~6.2L; Hayabusa/sportbike=high-rev I4 ~1.1L bike; \
    K20=I4 ~2.0L vtec; Cummins/Duramax=big diesel ~6.5L truck; Merlin=~27L V12; \
    Mad Max/Batmobile=huge V8. If unsure of a name, infer from era/country/type — \
    do NOT default to a generic 1.6L four unless it's truly economy.

    Fill `analysis` FIRST with ONE short sentence, then keep every field \
    consistent with it.
    """
    private static let maxNameLength = 40

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

    func generate(from d: String) async throws -> EngineSpec {
        guard case .available = Self.availability else {
            let reason: String = { if case .unavailable(let r) = Self.availability { return r }; return "Unavailable." }()
            throw EngineGenerationError.modelUnavailable(reason)
        }

        // ONE holistic reasoning call: the model reads the whole description,
        // thinks first (the `analysis` field, generated before the rest, acts
        // as chain-of-thought), then produces a coherent intent where every
        // field agrees. Its own knowledge handles named engines / movie cars /
        // vibes — no lexicon. The keyword pass is only a light override for
        // explicit facts the user spelled out.
        let kw = PromptKeywords.extract(from: d)
        let draft = try await run(d, Self.designInstructions, EngineDesignDraft.self, Self.designTemp)

        let layout = kw.layout ?? draft.layout.engineLayout
        let camProfile = draft.camProfile.design

        let intent = EngineIntent(
            name: cleanName(draft.name, layout: layout, camProfile: camProfile),
            layout: layout,
            displacementL: kw.displacementL ?? draft.displacementLitres,
            redlineRpm: kw.redlineRpm ?? draft.redlineRpm,
            compressionRatio: kw.compressionRatio,
            aspiration: kw.aspiration ?? draft.aspiration.design,
            fuel: kw.fuel ?? draft.fuel.preset,
            vtec: kw.vtec ?? draft.vtec,
            performance: draft.performance.design,
            condition: kw.condition ?? .normal,   // wear is keyword-driven; model over-reports "worn"
            camProfile: camProfile,
            powerBand: draft.powerBand.design,
            idle: draft.idle.design,
            vehicleClass: kw.vehicleClass ?? draft.vehicleClass.design,
            sound: draft.sound.design,
            gearing: draft.gearing.design,
            features: kw.features
        )

        return EngineDesignExpander.expand(intent)
    }

    private func cleanName(_ raw: String, layout: EngineLayout?, camProfile: DesignCamProfile) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\"'"))
        if !trimmed.isEmpty && trimmed.count <= 40 { return trimmed }
        let adj: String
        switch camProfile {
        case .economy: adj = "Street"; case .stock: adj = "Custom"
        case .sport: adj = "Sport"; case .race: adj = "Race"
        }
        return "\(adj) \(layout?.shortLabel ?? "Engine")"
    }

    // MARK: Helpers

    private func run<T: Generable>(_ description: String, _ instructions: String, _ type: T.Type, _ temp: Double) async throws -> T {
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(
            to: description, generating: type,
            options: GenerationOptions(temperature: temp)
        ).content
    }

    /// Clean the model's name; fall back to a sensible derived name if it's
    /// empty or junk (this is what the broken "GenVibe…" string was).
    private func sanitizedName(_ stage: GenNameStage?, layout: EngineLayout?, camProfile: DesignCamProfile) -> String {
        let raw = (stage?.name ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\"'"))
        if !raw.isEmpty && raw.count <= Self.maxNameLength {
            return raw
        }
        let adjective: String
        switch camProfile {
        case .economy: adjective = "Street"
        case .stock:   adjective = "Custom"
        case .sport:   adjective = "Sport"
        case .race:    adjective = "Race"
        }
        return "\(adjective) \(layout?.shortLabel ?? "Engine")"
    }
}
