import StackWriteCore
import StackWriteUI
import SwiftUI
import UIKit

/// A text view with the StackWrite keyboard as its input view, for the app's own
/// screens (Try it, Practice): the same `KeyboardView` and `KeyboardModel` as the
/// extension, on the same `Composer`. One session per screen.
@MainActor
final class KeyboardSession: NSObject, UITextViewDelegate {
    let model: KeyboardModel
    let keyboard: StackWriteUI.KeyboardView
    let target = TextViewTarget()
    /// A word went into the field.
    var onCommit: ((String) -> Void)?
    /// The keyboard learned, boosted or forgot a word.
    var onWordsChange: ((LearnedWords) -> Void)?

    init(settingsStore: SettingsStore, learned: LearnedWords = LearnedWords()) {
        let dictionary = (try? Lexicon.bundled()) ?? Lexicon(entries: [])
        model = KeyboardModel(composer: Composer(dictionary: dictionary, layout: Layout.qwerty(width: 390)),
                              store: settingsStore, wordStore: MemoryWordStore(learned))
        model.target = target
        keyboard = StackWriteUI.KeyboardView(model: model)
        keyboard.autoresizingMask = [.flexibleWidth]
        super.init()
        keyboard.onHeightChange = { [weak self] height in
            guard let self else { return }
            self.keyboard.frame.size.height = height
            self.target.textView?.reloadInputViews()
        }
        model.onCommit = { [weak self] word in self?.onCommit?(word) }
        model.onWordsChange = { [weak self] words in self?.onWordsChange?(words) }
    }

    var text: String { target.textView?.text ?? "" }

    /// Empties the field and drops any open word.
    func clear() {
        target.textView?.text = ""
        model.reset()
    }

    func focus() {
        target.textView?.becomeFirstResponder()
    }

    /// Plays a Try it word's strokes on the keys without typing.
    func replay(_ word: TryWord, completion: (@MainActor () -> Void)? = nil) {
        keyboard.surface.replay(word.strokes.map { (side: $0.side, letters: $0.letters) }, completion: completion)
    }

    /// The settings changed in the app: the practice keyboard follows.
    func apply(_ settings: KeyboardSettings) {
        if model.keyboardSettings != settings { model.keyboardSettings = settings }
    }

    func textViewDidChange(_ textView: UITextView) {
        model.contextChanged()
    }
}

/// The field itself. Put it where the text goes; the keyboard comes up under it.
struct KeyboardField: UIViewRepresentable {
    let session: KeyboardSession
    var font: UIFont = .preferredFont(forTextStyle: .title2)

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = font
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        textView.backgroundColor = .clear
        textView.textColor = Theme.ui(.ink)
        textView.tintColor = Theme.ui(.accent)
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.autocapitalizationType = .none
        textView.inputView = session.keyboard
        textView.delegate = session
        session.target.textView = textView
        Task { @MainActor in textView.becomeFirstResponder() }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}
}
