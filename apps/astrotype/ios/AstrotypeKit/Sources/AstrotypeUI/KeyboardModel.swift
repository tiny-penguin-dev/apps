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
    /// Show `text` as the open word, right before the cursor, in place of the last
    /// open word. It is ordinary text: never marked (underlined) text, which hid the
    /// person's taps and selections from the keyboard (removed 8 Nov 2026).
    func mark(_ text: String)
    /// The open word went in: keep it as it is and stop replacing it.
    func unmark()
    /// Move the cursor by `offset` characters (negative is left).
    func moveCursor(by offset: Int)
    /// Whether the field has any text (for a return key that waits for some).
    var hasText: Bool { get }
    /// Whether the open word is no longer where it was typed: the person selected text,
    /// or the keyboard moved to another field. It is dropped then, not edited.
    var lostOpenWord: Bool { get }
    /// Whether the person has text selected in the field: a key is then for the
    /// selection, never for the word before it.
    var hasSelection: Bool { get }
    /// What the field reports right now, for the typing recorder (`TypingEvent.fieldState`).
    var fieldState: String? { get }
    /// The text after the cursor (or after the selection), as far as the field tells.
    var textAfterCursor: String? { get }
    /// The selected text, if any.
    var selectedText: String? { get }
    /// Forget the open word without typing it again.
    func dropOpenWord()
}

extension TextTarget {
    public var hasText: Bool { !(textBeforeCursor ?? "").isEmpty }
    public var lostOpenWord: Bool { false }
    public var hasSelection: Bool { false }
    public var fieldState: String? { nil }
    public var textAfterCursor: String? { nil }
    public var selectedText: String? { nil }
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
    /// A word written earlier was swapped (features/fix-earlier-word): what was there
    /// and what went in, for the bar to say so with Undo (`undoEarlierFix`).
    public var onEarlierFixed: ((String, String) -> Void)?
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
    /// A timed stretch of typing ended and counts toward the everyday speed
    /// (features/typing-speed): times and counts only. The extension sets it with Full
    /// Access; nil measures nothing (the app's practice fields).
    public var onSpeedRun: ((SpeedRun) -> Void)?
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
            endSpeedRun()
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
        settings.replacements = TextReplacements(own: keyboardSettings.textReplacements,
                                                 phone: keyboardSettings.usesPhoneReplacements ? phoneReplacements : [])
        // The app's practice fields measure typing word by word: no replacements there.
        settings.replacesText = settings.replacesText && offersNextWords
        composer.settings = settings
    }

    /// The phone's own text replacements (Settings → General → Keyboard → Text
    /// Replacement), which the extension reads from iOS (`UILexicon`); used when
    /// `KeyboardSettings.usesPhoneReplacements` is on (features/text-replacements).
    public var phoneReplacements: [TextReplacement] = [] {
        didSet {
            guard phoneReplacements != oldValue else { return }
            applyComposerSettings()
            onChange?()
        }
    }

    /// The replacements the snippet page lists: the person's own, newest first, then the
    /// phone's in A to Z order, one per shortcut (features/text-replacements).
    public var snippets: [TextReplacement] {
        guard composer.settings.replacesText else { return [] }
        let own = keyboardSettings.textReplacements
        let taken = Set(own.map(\.shortcut))
        let phone = (keyboardSettings.usesPhoneReplacements ? phoneReplacements : [])
            .filter { TextReplacements.shortcut($0.shortcut).map { !taken.contains($0) } ?? false }
            .sorted { $0.shortcut.localizedCaseInsensitiveCompare($1.shortcut) == .orderedAscending }
        return own + phone
    }

    /// Whether the bar offers the snippet page: there are replacements, and they apply here.
    public var offersSnippets: Bool {
        composer.settings.replacesText && !composer.settings.replacements.isEmpty && search == nil
    }

    /// A replacement picked on the snippet page: its phrase goes in at the cursor.
    public func write(replacement shortcut: String) {
        log(TypingEvent(t: now, e: .snippet, s: shortcut))
        autospace?.cancel()
        apply(composer.write(replacement: shortcut, time: now))
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
            self.refreshNextWordModels()
            self.onChange?()
        }
    }

    /// Loads one language's next-word model (features/next-word-model), or nil when
    /// this build has none for it. The keyboard sets it; the app's practice field leaves
    /// it nil and keeps the word pairs. Runs off the main thread.
    public var loadNextWordModel: (@Sendable (String) -> NextWordModel?)? {
        didSet { refreshNextWordModels() }
    }
    private var nextWordLoad: Task<Void, Never>?

    /// Loads the models of the languages typed in now, in the background; the word
    /// pairs answer until they are in.
    private func refreshNextWordModels() {
        guard let load = loadNextWordModel, let code = composer.languageCode else { return }
        let codes = code.split(separator: "+").map(String.init)
        guard codes != composer.nextWordModels.map(\.code) else { return }
        nextWordLoad?.cancel()
        nextWordLoad = Task { [weak self] in
            let (models, line) = await Task.detached(priority: .utility) { () -> ([NextWordModel], String) in
                let before = MemoryReading.current()?.footprintMB ?? 0
                let started = Date()
                let models = codes.compactMap(load)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                let after = MemoryReading.current()?.footprintMB ?? 0
                let line = "\(models.map(\.code).joined(separator: "+")) \(ms) ms "
                    + String(format: "%.1f → %.1f MB", before, after)
                return (models, line)
            }.value
            guard !Task.isCancelled, let self, self.composer.languageCode == code,
                  models.map(\.code) != self.composer.nextWordModels.map(\.code) else { return }
            // What they cost, so the typing log shows it on a real phone (a second load
            // in the same process is the shared copy, near zero).
            self.recorder?.record(TypingEvent(t: self.now, e: .nextWordLoad, s: line))
            self.composer.nextWordModels = models
            self.onChange?()
        }
    }

    /// Back to the word pairs alone, for a memory warning; the models load again the
    /// next time the languages change or the keyboard asks.
    public func dropNextWordModels() {
        nextWordLoad?.cancel()
        composer.nextWordModels = []
        onChange?()
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
        // `{clipboard}` in a replacement: read only as the phrase goes in. Without Full
        // Access iOS gives the keyboard nothing, and it writes nothing.
        composer.clipboard = { MainActor.assumeIsolated { UIPasteboard.general.string } }
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
        endSpeedRun()
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
        if measuringSpeed { speed.wordWentIn() }
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
        speedTouched()
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
        dropLostWord()
        speedTouched()
        log(TypingEvent(t: now, e: .key, s: TypingEvent.code(of: key)))
        apply(composer.press(key, time: now))
    }

    public func press(character: Character) {
        dropLostWord()
        speedTouched()
        log(TypingEvent(t: now, e: .character, s: String(character)))
        apply(composer.press(character: character, time: now))
    }

    /// A key that types a string (".com").
    public func press(text: String) {
        dropLostWord()
        speedTouched()
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
        let earlier: (old: String, new: String)?
        if case .earlier(let words, let chosen) = composer.state.bar, words.indices.contains(index), index != chosen {
            earlier = (words[chosen], words[index])
        } else {
            earlier = nil
        }
        apply(composer.choose(guess: index, time: now))
        if let earlier, composer.canUndoEarlierFix { earlierFixed(earlier.old, earlier.new, how: "reading") }
    }

    /// A word written earlier went in place of another: counted, and the bar says so.
    private func earlierFixed(_ old: String, _ new: String, how: String) {
        onWordAction?("earlier.fixed", how)
        onEarlierFixed?(old, new)
    }

    /// Undo on the bar after a word written earlier was swapped: it goes back.
    public func undoEarlierFix() {
        guard composer.canUndoEarlierFix else { return }
        log(TypingEvent(t: now, e: .earlierUndo))
        apply(composer.undoEarlierFix())
        onWordAction?("earlier.undone", nil)
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
        lastOwnEdit = now
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
        let old = composer.earlierWord
        let typed: String? = { if case .correcting(let typed) = composer.state.bar { typed } else { nil } }()
        apply(composer.saveCorrection(time: now))
        if let old, let typed, composer.canUndoEarlierFix { earlierFixed(old, typed, how: "typed") }
    }

    /// A swipe left on backspace.
    public func deleteWord() {
        logFieldState()
        dropLostWord()
        log(TypingEvent(t: now, e: .deleteWord))
        apply(composer.deleteWord(time: now))
    }

    /// "Suggest more" or "Learn it" from the word menu, or a hold slid up
    /// (features/word-control): the word is learned now if it was not, and ranks higher.
    public func boost(guess index: Int, how: String = "slide") {
        guard let word = barWord(at: index) else { return }
        log(TypingEvent(t: now, e: .boost, n: index))
        changeWord(word) { $0.teach(word, at: Date()) }
        onWordAction?("word.boosted", how)
    }

    /// "Never suggest" from the word menu, or a hold slid down: the word is not offered
    /// again, on any device.
    public func forget(guess index: Int, how: String = "slide") {
        guard let word = barWord(at: index) else { return }
        log(TypingEvent(t: now, e: .forget, n: index))
        changeWord(word) { $0.block(word, at: Date()) }
        onWordAction?("word.blocked", how)
    }

    /// Undo on the bar: the last word changed from the bar goes back as it was.
    public func undoWordChange() {
        guard let (word, before) = lastWordChange else { return }
        lastWordChange = nil
        log(TypingEvent(t: now, e: .wordUndo, s: word))
        var words = composer.learned
        words.restore(word, to: before, at: Date())
        learnedWords = words
        onWordsChange?(words)
        onWordAction?("word.allowed", "undo")
    }

    /// The word menu opened on a held guess (counted only).
    public func wordMenuOpened() {
        onWordAction?("word.menu", nil)
    }

    /// The last word changed from the bar and how it was before, for Undo.
    public private(set) var lastWordChange: (word: String, before: LearnedWords.Entry?)?

    /// Something was done to a word from the bar (features/word-control): the metric's
    /// name and its `how`, for the host to count (`GuessTally.addAction`).
    public var onWordAction: ((String, String?) -> Void)?

    /// Whether the guess at `index` is a word the keyboard already knows (the
    /// dictionary's or the person's): the word menu offers "Suggest more" for one,
    /// "Learn it" for letters it does not know.
    public func knows(guess index: Int) -> Bool {
        guard let word = barWord(at: index) else { return true }
        return composer.matcher.knows(word)
    }

    private func changeWord(_ word: String, _ change: (inout LearnedWords) -> Void) {
        var words = composer.learned
        lastWordChange = (word, words.entry(for: word))
        change(&words)
        learnedWords = words
        onWordsChange?(words)
    }

    private func barWord(at index: Int) -> String? {
        switch composer.state.bar {
        case .guesses(let words, _), .fix(let words, _), .next(let words, _, _), .earlier(let words, _):
            words.indices.contains(index) ? words[index].lowercased() : nil
        case .idle, .correcting:
            nil
        }
    }

    /// The field changed (the host's `textDidChange`, `selectionDidChange`): re-read the
    /// context. `why` goes to the typing recorder.
    public func contextChanged(_ why: String = "change") {
        logFieldState(why)
        if dropLostWord() {
            lookAtCursor()
            return
        }
        logContext(.context)
        composer.setContext(before: output?.textBeforeCursor)
        lookAtCursor()
        onChange?()
    }

    /// When the keyboard last changed the field itself: a change the field reports
    /// right after is its own, not the person moving the cursor.
    private var lastOwnEdit: TimeInterval = 0
    /// What was after the cursor when the keyboard last typed, so a fix of a word
    /// written earlier can put the cursor back there (`EarlierSpot.rest`).
    private var typedAfter: String?

    /// The person put the cursor in a word written earlier, or selected one
    /// (features/fix-earlier-word): the bar shows it with its other readings. Only in
    /// a field that learns, and not in the app's practice fields.
    private func lookAtCursor() {
        guard search == nil, learningAllowed, offersNextWords, !composer.hasOpenWord,
              now - lastOwnEdit > 0.3, let output else { return }
        let wasShowing: Bool = { if case .earlier = composer.state.bar { true } else { false } }()
        let spot = EarlierSpot.find(before: output.textBeforeCursor ?? "", after: output.textAfterCursor ?? "",
                                    selected: output.selectedText, typedAfter: typedAfter)
        guard spot != nil || wasShowing else { return }
        log(TypingEvent(t: now, e: .earlier, i: spot?.rest, n: spot?.offset, s: spot?.word, k: spot?.selected == true ? "sel" : nil))
        apply(composer.cursorLanded(at: spot))
        if let spot, !wasShowing, case .earlier = composer.state.bar {
            onWordAction?("earlier.shown", spot.selected ? "select" : "cursor")
        }
    }

    /// The field was replaced or the cursor moved: drop the open word.
    public func reset() {
        logContext(.reset)
        autospace?.cancel()
        output?.dropOpenWord()
        markLength = 0
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

    /// How long the keyboard took to open (`OpenTiming.line`). Logged in every field.
    public func logOpen(_ line: String) {
        recorder?.record(TypingEvent(t: now, e: .open, s: line))
    }

    public func markMoment() {
        guard let recorder else { return }
        recorder.record(TypingEvent(t: now, e: .mark))
        recorder.flush()
    }

    /// What the field reports (selection included), when it differs from the last.
    /// With `why` (the host said the field changed), every time, so the recording shows
    /// which changes the host reports at all.
    private func logFieldState(_ why: String? = nil) {
        guard recording, let state = output?.fieldState, why != nil || state != lastFieldState else { return }
        lastFieldState = state
        recorder?.record(TypingEvent(t: now, e: .fieldState, s: why.map { "\($0): " + state } ?? state))
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
    ///
    /// Text selected with no word open drops the last word too: backspace reopened it
    /// (the text before a whole-text selection is empty) and typed it back into the
    /// emptied field instead of just deleting the selection (recording, 6 Nov 2026).
    private func dropLostWord() -> Bool {
        guard let output, output.lostOpenWord || output.hasSelection else { return false }
        reset()
        return true
    }

    // MARK: Effects

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func apply(_ effects: [Composer.Effect]) {
        var typed = 0
        for effect in effects {
            switch effect {
            case .insert(let text):
                output?.insert(text)
                typed += text.count
            case .deleteBackward(let count):
                for _ in 0..<count { output?.deleteBackward() }
                typed -= count
            case .mark(let text):
                output?.mark(text)
                typed += text.count - markLength
                markLength = text.count
            case .commit(let text):
                output?.mark(text)
                output?.unmark()
                typed += text.count - markLength
                markLength = 0
                onCommit?(text)
            case .clearMark:
                output?.mark("")
                output?.unmark()
                typed -= markLength
                markLength = 0
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
            case .moveCursor(let offset):
                output?.moveCursor(by: offset)
            }
        }
        if measuringSpeed { speed.edited(characters: typed, at: now) }
        if effects.contains(where: Self.editsField) {
            lastOwnEdit = now
            typedAfter = output?.textAfterCursor
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

    // MARK: Typing speed

    private var speed = SpeedMeter()
    /// How long the open word shown in the field is, to count what a new mark adds.
    private var markLength = 0
    /// Timing runs: someone takes them, the setting is on, the field learns (no
    /// passwords or codes) and emoji search is closed.
    private var measuringSpeed: Bool {
        onSpeedRun != nil && keyboardSettings.measuresSpeed && hostField.learns && search == nil
    }

    private func speedTouched() {
        guard measuringSpeed else { return }
        if let run = speed.touched(at: now, date: Date()) { onSpeedRun?(run) }
    }

    private func endSpeedRun() {
        if let run = speed.end() { onSpeedRun?(run) }
    }

    /// Whether an effect changes the field's text or moves its cursor.
    private static func editsField(_ effect: Composer.Effect) -> Bool {
        switch effect {
        case .insert, .deleteBackward, .mark, .commit, .clearMark, .moveCursor: true
        case .haptic, .learn, .unlearn, .notice, .settled: false
        }
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

    /// The open word, as it stands in the field right before the cursor.
    private var open = ""
    /// True while the open word is being swapped for a new reading, so the field's
    /// change callbacks in between (the old word half deleted) can be ignored, as the
    /// extension never hears about its own edits.
    public private(set) var isSwappingWord = false

    /// The text before the cursor without the open word.
    public var textBeforeCursor: String? {
        guard let before = beforeCursor else { return nil }
        return !open.isEmpty && before.hasSuffix(open) ? String(before.dropLast(open.count)) : before
    }

    private var beforeCursor: String? {
        guard let textView, let selected = textView.selectedTextRange,
              let range = textView.textRange(from: textView.beginningOfDocument, to: selected.start) else { return nil }
        return textView.text(in: range)
    }

    public var hasText: Bool { textView?.hasText ?? false }

    public var textAfterCursor: String? {
        guard let textView, let selected = textView.selectedTextRange,
              let range = textView.textRange(from: selected.end, to: textView.endOfDocument) else { return nil }
        return textView.text(in: range)
    }

    public var selectedText: String? {
        guard let textView, let selected = textView.selectedTextRange, !selected.isEmpty else { return nil }
        return textView.text(in: selected)
    }

    public func insert(_ text: String) { textView?.insertText(text) }
    public func deleteBackward() { textView?.deleteBackward() }

    /// The open word as ordinary text, like in other apps: the old reading is taken out
    /// and the new one typed, unless the cursor moved away from it.
    public func mark(_ text: String) {
        guard let textView, text != open else { return }
        isSwappingWord = true
        defer { isSwappingWord = false }
        if !open.isEmpty, (beforeCursor ?? "").hasSuffix(open) {
            for _ in 0..<open.count { textView.deleteBackward() }
        }
        if !text.isEmpty { textView.insertText(text) }
        open = text
    }
    public func unmark() { open = "" }
    public func dropOpenWord() { open = "" }

    public func moveCursor(by offset: Int) {
        guard let textView, let selected = textView.selectedTextRange,
              let position = textView.position(from: selected.start, offset: offset) else { return }
        textView.selectedTextRange = textView.textRange(from: position, to: position)
    }
}
#endif
