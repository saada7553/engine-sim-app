//
//  UsernameValidator.swift
//  engine-simulator
//
//  Gate for leaderboard usernames. The board is public, so a name has to clear
//  three layers, cheapest first:
//
//    1. Format   — length + allowed characters (always, instant).
//    2. Blocklist — a bundled profanity list with leetspeak normalisation
//                   (always; the offline floor when Apple Intelligence is off).
//    3. Model     — Apple's on-device Foundation Models judges appropriateness,
//                   catching disguised/creative spellings the list misses. Only
//                   runs when available; it is additive, never the sole gate.
//
//  The model's own safety guardrail throws on flagged input — we treat that
//  throw as a rejection (fail-closed for obvious abuse), while other model
//  failures fall through to "accept", since layers 1–2 already passed.
//

import Foundation
import FoundationModels

// MARK: - Result

enum UsernameValidationResult: Equatable {
    case valid
    case invalid(String)   // user-facing reason

    var isValid: Bool { self == .valid }
    var reason: String? { if case .invalid(let r) = self { return r }; return nil }
}

// MARK: - Validator

enum UsernameValidator {

    /// Validate a raw, user-typed name. Runs the instant layers synchronously
    /// and only awaits the model when the first two pass and it is available.
    static func validate(_ raw: String) async -> UsernameValidationResult {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let formatError = formatError(for: name) { return .invalid(formatError) }
        if containsBlockedWord(name) { return .invalid(rejectionReason) }

        if #available(macOS 26.0, iOS 26.0, *) {
            return await modelJudgement(for: name)
        }
        return .valid
    }

    // MARK: Layer 1 — format

    private static func formatError(for name: String) -> String? {
        if name.count < UsernameRules.minLength {
            return "Pick a name with at least \(UsernameRules.minLength) characters."
        }
        if name.count > UsernameRules.maxLength {
            return "Keep it under \(UsernameRules.maxLength) characters."
        }
        if name.unicodeScalars.contains(where: { !UsernameRules.allowed.contains($0) }) {
            return "Use only letters, numbers, spaces, _ or -."
        }
        return nil
    }

    // MARK: Layer 2 — blocklist

    private static let rejectionReason = "That name isn't allowed. Try another."

    /// Common substitutions collapse so "a$$", "sh1t", "f@g" normalise to their
    /// plain spelling before the substring check. Lowercased and stripped of
    /// separators so spacing/casing can't smuggle a word past the list.
    private static func normalise(_ name: String) -> String {
        let substitutions: [Character: Character] = [
            "0": "o", "1": "i", "3": "e", "4": "a", "5": "s",
            "7": "t", "8": "b", "9": "g", "@": "a", "$": "s", "!": "i"
        ]
        let lowered = name.lowercased()
        var result = ""
        for char in lowered {
            if char.isLetter { result.append(char) }
            else if let sub = substitutions[char] { result.append(sub) }
            // digits/separators with no mapping are dropped, not preserved,
            // so "f u c k" and "f-u-c-k" both collapse to "fuck".
        }
        return result
    }

    /// Seed list of slurs / profanity in normalised form. Deliberately compact —
    /// it backstops the model and covers the offline case; extend as needed.
    private static let blockedWords: [String] = [
        "fuck", "shit", "bitch", "cunt", "asshole", "bastard", "dick",
        "pussy", "cock", "slut", "whore", "nigger", "nigga", "faggot",
        "retard", "rape", "nazi", "hitler", "kike", "spic", "chink",
        "wank", "twat", "bollocks", "jizz", "cum", "tits", "boner"
    ]

    private static func containsBlockedWord(_ name: String) -> Bool {
        let normalised = normalise(name)
        return blockedWords.contains { normalised.contains($0) }
    }

    // MARK: Layer 3 — on-device model

    @available(macOS 26.0, iOS 26.0, *)
    @Generable
    fileprivate struct UsernameJudgement {
        @Guide(description: "true if the name is appropriate for a public leaderboard seen by all ages; false if it is profane, a slur, sexual, hateful, or harassing — including disguised or leetspeak spellings.")
        var isAppropriate: Bool
    }

    @available(macOS 26.0, iOS 26.0, *)
    private static func modelJudgement(for name: String) async -> UsernameValidationResult {
        guard case .available = SystemLanguageModel.default.availability else {
            return .valid   // model not ready; layers 1–2 already cleared it
        }

        let instructions = "You screen usernames for a public video-game leaderboard. Decide if the given name is appropriate for an audience of all ages."
        let session = LanguageModelSession(instructions: instructions)

        do {
            let judgement = try await session.respond(
                to: name,
                generating: UsernameJudgement.self,
                options: GenerationOptions(temperature: 0.0)
            ).content
            return judgement.isAppropriate ? .valid : .invalid(rejectionReason)
        } catch {
            // Apple's safety guardrail throws (rather than returning false) on
            // egregious input — treat that as a rejection so a slur can't slip
            // through when the model declines to even classify it. Matched on
            // the error's description so we don't depend on the exact private
            // case spelling. Any other (operational) failure soft-passes, since
            // the format + blocklist layers already cleared the name.
            let description = String(describing: error).lowercased()
            if description.contains("guardrail") || description.contains("safety") {
                return .invalid(rejectionReason)
            }
            return .valid
        }
    }
}
