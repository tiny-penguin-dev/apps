import Foundation
@preconcurrency import Sentry

/// Crash reports and anonymous usage metrics, sent to Sentry.
///
/// Rules (see docs/telemetry.md): no names, emails, user IDs, free text or anything
/// someone typed. Metric names are lowercase and dotted, like `alarm.created`.
enum Telemetry {
    /// People can turn sharing off in Settings. Takes effect on the next launch.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Starts Sentry. Call once, first thing in the App's `init`. Does nothing when the
    /// build has no DSN (local and simulator builds) or the person turned sharing off.
    static func start() {
        guard isEnabled,
              let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
              dsn.hasPrefix("https://") else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = false
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif
            options.tracesSampleRate = 0.1
            options.enableMetrics = true
        }
    }

    /// Counts something that happened, like `Telemetry.count("alarm.created")`.
    static func count(_ name: String, _ attributes: [String: String] = [:]) {
        SentrySDK.metrics.count(name, value: 1, options: options(attributes))
    }

    /// Records a duration in seconds, like how long setup took.
    static func duration(_ name: String, seconds: Double, _ attributes: [String: String] = [:]) {
        SentrySDK.metrics.distribution(name, value: seconds, options: options(attributes, unit: .second))
    }

    /// Records a current value, like how many alarms someone has.
    static func gauge(_ name: String, value: Double, _ attributes: [String: String] = [:]) {
        SentrySDK.metrics.gauge(name, value: value, options: options(attributes))
    }

    /// Reports an error that was handled but shouldn't have happened.
    static func report(_ error: Error) {
        SentrySDK.capture(error: error)
    }

    private static let enabledKey = "telemetry.enabled"

    private static func options(_ attributes: [String: String], unit: SentryUnit? = nil) -> SentryMetricOptions {
        SentryMetricOptions(unit: unit, attributes: attributes.mapValues { $0 as SentryAttributeValue })
    }
}
