//
//  AIEngineGenerator.swift
//  engine-simulator
//
//  Per-dimension, on-device engine generation via Apple's Foundation Models.
//  A 3B model is unreliable when asked to fill many coupled fields in one call
//  (it would read "fast one-cylinder" and still hand back a slow 6k-rpm motor),
//  so the work is split into MANY focused single-question calls. Each call has
//  ONE narrow job — "how fast does the user want this?", "how high does it rev?",
//  "what cam character?" — and the model never juggles coupled numbers.
//
//  Calls fire concurrently (async let) and merge into an EngineIntent. Explicit
//  facts the deterministic keyword pass already nailed (displacement, redline,
//  layout, …) skip their model call entirely. A final reconciliation pass folds
//  the rev-character vibe into the redline target and enforces cross-field
//  coherence the per-axis calls can't see on their own. EngineDesignExpander
//  then does all the heavy procedural work.
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
enum GenYesNoChoice: String {
    case unspecified, yes, no
    var bool: Bool? {
        switch self { case .unspecified: return nil; case .yes: return true; case .no: return false }
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
    @Guide(description: "true only if the user gave an EXPLICIT redline / max-rpm NUMBER (e.g. '9000 rpm', 'redline 7500'); false if they only used vibe words like 'high revving'.")
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
enum GenPerformance: String {
    case weak, modest, strong, extreme
    var design: DesignPerformance {
        switch self {
        case .weak: return .weak; case .modest: return .modest
        case .strong: return .strong; case .extreme: return .extreme
        }
    }
}

/// How high the engine wants to rev, as a FEELING — used when the user gives no
/// explicit redline number. Folded into the redline target by the reconciler.
@available(macOS 26.0, iOS 26.0, *)
@Generable
enum GenRevCharacter: String {
    case low, medium, high, screamer
    var character: RevCharacter {
        switch self {
        case .low: return .low; case .medium: return .medium
        case .high: return .high; case .screamer: return .screamer
        }
    }
}

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

@available(macOS 26.0, iOS 26.0, *)
struct AIEngineGenerator {

    private static let classifyTemp = 0.0
    private static let creativeTemp = 0.5
    private static let maxNameLength = 40

    // Each instruction is ONE narrow job. Single-job framing is what makes a
    // small model reliable — it can't conflate the question with a neighbour.
    private enum Inst {
        static let performance = """
        Judge ONLY how FAST / powerful the user wants this engine, on a 4-step \
        scale: weak, modest, strong, extreme.
        weak = slow, gutless, economy, sluggish, grandma, eco, putt-putt.
        modest = ordinary daily, normal, nothing special.
        strong = fast, quick, rapid, sporty, punchy, lively, spirited.
        extreme = insane, monster, brutal, race, maximum, rocket, ballistic, \
        track weapon, fastest possible.
        IGNORE engine size and cylinder count entirely: a "fast single-cylinder" \
        is strong or extreme, NOT weak. A "slow V8" is weak. Read the user's \
        intent about SPEED, nothing else.
        """

        static let revCharacter = """
        Judge ONLY how high this engine likes to REV, as a feeling: low, medium, \
        high, screamer.
        low = lazy, low-rpm, torquey diesel/truck, big lazy cruiser.
        medium = ordinary engine, no rev comment.
        high = high-revving, revvy, loves to rev, spins up fast, "high rev", \
        "high rpm", buzzy.
        screamer = screamer, F1/race wail, motorcycle/superbike, redline monster, \
        revs forever, stratospheric rpm.
        Words like "high rev" or "high revving" MUST map to high (or screamer if \
        extreme). Do not downplay them.
        """

        static let cam = """
        Pick the camshaft character: economy (smooth quiet daily), stock \
        (ordinary), sport (lively, slight lope), race (big lumpy aggressive cam). \
        Base it on how aggressive/racy the description sounds.
        """

        static let idle = """
        Pick the idle character: smooth (refined, luxury, quiet), mild (ordinary), \
        lumpy (racy, choppy, big-cam thump). Base it on aggressiveness.
        """

        static let sound = """
        Pick the exhaust tone: smooth (quiet/refined), stock (ordinary), \
        aggressive (loud/snarly), raw (unfiltered/violent open-pipe).
        """

        static let powerBand = """
        Where does the power live? lowEnd (low-rpm grunt/torque, trucks, \
        cruisers, towing), broad (usable everywhere), topEnd (peaky high-rpm \
        power, race engines, bikes, screamers).
        """

        static let gearing = """
        Pick the gearing: short (hard acceleration, drag, off-the-line), \
        balanced (all-round), tall (relaxed cruising, highway, top speed).
        """

        static let vehicleClass = """
        What kind of vehicle is this engine for? lightweight, sportsCar, sedan, \
        muscle, supercar, truck, raceCar, motorcycle. Infer from the description; \
        if it just sounds like an ordinary car, pick sedan or sportsCar.
        """

        static let layout = """
        What cylinder layout did the user ask for? Answer unspecified unless they \
        clearly stated or strongly implied one (single, inline2-7, v6/v8/v10/v12, \
        flat4/flat6).
        """

        static let aspiration = """
        Did the user ask for forced induction? unspecified unless they imply it: \
        turbocharged (turbo/boosted), supercharged (blower/whipple/roots), or \
        naturallyAspirated (all-motor / N/A).
        """

        static let fuel = """
        What fuel did the user call for? unspecified unless implied: gasoline, \
        e85 (ethanol/flex), methanol, diesel.
        """

        static let vtec = """
        Did the user ask for a Honda-style variable valvetrain (VTEC / variable \
        valve / VVT, or a Honda/Acura engine)? yes / no / unspecified.
        """

        static let displacement = """
        Did the user state a displacement, OR name a real engine/car whose size \
        you know? If so report it in litres; otherwise stated=false.
        """

        static let redline = """
        Did the user give an EXPLICIT redline / max-rpm NUMBER (digits like \
        "9000 rpm" or "redline 7500")? Vibe words like "high revving" do NOT \
        count — those are handled elsewhere. If a real number, report it; else \
        stated=false.
        """

        static let compression = """
        Did the user give an explicit compression ratio (e.g. "11:1")? If so \
        report it; otherwise stated=false.
        """

        static let features = """
        List specific mechanical PARTS the user explicitly named. Empty if none.
        """

        static let name = """
        Invent a short, evocative engine name (2-4 words) that fits the \
        description. No quotes, no explanation, just the name.
        """
    }

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

    // MARK: - Orchestration

    func generate(from d: String) async throws -> EngineSpec {
        guard case .available = Self.availability else {
            let reason: String = { if case .unavailable(let r) = Self.availability { return r }; return "Unavailable." }()
            throw EngineGenerationError.modelUnavailable(reason)
        }

        // Deterministic facts first — explicit words ("inline six", "5.7L",
        // "twin turbo") resolve here with 100% reliability and SKIP their model
        // call. The model only handles what's left: the fuzzy, feel-based axes.
        let kw = PromptKeywords.extract(from: d)

        // Every focused call fires at once. Each is a single narrow question, so
        // the model never has to hold coupled fields in its head simultaneously.
        async let performance = classify(d, Inst.performance, GenPerformance.self, fallback: .modest)
        async let revChar     = classify(d, Inst.revCharacter, GenRevCharacter.self, fallback: .medium)
        async let cam         = classify(d, Inst.cam, GenCamProfile.self, fallback: .stock)
        async let idle        = classify(d, Inst.idle, GenIdle.self, fallback: .mild)
        async let sound       = classify(d, Inst.sound, GenSound.self, fallback: .stock)
        async let powerBand   = classify(d, Inst.powerBand, GenPowerBand.self, fallback: .broad)
        async let gearing     = classify(d, Inst.gearing, GenGearing.self, fallback: .balanced)
        async let vehicle     = resolveVehicleClass(d, kw)
        async let layout      = resolveLayout(d, kw)
        async let aspiration  = resolveAspiration(d, kw)
        async let fuel        = resolveFuel(d, kw)
        async let vtec        = resolveVtec(d, kw)
        async let displacement = resolveDisplacement(d, kw)
        async let redline     = resolveRedlineNumber(d, kw)
        async let compression = resolveCompression(d, kw)
        async let features    = resolveFeatures(d, kw)
        async let name        = resolveName(d)

        let resolvedLayout = await layout
        var intent = EngineIntent(
            name: cleanName(await name, layout: resolvedLayout, camProfile: (await cam).design),
            layout: resolvedLayout,
            displacementL: await displacement,
            redlineRpm: await redline,
            compressionRatio: await compression,
            aspiration: await aspiration,
            fuel: await fuel,
            vtec: await vtec,
            performance: flooredPerformance((await performance).design, floor: kw.performanceFloor),
            condition: kw.condition ?? .normal,
            camProfile: (await cam).design,
            powerBand: (await powerBand).design,
            idle: (await idle).design,
            vehicleClass: await vehicle,
            sound: (await sound).design,
            gearing: (await gearing).design,
            features: await features
        )

        IntentReconciler.reconcile(&intent, revCharacter: (await revChar).character)
        return EngineDesignExpander.expand(intent)
    }

    /// The model's power judgement, raised to the keyword floor if one fired.
    /// Never lowered — "fast" can only make an engine faster, not slower.
    private func flooredPerformance(_ model: DesignPerformance, floor: DesignPerformance?) -> DesignPerformance {
        guard let floor, floor.rank > model.rank else { return model }
        return floor
    }

    // MARK: - Resolvers (keyword wins; model only fills the gap)

    private func resolveLayout(_ d: String, _ kw: KeywordHints) async -> EngineLayout? {
        if let l = kw.layout { return l }
        return await classify(d, Inst.layout, GenLayoutChoice.self, fallback: .unspecified).engineLayout
    }

    private func resolveVehicleClass(_ d: String, _ kw: KeywordHints) async -> DesignVehicleClass {
        if let v = kw.vehicleClass { return v }
        return await classify(d, Inst.vehicleClass, GenVehicleClass.self, fallback: .sportsCar).design
    }

    private func resolveAspiration(_ d: String, _ kw: KeywordHints) async -> DesignAspiration? {
        if let a = kw.aspiration { return a }
        return await classify(d, Inst.aspiration, GenAspirationChoice.self, fallback: .unspecified).design
    }

    private func resolveFuel(_ d: String, _ kw: KeywordHints) async -> FuelPreset? {
        if let f = kw.fuel { return f }
        return await classify(d, Inst.fuel, GenFuelChoice.self, fallback: .unspecified).preset
    }

    private func resolveVtec(_ d: String, _ kw: KeywordHints) async -> Bool? {
        if let v = kw.vtec { return v }
        return await classify(d, Inst.vtec, GenYesNoChoice.self, fallback: .unspecified).bool
    }

    private func resolveDisplacement(_ d: String, _ kw: KeywordHints) async -> Double? {
        if let v = kw.displacementL { return v }
        guard let s = await structured(d, Inst.displacement, GenSizeStage.self), s.stated else { return nil }
        return s.litres
    }

    private func resolveRedlineNumber(_ d: String, _ kw: KeywordHints) async -> Double? {
        if let v = kw.redlineRpm { return v }
        guard let s = await structured(d, Inst.redline, GenRedlineStage.self), s.stated else { return nil }
        return s.rpm
    }

    private func resolveCompression(_ d: String, _ kw: KeywordHints) async -> Double? {
        if let v = kw.compressionRatio { return v }
        guard let s = await structured(d, Inst.compression, GenCompressionStage.self), s.stated else { return nil }
        return s.ratio
    }

    private func resolveFeatures(_ d: String, _ kw: KeywordHints) async -> Set<DesignFeature> {
        var f = kw.features
        if let stage = await structured(d, Inst.features, GenFeatureStage.self) {
            for gf in stage.features { f.insert(gf.design) }
        }
        return f
    }

    private func resolveName(_ d: String) async -> String {
        (await structured(d, Inst.name, GenNameStage.self, temp: Self.creativeTemp))?.name ?? ""
    }

    // MARK: - Model call helpers (a failed/empty call falls back; never throws)

    private func classify<T: Generable>(_ d: String, _ instructions: String,
                                        _ type: T.Type, fallback: T) async -> T {
        (await structured(d, instructions, type)) ?? fallback
    }

    private func structured<T: Generable>(_ d: String, _ instructions: String,
                                          _ type: T.Type, temp: Double = classifyTemp) async -> T? {
        do {
            let session = LanguageModelSession(instructions: instructions)
            return try await session.respond(to: d, generating: type,
                                              options: GenerationOptions(temperature: temp)).content
        } catch {
            return nil
        }
    }

    // MARK: - Name cleanup

    private func cleanName(_ raw: String, layout: EngineLayout?, camProfile: DesignCamProfile) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\"'"))
        if !trimmed.isEmpty && trimmed.count <= Self.maxNameLength { return trimmed }
        let adj: String
        switch camProfile {
        case .economy: adj = "Street"; case .stock: adj = "Custom"
        case .sport: adj = "Sport"; case .race: adj = "Race"
        }
        return "\(adj) \(layout?.shortLabel ?? "Engine")"
    }
}
