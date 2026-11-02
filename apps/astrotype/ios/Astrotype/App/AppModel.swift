import Foundation
import Observation
import AstrotypeCore

/// The app's state and the only thing its views talk to (docs/building.md §4): which
/// screen is up, how far setup got, whether the keyboard is on, the settings the
/// practice field types with, the learned words and their sync, where the person
/// stands with Pro, and the counts that go to telemetry.
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
    /// What the keyboard learned from the person's typing in other apps, as last read
    /// from the shared store (features/smart-matching Phase B).
    private(set) var personal: PersonalModel
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

    /// The App Store's last answer: an active Astrotype Pro subscription.
    private(set) var isSubscribed = false
    /// The App Store has answered at least once this run (the cached answer is not
    /// enough to say a trial is over).
    private(set) var proChecked = false
    private var proListener: Task<Void, Never>?

    @ObservationIgnored private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        var state = environment.appStateStore.load() ?? AppState()
        if state.firstLaunch == nil {
            state.firstLaunch = environment.now()
            environment.metrics.count("trial.started")
        }
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
        self.personal = environment.personalStore.load() ?? PersonalModel()
        environment.appStateStore.save(state)
        shareTrial()
        refreshKeyboardStatus()
    }

    var now: Date { environment.now() }

    var trial: Trial { Trial(start: state.firstLaunch ?? now) }

    /// Writes the trial's start where the keyboard extension reads it (the App Group,
    /// with Full Access), keeping the earlier start if the extension wrote one first.
    private func shareTrial() {
        guard let store = environment.trialStore else { return }
        let mine = trial
        if let saved = store.load(), saved.start <= mine.start { return }
        store.save(mine)
    }

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

    // MARK: Pro

    /// Where the person stands: subscribed, on the trial, or on the free keyboard.
    var proStatus: ProStatus { ProStatus.from(subscribed: isSubscribed, trial: trial, now: now) }

    /// What the person may use, for the practice keyboard and the Pro rows.
    var entitlement: Entitlement { Entitlement(status: proStatus, now: now) }

    /// The Trial over sheet is due: the App Store has answered, there is no
    /// subscription, the trial has ended, and the sheet has not been shown yet.
    var trialOverDue: Bool {
        proChecked && !isSubscribed && state.onboardingDone && trial.isOver(now: now) && !state.trialOverShown
    }

    /// Asks the App Store once and then follows every change (a purchase, a renewal, a
    /// refund, a purchase on another device). Call at launch.
    func startPro() {
        guard proListener == nil else { return }
        let changes = environment.proStore.changes()
        proListener = Task { [weak self] in
            await self?.refreshPro()
            for await _ in changes {
                await self?.refreshPro()
            }
        }
    }

    /// One fresh answer from the App Store.
    func refreshPro() async {
        let subscribed = await environment.proStore.isPro()
        isSubscribed = subscribed
        proChecked = true
    }

    /// A subscription was just bought on the Pro screen; counted as `pro.subscribed`.
    func subscribed(to productID: String) {
        environment.metrics.count("pro.subscribed", ["plan": ProProducts.plan(of: productID)])
        Task { await refreshPro() }
    }

    /// "Restore purchases": asks the App Store for this Apple Account's purchases.
    /// Returns whether Pro was found.
    func restorePurchases() async throws -> Bool {
        try await environment.proStore.restore()
        await refreshPro()
        return isSubscribed
    }

    /// The Trial over sheet was seen: it does not come back.
    func trialOverSeen() {
        guard !state.trialOverShown else { return }
        state.trialOverShown = true
    }

    // MARK: Practice

    /// A word typed in the app: ticks today on the week.
    func recordPractice() {
        state.recordPractice(at: now)
    }

    /// Days in a row with practice, for the result screen's chip.
    var streak: Int { Streak.days(practiceDays: state.practiceDays, now: now) }

    var bestWordsPerMinute: Int? { state.bestWordsPerMinute }
    var appleWordsPerMinute: Int? { state.appleWordsPerMinute }
    var speedTests: [SpeedResult] { state.speedTests }

    /// A speed test finished: kept, the best updated, counted as `speedtest.finished`.
    /// Returns whether it is a new best on the Astrotype keyboard.
    @discardableResult
    func speedTestFinished(_ result: SpeedResult) -> Bool {
        state.recordPractice(at: now)
        let best = state.record(result)
        environment.metrics.gauge("speedtest.finished", value: Double(result.wordsPerMinute), ["keyboard": result.keyboard.rawValue])
        return best
    }

    /// A drill's five words were typed: ticked on Home today, counted as `drill.finished`.
    func drillFinished(_ id: Drill.ID) {
        state.recordPractice(at: now)
        state.drillsDone[id.rawValue] = now
        environment.metrics.count("drill.finished", ["drill": id.rawValue])
    }

    /// Whether a drill was finished today (the tick on Home).
    func isDrillDone(_ id: Drill.ID) -> Bool {
        guard let date = state.drillsDone[id.rawValue] else { return false }
        return AppState.dayKey(date) == AppState.dayKey(now)
    }

    // MARK: Milestones

    /// The next milestone sheet to show, if one was reached and not seen yet.
    var pendingMilestone: Milestone? {
        let reached = Milestone.reached(bestWordsPerMinute: state.bestWordsPerMinute, practiceDays: state.practiceDays,
                                        learnedWords: learnedWords.recent.count)
        return Milestone.pending(reached: reached, seen: state.milestonesSeen)
    }

    func milestoneSeen(_ milestone: Milestone) {
        guard !state.milestonesSeen.contains(milestone.rawValue) else { return }
        state.milestonesSeen.append(milestone.rawValue)
    }

    // MARK: Sharing (features/smart-matching Phase C)

    /// Send practice words to tune the keyboard (off by default, Settings → Privacy):
    /// the words of speed tests and drills, one at a time with their touches, and the
    /// keyboard's corrections when `shareCorrections` is on too. Turning it off drops
    /// whatever was waiting and stops the corrections.
    var sharePractice: Bool {
        get { state.sharePractice }
        set {
            guard state.sharePractice != newValue else { return }
            state.sharePractice = newValue
            if newValue {
                uploadPractice()
            } else {
                keyboardSettings.shareCorrections = false
                environment.sharedWords?.remove(pendingShared.map(\.id))
                reloadShared()
            }
        }
    }

    /// "Include corrections from other apps": the keyboard keeps each fix made from the
    /// bar (the word and its first guess, nothing around them) for the app to send.
    /// Needs sharing on, and Full Access for the keyboard to hand them over.
    var shareCorrections: Bool {
        get { keyboardSettings.shareCorrections }
        set { keyboardSettings.shareCorrections = newValue && state.sharePractice }
    }

    /// What will go up next, exactly as it will be sent but for the device line the
    /// upload adds ("What gets shared").
    private(set) var pendingShared: [SharedWord] = []
    private(set) var uploadingPractice = false

    /// Where a recording says it was made.
    var device: PracticeRecording.Device { environment.device }

    /// A session's recording: its words kept to send when sharing is on, dropped
    /// otherwise.
    func savePractice(_ recording: PracticeRecording) {
        guard state.sharePractice, let store = environment.sharedWords else { return }
        store.save(SharedWord.words(of: recording))
        uploadPractice()
    }

    /// Re-reads what is waiting (the keyboard may have added corrections).
    func reloadShared() {
        pendingShared = environment.sharedWords?.pending() ?? []
    }

    /// Taken off the list on "What gets shared": it never goes.
    func removeShared(_ id: UUID) {
        environment.sharedWords?.remove([id])
        reloadShared()
    }

    /// Sends what is waiting, in the background. Safe to call often. Counts
    /// `practice.shared` per kind of word sent.
    func uploadPractice() {
        guard let store = environment.sharedWords else { return }
        migrateRecordings(into: store)
        reloadShared()
        guard state.sharePractice, !uploadingPractice, let uploader = environment.sharedUploader else { return }
        // Corrections only while their switch is on; any left from before wait no more.
        let stale = pendingShared.filter { $0.isCorrection && !keyboardSettings.shareCorrections }
        if !stale.isEmpty { store.remove(stale.map(\.id)); reloadShared() }
        let pending = Array(pendingShared.prefix(100)).map { $0.stamped(with: environment.device) }
        guard !pending.isEmpty else { return }
        uploadingPractice = true
        Task { @MainActor in
            if let sent = try? await uploader.upload(pending) {
                store.markUploaded(sent)
                var kinds: [String: Int] = [:]
                for word in pending where sent.contains(word.id) { kinds[word.kind, default: 0] += 1 }
                for (kind, count) in kinds.sorted(by: { $0.key < $1.key }) {
                    for _ in 0..<count { environment.metrics.count("practice.shared", ["kind": kind]) }
                }
            }
            uploadingPractice = false
            reloadShared()
        }
    }

    /// Whole recordings saved before Phase C go as their words, like new ones.
    private func migrateRecordings(into store: SharedWordStore) {
        guard let recordings = environment.practiceStore, state.sharePractice else { return }
        let old = recordings.pending(limit: .max)
        guard !old.isEmpty else { return }
        store.save(old.flatMap { SharedWord.words(of: $0) })
        recordings.markUploaded(old.map(\.id))
    }

    // MARK: Learned words

    /// Re-reads the shared words and what the keyboard learned (it may have learned
    /// some since).
    func reloadWords() {
        if let words = environment.wordStore.load() { learnedWords = words }
        if let model = environment.personalStore.load() { personal = model }
    }

    // MARK: Learns from you

    /// "Learns from you" (Settings → Typing): the keyboard learns the person's words,
    /// pairs and thumbs, and uses them. It follows the settings to the keyboard.
    var learnsFromYou: Bool {
        get { keyboardSettings.learnsFromYou }
        set { keyboardSettings.learnsFromYou = newValue }
    }

    /// What the keyboard knows, for the line under the switch.
    var personalSummary: PersonalModel.Summary { personal.summary }

    /// "Forget everything": the shared copy is cleared now, and the forget travels with
    /// the settings to the keyboard and through iCloud to the other devices. Counted as
    /// `personal.reset`.
    func forgetPersonal() {
        let date = now
        var model = personal
        model.forget(at: date)
        personal = model
        environment.personalStore.save(model)
        keyboardSettings.forgetPersonalAt = date
        environment.metrics.count("personal.reset")
        sync()
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
                                 settingsChanged: environment.settingsStore.lastChanged() ?? .distantPast,
                                 personal: personal)
        Task { @MainActor in
            do {
                let merged = try await Syncer.sync(local: local, cloud: cloud)
                saveWords(merged.words)
                if let model = merged.personal, model != personal {
                    personal = model
                    environment.personalStore.save(model)
                }
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
