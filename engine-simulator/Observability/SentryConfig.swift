import Foundation
import Sentry

/// Sentry DSN for crash/error reporting. This is a client-side public key, so
/// it's safe to ship embedded in the binary. We run error monitoring only — no
/// tracing, profiling, or session replay — so nothing samples the real-time
/// render loop or the C++ engine-sim hot path.
private let sentryDSN = "https://dcd05699e199354cd229fe74e8eaa55c@o4510452902526976.ingest.us.sentry.io/4510452906721280"

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
        options.enableAppHangTrackingV2 = true
        options.enableWatchdogTerminationTracking = true
        #if os(macOS)
        options.enableUncaughtNSExceptionReporting = true
        #endif

        options.attachScreenshot = true
        options.attachViewHierarchy = true
        options.sendDefaultPii = true
    }
}
