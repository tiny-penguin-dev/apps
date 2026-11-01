import Foundation
import Observation
import AstrotypeCore

/// The app's state and the only thing its views talk to (docs/building.md §4): which
/// screen is up, how far setup got, whether the keyboard is on, the settings the
/// practice field types with, the learned words and their sync, and the counts that
/// go to telemetry.
@MainActor
@Observable
final class AppModel {
    enum Screen: Equatable {
        case hello, turnOn, sync, tryIt, home
    }

    private(set) var screen: Screen
    private(set) var state: AppState {
        didSet { environment.appStateStore.save(state) }
    }
    /// Whether the Astrotype keyboard is turned on in Settings, as last read.
    private(set) var isKeyboardOn = false
    /// Set once, the moment the keyboard is first seen on: the Turn on screen throws confetti.
    private(set) var celebrateKeyboardOn = false
    /// The keyboard settings, shared with the keyboard through the App Group, saved on
    /// every change.
    var keyboardSettings: KeyboardSettings {
        didSet {
            guard keyboardSettings != oldValue else { return }
            environment.settingsStore.save(keyboardSettings)
        }
    }
    /// What the keyboard learned from the person, as last read from the shared store.
    private(set) var learnedWords: LearnedWords
    /// What the keyboard extension last told us (nil until it has run with Full Access).
    private(set) var extensionStatus: ExtensionStatus?

    enum SyncState: Equatable {
        /// The keyboard has never reported Full Access, so nothing it learns leaves it.
        case needsFullAccess
        case idle(last: Date?)
        case syncing
        case failed(String)
    }

    private(set) var syncState: SyncState = .needsFullAccess
    private var syncFailureCounted = false

    @ObservationIgnored private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        var state = environment.appStateStore.load() ?? AppState()
        if state.firstLaunch == nil { state.firstLaunch = environment.now() }
        // The v1 app kept its own flag; people who finished that setup skip this one.
        if !state.onboardingDone, UserDefaults.standard.bool(forKey: "onboarding.done") { state.onboardingDone = true }
        // A new version backs the data up before it reads or writes any of it.
        if state.lastRunVersion != environment.appVersion {
            if let previous = state.lastRunVersion { environment.backup(previous) }
            state.lastRunVersion = environment.appVersion
        }
        self.state = state
        self.screen = state.onboardingDone ? .home : .hello
        self.keyboardSettings = environment.settingsStore.load() ?? KeyboardSettings()
        self.learnedWords = environment.wordStore.load() ?? LearnedWords()
        environment.appStateStore.save(state)
        refreshKeyboardStatus()
    }

    var now: Date { environment.now() }

    var trial: Trial { Trial(start: state.firstLaunch ?? now) }

    var week: Week { Week(practiceDays: state.practiceDays, now: now) }

    /// The Full Access screen was answered already (its ghost button says Next, not Skip).
    var fullAccessAsked: Bool { state.fullAccessAsked }

    // MARK: Keyboard status

    /// Re-reads whether the keyboard is on and what the extension last reported; counts
    /// `setup.keyboard_on` the first time the keyboard is on.
    func refreshKeyboardStatus() {
        extensionStatus = environment.extensionStatus.load()
        if case .needsFullAccess = syncState, extensionStatus?.fullAccess == true {
            syncState = .idle(last: extensionStatus?.lastSync)
        }
        let on = environment.keyboardStatus.isKeyboardOn()
        guard on != isKeyboardOn || (on && !state.keyboardOnSeen) else { return }
        isKeyboardOn = on
        if on, !state.keyboardOnSeen {
            state.keyboardOnSeen = true
            celebrateKeyboardOn = true
            environment.metrics.count("setup.keyboard_on")
        }
    }

    /// Whether the keyboard has run with Full Access, as far as the app can tell.
    var isFullAccessOn: Bool { extensionStatus?.fullAccess == true }

    func openSettings() {
        environment.openSettings()
    }

    // MARK: Setup

    /// The next setup screen, from Hello through to Home.
    func next() {
        switch screen {
        case .hello: screen = .turnOn
        case .turnOn: screen = .sync
        case .sync: screen = .tryIt
        case .tryIt: finishOnboarding()
        case .home: break
        }
    }

    /// Open Settings from the Full Access screen; counted once as `setup.full_access`.
    func openSettingsForFullAccess() {
        answerFullAccess("opened")
        environment.openSettings()
    }

    func skipFullAccess() {
        answerFullAccess("skipped")
        if screen == .sync { screen = .tryIt }
    }

    private func answerFullAccess(_ answer: String) {
        guard !state.fullAccessAsked else { return }
        state.fullAccessAsked = true
        environment.metrics.count("setup.full_access", ["answer": answer])
    }

    /// Home reached: setup never shows again; the time it took is counted once.
    func finishOnboarding() {
        if !state.onboardingDone {
            state.onboardingDone = true
            if let first = state.firstLaunch {
                environment.metrics.duration("onboarding.finished", seconds: now.timeIntervalSince(first))
            }
        }
        screen = .home
    }

    // MARK: Practice

    /// A word typed in the app: ticks today on the week.
    func recordPractice() {
        state.recordPractice(at: now)
    }

    // MARK: Learned words

    /// Re-reads the shared words (the keyboard may have learned some since).
    func reloadWords() {
        if let words = environment.wordStore.load() { learnedWords = words }
    }

    /// The practice keyboard learned, boosted or forgot something.
    func learnedWordsChanged(_ words: LearnedWords) {
        saveWords(learnedWords.merged(with: words))
        sync()
    }

    /// Swiped away in the learned words list: not offered again.
    func forget(_ word: String) {
        var words = learnedWords
        words.forget(word, at: now)
        saveWords(words)
        sync()
    }

    private func saveWords(_ words: LearnedWords) {
        guard words != learnedWords else { return }
        learnedWords = words
        environment.wordStore.save(words)
    }

    // MARK: Sync

    /// One round with iCloud: the words and settings merged with the cloud's copy and
    /// written back. Counts `sync.failed` once per run of failures.
    func sync() {
        guard let cloud = environment.cloudSync, syncState != .syncing else { return }
        let before = syncState
        syncState = .syncing
        let local = SyncSnapshot(words: learnedWords, settings: keyboardSettings,
                                 settingsChanged: environment.settingsStore.lastChanged() ?? .distantPast)
        Task { @MainActor in
            do {
                let merged = try await Syncer.sync(local: local, cloud: cloud)
                saveWords(merged.words)
                if merged.settingsChanged > local.settingsChanged { keyboardSettings = merged.settings }
                syncFailureCounted = false
                syncState = isFullAccessOn || before != .needsFullAccess ? .idle(last: now) : .needsFullAccess
            } catch {
                syncState = .failed(error.localizedDescription)
                if !syncFailureCounted {
                    syncFailureCounted = true
                    environment.metrics.count("sync.failed")
                }
            }
        }
    }
}
