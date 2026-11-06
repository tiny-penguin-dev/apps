#if canImport(UIKit)
import Foundation
import AstrotypeCore
import Synchronization
import UIKit

/// Where the keyboard types: the extension's text document proxy, or a text view in
/// the app. The engine's effects are applied through this, so both hosts behave alike.
@MainActor
public protocol TextTarget: AnyObject {
    var textBeforeCursor: String? { get }
    func insert(_ text: String)
    func deleteBackward()
    /// Show `text` as marked (underlined) text, replacing any marked text.
    func mark(_ text: String)
    /// Turn the marked text into ordinary text.
    func unmark()
    /// Move the cursor by `offset` characters (negative is left).
    func moveCursor(by offset: Int)
    /// Whether the field has any text (for a return key that waits for some).
    var hasText: Bool { get }
    /// Whether the open word is no longer where it was typed: the person selected text,
    /// or the keyboard moved to another field. It is dropped then, not edited.
    var lostOpenWord: Bool { get }
    /// Whether the text right before the cursor is no longer the open word (the person
    /// selected it, or moved the cursor). Checked only before a delete: the field can
    /// lag behind fast typing, and a delete loses nothing when it is wrong.
    var cursorLeftOpenWord: Bool { get }
    /// What the field reports right now, for the typing recorder (`TypingEvent.fieldState`).
    var fieldState: String? { get }
    /// Forget the open word without typing it again.
    func dropOpenWord()
}

extension TextTarget {
    public var hasText: Bool { !(textBeforeCursor ?? "").isEmpty }
    public var lostOpenWord: Bool { false }
    public var cursorLeftOpenWord: Bool { false }
    public var fieldState: String? { nil }
    public func dropOpenWord() {}
}

/// The keyboard's model, one per host (BUILD.md "The engine runs in both processes"):
/// owns the pure `Composer`, applies its effects to the `TextTarget`, keeps the
/// autospace timer and tells the views when the bar or shift changed. Views call this
/// and nothing else.
///
///     let model = KeyboardModel(composer: Composer(dictionary: lexicon, layout: layout))
///     model.target = ProxyTarget(controller: self)
///     model.onChange = { render() }
@MainActor
public final class KeyboardModel {
    public private(set) var composer: Composer
    public weak var target: TextTarget?
    /// Called after every change to the bar, the open word, shift or the settings.
    public var onChange: (() -> Void)?
    public var onHaptic: ((Composer.Haptic) -> Void)?
    /// A word went into the field (space, punctuation, autospace or a tapped guess).
    public var onCommit: ((String) -> Void)?
    /// The learned words changed here: a word learned on commit, a boost or a forget.
    public var onWordsChange: ((LearnedWords) -> Void)?
    /// The settings changed here (the panel, or the app's Settings).
    public var onSettingsChange: ((KeyboardSettings) -> Void)?
    /// The bar should say this for a moment (a second thumb on the free keyboard).
    public var onNotice: ((Composer.Notice) -> Void)?
    /// A word already written was swapped for another from the bar (a fix).
    public var onFix: (() -> Void)?
    /// A fix made from the bar, as a word to share, when the person turned "Include
    /// corrections from other apps" on and the field allows it. The host keeps it for
    /// the app (it needs Full Access to reach it).
    public var onCorrection: ((SharedWord) -> Void)?
    /// A word the keyboard missed, typed with "Not it?" (features/missed-words), in a
    /// field that allows learning. The host keeps it for "Words it missed"; it is also
    /// given to `onCorrection` when corrections are shared.
    public var onMiss: ((SharedWord) -> Void)?
    /// A word went in and was left alone, in a field that allows learning, for the
    /// host to count how often the first guess was right (`GuessTally`). Only counts
    /// leave the host.
    public var onSettled: ((SettledWord) -> Void)?
    /// What the keyboard learned from the person changed here (a word settled, a
    /// forget), for the host's sync. Saving is the model's own job.
    public var onPersonalChange: ((PersonalModel) -> Void)?
    /// Every touch on the keys as the engine sees it, for the app's practice
    /// recordings (never set in the extension).
    public var onTouch: ((TouchRecorder.Phase, Int, CGPoint, TimeInterval) -> Void)?
    /// What the person may use (`Entitlement`): the host sets it from the App Store
    /// and the trial. Everything is allowed until it does.
    public var entitlement: Entitlement = .full {
        didSet {
            guard entitlement != oldValue else { return }
            composer.settings.twoThumbs = entitlement.allows(.twoThumbs)
            log(TypingEvent(t: now, e: .pro, n: entitlement.isPro ? 1 : 0))
            refreshLanguage()
            onChange?()
        }
    }
    /// Whether the keys split on a wide screen: the setting, and Pro allows it.
    public var splitOnWide: Bool { keyboardSettings.splitOnWide && entitlement.allows(.splitLayout) }
    /// The person's keyboard settings; saved to `store` on every change.
    public var keyboardSettings: KeyboardSettings {
        didSet {
            guard keyboardSettings != oldValue else { return }
            applyComposerSettings()
            applyPersonalSettings()
            refreshLanguage()
            settingsChanged = Date()
            log(TypingEvent(t: now, e: .settings, settings: keyboardSettings))
            store?.save(keyboardSettings)
            onChange?()
            onSettingsChange?(keyboardSettings)
        }
    }
    /// When the settings last changed, here or in the store they came from.
    public private(set) var settingsChanged: Date
    public var store: SettingsStore?
    public var wordStore: WordStore?
    /// Where what the keyboard learns from the person is kept; nil learns nothing
    /// (the app's practice field reads the model but never writes it).
    public var personalStore: PersonalStore?
    /// The field being typed in (features/field-types), which the host reads from the
    /// app's traits each time the keyboard appears or the field changes. It decides the
    /// bottom row, the return key, capitals, exact taps, autospace and learning.
    /// While emoji search is open the keys type into the search field instead
    /// (`Field.emojiSearch`); what the host sets meanwhile is kept for when it closes.
    public var field: Field {
        get { search == nil ? hostField : .emojiSearch }
        set { hostField = newValue }
    }
    private var hostField: Field = .text {
        didSet {
            guard hostField != oldValue else { return }
            recordFieldChange(from: oldValue)
            guard search == nil else { return }
            applyComposerSettings()
            composer.setContext(before: output?.textBeforeCursor)
            onChange?()
        }
    }

    /// Where the engine's effects go: the search field while emoji search is open,
    /// else the host's target.
    private var output: TextTarget? {
        if let search { return search }
        return target
    }

    /// Whether the bar may offer next words here at all: the app's practice fields turn
    /// it off, since they measure typing and record every word's touches.
    public var offersNextWords = true {
        didSet {
            guard offersNextWords != oldValue else { return }
            applyComposerSettings()
            composer.setContext(before: output?.textBeforeCursor)
            onChange?()
        }
    }

    /// The engine's settings from the person's and the field's: next words only where
    /// the field learns (no guesses in passwords, codes and addresses, features/next-word).
    private func applyComposerSettings() {
        var settings = field.composerSettings(keyboardSettings.composerSettings(from: composer.settings))
        settings.nextWords = settings.nextWords && learningAllowed && offersNextWords
        composer.settings = settings
    }

    /// Whether the field being typed in may teach the keyboard: never an address, a
    /// code, a number or a field that asks for no autocorrection (`Field.learns`).
    public var learningAllowed: Bool { field.learns }

    /// Whether return does anything now: a field that waits for text (the app's
    /// `enablesReturnKeyAutomatically`) has it off until there is some.
    public var returnEnabled: Bool {
        !field.returnNeedsText || composer.hasOpenWord || (output?.hasText ?? false)
    }

    /// What the keyboard learned from the person's typing (features/smart-matching).
    public private(set) var personal: PersonalLearner
    private var personalSave: Task<Void, Never>?

    /// What the person taught the keyboard; saved to `wordStore` on every change.
    public var learnedWords: LearnedWords {
        get { composer.learned }
        set {
            guard newValue != composer.learned else { return }
            composer.learned = newValue
            wordStore?.save(newValue)
            apply(composer.learnedDidChange(time: now))
        }
    }

    private var autospace: Task<Void, Never>?

    // MARK: Languages

    /// The phone's languages, most preferred first (`Locale.preferredLanguages`): a
    /// Spanish phone types Spanish until the person chooses (features/languages).
    public var preferredLanguages: [String] = Locale.preferredLanguages {
        didSet { if preferredLanguages != oldValue { refreshLanguage() } }
    }
    /// Loads the dictionaries for some languages, off the main thread; the bundled ones
    /// unless a test says otherwise.
    public var loadLanguage: @Sendable ([String]) -> Language? = { try? Language.bundled($0) }
    /// The languages the keyboard types in now: the chosen ones, or one on the free
    /// keyboard (two at once is Pro).
    public var activeLanguages: [String] {
        keyboardSettings.activeLanguages(preferred: preferredLanguages, allowsTwo: entitlement.allows(.twoLanguages))
    }
    private var languageLoad: Task<Void, Never>?
    /// Whether the languages follow the settings. The app's practice field stays in the
    /// language it was made with: the speed test and drills are English.
    public var followsLanguages = true

    /// Swaps the dictionaries when the languages to type in changed. Loading two takes
    /// a moment, so it happens in the background and the keys keep typing meanwhile.
    private func refreshLanguage() {
        guard followsLanguages else { return }
        let codes = activeLanguages
        let code = codes.joined(separator: "+")
        guard code != composer.languageCode else { languageLoad?.cancel(); return }
        languageLoad?.cancel()
        let load = loadLanguage
        languageLoad = Task { [weak self] in
            let language = await Task.detached(priority: .userInitiated) { load(codes) }.value
            guard !Task.isCancelled, let self, let language, self.activeLanguages == codes else { return }
            self.log(TypingEvent(t: self.now, e: .language, s: language.code))
            self.apply(self.composer.setLanguage(language, time: self.now))
            self.onChange?()
        }
    }

    /// `store`'s settings and `wordStore`'s words apply when they have any; otherwise
    /// the defaults and no words.
    ///
    /// With a `personalStore`, the model learns from each settled word into the shard
    /// of `installID`; with only a `personal` model it reads and never learns.
    public init(composer: Composer, store: SettingsStore? = nil, wordStore: WordStore? = nil,
                personalStore: PersonalStore? = nil, personal: PersonalModel? = nil, installID: String = "app") {
        var composer = composer
        LiveCount.models.add(1, ordering: .relaxed)
        let settings = store?.load() ?? KeyboardSettings()
        composer.settings = settings.composerSettings(from: composer.settings)
        if let words = wordStore?.load() { composer.learned = words }
        let now = Date()
        var learner = PersonalLearner(model: personalStore?.load() ?? personal ?? PersonalModel(), device: installID, now: now)
        let forgot = learner.apply(settings, now: now)
        composer.personal = learner.index
        self.composer = composer
        self.store = store
        self.wordStore = wordStore
        self.personalStore = personalStore
        self.personal = learner
        self.keyboardSettings = settings
        self.settingsChanged = store?.lastChanged() ?? .distantPast
        if forgot { personalStore?.save(learner.model) }
    }

    /// "Forget everything" from the keyboard's own settings: the forget travels with
    /// the settings, so the app and the other devices forget too.
    public func forgetPersonal() {
        keyboardSettings.forgetPersonalAt = Date()
    }

    deinit {
        LiveCount.models.subtract(1, ordering: .relaxed)
    }

    /// A personal model from elsewhere (the App Group, iCloud), merged in.
    public func adoptPersonal(_ model: PersonalModel) {
        guard personal.merge(model, now: Date()) else { return }
        composer.personal = personal.index
        savePersonalSoon()
    }

    /// Writes what was learned now, not after the usual pause (the keyboard is going away).
    /// The keyboard is going away: settle the last word (a miss saved just before
    /// is kept now) and write what was learned.
    public func keyboardWillHide() {
        log(TypingEvent(t: now, e: .hide))
        defer { recorder?.flush() }
        for case .settled(let word) in composer.keyboardWillHide() { learn(from: word) }
        onChange?()
        savePersonalNow()
    }

    public func savePersonalNow() {
        guard personalSave != nil else { return }
        personalSave?.cancel()
        personalSave = nil
        personalStore?.save(personal.model)
    }

    private func applyPersonalSettings() {
        let changed = personal.apply(keyboardSettings, now: Date())
        composer.personal = personal.index
        if changed {
            personalStore?.save(personal.model)
            onPersonalChange?(personal.model)
        }
    }

    private func learn(from word: SettledWord) {
        if learningAllowed { onSettled?(word) }
        let share = keyboardSettings.shareCorrections && onCorrection != nil
        if learningAllowed, share || (word.missed && onMiss != nil),
           let correction = SharedWord.correction(word, layout: composer.layout, now: Date()) {
            if correction.isMiss { onMiss?(correction) }
            if share { onCorrection?(correction) }
        }
        guard personalStore != nil, personal.learn(word, allowed: learningAllowed, now: Date()) else { return }
        composer.personal = personal.index
        savePersonalSoon()
        onPersonalChange?(personal.model)
    }

    /// Saves a few seconds after the last word, so typing does not write a file per word.
    private func savePersonalSoon() {
        personalSave?.cancel()
        personalSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            self.personalSave = nil
            self.personalStore?.save(self.personal.model)
        }
    }

    /// Settings that arrived from elsewhere (a sync) with the time they changed there.
    public func adopt(_ settings: KeyboardSettings, changed: Date) {
        guard changed > settingsChanged else { return }
        keyboardSettings = settings
        settingsChanged = changed
    }

    public var state: Composer.State { composer.state }

    public var layout: Layout {
        get { composer.layout }
        set {
            guard newValue != composer.layout else { return }
            composer.layout = newValue
            log(TypingEvent(t: now, e: .layout, layout: TypingLayout(newValue)))
        }
    }

    public var settings: Composer.Settings {
        get { composer.settings }
        set { composer.settings = newValue }
    }

    // MARK: Input

    public func touchBegan(id: Int, at point: CGPoint, time: TimeInterval) {
        dropLostWord()
        onTouch?(.began, id, point, time)
        down.insert(id)
        log(TypingEvent(t: time, e: .down, i: id, x: point.x, y: point.y))
        apply(composer.touchDown(id: id, at: point, time: time))
    }

    public func touchMoved(id: Int, to point: CGPoint, time: TimeInterval) {
        onTouch?(.moved, id, point, time)
        log(TypingEvent(t: time, e: .move, i: id, x: point.x, y: point.y))
        apply(composer.touchMoved(id: id, to: point, time: time))
    }

    public func touchEnded(id: Int, at point: CGPoint, time: TimeInterval) {
        onTouch?(.ended, id, point, time)
        down.remove(id)
        log(TypingEvent(t: time, e: .up, i: id, x: point.x, y: point.y))
        apply(composer.touchUp(id: id, at: point, time: time))
    }

    /// A held key's callout gave another letter for the touch `id` ("ñ" from n).
    public func pick(_ letter: Character, touch id: Int, time: TimeInterval) {
        onTouch?(.cancelled, id, .zero, time)
        down.remove(id)
        log(TypingEvent(t: time, e: .pick, i: id, s: String(letter)))
        apply(composer.pick(letter, touch: id, time: time))
    }

    public func touchCancelled(id: Int, time: TimeInterval) {
        onTouch?(.cancelled, id, .zero, time)
        down.remove(id)
        log(TypingEvent(t: time, e: .cancel, i: id))
        apply(composer.touchCancelled(id: id, time: time))
    }

    public func press(_ key: Key) {
        if key == .backspace { logFieldState() }
        dropLostWord(deleting: key == .backspace)
        log(TypingEvent(t: now, e: .key, s: TypingEvent.code(of: key)))
        apply(composer.press(key, time: now))
    }

    public func press(character: Character) {
        dropLostWord()
        log(TypingEvent(t: now, e: .character, s: String(character)))
        apply(composer.press(character: character, time: now))
    }

    /// A key that types a string (".com").
    public func press(text: String) {
        dropLostWord()
        log(TypingEvent(t: now, e: .text, s: text))
        apply(composer.press(text: text, time: now))
    }

    // MARK: Emoji

    /// Where the emoji history is kept (the keyboard's own file); nil keeps it in
    /// memory only. Setting it loads what it holds.
    public var emojiStore: EmojiStore? {
        didSet { emojiHistory = emojiStore?.load() ?? EmojiHistory() }
    }
    /// Frequently used and the skin tones picked (features/emoji).
    public private(set) var emojiHistory = EmojiHistory()

    /// An emoji tapped on the emoji page: `form` is what goes in (a skin tone form, or
    /// the emoji itself), `base` the emoji it belongs to. Counts for Frequently used.
    public func type(emoji form: String, base: String) {
        log(TypingEvent(t: now, e: .emoji, s: form))
        apply(composer.insert(emoji: form, time: now))
        emojiHistory.record(base, at: Date())
        emojiStore?.save(emojiHistory)
    }

    /// A skin tone picked for `base`, remembered for next time.
    public func setTone(_ form: String, for base: String) {
        emojiHistory.setTone(form, for: base)
        emojiStore?.save(emojiHistory)
    }

    // MARK: Emoji search

    /// The search field while emoji search is open (features/emoji-search).
    public private(set) var search: SearchTarget?

    /// What is in the search field, the open word included.
    public var searchQuery: String { search?.query ?? "" }

    /// Emoji search opens: an open word goes into the app first (as the cursor moving
    /// would write it), then the keys type into the search field, learning nothing.
    public func beginEmojiSearch() {
        guard search == nil else { return }
        log(TypingEvent(t: now, e: .searchOpen))
        apply(composer.cursorWillMove())
        for case .settled(let word) in composer.reset() { learn(from: word) }
        autospace?.cancel()
        search = SearchTarget()
        applyComposerSettings()
        composer.setContext(before: nil)
        onChange?()
    }

    /// Emoji search closes: what was typed there is dropped (never learned), and the
    /// keys type into the app again.
    public func endEmojiSearch() {
        guard search != nil else { return }
        log(TypingEvent(t: now, e: .searchClose))
        autospace?.cancel()
        _ = composer.reset()
        search = nil
        applyComposerSettings()
        composer.setContext(before: output?.textBeforeCursor)
        onChange?()
    }

    /// The × in the search field: empty again, any open word dropped.
    public func clearSearch() {
        guard let search else { return }
        log(TypingEvent(t: now, e: .searchClear))
        autospace?.cancel()
        _ = composer.reset()
        search.clear()
        composer.setContext(before: search.textBeforeCursor)
        onChange?()
    }

    /// A search result tapped: it goes into the app (not the search field), and counts
    /// for Frequently used like one from the page.
    public func typeFromSearch(emoji form: String, base: String) {
        log(TypingEvent(t: now, e: .searchEmoji, s: form))
        target?.insert(form)
        onHaptic?(.key)
        emojiHistory.record(base, at: Date())
        emojiStore?.save(emojiHistory)
    }

    /// A guess tapped on the bar: a guess for the open word, another reading of the
    /// last word (FIX), or a next word.
    public func choose(guess index: Int) {
        log(TypingEvent(t: now, e: .guess, n: index))
        if case .fix(_, let chosen) = composer.state.bar, chosen != index { onFix?() }
        apply(composer.choose(guess: index, time: now))
    }

    /// Another reading of the last word, picked from the bar's fix row while next words
    /// show (features/guesses-bar): `reading` indexes `Bar.next`'s `fix`.
    public func chooseFix(reading: Int) {
        guard case .next(_, let fix, let chosen) = composer.state.bar,
              fix.indices.contains(reading), reading != chosen else { return }
        log(TypingEvent(t: now, e: .fix, n: reading))
        onFix?()
        apply(composer.chooseFix(reading: reading))
    }

    /// A slide on the space bar: the open word goes in, then the cursor moves.
    public func moveCursor(by offset: Int) {
        guard offset != 0 else { return }
        log(TypingEvent(t: now, e: .cursor, n: offset))
        apply(composer.cursorWillMove())
        output?.moveCursor(by: offset)
        composer.setContext(before: output?.textBeforeCursor)
        onChange?()
    }

    /// "Not it?" on the bar: the keys type the word meant into the bar.
    public func beginCorrection() {
        log(TypingEvent(t: now, e: .notIt))
        composer.beginCorrection()
        autospace?.cancel()
        onChange?()
    }

    /// The ✕ in the "Not it?" field.
    public func cancelCorrection() {
        log(TypingEvent(t: now, e: .notItCancel))
        composer.cancelCorrection(time: now)
        scheduleAutospace()
        onChange?()
    }

    /// Save in the "Not it?" field: the word meant replaces the swiped one.
    public func saveCorrection() {
        log(TypingEvent(t: now, e: .notItSave))
        apply(composer.saveCorrection(time: now))
    }

    /// A swipe left on backspace.
    public func deleteWord() {
        logFieldState()
        dropLostWord(deleting: true)
        log(TypingEvent(t: now, e: .deleteWord))
        apply(composer.deleteWord(time: now))
    }

    /// Held a guess on the bar and slid up: the word sticks from now on.
    public func boost(guess index: Int) {
        guard let word = barWord(at: index) else { return }
        log(TypingEvent(t: now, e: .boost, n: index))
        var words = composer.learned
        words.boost(word, at: Date())
        learnedWords = words
        onWordsChange?(words)
    }

    /// Held a guess on the bar and slid down: the word is not offered again.
    public func forget(guess index: Int) {
        guard let word = barWord(at: index) else { return }
        log(TypingEvent(t: now, e: .forget, n: index))
        var words = composer.learned
        words.forget(word, at: Date())
        learnedWords = words
        onWordsChange?(words)
    }

    private func barWord(at index: Int) -> String? {
        switch composer.state.bar {
        case .guesses(let words, _), .fix(let words, _), .next(let words, _, _):
            words.indices.contains(index) ? words[index].lowercased() : nil
        case .idle, .correcting:
            nil
        }
    }

    /// The field changed (the host's `textDidChange`): re-read the context.
    public func contextChanged() {
        logFieldState()
        if dropLostWord() { return }
        logContext(.context)
        composer.setContext(before: output?.textBeforeCursor)
        onChange?()
    }

    /// The field was replaced or the cursor moved: drop the open word.
    public func reset() {
        logContext(.reset)
        autospace?.cancel()
        output?.dropOpenWord()
        for case .settled(let word) in composer.reset() { learn(from: word) }
        composer.setContext(before: output?.textBeforeCursor)
        onChange?()
    }

    // MARK: Recording

    /// Where the typing recording goes (Settings → Debug → "Keep recording",
    /// `TypingRecorder`); nil records nothing. The extension sets it while the setting
    /// is on and it has Full Access. Every touch, key and tap on the bar is written down
    /// with what it did, except in a field that never learns (an address, a code, a
    /// password), where it pauses.
    public var recorder: TypingRecorder? {
        didSet {
            guard recorder !== oldValue else { return }
            oldValue?.flush()
            lastContext = nil
            lastFieldState = nil
            if recorder != nil { snapshot() }
        }
    }
    /// What the extension says about the phone and the build, for each snapshot.
    public var device = TypingSnapshot.Device(app: "?", system: "?", model: "?")
    /// The page showing, which the view keeps (for the snapshot and the log).
    public private(set) var page: Layout.Page = .letters
    /// Fingers down on the letters now: no snapshot while any is.
    private var down: Set<Int> = []
    private var lastContext: String?
    private var lastFieldState: String?

    private var recording: Bool { recorder != nil && hostField.learns }

    private func log(_ event: @autoclosure () -> TypingEvent) {
        guard recording else { return }
        recorder?.record(event())
    }

    /// Writes down where the keyboard stands now, so a replay can start here.
    public func snapshot() {
        guard let recorder, hostField.learns else { return }
        let context = TypingSnapshot.trim(target?.textBeforeCursor)
        lastContext = context
        recorder.snapshot(TypingSnapshot(date: Date(), settings: keyboardSettings, field: hostField, layout: composer.layout,
                                         page: page, languages: activeLanguages, preferred: preferredLanguages,
                                         pro: entitlement.isPro, context: context, device: device), time: now)
    }

    /// A snapshot when one is due and nothing is open: no word, no finger down.
    private func snapshotIfIdle() {
        guard let recorder, recorder.needsSnapshot(at: now), down.isEmpty, !composer.hasOpenWord, search == nil else { return }
        snapshot()
    }

    /// The page the view shows changed (123, #+=, ABC).
    public func pageChanged(_ page: Layout.Page) {
        guard page != self.page else { return }
        self.page = page
        log(TypingEvent(t: now, e: .page, s: page.rawValue))
    }

    /// A touch the engine never gets (space, backspace, a symbol, no key): `phase` is
    /// b, m, e or x, or n for a touch on no key.
    public func otherTouch(_ phase: String, id: Int?, at point: CGPoint, time: TimeInterval, key: Key?) {
        log(TypingEvent(t: time, e: .other, i: id, x: point.x, y: point.y, s: phase, k: key.map(TypingEvent.code(of:))))
    }

    /// Mark in the keyboard's settings: something went wrong around now. Written at
    /// once, so it is there when the person opens the app to send it.
    /// A memory reading for the log (`MemorySample`), with why it goes in now. Logged in
    /// every field, since it holds nothing typed.
    public func logMemory(_ sample: MemorySample, why: String) {
        recorder?.record(TypingEvent(t: now, e: .memory, s: why, mem: sample))
    }

    public func markMoment() {
        guard let recorder else { return }
        recorder.record(TypingEvent(t: now, e: .mark))
        recorder.flush()
    }

    /// What the field reports (selection included), when it differs from the last.
    private func logFieldState() {
        guard recording, let state = output?.fieldState, state != lastFieldState else { return }
        lastFieldState = state
        recorder?.record(TypingEvent(t: now, e: .fieldState, s: state))
    }

    /// The text before the cursor as the app now has it, when it differs from the last.
    private func logContext(_ kind: TypingEvent.Kind) {
        guard recording else { return }
        let context = TypingSnapshot.trim(output?.textBeforeCursor)
        guard context != lastContext || kind == .reset else { return }
        lastContext = context
        recorder?.record(TypingEvent(t: now, e: kind, s: context))
    }

    /// Into a field that never learns: a pause. Back out of one: a snapshot.
    private func recordFieldChange(from old: Field) {
        guard let recorder else { return }
        if old.learns, !hostField.learns {
            recorder.record(TypingEvent(t: now, e: .pause))
            recorder.flush()
        } else if !old.learns, hostField.learns {
            snapshot()
        } else {
            log(TypingEvent(t: now, e: .field, field: hostField))
        }
    }

    /// Drops the open word when it is no longer in the field where it was typed, so the
    /// next key starts afresh: backspace on a selected underlined word deleted one
    /// letter, and a word left underlined was typed again into the next field (Gabriel,
    /// 6 Nov 2026).
    @discardableResult
    private func dropLostWord(deleting: Bool = false) -> Bool {
        guard let output, output.lostOpenWord || (deleting && output.cursorLeftOpenWord) else { return false }
        reset()
        return true
    }

    // MARK: Effects

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func apply(_ effects: [Composer.Effect]) {
        for effect in effects {
            switch effect {
            case .insert(let text):
                output?.insert(text)
            case .deleteBackward(let count):
                for _ in 0..<count { output?.deleteBackward() }
            case .mark(let text):
                output?.mark(text)
            case .commit(let text):
                output?.mark(text)
                output?.unmark()
                onCommit?(text)
            case .clearMark:
                output?.mark("")
                output?.unmark()
            case .haptic(let haptic):
                onHaptic?(haptic)
            case .learn(let word):
                guard learningAllowed else { continue }
                var words = composer.learned
                words.learn(word, at: Date())
                composer.learned = words
                wordStore?.save(words)
                onWordsChange?(words)
            case .unlearn(let word):
                var words = composer.learned
                words.unlearn(word, at: Date())
                composer.learned = words
                wordStore?.save(words)
                onWordsChange?(words)
            case .notice(let notice):
                onNotice?(notice)
            case .settled(let word):
                learn(from: word)
            }
        }
        composer.setContext(before: output?.textBeforeCursor)
        if recording {
            let codes = TypingEvent.codes(of: effects)
            if !codes.isEmpty { recorder?.record(TypingEvent(t: now, e: .effects, fx: codes)) }
            snapshotIfIdle()
        }
        scheduleAutospace()
        onChange?()
    }

    private func scheduleAutospace() {
        autospace?.cancel()
        autospace = nil
        guard let due = composer.autospaceDue else { return }
        let delay = max(0, due - now)
        autospace = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.dropLostWord() else { return }
            self.log(TypingEvent(t: self.now, e: .tick))
            self.apply(self.composer.tick(time: self.now))
        }
    }
}

/// The emoji search field as the engine types into it (features/emoji-search): plain
/// text in memory, with the open word kept apart as marked text, like a real field's.
@MainActor
public final class SearchTarget: TextTarget {
    /// The words written so far.
    public private(set) var text = ""
    /// The open word, still being guessed.
    public private(set) var marked = ""
    /// The longest search kept; more is dropped.
    static let longest = 60

    public init() {}

    /// Everything in the field, the open word included.
    public var query: String { text + marked }

    public var textBeforeCursor: String? { text }
    public var hasText: Bool { !query.isEmpty }

    public func insert(_ text: String) {
        self.text = String((self.text + text).prefix(Self.longest))
    }

    public func deleteBackward() {
        if !marked.isEmpty { marked.removeLast() } else if !text.isEmpty { text.removeLast() }
    }

    public func mark(_ text: String) { marked = text }

    public func unmark() {
        insert(marked)
        marked = ""
    }

    /// The cursor stays at the end: the search field has no cursor to move.
    public func moveCursor(by offset: Int) {}

    /// The × in the field.
    public func clear() {
        text = ""
        marked = ""
    }
}

/// A `TextTarget` on a `UITextView`, for the app's practice field.
@MainActor
public final class TextViewTarget: TextTarget {
    public weak var textView: UITextView?

    public init(textView: UITextView? = nil) {
        self.textView = textView
    }

    public var textBeforeCursor: String? {
        guard let textView, let selected = textView.selectedTextRange,
              let range = textView.textRange(from: textView.beginningOfDocument, to: selected.start) else { return nil }
        return textView.text(in: range)
    }

    public func insert(_ text: String) { textView?.insertText(text) }
    public func deleteBackward() { textView?.deleteBackward() }
    public func mark(_ text: String) {
        textView?.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
    }
    public func unmark() { textView?.unmarkText() }
    public func moveCursor(by offset: Int) {
        guard let textView, let selected = textView.selectedTextRange,
              let position = textView.position(from: selected.start, offset: offset) else { return }
        textView.selectedTextRange = textView.textRange(from: position, to: position)
    }
}
#endif
