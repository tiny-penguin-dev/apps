import AstrotypeCore
import Foundation
@preconcurrency import Sentry

/// The keyboard's crash reports, and nothing else (PRODUCT.md §10b, docs/telemetry.md).
///
/// Sentry runs here only with Full Access (no network without it) and with the app's
/// "Share anonymous usage data" switch on (`UsageSharing`), in a build with a DSN. It is
/// set up to send crashes as stack traces with device and memory details,
/// and to keep everything else off: no breadcrumbs, logs, screenshots, view
/// hierarchy, session replay, traces, profiles, sessions or metrics, and no user or
/// install ID. `scrub` strips anything that could hold text before an event leaves.
/// Memory readings go through the app instead (`KeyboardHealth`).
enum KeyboardTelemetry {
    static func start(fullAccess: Bool) {
        guard fullAccess, !SentrySDK.isEnabled,
              UsageSharing.load(from: KeyboardFiles.shared(KeyboardFiles.usage)),
              let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
              dsn.hasPrefix("https://") else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif
            options.sendDefaultPii = false

            // Crashes: stack traces only. Sentry's hang tracking stays off: it runs a
            // watchdog thread and gives noisy traces (it goes away in Sentry 10).
            options.enableCrashHandler = true
            options.enableAppHangTracking = false

            // Nothing that follows what the person does.
            options.maxBreadcrumbs = 0
            options.enableAutoBreadcrumbTracking = false
            options.enableNetworkBreadcrumbs = false
            options.beforeBreadcrumb = { _ in nil }
            options.enableLogs = false
            options.beforeSendLog = { _ in nil }
            options.enableMetrics = false
            options.beforeSendMetric = { _ in nil }
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.sessionReplay.sessionSampleRate = 0
            options.sessionReplay.onErrorSampleRate = 0
            options.enableAutoSessionTracking = false
            options.enableWatchdogTerminationTracking = false
            options.enableMetricKit = false

            // No tracing: less work in the keyboard, and no view or touch names.
            options.tracesSampleRate = nil
            options.enableAutoPerformanceTracing = false
            options.enableUIViewControllerTracing = false
            options.enableUserInteractionTracing = false
            options.enableNetworkTracking = false
            options.enableFileIOTracing = false
            options.enableCoreDataTracing = false
            options.enableCaptureFailedRequests = false
            options.enableSwizzling = false

            options.initialScope = { scope in
                scope.setTag(value: "keyboard", key: "target")
                return scope
            }
            options.beforeSend = { scrub($0) }
        }
    }

    /// Whether the keyboard's last process crashed, as Sentry saw it. Nil when Sentry
    /// isn't running (no Full Access, sharing off, or no DSN), since then it can't tell.
    static var crashedLastRun: Bool? {
        SentrySDK.isEnabled ? SentrySDK.crashedLastRun : nil
    }

    /// What leaves: where it crashed (exception type, mechanism, stack traces, loaded
    /// images) and the device, OS and memory. Gone: any message or exception text (a
    /// reason can quote a string), breadcrumbs, extra data, the request, the user and
    /// Sentry's install ID that stands in for one.
    static func scrub(_ event: Event) -> Event? {
        event.message = nil
        event.breadcrumbs = nil
        event.extra = nil
        event.request = nil
        event.user = nil
        event.serverName = nil
        event.error = nil
        for exception in event.exceptions ?? [] {
            exception.value = nil
            exception.mechanism?.desc = nil
        }
        return event
    }
}
