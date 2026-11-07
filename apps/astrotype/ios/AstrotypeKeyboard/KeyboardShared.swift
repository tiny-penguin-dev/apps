import AstrotypeCore
import AstrotypeUI
import Foundation
import UIKit

/// What one keyboard process keeps whichever keyboard iOS is showing: the model (with
/// its dictionaries, learned words and personal model), the iCloud sync and the Pro
/// check. iOS makes a new `KeyboardViewController` each time the keyboard comes up in
/// a new place and can keep old ones alive long after they close; each used to make
/// its own model, and they piled up at about 10 MB each (Gabriel, 6 Nov 2026:
/// "3 keyboards, 9 models" at 120 MB). Now every controller types through this one,
/// and the one showing (`showing`) gets its callbacks.
@MainActor
final class KeyboardShared {
    private(set) static var current: KeyboardShared?

    let model: KeyboardModel
    private(set) var sync: SyncController?
    private var entitlement: EntitlementController?
    /// The keyboard on screen, or the last one shown.
    weak var showing: KeyboardViewController?

    /// The process's one, made the first time it is asked for.
    static func get(fullAccess: Bool) -> KeyboardShared {
        if let current { return current }
        let shared = KeyboardShared(fullAccess: fullAccess)
        current = shared
        return shared
    }

    private init(fullAccess: Bool) {
        let (settingsStore, wordStore, personalStore) = Self.stores(fullAccess: fullAccess)
        // The languages turned on, or the phone's (features/languages), with their word
        // pairs. Pro is not known yet, so both load; the model drops to one when the
        // entitlement says the keyboard is free.
        // The dictionaries are read in place from files in the extension's Caches,
        // made there the first time, instead of held in memory (`Language.cacheFolder`).
        Language.cacheFolder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Dictionaries", isDirectory: true)
        let codes = (settingsStore.load() ?? KeyboardSettings())
            .activeLanguages(preferred: Locale.preferredLanguages, allowsTwo: true)
        let language = (try? Language.bundled(codes)) ?? (try? Language.bundled())
            ?? Language(code: "en", lexicon: Lexicon(entries: []))
        let model = KeyboardModel(composer: Composer(language: language, layout: Layout.qwerty(width: 390)),
                                  store: settingsStore, wordStore: wordStore, personalStore: personalStore,
                                  installID: InstallID.load(from: KeyboardFiles.own(KeyboardFiles.install)))
        self.model = model
        // Frequently used emoji and skin tones, in the extension's own files (they don't
        // sync, features/emoji).
        model.emojiStore = FileEmojiStore(url: KeyboardFiles.own(KeyboardFiles.emoji))
        // The next-word models, loaded in the background (features/next-word-model).
        model.loadNextWordModel = NextWordModels.load
        model.device = TypingSnapshot.Device(app: KeyboardViewController.appVersion,
                                             system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                                             model: KeyboardViewController.hardware)
        model.onSettled = { [weak self] word in self?.showing?.health?.settled(word) }
        // The switch can change here (a sync) or in the app (read on each appearance).
        // Set before the sync wraps it.
        model.onSettingsChange = { [weak self] _ in self?.showing?.updateRecorder() }

        if fullAccess {
            sync = Self.makeSync(model: model)
            // Fixes go where the app can send them, only if the person said so (the
            // model checks the setting); without Full Access there is nowhere to put them.
            if let folder = KeyboardFiles.shared(KeyboardFiles.sharing) {
                let store = SharedWordStore(folder: folder)
                model.onCorrection = { word in store.save([word]) }
            }
        }
        // Misses from "Not it?" are kept for "Words it missed" (features/missed-words):
        // in the App Group where the app can list them, else in our own files.
        let misses = SharedWordStore(folder: (fullAccess ? KeyboardFiles.shared(KeyboardFiles.misses) : nil)
            ?? KeyboardFiles.own(KeyboardFiles.misses), limit: 200)
        model.onMiss = { word in misses.save([word]) }
        entitlement = Self.makeEntitlement(model: model, fullAccess: fullAccess)
    }

    /// Pro from StoreKit, the trial from the earliest start we can see: the app's (in
    /// the App Group, with Full Access) or this extension's own first run.
    private static func makeEntitlement(model: KeyboardModel, fullAccess: Bool) -> EntitlementController {
        let now = Date()
        let own = TrialStore(url: KeyboardFiles.own(KeyboardFiles.trial))
        let shared = fullAccess ? KeyboardFiles.shared(KeyboardFiles.trial).flatMap { TrialStore(url: $0).load() } : nil
        let trial = TrialStore.earliest(shared, own.loadOrStart(now: now)) ?? Trial(start: now)
        if let shared, shared.start < (own.load()?.start ?? .distantFuture) { own.save(shared) }
        let controller = EntitlementController(model: model, store: StoreKitProStore(),
                                               cache: ProCache(url: KeyboardFiles.own(KeyboardFiles.pro)), trial: trial)
        controller.start()
        return controller
    }

    /// The extension's own files, which it can always write, mirrored to the App Group's
    /// when Full Access allows. The Phase 3 settings in `UserDefaults` move over once.
    private static func stores(fullAccess: Bool) -> (SettingsStore, WordStore, PersonalStore) {
        let own = FileSettingsStore(url: KeyboardFiles.own(KeyboardFiles.settings))
        let legacy = UserDefaultsSettingsStore()
        if own.load() == nil, let old = legacy.load() {
            own.save(old, changed: legacy.lastChanged() ?? .distantPast)
        }
        let ownWords = FileWordStore(url: KeyboardFiles.own(KeyboardFiles.words))
        let ownPersonal = FilePersonalStore(url: KeyboardFiles.own(KeyboardFiles.personal))
        guard fullAccess,
              let sharedSettings = KeyboardFiles.shared(KeyboardFiles.settings),
              let sharedWords = KeyboardFiles.shared(KeyboardFiles.words),
              let sharedPersonal = KeyboardFiles.shared(KeyboardFiles.personal) else {
            return (own, ownWords, ownPersonal)
        }
        return (MirroredSettingsStore(own: own, shared: FileSettingsStore(url: sharedSettings)),
                MirroredWordStore(own: ownWords, shared: FileWordStore(url: sharedWords)),
                MirroredPersonalStore(own: ownPersonal, shared: FilePersonalStore(url: sharedPersonal)))
    }

    /// With Full Access: tell the app we have it, and keep words and settings in step
    /// with iCloud (on each new keyboard, and after each change).
    private static func makeSync(model: KeyboardModel) -> SyncController? {
        guard let url = KeyboardFiles.shared(KeyboardFiles.status) else { return nil }
        let statusStore = FileExtensionStatusStore(url: url)
        var status = statusStore.load() ?? ExtensionStatus(fullAccess: true, seen: Date())
        status.fullAccess = true
        status.seen = Date()
        statusStore.save(status)

        let sync = SyncController(model: model, cloud: CloudKitSync())
        sync.onResult = { result in
            var status = statusStore.load() ?? ExtensionStatus(fullAccess: true, seen: Date())
            switch result {
            case .success(let date):
                status.lastSync = date
                status.lastSyncError = nil
            case .failure(let error):
                status.lastSyncError = error.localizedDescription
            }
            statusStore.save(status)
        }
        return sync
    }
}
