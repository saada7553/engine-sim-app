//
//  ContentModerator.swift
//  engine-simulator
//
//  The shared profanity / appropriateness core used everywhere user-typed text
//  becomes public: leaderboard + community usernames (UsernameValidator) and the
//  name / description of any shared engine (EngineContentValidator). Two layers,
//  cheapest first:
//
//    1. Blocklist — a bundled profanity list with leetspeak normalisation
//                   (always available; the offline floor when Apple Intelligence
//                   is off, which is every device below macOS/iOS 26).
//    2. Model     — Apple's on-device Foundation Models judges appropriateness,
//                   catching disguised/creative spellings the list misses. Only
//                   runs when available; additive, never the sole gate.
//
//  The model's own safety guardrail throws on egregious input — we treat that
//  throw as a rejection (fail-closed), while other (operational) model failures
//  soft-pass since the blocklist already cleared the text.
//

import Foundation
import FoundationModels

enum ContentModerator {

    /// True if `text` is clean enough to make public. Runs the instant blocklist
    /// first and only awaits the on-device model when the list passes and the
    /// model is available. `modelInstructions` frames the screening task for the
    /// surface being checked (a username vs. an engine description).
    static func isClean(_ text: String, modelInstructions: String) async -> Bool {
        if containsBlockedWord(text) { return false }
        if #available(macOS 26.0, iOS 26.0, *) {
            return await modelApproves(text, instructions: modelInstructions)
        }
        return true
    }

    // MARK: Layer 1 — blocklist

    /// Common substitutions collapse so "a$$", "sh1t", "f@g" normalise to their
    /// plain spelling before the substring check. Lowercased and stripped of
    /// separators so spacing/casing can't smuggle a word past the list.
    private static func normalise(_ text: String) -> String {
        let substitutions: [Character: Character] = [
            "0": "o", "1": "i", "3": "e", "4": "a", "5": "s",
            "7": "t", "8": "b", "9": "g", "@": "a", "$": "s", "!": "i"
        ]
        let lowered = text.lowercased()
        var result = ""
        for char in lowered {
            if char.isLetter { result.append(char) }
            else if let sub = substitutions[char] { result.append(sub) }
            // digits/separators with no mapping are dropped, not preserved,
            // so "f u c k" and "f-u-c-k" both collapse to "fuck".
        }
        return result
    }

    /// Slurs / profanity in normalised form (lowercase letters only — leetspeak
    /// and separators are already collapsed by `normalise`, so a single root here
    /// matches every spacing/digit/suffix variant: "fuck" also catches "f u c k",
    /// "f4ck" and "motherfucker"). It backstops the on-device model and is the
    /// whole filter on devices below macOS/iOS 26.
    ///
    /// Two deliberate rules keep this useful rather than just long:
    ///   • Roots, not inflections. `.contains` matching means a root covers all
    ///     its compounds, so listing them separately would be dead weight.
    ///   • No short, ambiguous fragments. Because matching is substring over a
    ///     separator-stripped string, a token like "anal"/"homo"/"slant" would
    ///     wrongly block "analog"/"homologation"/"Slant-6" — exactly the words a
    ///     car app sees. Those are intentionally omitted; the model layer (and
    ///     user reports) catch what a safe-substring list can't.
    private static let blockedWords: [String] = [
        // ── General profanity / vulgarity ───────────────────────────────────
        "fuck", "shit", "bitch", "cunt", "asshole", "arsehole", "dumbass",
        "jackass", "bastard", "dick", "prick", "pussy", "cock", "wank",
        "twat", "bollocks", "bugger", "bellend", "knobhead", "numbnuts",
        "tosser", "wanker", "douche", "douchebag", "scumbag", "gobshite",
        "piss", "slut", "whore", "hooker", "skank", "fuckwit", "fucktard",
        "shitbag", "cocksucker", "motherfucker", "asshat", "dickhead",
        // ── Sexual / explicit ───────────────────────────────────────────────
        "blowjob", "handjob", "rimjob", "rimming", "cumshot", "creampie",
        "cumdump", "jizz", "spunk", "jerkoff", "jackoff", "fap", "coomer",
        "dildo", "buttplug", "butthole", "anus", "rectum", "genital",
        "penis", "vagina", "clitoris", "labia", "scrotum", "ballsack",
        "nutsack", "boner", "erection", "ejaculat", "semen", "felch",
        "gangbang", "bukkake", "deepthroat", "fellatio", "cunnilingus",
        "sodomy", "sodomize", "bestiality", "incest", "molest", "pedophile",
        "paedophile", "rape", "rapist", "fondle", "upskirt", "voyeur",
        "porn", "pornhub", "hentai", "milf", "gilf", "nympho", "orgasm",
        "orgy", "threesome", "cameltoe", "queef", "smegma", "fuckboy",
        "fuckface", "goldenshower", "lesbo", "tits", "titties", "boobs",
        // ── Racial / ethnic slurs ───────────────────────────────────────────
        "nigger", "nigga", "nigress", "niglet", "jigaboo", "jiggaboo",
        "pickaninny", "porchmonkey", "junglebunny", "darkie", "sambo",
        "tarbaby", "coonass", "wigger", "negroid", "groid", "mulatto",
        "halfbreed", "uncletom", "spic", "beaner", "wetback", "greaseball",
        "chink", "chinaman", "gook", "zipperhead", "coolie", "paki",
        "raghead", "towelhead", "sandnigger", "cameljockey", "muzzie",
        "mudslime", "redskin", "injun", "squaw", "wagonburner", "gyppo",
        "kraut", "wop", "dago", "polack", "gringo", "pajeet", "poopjeet",
        // ── Antisemitic / religious slurs ───────────────────────────────────
        "kike", "heeb", "hymie", "sheeny", "shylock", "christkiller", "zog",
        // ── Homophobic / transphobic slurs ──────────────────────────────────
        "faggot", "faggit", "dyke", "queer", "poofter", "tranny", "shemale",
        "ladyboy", "fudgepacker", "buttpirate", "carpetmuncher", "rugmuncher",
        // ── Ableist slurs ───────────────────────────────────────────────────
        "retard", "spastic", "mongoloid", "midget", "cripple",
        // ── Hate / extremism / violence ─────────────────────────────────────
        "nazi", "hitler", "heilhitler", "gestapo", "klansman", "whitepower",
        "swastika", "jihadist", "terrorist", "alqaeda", "incel",
        // ── Self-harm harassment ────────────────────────────────────────────
        "kys", "killyourself", "killurself"
    ]

    /// True if `text` contains a blocked word after normalisation.
    static func containsBlockedWord(_ text: String) -> Bool {
        let normalised = normalise(text)
        return blockedWords.contains { normalised.contains($0) }
    }

    // MARK: Layer 2 — on-device model

    @available(macOS 26.0, iOS 26.0, *)
    @Generable
    fileprivate struct AppropriatenessJudgement {
        @Guide(description: "true if the text is appropriate for a public space seen by all ages; false if it is profane, a slur, sexual, hateful, or harassing — including disguised or leetspeak spellings.")
        var isAppropriate: Bool
    }

    /// Asks the on-device model whether `text` is appropriate. Returns true on a
    /// positive judgement, false when flagged or when the safety guardrail throws.
    @available(macOS 26.0, iOS 26.0, *)
    static func modelApproves(_ text: String, instructions: String) async -> Bool {
        guard case .available = SystemLanguageModel.default.availability else {
            return true   // model not ready; the blocklist already cleared it
        }

        let session = LanguageModelSession(instructions: instructions)
        do {
            let judgement = try await session.respond(
                to: text,
                generating: AppropriatenessJudgement.self,
                options: GenerationOptions(temperature: 0.0)
            ).content
            return judgement.isAppropriate
        } catch {
            // Apple's safety guardrail throws (rather than returning false) on
            // egregious input — treat that as a rejection so a slur can't slip
            // through when the model declines to even classify it. Matched on the
            // error's description so we don't depend on the exact private case
            // spelling. Any other (operational) failure soft-passes, since the
            // blocklist layer already cleared the text.
            let description = String(describing: error).lowercased()
            if description.contains("guardrail") || description.contains("safety") {
                return false
            }
            return true
        }
    }
}
