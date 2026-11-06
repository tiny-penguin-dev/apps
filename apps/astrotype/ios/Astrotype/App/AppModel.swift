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
        case hello, turnOn, languages, sync, tryIt, home
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
            // Recording off: what the phone kept goes too.
            if oldValue.recordsTyping, !keyboardSettings.recordsTyping { clearTypingRecording() }
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

    /// Sends the keyboard's memory readings the app has not sent yet (`KeyboardHealth`).
    /// With sharing off the keyboard writes none, and the metrics go nowhere.
    func sendKeyboardHealth() {
        guard let health = environment.keyboardHealth?.load() else { return }
        let due = health.toSend(after: state.keyboardHealthSent, now: environment.now())
        guard !due.isEmpty else { return }
        if let newest = KeyboardHealth.report(due, to: environment.metrics) { state.keyboardHealthSent = newest }
    }

    // MARK: Debug

    /// The keyboard's last memory readings (Settings → Debug), as last read. Nil until
    /// the keyboard has run with Full Access.
    private(set) var keyboardDebug: KeyboardDebug?
    /// The keyboard's recent sessions as kept for Sentry (only with sharing on), newest first.
    private(set) var keyboardSessions: [KeyboardHealth.Session] = []
    /// The app's own memory, as last read.
    private(set) var appMemory: MemoryReading?

    /// Re-reads the keyboard's memory and the app's own, for the Debug page (each second
    /// while it is open).
    func reloadDebug() {
        let debug = environment.keyboardDebug?.load()
        if debug != keyboardDebug { keyboardDebug = debug }
        let sessions = Array((environment.keyboardHealth?.load()?.sessions ?? []).reversed())
        if sessions != keyboardSessions { keyboardSessions = sessions }
        appMemory = environment.readMemory()
    }

    /// Whether the keyboard has run with Full Access, as far as the app can tell.
    var isFullAccessOn: Bool { extensionStatus?.fullAccess == true }

    func openSettings() {
        environment.openSettings()
    }

    // MARK: Typing recorder

    /// Whether the recorder is offered: TestFlight and Xcode builds only, never the App
    /// Store's (it records everything typed, for Gabriel's bug reports).
    private(set) var isTestBuild = false
    /// The marks kept in the recording, newest first, and its size on the phone.
    private(set) var typingMarks: [Date] = []
    private(set) var typingKB = 0
    /// The stretch being sent, in minutes, while it goes.
    private(set) var typingSending: Int?
    /// What the last send or delete came to, for the Debug page.
    private(set) var typingNote: String?

    var typingLogsSent: [SentTypingLog] { state.typingLogsSent }

    func checkTestBuild() async {
        isTestBuild = await environment.isTestBuild()
    }

    /// Re-reads the marks and the size (the Debug page, each second).
    func reloadTyping() {
        guard let files = environment.typingLog else { return }
        let marks = files.marks()
        if marks != typingMarks { typingMarks = marks }
        let kb = files.size() / 1024
        if kb != typingKB { typingKB = kb }
    }

    /// The last `minutes` of the recording as a log, with what the keyboard learned so
    /// a replay guesses as the phone did. Nil when nothing was typed in that time.
    func typingLog(minutes: Int) -> TypingLog? {
        environment.typingLog?.log(last: TimeInterval(minutes * 60), now: environment.now(), writer: environment.device.writer,
                                   app: environment.appVersion, learned: environment.wordStore.load(),
                                   personal: environment.personalStore.load())
    }

    /// Sends the last `minutes` to CloudKit, where Claude downloads it
    /// (`ml/download_samples.py --typing`).
    func sendTyping(minutes: Int) {
        guard typingSending == nil, let uploader = environment.typingUploader else { return }
        guard let log = typingLog(minutes: minutes) else {
            typingNote = "Nothing was typed in the last \(Self.minutes(minutes))."
            return
        }
        guard let data = try? log.encoded(), let compressed = environment.compress(data) else {
            typingNote = "Couldn't pack the recording up."
            return
        }
        typingSending = minutes
        typingNote = nil
        Task { @MainActor in
            do {
                let records = try await uploader.upload(log.parts(compressed: compressed))
                state.typingLogsSent.append(SentTypingLog(id: log.id, sent: environment.now(), summary: log.summary, records: records))
                typingNote = "Sent the last \(Self.minutes(minutes)) (\(log.summary)). Tell Claude what went wrong."
            } catch {
                typingNote = "Couldn't send it: \(error.localizedDescription)"
            }
            typingSending = nil
        }
    }

    /// The last `minutes` as a file to share another way (AirDrop, Files).
    func typingFile(minutes: Int) -> URL? {
        guard let log = typingLog(minutes: minutes), let data = try? log.encoded() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("typing-\(log.id.uuidString.prefix(8)).json")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    /// Deletes the logs sent from iCloud again.
    func deleteSentTyping() {
        guard let uploader = environment.typingUploader, !state.typingLogsSent.isEmpty else { return }
        let sent = state.typingLogsSent
        Task { @MainActor in
            do {
                try await uploader.delete(sent.flatMap(\.records))
                state.typingLogsSent.removeAll { log in sent.contains { $0.id == log.id } }
                typingNote = sent.count == 1 ? "Deleted the log you sent from iCloud." : "Deleted the \(sent.count) logs you sent from iCloud."
            } catch {
                typingNote = "Couldn't delete them: \(error.localizedDescription)"
            }
        }
    }

    /// Throws away what the phone has kept.
    func clearTypingRecording() {
        environment.typingLog?.removeAll()
        reloadTyping()
        typingNote = "The recording on this phone is cleared."
    }

    static func minutes(_ minutes: Int) -> String { minutes == 1 ? "minute" : "\(minutes) minutes" }

    // MARK: Setup

    /// The next setup screen, from Hello through to Home.
    func next() {
        switch screen {
        case .hello: screen = .turnOn
        case .turnOn: screen = asksLanguages ? .languages : .sync
        case .languages: screen = .sync
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

    // MARK: Languages

    /// The phone's languages, most preferred first.
    var preferredLanguages: [String] { Locale.preferredLanguages }

    /// The languages the keyboard types in (features/languages): the chosen ones, or
    /// the phone's, one on the free keyboard.
    var activeLanguages: [String] {
        keyboardSettings.activeLanguages(preferred: preferredLanguages, allowsTwo: entitlement.allows(.twoLanguages))
    }

    /// Setup asks which languages only when the phone lists more than one the keyboard
    /// knows, and nobody chose yet.
    var asksLanguages: Bool {
        keyboardSettings.languages == nil && KeyboardSettings.phoneLanguages(preferredLanguages).count > 1
    }

    /// A language chosen but off because the keyboard is free (the trial ended with
    /// two on): it comes back with Pro.
    var languageOffWithoutPro: String? {
        guard !entitlement.allows(.twoLanguages) else { return nil }
        return keyboardSettings.chosenLanguages(preferred: preferredLanguages).first { !activeLanguages.contains($0) }
    }

    /// Turns a language on or off: on adds it (free, it takes the other's place), off
    /// drops it unless it is the last one. Counted as `languages.enabled`.
    func setLanguage(_ code: String, on: Bool) {
        var chosen = activeLanguages
        if on {
            guard !chosen.contains(code) else { return }
            chosen = entitlement.allows(.twoLanguages) ? chosen + [code] : [code]
        } else {
            guard chosen.count > 1 else { return }
            chosen.removeAll { $0 == code }
        }
        setLanguages(chosen)
    }

    /// The languages from setup's question, or the page.
    func setLanguages(_ codes: [String]) {
        guard !codes.isEmpty, codes != keyboardSettings.languages else { return }
        keyboardSettings.languages = codes
        environment.metrics.count("languages.enabled", ["set": codes.sorted().joined(separator: "+")])
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

    /// The prompts for "Practice words": common words and short phrases from the
    /// language's dictionary and word pairs. Nil if the language files are missing.
    func practiceWords() -> PracticeWords? {
        (try? Language.bundled()).map { PracticeWords(language: $0) }
    }

    /// Re-reads what is waiting (the keyboard may have added corrections).
    func reloadShared() {
        pendingShared = environment.sharedWords?.pending() ?? []
    }

    /// The words the keyboard missed, newest first ("Words it missed").
    private(set) var missedWords: [SharedWord] = []
    /// Of those, the ones already sent, and the ones waiting to go.
    private(set) var sentMisses: Set<UUID> = []
    private(set) var waitingMisses: Set<UUID> = []

    /// Re-reads the misses (the keyboard adds them as you type).
    func reloadMissed() {
        missedWords = Array((environment.missedWords?.pending() ?? []).reversed())
        sentMisses = environment.sharedWords?.uploadedIDs() ?? []
        waitingMisses = Set((environment.sharedWords?.pending() ?? []).map(\.id))
    }

    /// Swiped away on "Words it missed": off the list, and not sent if it was waiting.
    func removeMissed(_ id: UUID) {
        environment.missedWords?.remove([id])
        environment.sharedWords?.remove([id])
        reloadMissed()
        reloadShared()
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
        if let model = environment.personalStore.load() { personal = personal.merged(with: model) }
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
        // The remembered swipes went with the model; the list of misses goes too.
        environment.missedWords?.remove((environment.missedWords?.pending() ?? []).map(\.id))
        missedWords = []
        keyboardSettings.forgetPersonalAt = date
        environment.metrics.count("personal.reset")
        sync()
    }

    /// The practice keyboard learned, boosted or forgot something.
    func learnedWordsChanged(_ words: LearnedWords) {
        saveWords(learnedWords.merged(with: words))
        sync()
    }

    /// Dropped from the learned words list, by a swipe or several with Select: not
    /// offered again. Counted as `words.deleted`.
    func forget(_ words: [String], how: DeleteGesture) {
        guard !words.isEmpty else { return }
        var learned = learnedWords
        for word in words { learned.forget(word, at: now) }
        saveWords(learned)
        environment.metrics.count("words.deleted", by: words.count, ["how": how.rawValue])
        sync()
    }

    /// Typed in with + on the learned words list: learned and kept, on every device.
    /// Returns false for text that isn't one word (`LearnedWords.addable`). Counted as
    /// `words.added`.
    @discardableResult
    func addWord(_ text: String) -> Bool {
        guard let word = LearnedWords.addable(text) else { return false }
        var learned = learnedWords
        learned.add(word, at: now)
        saveWords(learned)
        environment.metrics.count("words.added")
        sync()
        return true
    }

    /// How a list entry was deleted, for the metrics.
    enum DeleteGesture: String { case swipe, select }

    // MARK: Word pairs

    /// The pairs the keyboard learned, for Settings → Word pairs (re-read first: the
    /// keyboard may have learned some since).
    func learnedPairs() -> [LearnedPair] {
        reloadWords()
        return personal.learnedPairs(at: now)
    }

    /// Deleted from Settings → Word pairs (`LearnedPair.id`s): gone here, in the
    /// keyboard, and on the other devices once they sync. Counted as `pairs.deleted`.
    func forgetPairs(_ ids: [String], how: DeleteGesture) {
        guard !ids.isEmpty else { return }
        var model = environment.personalStore.load().map { personal.merged(with: $0) } ?? personal
        model.forgetPairs(ids, at: now)
        personal = model
        environment.personalStore.save(model)
        environment.metrics.count("pairs.deleted", by: ids.count, ["how": how.rawValue])
        sync()
    }

    /// The word pairs list opened. Counted as `pairs.opened`.
    func pairsOpened() {
        environment.metrics.count("pairs.opened")
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

    // MARK: Keyboard styles (features/customization)

    /// Puts a theme on the keys.
    func chooseTheme(_ id: String) {
        keyboardSettings.themeID = id
        let theme = keyboardSettings.chosenTheme
        environment.metrics.count("appearance.theme_chosen", ["theme": theme.isCustom ? "custom" : theme.id])
    }

    /// Picks an effects preset, or flow on or off.
    func chooseEffects(_ effects: EffectsSettings) {
        keyboardSettings.effects = effects
        environment.metrics.count("appearance.effects_chosen",
                                  ["preset": effects.preset?.rawValue ?? "mix", "flow": effects.flow ? "on" : "off"])
    }

}
