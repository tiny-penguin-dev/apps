#if canImport(UIKit)
import Foundation
import AstrotypeCore
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
}

extension TextTarget {
    public var hasText: Bool { !(textBeforeCursor ?? "").isEmpty }
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
            composer.settings = field.composerSettings(keyboardSettings.composerSettings(from: composer.settings))
            applyPersonalSettings()
            refreshLanguage()
            settingsChanged = Date()
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
    public var field: Field = .text {
        didSet {
            guard field != oldValue else { return }
            composer.settings = field.composerSettings(keyboardSettings.composerSettings(from: composer.settings))
            onChange?()
        }
    }

    /// Whether the field being typed in may teach the keyboard: never an address, a
    /// code, a number or a field that asks for no autocorrection (`Field.learns`).
    public var learningAllowed: Bool { field.learns }

    /// Whether return does anything now: a field that waits for text (the app's
    /// `enablesReturnKeyAutomatically`) has it off until there is some.
    public var returnEnabled: Bool {
        !field.returnNeedsText || composer.hasOpenWord || (target?.hasText ?? false)
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

    /// A personal model from elsewhere (the App Group, iCloud), merged in.
    public func adoptPersonal(_ model: PersonalModel) {
        guard personal.merge(model, now: Date()) else { return }
        composer.personal = personal.index
        savePersonalSoon()
    }

    /// Writes what was learned now, not after the usual pause (the keyboard is going away).
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
        set { composer.layout = newValue }
    }

    public var settings: Composer.Settings {
        get { composer.settings }
        set { composer.settings = newValue }
    }

    // MARK: Input

    public func touchBegan(id: Int, at point: CGPoint, time: TimeInterval) {
        onTouch?(.began, id, point, time)
        apply(composer.touchDown(id: id, at: point, time: time))
    }

    public func touchMoved(id: Int, to point: CGPoint, time: TimeInterval) {
        onTouch?(.moved, id, point, time)
        apply(composer.touchMoved(id: id, to: point, time: time))
    }

    public func touchEnded(id: Int, at point: CGPoint, time: TimeInterval) {
        onTouch?(.ended, id, point, time)
        apply(composer.touchUp(id: id, at: point, time: time))
    }

    /// A held key's callout gave another letter for the touch `id` ("ñ" from n).
    public func pick(_ letter: Character, touch id: Int, time: TimeInterval) {
        onTouch?(.cancelled, id, .zero, time)
        apply(composer.pick(letter, touch: id, time: time))
    }

    public func touchCancelled(id: Int, time: TimeInterval) {
        onTouch?(.cancelled, id, .zero, time)
        apply(composer.touchCancelled(id: id, time: time))
    }

    public func press(_ key: Key) {
        apply(composer.press(key, time: now))
    }

    public func press(character: Character) {
        apply(composer.press(character: character, time: now))
    }

    /// A key that types a string (".com").
    public func press(text: String) {
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
        apply(composer.insert(emoji: form, time: now))
        emojiHistory.record(base, at: Date())
        emojiStore?.save(emojiHistory)
    }

    /// A skin tone picked for `base`, remembered for next time.
    public func setTone(_ form: String, for base: String) {
        emojiHistory.setTone(form, for: base)
        emojiStore?.save(emojiHistory)
    }

    public func choose(guess index: Int) {
        if case .fix(_, let chosen) = composer.state.bar, chosen != index { onFix?() }
        apply(composer.choose(guess: index, time: now))
    }

    /// A slide on the space bar: the open word goes in, then the cursor moves.
    public func moveCursor(by offset: Int) {
        guard offset != 0 else { return }
        apply(composer.cursorWillMove())
        target?.moveCursor(by: offset)
        composer.setContext(before: target?.textBeforeCursor)
        onChange?()
    }

    /// "Not it?" on the bar: the keys type the word meant into the bar.
    public func beginCorrection() {
        composer.beginCorrection()
        autospace?.cancel()
        onChange?()
    }

    /// The ✕ in the "Not it?" field.
    public func cancelCorrection() {
        composer.cancelCorrection(time: now)
        scheduleAutospace()
        onChange?()
    }

    /// Save in the "Not it?" field: the word meant replaces the swiped one.
    public func saveCorrection() {
        apply(composer.saveCorrection(time: now))
    }

    /// A swipe left on backspace.
    public func deleteWord() {
        apply(composer.deleteWord(time: now))
    }

    /// Held a guess on the bar and slid up: the word sticks from now on.
    public func boost(guess index: Int) {
        guard let word = barWord(at: index) else { return }
        var words = composer.learned
        words.boost(word, at: Date())
        learnedWords = words
        onWordsChange?(words)
    }

    /// Held a guess on the bar and slid down: the word is not offered again.
    public func forget(guess index: Int) {
        guard let word = barWord(at: index) else { return }
        var words = composer.learned
        words.forget(word, at: Date())
        learnedWords = words
        onWordsChange?(words)
    }

    private func barWord(at index: Int) -> String? {
        switch composer.state.bar {
        case .guesses(let words, _), .fix(let words, _):
            words.indices.contains(index) ? words[index].lowercased() : nil
        case .idle, .correcting:
            nil
        }
    }

    /// The field changed (the host's `textDidChange`): re-read the context.
    public func contextChanged() {
        composer.setContext(before: target?.textBeforeCursor)
        onChange?()
    }

    /// The field was replaced or the cursor moved: drop the open word.
    public func reset() {
        autospace?.cancel()
        for case .settled(let word) in composer.reset() { learn(from: word) }
        composer.setContext(before: target?.textBeforeCursor)
        onChange?()
    }

    // MARK: Effects

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func apply(_ effects: [Composer.Effect]) {
        for effect in effects {
            switch effect {
            case .insert(let text):
                target?.insert(text)
            case .deleteBackward(let count):
                for _ in 0..<count { target?.deleteBackward() }
            case .mark(let text):
                target?.mark(text)
            case .commit(let text):
                target?.mark(text)
                target?.unmark()
                onCommit?(text)
            case .clearMark:
                target?.mark("")
                target?.unmark()
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
        composer.setContext(before: target?.textBeforeCursor)
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
            guard !Task.isCancelled, let self else { return }
            self.apply(self.composer.tick(time: self.now))
        }
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
