import SwiftUI
import StoreKit
import Combine

// All persisted at module scope (UserDefaults is thread-safe) so the gate can be
// evaluated off the main actor from a service's success path.
private let happyMomentsKey = "review.happyMomentCount"
private let lastPromptedVersionKey = "review.lastPromptedVersion"
private let happyMomentThreshold = 3

private var currentAppVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
}

/// Drives App Store review prompts at genuine "happy moments" (e.g. after a
/// successful leaderboard post), never on launch and never after a failure.
///
/// Robust + non-spammy by construction:
///   • Only prompts once `happyMomentThreshold` positive moments have accrued.
///   • At most once per app version (tracked by CFBundleShortVersionString).
///   • Apple independently hard-caps the real prompt at ~3×/365 days, so even a
///     bug in our gate can't actually over-ask the user.
///   • State lives in UserDefaults; every path is no-throw. The prompt itself is
///     delivered by the modern SwiftUI `requestReview` action via `.reviewPrompt()`.
@MainActor
final class ReviewRequest: ObservableObject {
    static let shared = ReviewRequest()

    /// Bumped when a prompt is due; the `.reviewPrompt()` modifier observes it.
    @Published fileprivate var promptToken = 0

    private init() {}

    /// Record a positive event. Safe to call from any thread / async context.
    nonisolated static func registerHappyMoment() {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: happyMomentsKey) + 1
        defaults.set(count, forKey: happyMomentsKey)

        guard count >= happyMomentThreshold,
              defaults.string(forKey: lastPromptedVersionKey) != currentAppVersion else { return }

        defaults.set(currentAppVersion, forKey: lastPromptedVersionKey)
        Task { @MainActor in shared.promptToken += 1 }
    }
}

extension View {
    /// Attach once near the app root. When a happy-moment threshold is crossed,
    /// asks for a review using StoreKit's cross-platform SwiftUI action. (Apple
    /// still decides whether to actually show the dialog and rate-limits it.)
    func reviewPrompt() -> some View { modifier(ReviewPromptModifier()) }
}

private struct ReviewPromptModifier: ViewModifier {
    @Environment(\.requestReview) private var requestReview
    @ObservedObject private var review = ReviewRequest.shared

    func body(content: Content) -> some View {
        content.onChange(of: review.promptToken) { _, token in
            guard token > 0 else { return }
            requestReview()
        }
    }
}