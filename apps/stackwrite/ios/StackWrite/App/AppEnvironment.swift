import Foundation
import StackWriteCore
import UIKit

/// The app's services, named in one place (docs/building.md §4). `live()` is the only
/// place real implementations appear; `test(...)` takes the fakes.
@MainActor
struct AppEnvironment {
    var appStateStore: AppStateStore
    var settingsStore: SettingsStore
    var keyboardStatus: KeyboardStatusReading
    var metrics: Metrics
    var now: () -> Date
    /// Opens the app's page in Settings, where Keyboards and Full Access live.
    var openSettings: () -> Void

    static func live() -> AppEnvironment {
        AppEnvironment(
            appStateStore: UserDefaultsAppStateStore(),
            settingsStore: UserDefaultsSettingsStore(),
            keyboardStatus: UserDefaultsKeyboardStatus(),
            metrics: LiveMetrics(),
            now: { Date() },
            openSettings: {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        )
    }

    static func test(
        appStateStore: AppStateStore = MemoryAppStateStore(),
        settingsStore: SettingsStore = MemorySettingsStore(),
        keyboardStatus: KeyboardStatusReading = FakeKeyboardStatus(),
        metrics: Metrics = RecordingMetrics(),
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_793_491_200) },
        openSettings: @escaping () -> Void = {}
    ) -> AppEnvironment {
        AppEnvironment(appStateStore: appStateStore, settingsStore: settingsStore, keyboardStatus: keyboardStatus,
                       metrics: metrics, now: now, openSettings: openSettings)
    }
}

/// Metrics through `Telemetry` (Sentry).
struct LiveMetrics: Metrics {
    func count(_ name: String, _ attributes: [String: String]) {
        Telemetry.count(name, attributes)
    }

    func duration(_ name: String, seconds: Double) {
        Telemetry.duration(name, seconds: seconds)
    }
}
