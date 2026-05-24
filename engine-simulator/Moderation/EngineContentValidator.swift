//
//  EngineContentValidator.swift
//  engine-simulator
//
//  Screens the free-text on a shared engine — its name and its optional
//  description — for objectionable content before the engine can be saved (and
//  therefore before it can ever reach the public community board or leaderboard).
//
//  Unlike a username there are no format rules here: engine names legitimately
//  carry spaces, digits and punctuation ("Chevy 454 Big Block", "5.0L Coyote"),
//  and descriptions are free prose. So this only runs the shared profanity /
//  appropriateness check (``ContentModerator``) on each field.
//

import Foundation

enum EngineContentValidator {

    /// Which field tripped the check, so the caller can point the user at it.
    enum Field {
        case name
        case description
    }

    struct Rejection {
        let field: Field
        let reason: String
    }

    /// Validate an engine's user-authored text. Returns nil when everything is
    /// clean, or the first offending field with a user-facing reason. Empty
    /// descriptions are skipped (they're optional).
    static func validate(name: String, description: String?) async -> Rejection? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !(await ContentModerator.isClean(trimmedName, modelInstructions: nameInstructions)) {
            return Rejection(field: .name,
                             reason: "That engine name isn't allowed. Try another.")
        }

        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDescription.isEmpty,
           !(await ContentModerator.isClean(trimmedDescription, modelInstructions: descriptionInstructions)) {
            return Rejection(field: .description,
                             reason: "That description isn't allowed. Please revise it.")
        }

        return nil
    }

    // MARK: Model framing

    private static let nameInstructions =
        "You screen the names players give engines they share publicly in a car game. Decide if the name is appropriate for an audience of all ages."

    private static let descriptionInstructions =
        "You screen the descriptions players write for engines they share publicly in a car game. Decide if the description is appropriate for an audience of all ages."
}
