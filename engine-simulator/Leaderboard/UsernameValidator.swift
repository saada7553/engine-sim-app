//
//  UsernameValidator.swift
//  engine-simulator
//
//  Gate for leaderboard usernames. The board is public, so a name has to clear
//  three layers, cheapest first:
//
//    1. Format    — length + allowed characters (always, instant). Username-only,
//                   so it lives here.
//    2/3. Profanity — the blocklist + on-device model appropriateness check,
//                   shared with engine name/description screening via
//                   ``ContentModerator``.
//

import Foundation

// MARK: - Result

enum UsernameValidationResult: Equatable {
    case valid
    case invalid(String)   // user-facing reason

    var isValid: Bool { self == .valid }
    var reason: String? { if case .invalid(let r) = self { return r }; return nil }
}

// MARK: - Validator

enum UsernameValidator {

    /// Validate a raw, user-typed name. Format is checked instantly here; the
    /// profanity layers (blocklist + on-device model) are shared via
    /// ``ContentModerator``.
    static func validate(_ raw: String) async -> UsernameValidationResult {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let formatError = formatError(for: name) { return .invalid(formatError) }

        let clean = await ContentModerator.isClean(name, modelInstructions: modelInstructions)
        return clean ? .valid : .invalid(rejectionReason)
    }

    /// Frames the on-device model's screening task for a leaderboard username.
    private static let modelInstructions =
        "You screen usernames for a public video-game leaderboard. Decide if the given name is appropriate for an audience of all ages."

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

    // MARK: Rejection copy

    private static let rejectionReason = "That name isn't allowed. Try another."
}
