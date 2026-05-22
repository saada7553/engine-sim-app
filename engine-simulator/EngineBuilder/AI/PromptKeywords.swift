//
//  PromptKeywords.swift
//  engine-simulator
//
//  Deterministic keyword pre-pass. Explicit facts in the description — layout,
//  vehicle type, aspiration, fuel, displacement, redline, compression, named
//  features — are detected here with 100% reliability instead of trusting a
//  3B model to recognize obvious words like "sportbike" or "inline six". The
//  AI stages then only run for fields this pass leaves unresolved (the fuzzy,
//  feel-based ones). Facts -> keywords; feel -> model.
//
//  Framework-free / all-OS / unit-testable.
//

import Foundation

struct KeywordHints {
    var layout: EngineLayout?
    var displacementL: Double?
    var redlineRpm: Double?
    var compressionRatio: Double?
    var aspiration: DesignAspiration?
    var fuel: FuelPreset?
    var vtec: Bool?
    var vehicleClass: DesignVehicleClass?
    var camProfile: DesignCamProfile?
    var idle: DesignIdle?
    var sound: DesignSound?
    var gearing: DesignGearing?
    var powerBand: DesignPowerBand?
    var condition: DesignCondition?
    var features: Set<DesignFeature> = []
}

enum PromptKeywords {

    static func extract(from raw: String) -> KeywordHints {
        let t = " " + raw.lowercased() + " "
        var h = KeywordHints()

        h.layout = layout(in: t)
        h.vehicleClass = vehicleClass(in: t)
        h.aspiration = aspiration(in: t)
        h.fuel = fuel(in: t)
        h.vtec = vtec(in: t)
        h.displacementL = displacement(in: t)
        h.redlineRpm = redline(in: t)
        h.compressionRatio = compression(in: t)
        h.features = features(in: t)
        h.condition = condition(in: t)
        // Performance + feel (cam/idle/sound/gearing) are left to the AI's
        // holistic reasoning. Condition (wear) is explicit and the model is
        // unreliable on it, so it's keyword-driven here.

        return h
    }

    // MARK: - Condition (wear is explicit; the model over-reports "worn")

    private static func condition(in t: String) -> DesignCondition? {
        if t.containsAny(["worn", "tired", "high mileage", "high-mileage", "blowby", "blow-by",
                          "smoky", "smokey", "clapped", "beat up", "beat-up", "leaky", "leaking",
                          "old ", "ragged", "neglected", "rough idle", "rattly", "knackered"]) { return .worn }
        if t.containsAny(["fresh", "freshly built", "brand new", "rebuilt", "rebuild", "built engine",
                          "blueprinted", "new rings", "just built", "newly built", "showroom"]) { return .fresh }
        return nil
    }

    // MARK: - Layout

    private static func layout(in t: String) -> EngineLayout? {
        // Single + twin (check first; "twin turbo" is forced induction, NOT a 2-cyl).
        if t.containsAny(["single cylinder", "single-cylinder", "one cylinder", "one-cylinder",
                          "1 cylinder", "1-cylinder", "thumper"]) { return .inline1 }
        let twinTurbo = t.containsAny(["twin turbo", "twin-turbo", "twinturbo", "twin scroll", "twin-scroll"])
        if !twinTurbo && t.containsAny(["parallel twin", "v-twin", "v twin", "vtwin",
                                        "two cylinder", "two-cylinder", "2 cylinder", "2-cylinder",
                                        "twin cylinder"]) { return .inline2 }
        // V-engines (check before bare cylinder counts).
        if t.containsAny(["v12", "v-12", "v 12"]) { return .v12_60 }
        if t.containsAny(["v10", "v-10", "v 10"]) { return .v10_72 }
        if t.containsAny(["v8", "v-8", "v 8"])     { return .v8_90 }
        if t.containsAny(["v6", "v-6", "v 6"])     { return .v6_60 }
        // Flat / boxer.
        if t.containsAny(["flat six", "flat-six", "flat 6", "flat6", "boxer 6", "boxer six"]) { return .flat6 }
        if t.containsAny(["boxer", "flat four", "flat-four", "flat 4", "flat4"]) { return .flat4 }
        // Inline / straight.
        if t.containsInlineCount(7) { return .inline7 }
        if t.containsInlineCount(6) { return .inline6 }
        if t.containsInlineCount(5) { return .inline5 }
        if t.containsInlineCount(4) { return .inline4 }
        if t.containsInlineCount(3) { return .inline3 }
        if t.containsInlineCount(2) { return .inline2 }
        if t.containsInlineCount(1) { return .inline1 }
        return nil
    }

    // MARK: - Vehicle (motorcycle FIRST so "race bike" -> motorcycle, not raceCar)

    private static func vehicleClass(in t: String) -> DesignVehicleClass? {
        if t.containsAny(["sportbike", "superbike", "motorcycle", "motorbike", "motorb.ke", "litre bike", "liter bike", " bike ", "two-wheel", "two wheel"]) { return .motorcycle }
        if t.containsAny(["truck", "pickup", "pick-up", "hauler", "towing", "lorry", "semi "]) { return .truck }
        if t.containsAny(["muscle", "hot rod", "hotrod", "musclecar", "pony car", "ponycar"]) { return .muscle }
        if t.containsAny(["f1", "formula 1", "formula one", "formula", "le mans", "lemans", "race car", "racecar", "track car", "race ", "racing", "track weapon", "endurance"]) { return .raceCar }
        if t.containsAny(["supercar", "hypercar", "exotic", "ferrari", "lamborghini", "mclaren", "koenigsegg"]) { return .supercar }
        if t.containsAny(["lightweight", "featherweight", "kit car", "kit-car", "kart", "track toy", "stripped"]) { return .lightweight }
        if t.containsAny(["sedan", "saloon", "commuter", "daily", "grocery", "family car", "economy car"]) { return .sedan }
        if t.containsAny(["sports car", "sportscar", "roadster", "coupe", "coupé"]) { return .sportsCar }
        return nil
    }

    // MARK: - Aspiration

    private static func aspiration(in t: String) -> DesignAspiration? {
        if t.containsAny(["supercharg", "blower", "whipple", "roots", "positive displacement"]) { return .supercharged }
        if t.containsAny(["turbo", "boosted", "snail"]) { return .turbocharged }
        if t.containsAny(["naturally aspirated", "n/a ", " na ", "all motor", "all-motor"]) { return .naturallyAspirated }
        return nil
    }

    // MARK: - Fuel

    private static func fuel(in t: String) -> FuelPreset? {
        // methanol BEFORE ethanol — "methanol" contains the substring "ethanol".
        if t.containsAny(["methanol", "meth "]) { return .methanol }
        if t.containsAny(["e85", "ethanol", "flex fuel", "flex-fuel"]) { return .e85 }
        if t.containsAny(["diesel", "compression ignition", "oil burner"]) { return .diesel }
        if t.containsAny(["gasoline", "petrol", "pump gas", "race gas", "premium fuel"]) { return .gasoline }
        return nil
    }

    // MARK: - VTEC (explicit, or leaned-on for Honda)

    private static func vtec(in t: String) -> Bool? {
        if t.containsAny(["no vtec", "non-vtec", "non vtec", "without vtec", "vtec delete", "no variable valve"]) {
            return false
        }
        if t.containsAny(["vtec", "i-vtec", "ivtec", "variable valve", "variable cam", "vvt", "vvtl"]) {
            return true
        }
        // Honda / Acura context strongly implies VTEC unless ruled out above.
        if t.containsAny(["honda", "acura", " k20", " k24", " b16", " b18", " f20", " f22",
                          "type r", "type-r", "civic", "s2000", "integra", "rsx", "vtec"]) {
            return true
        }
        return nil
    }

    // MARK: - Displacement

    private static func displacement(in t: String) -> Double? {
        // Litres: "2.0l", "5.7 l", "3 litre".
        if let l = firstCapture(t, #"(\d{1,2}(?:\.\d{1,2})?)\s?-?\s?(?:l\b|litre|liter)"#), l >= 0.5, l <= 30 {
            return l
        }
        // CC: "1000cc", "650 cc".
        if let cc = firstCapture(t, #"(\d{2,4})\s?cc\b"#) {
            let l = cc / 1000.0
            if l >= 0.5, l <= 30 { return l }
        }
        return nil
    }

    // MARK: - Redline

    private static func redline(in t: String) -> Double? {
        if let r = firstCapture(t, #"(\d{4,5})\s?rpm"#), r >= 3000, r <= 12000 { return r }
        if let r = firstCapture(t, #"(?:redline|rev limit|revs? to|spins? to)\D{0,8}(\d{4,5})"#), r >= 3000, r <= 12000 { return r }
        return nil
    }

    // MARK: - Compression

    private static func compression(in t: String) -> Double? {
        if let c = firstCapture(t, #"(\d{1,2}(?:\.\d)?)\s?:\s?1"#), c >= 7, c <= 14 { return c }
        if let c = firstCapture(t, #"compression\D{0,10}(\d{1,2}(?:\.\d)?)"#), c >= 7, c <= 14 { return c }
        return nil
    }

    // MARK: - Features

    private static func features(in t: String) -> Set<DesignFeature> {
        var f = Set<DesignFeature>()
        if t.containsAny(["twin turbo", "twin-turbo", "biturbo", "big turbo", "high boost", "max boost"]) { f.insert(.highBoost) }
        if t.containsAny(["stroker", "long stroke", "long-stroke", "undersquare"]) { f.insert(.longStroke) }
        if t.containsAny(["big bore", "overbore", "over-bore", "oversquare"]) { f.insert(.bigBore) }
        if t.containsAny(["lightweight internal", "light internal", "forged light", "lightened rotating"]) { f.insert(.lightweightInternals) }
        if t.containsAny(["heavy flywheel", "heavier flywheel"]) { f.insert(.heavyFlywheel) }
        if t.containsAny(["light flywheel", "lightened flywheel", "lightweight flywheel"]) { f.insert(.lightFlywheel) }
        if t.containsAny(["big cam", "huge cam", "lumpy cam", "aggressive cam", "race cam"]) { f.insert(.bigCam) }
        if t.containsAny(["mild cam", "small cam", "stock cam"]) { f.insert(.mildCam) }
        if t.containsAny(["tight lsa", "narrow lsa", "tight lobe"]) { f.insert(.tightLSA) }
        if t.containsAny(["wide lsa", "wide lobe"]) { f.insert(.wideLSA) }
        if t.containsAny(["long tube", "long-tube", "longtube", "long header"]) { f.insert(.longHeaders) }
        if t.containsAny(["shorty header", "short header", "shorty"]) { f.insert(.shortHeaders) }
        if t.containsAny(["long runner", "long-runner"]) { f.insert(.longRunners) }
        if t.containsAny(["short runner", "short-runner"]) { f.insert(.shortRunners) }
        if t.containsAny(["big plenum", "large plenum"]) { f.insert(.bigPlenum) }
        if t.containsAny(["small plenum", "tight plenum"]) { f.insert(.smallPlenum) }
        if t.containsAny(["short gear", "close ratio", "close-ratio"]) { f.insert(.shortGears) }
        if t.containsAny(["tall gear", "long gear", "overdrive"]) { f.insert(.tallGears) }
        if t.containsAny(["high compression", "high-compression"]) { f.insert(.highCompression) }
        if t.containsAny(["low compression", "low-compression"]) { f.insert(.lowCompression) }
        if t.containsAny(["high revving", "high-revving", "screamer", "revs high", "high rpm", "high-rpm"]) { f.insert(.highRedline) }
        return f
    }

    // MARK: - Regex helper

    private static func firstCapture(_ text: String, _ pattern: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Double(text[r])
    }
}

// MARK: - String helpers

private extension String {
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }

    /// Matches "inline six", "straight 6", "i6", "l6", "6 cylinder" for the count.
    func containsInlineCount(_ n: Int) -> Bool {
        let words = ["", "one", "two", "three", "four", "five", "six", "seven"]
        let word = n < words.count ? words[n] : ""
        var variants = ["inline \(n)", "inline-\(n)", "inline\(n)", "straight \(n)", "straight-\(n)",
                        "i\(n) ", "l\(n) ", "\(n) cylinder", "\(n)-cylinder", "\(n) cyl"]
        if !word.isEmpty {
            variants += ["inline \(word)", "straight \(word)", "\(word) cylinder", "\(word)-cylinder"]
        }
        return containsAny(variants)
    }
}
