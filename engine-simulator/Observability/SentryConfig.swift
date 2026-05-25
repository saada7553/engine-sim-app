import Foundation
import CloudKit
import Sentry

/// Sentry DSN for crash/error reporting. This is a client-side public key, so
/// it's safe to ship embedded in the binary. We run error monitoring only — no
/// tracing, profiling, or session replay — so nothing samples the real-time
/// render loop or the C++ engine-sim hot path.
private let sentryDSN = "https://19c2d4e93c8bafd0ebb0186f9d3040d3@o4510452902526976.ingest.us.sentry.io/4511446571220992"

/// Boots Sentry crash/error reporting. Must run before any other startup work
/// and on the main thread — `App.init` satisfies both. Error monitoring only:
/// crash signals, app hangs, and watchdog terminations, with a screenshot and
/// view hierarchy attached to the event. Tracing/profiling/replay are left off
/// on purpose to keep the sim's CPU budget free.
func configureSentry() {
    SentrySDK.start { options in
        options.dsn = sentryDSN
        #if DEBUG
        options.environment = "debug"
        #else
        options.environment = "production"
        #endif
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let shortVersion, let build {
            options.releaseName = "engine-simulator@\(shortVersion)+\(build)"
        }

        options.enableCrashHandler = true
        options.enableWatchdogTerminationTracking = true
        #if os(macOS)
        // App hangs aren't supported on macOS; uncaught NSException reporting is.
        options.enableUncaughtNSExceptionReporting = true
        #else
        // These all require UIKit (iOS/tvOS) and don't exist in an AppKit build:
        // app-hang V2 differentiates fully- vs non-fully-blocking hangs, and the
        // screenshot / view-hierarchy attachments capture UI state on an error.
        options.enableAppHangTrackingV2 = true
        options.attachScreenshot = true
        options.attachViewHierarchy = true
        #endif

        // Off: no IP/geolocation or user-assigned device name on events. Crash
        // type, stack trace, device model, OS, and app version are unaffected.
        options.sendDefaultPii = false
    }
}

/// Reports a non-fatal backend/network failure (e.g. a failed CloudKit write) to
/// Sentry, tagged with the operation that failed. Call this only for unexpected
/// operational failures, never for expected validation conditions (which can
/// carry user-facing text like usernames).
///
/// The event carries error codes and generic descriptions only — never the
/// username, anonymous player id, engine content, or CloudKit record IDs. The
/// error is re-wrapped without its `userInfo` (which can hold record IDs and
/// server payloads); the useful, non-identifying details are pulled into a
/// curated "failure" context by `failureDiagnostics`.
func reportFailure(_ error: Error, op: String) {
    // Offline / not-signed-in / quota-full / rate-limited are the user's
    // environment, not our bug. Reporting them would flood Sentry with
    // non-actionable noise and burn the event quota, so drop them silently.
    guard !isExpectedEnvironmentFailure(error) else { return }

    let ns = error as NSError
    let safe = NSError(domain: ns.domain, code: ns.code,
                       userInfo: [NSLocalizedDescriptionKey: ns.localizedDescription])
    SentrySDK.capture(error: safe) { scope in
        scope.setLevel(.error)
        scope.setTag(value: op, key: "operation")
        scope.setContext(value: failureDiagnostics(error), key: "failure")
    }
}

/// True for failures that reflect the user's connectivity or iCloud account
/// state rather than a bug in the app: no/lost connection, iCloud signed out,
/// storage quota full, rate-limited, or a transient server hiccup. These are
/// expected and not worth reporting.
private func isExpectedEnvironmentFailure(_ error: Error) -> Bool {
    if let ck = error as? CKError {
        switch ck.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .notAuthenticated, .quotaExceeded,
             .zoneBusy, .serverResponseLost, .accountTemporarilyUnavailable:
            return true
        default:
            break
        }
    }
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain {
        switch ns.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut,
             NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return true
        default:
            break
        }
    }
    return false
}

/// Privacy-safe diagnostics for a failed operation: error codes and generic
/// descriptions only. For a CloudKit partial failure, the per-record error map
/// is keyed by record ID (which embeds the anonymous player id), so the keys are
/// dropped and only the sub-error code/description values are kept — that's where
/// the real cause (conflict, invalid field, permission) lives.
private func failureDiagnostics(_ error: Error) -> [String: Any] {
    let ns = error as NSError
    var info: [String: Any] = ["domain": ns.domain, "code": ns.code]

    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
        info["underlying"] = "\(underlying.domain) \(underlying.code): \(underlying.localizedDescription)"
    }
    if let ckError = error as? CKError {
        if let partials = ckError.partialErrorsByItemID, !partials.isEmpty {
            info["partialErrors"] = partials.values.map { sub in
                let s = sub as NSError
                return "\(s.code): \(s.localizedDescription)"
            }
        }
        if let retry = ckError.retryAfterSeconds { info["retryAfterSeconds"] = retry }
    }
    return info
}

/// Sends a user-submitted bug report to Sentry's User Feedback inbox. Anonymous
/// by design — no name or email is attached, so the only personal data is
/// whatever the user chose to type. Empty/whitespace messages are ignored.
func sendBugReport(_ message: String) {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let feedback = SentryFeedback(message: trimmed, name: nil, email: nil, source: .custom)
    SentrySDK.capture(feedback: feedback)
}

#if DEBUG
/// Fires a one-off test event so you can confirm events reach the Sentry
/// dashboard. DEBUG-only. The message is stamped with the local date/time so
/// repeated triggers are distinguishable in the issue stream.
func sendSentryTestEvent() {
    let timestamp = Date().formatted(date: .abbreviated, time: .standard)
    SentrySDK.capture(message: "Sentry test event — \(timestamp)")
}
#endif
