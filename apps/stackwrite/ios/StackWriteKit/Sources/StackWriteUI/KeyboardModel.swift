#if canImport(UIKit)
import Foundation
import StackWriteCore
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
    /// Called after every change to the bar, the open word or shift.
    public var onChange: (() -> Void)?
    public var onHaptic: ((Composer.Haptic) -> Void)?

    private var autospace: Task<Void, Never>?

    public init(composer: Composer) {
        self.composer = composer
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
        apply(composer.touchDown(id: id, at: point, time: time))
    }

    public func touchMoved(id: Int, to point: CGPoint, time: TimeInterval) {
        apply(composer.touchMoved(id: id, to: point, time: time))
    }

    public func touchEnded(id: Int, at point: CGPoint, time: TimeInterval) {
        apply(composer.touchUp(id: id, at: point, time: time))
    }

    public func touchCancelled(id: Int, time: TimeInterval) {
        apply(composer.touchCancelled(id: id, time: time))
    }

    public func press(_ key: Key) {
        apply(composer.press(key, time: now))
    }

    public func press(character: Character) {
        apply(composer.press(character: character, time: now))
    }

    public func choose(guess index: Int) {
        apply(composer.choose(guess: index, time: now))
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
            case .clearMark:
                target?.mark("")
                target?.unmark()
            case .haptic(let haptic):
                onHaptic?(haptic)
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
}
#endif
