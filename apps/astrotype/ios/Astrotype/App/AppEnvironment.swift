import Foundation
import AstrotypeCore
import UIKit

/// The app's services, named in one place (docs/building.md §4). `live()` is the only
/// place real implementations appear; `test(...)` takes the fakes.
@MainActor
struct AppEnvironment {
    var appStateStore: AppStateStore
    /// The keyboard settings, in the App Group so the keyboard reads them with Full Access.
    var settingsStore: SettingsStore
    /// The learned words, in the App Group for the same reason.
    var wordStore: WordStore
    /// iCloud, nil when the app is not to sync (tests).
    var cloudSync: CloudSync?
    var keyboardStatus: KeyboardStatusReading
    /// What the keyboard extension last wrote for us (Full Access, its last sync).
    var extensionStatus: ExtensionStatusReading
    var metrics: Metrics
    var now: () -> Date
    var appVersion: String
    /// Copies the data files aside under this label, before a new version touches them.
    var backup: (String) -> Void
    /// Opens the app's page in Settings, where Keyboards and Full Access live.
    var openSettings: () -> Void

    static func live() -> AppEnvironment {
        AppEnvironment(
            appStateStore: UserDefaultsAppStateStore(),
            settingsStore: liveSettingsStore(),
            wordStore: FileWordStore(url: dataFile(KeyboardFiles.words)),
            cloudSync: CloudKitSync(),
            keyboardStatus: UserDefaultsKeyboardStatus(),
            extensionStatus: KeyboardFiles.shared(KeyboardFiles.status).map { FileExtensionStatusStore(url: $0) as ExtensionStatusReading } ?? FakeExtensionStatus(),
            metrics: LiveMetrics(),
            now: { Date() },
            appVersion: DeviceInfo.appVersion,
            backup: { label in
                let files = [dataFile(KeyboardFiles.words), dataFile(KeyboardFiles.settings)]
                try? Backup.make(of: files, into: KeyboardFiles.own("Backups"), label: label)
            },
            openSettings: {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        )
    }

    /// A data file in the App Group, or in the app's own container when there is none.
    private static func dataFile(_ name: String) -> URL {
        KeyboardFiles.shared(name) ?? KeyboardFiles.own(name)
    }

    /// The settings file, taking over the Phase 4 `UserDefaults` copy the first time.
    private static func liveSettingsStore() -> FileSettingsStore {
        let store = FileSettingsStore(url: dataFile(KeyboardFiles.settings))
        let legacy = UserDefaultsSettingsStore()
        if store.load() == nil, let old = legacy.load() {
            store.save(old, changed: legacy.lastChanged() ?? .distantPast)
        }
        return store
    }

    static func test(
        appStateStore: AppStateStore = MemoryAppStateStore(),
        settingsStore: SettingsStore = MemorySettingsStore(),
        wordStore: WordStore = MemoryWordStore(),
        cloudSync: CloudSync? = nil,
        keyboardStatus: KeyboardStatusReading = FakeKeyboardStatus(),
        extensionStatus: ExtensionStatusReading = FakeExtensionStatus(),
        metrics: Metrics = RecordingMetrics(),
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_793_491_200) },
        appVersion: String = "0.2.0",
        backup: @escaping (String) -> Void = { _ in },
        openSettings: @escaping () -> Void = {}
    ) -> AppEnvironment {
        AppEnvironment(appStateStore: appStateStore, settingsStore: settingsStore, wordStore: wordStore, cloudSync: cloudSync,
                       keyboardStatus: keyboardStatus, extensionStatus: extensionStatus, metrics: metrics, now: now,
                       appVersion: appVersion, backup: backup, openSettings: openSettings)
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
