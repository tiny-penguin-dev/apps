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
    /// What the keyboard learned from the person's typing, in the App Group: the
    /// keyboard writes it (with Full Access), the app shows it, syncs it and forgets it.
    var personalStore: PersonalStore
    /// iCloud, nil when the app is not to sync (tests).
    var cloudSync: CloudSync?
    var keyboardStatus: KeyboardStatusReading
    /// What the keyboard extension last wrote for us (Full Access, its last sync).
    var extensionStatus: ExtensionStatusReading
    /// The keyboard's memory readings, for the app to send (`KeyboardHealth`); nil in tests.
    var keyboardHealth: FileKeyboardHealthStore?
    /// Whether this Apple Account has Astrotype Pro (StoreKit).
    var proStore: ProStore
    /// Where the trial's start is written for the keyboard extension to read (the App
    /// Group); nil in tests.
    var trialStore: TrialStore?
    /// Whole practice recordings from before Phase C, waiting to be sent: they go as
    /// their words now. Nil in tests.
    var practiceStore: PracticeStore?
    /// Shared words waiting to be sent (practice words and the keyboard's corrections,
    /// features/smart-matching Phase C), and what sends them; nil in tests.
    var sharedWords: SharedWordStore?
    var sharedUploader: SharedWordUploader?
    /// What a recording says about where it was made (no name or account).
    var device: PracticeRecording.Device
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
            personalStore: FilePersonalStore(url: dataFile(KeyboardFiles.personal)),
            cloudSync: CloudKitSync(),
            keyboardStatus: UserDefaultsKeyboardStatus(),
            extensionStatus: KeyboardFiles.shared(KeyboardFiles.status).map { FileExtensionStatusStore(url: $0) as ExtensionStatusReading } ?? FakeExtensionStatus(),
            keyboardHealth: KeyboardFiles.shared(KeyboardFiles.health).map { FileKeyboardHealthStore(url: $0) },
            proStore: StoreKitProStore(),
            trialStore: TrialStore(url: dataFile(KeyboardFiles.trial)),
            practiceStore: PracticeStore(folder: KeyboardFiles.own("Practice")),
            sharedWords: SharedWordStore(folder: dataFile(KeyboardFiles.sharing)),
            sharedUploader: CloudKitPracticeUploader(),
            device: PracticeRecording.Device(model: DeviceInfo.model, system: DeviceInfo.system,
                                             app: DeviceInfo.appVersion, writer: DeviceInfo.writerID),
            metrics: LiveMetrics(),
            now: { Date() },
            appVersion: DeviceInfo.appVersion,
            backup: { label in
                let files = [dataFile(KeyboardFiles.words), dataFile(KeyboardFiles.settings), dataFile(KeyboardFiles.personal)]
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
        personalStore: PersonalStore = MemoryPersonalStore(),
        cloudSync: CloudSync? = nil,
        keyboardStatus: KeyboardStatusReading = FakeKeyboardStatus(),
        extensionStatus: ExtensionStatusReading = FakeExtensionStatus(),
        keyboardHealth: FileKeyboardHealthStore? = nil,
        proStore: ProStore = MemoryProStore(),
        trialStore: TrialStore? = nil,
        practiceStore: PracticeStore? = nil,
        sharedWords: SharedWordStore? = nil,
        sharedUploader: SharedWordUploader? = nil,
        device: PracticeRecording.Device = PracticeRecording.Device(model: "iPhone", system: "iOS 26", app: "0.2.0", writer: "test"),
        metrics: Metrics = RecordingMetrics(),
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_793_491_200) },
        appVersion: String = "0.2.0",
        backup: @escaping (String) -> Void = { _ in },
        openSettings: @escaping () -> Void = {}
    ) -> AppEnvironment {
        AppEnvironment(appStateStore: appStateStore, settingsStore: settingsStore, wordStore: wordStore,
                       personalStore: personalStore, cloudSync: cloudSync,
                       keyboardStatus: keyboardStatus, extensionStatus: extensionStatus,
                       keyboardHealth: keyboardHealth, proStore: proStore,
                       trialStore: trialStore, practiceStore: practiceStore,
                       sharedWords: sharedWords, sharedUploader: sharedUploader,
                       device: device, metrics: metrics, now: now,
                       appVersion: appVersion, backup: backup, openSettings: openSettings)
    }
}

/// Metrics through `Telemetry` (Sentry).
struct LiveMetrics: Metrics {
    func count(_ name: String, _ attributes: [String: String]) {
        Telemetry.count(name, attributes)
    }

    func count(_ name: String, by amount: Int, _ attributes: [String: String]) {
        Telemetry.count(name, by: amount, attributes)
    }

    func duration(_ name: String, seconds: Double) {
        Telemetry.duration(name, seconds: seconds)
    }

    func gauge(_ name: String, value: Double, _ attributes: [String: String]) {
        Telemetry.gauge(name, value: value, attributes)
    }

    func size(_ name: String, megabytes: Double) {
        Telemetry.size(name, megabytes: megabytes)
    }
}
