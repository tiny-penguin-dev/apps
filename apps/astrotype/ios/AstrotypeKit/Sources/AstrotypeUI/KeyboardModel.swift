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
    /// Every touch on the keys as the engine sees it, for the app's practice
    /// recordings (never set in the extension).
    public var onTouch: ((TouchRecorder.Phase, Int, CGPoint, TimeInterval) -> Void)?
    /// What the person may use (`Entitlement`): the host sets it from the App Store
    /// and the trial. Everything is allowed until it does.
    public var entitlement: Entitlement = .full {
        didSet {
            guard entitlement != oldValue else { return }
            composer.settings.twoThumbs = entitlement.allows(.twoThumbs)
            onChange?()
        }
    }
    /// Whether the keys split on a wide screen: the setting, and Pro allows it.
    public var splitOnWide: Bool { keyboardSettings.splitOnWide && entitlement.allows(.splitLayout) }
    /// The person's keyboard settings; saved to `store` on every change.
    public var keyboardSettings: KeyboardSettings {
        didSet {
            guard keyboardSettings != oldValue else { return }
            composer.settings = keyboardSettings.composerSettings(from: composer.settings)
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

    /// `store`'s settings and `wordStore`'s words apply when they have any; otherwise
    /// the defaults and no words.
    public init(composer: Composer, store: SettingsStore? = nil, wordStore: WordStore? = nil) {
        var composer = composer
        let settings = store?.load() ?? KeyboardSettings()
        composer.settings = settings.composerSettings(from: composer.settings)
        if let words = wordStore?.load() { composer.learned = words }
        self.composer = composer
        self.store = store
        self.wordStore = wordStore
        self.keyboardSettings = settings
        self.settingsChanged = store?.lastChanged() ?? .distantPast
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
        case .idle:
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
        composer.reset()
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
                var words = composer.learned
                words.learn(word, at: Date())
                composer.learned = words
                wordStore?.save(words)
                onWordsChange?(words)
            case .notice(let notice):
                onNotice?(notice)
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
