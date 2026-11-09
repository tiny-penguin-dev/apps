import AstrotypeCore
import AstrotypeUI
import SwiftUI
import UIKit

/// A text view with the Astrotype keyboard as its input view, for the app's own
/// screens (Try it, Practice): the same `KeyboardView` and `KeyboardModel` as the
/// extension, on the same `Composer`, in a `KeyboardFrame` that draws the margin iOS
/// puts around the extension. One session per screen.
@MainActor
final class KeyboardSession: NSObject, UITextViewDelegate {
    let model: KeyboardModel
    let keyboard: AstrotypeUI.KeyboardView
    /// The text view's input view: the keys with the system's margin around them.
    let inputFrame: KeyboardFrame
    let target = TextViewTarget()
    /// A word went into the field.
    var onCommit: ((String) -> Void)?
    /// The keyboard learned, boosted or forgot a word.
    var onWordsChange: ((LearnedWords) -> Void)?
    /// A written word was swapped from the bar (the speed test counts fixes).
    var onFix: (() -> Void)?
    /// A touch began on the keys (the speed test starts its clock).
    var onFirstTouch: (() -> Void)?
    /// The keyboard came up (true) or went away (false): Home's dock follows it.
    var onFocusChange: ((Bool) -> Void)?
    /// The session's touches, while recording (`startRecording`).
    private var recorder: TouchRecorder?

    /// `personal` is what the keyboard learned in other apps: the session types with it
    /// and never adds to it.
    init(settingsStore: SettingsStore, learned: LearnedWords = LearnedWords(), personal: PersonalModel? = nil) {
        // English, with its word pairs when they shipped (features/smart-matching).
        let language = (try? Language.bundled()) ?? Language(code: "en", lexicon: Lexicon(entries: []))
        model = KeyboardModel(composer: Composer(language: language, layout: Layout.qwerty(width: 390)),
                              store: settingsStore, wordStore: MemoryWordStore(learned), personal: personal)
        model.target = target
        // Practice is in English for now (features/languages): the speed test, drills
        // and practice words are English sentences.
        model.followsLanguages = false
        // Practice measures typing and records each word's touches: no next words.
        model.offersNextWords = false
        keyboard = AstrotypeUI.KeyboardView(model: model)
        inputFrame = KeyboardFrame(keyboard: keyboard, bottom: Self.windowBottom)
        super.init()
        keyboard.onHeightChange = { [weak self] height in
            guard let self else { return }
            self.inputFrame.frame.size.height = self.inputFrame.height(forKeys: height)
            self.target.textView?.reloadInputViews()
        }
        model.onCommit = { [weak self] word in
            // The same clock as the touches (UITouch.timestamp is system uptime).
            self?.recorder?.committed(word, time: ProcessInfo.processInfo.systemUptime)
            self?.onCommit?(word)
        }
        model.onWordsChange = { [weak self] words in self?.onWordsChange?(words) }
        model.onFix = { [weak self] in self?.onFix?() }
        model.onTouch = { [weak self] phase, id, point, time in
            guard let self else { return }
            if phase == .began { onFirstTouch?() }
            recorder?.touch(phase, id: id, x: point.x, y: point.y, time: time)
        }
    }

    // MARK: Recording

    /// Starts collecting the touches (a speed test or a drill, with sharing on).
    func startRecording(kind: String) {
        let layout = model.layout
        recorder = TouchRecorder(kind: kind, layoutWidth: layout.width, layoutHeight: layout.height, split: layout.split)
    }

    /// Stops and hands back what was collected, nil when nothing was recorded.
    func stopRecording(expected: String, device: PracticeRecording.Device, now: Date,
                       wordsPerMinute: Int? = nil, fixes: Int? = nil) -> PracticeRecording? {
        defer { recorder = nil }
        guard let recorder, recorder.touchCount > 0 else { return nil }
        return recorder.recording(expected: expected, device: device, now: now, wordsPerMinute: wordsPerMinute, fixes: fixes)
    }

    // MARK: Drill hints

    /// Outlines the keys of a drill word in each thumb's colour; nil clears them.
    func hint(_ word: Drill.Word?) {
        guard let word else {
            keyboard.surface.hints = [:]
            return
        }
        var hints: [Key: Side] = [:]
        for (letter, side) in Drill.keys(for: word) { hints[.letter(letter)] = side }
        keyboard.surface.hints = hints
    }

    var text: String { target.textView?.text ?? "" }

    /// Gives the keyboard the height it needs at `width` before (or after) UIKit reads
    /// it. UIKit sizes an input view from its frame when it comes up, and the frame
    /// started at a phone's height: on a wide screen the taller keys were cut off when
    /// the resize after the first layout came too late (Gabriel, 1 Nov 2026).
    func fit(width: CGFloat, bottom: CGFloat = KeyboardSession.windowBottom) {
        guard width > 0 else { return }
        inputFrame.setBottom(bottom)
        let height = inputFrame.height(forWidth: width)
        guard inputFrame.frame.size.height != height || inputFrame.frame.size.width != width else { return }
        inputFrame.frame = CGRect(x: 0, y: 0, width: width, height: height)
        target.textView?.reloadInputViews()
    }

    /// The width of the window the keyboard will come up in, before any view has one.
    static var windowWidth: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return 390 }
        return scene.keyWindow?.bounds.width ?? scene.screen.bounds.width
    }

    /// The strip under the keys: the window's home indicator area, where iOS leaves
    /// room under the extension too (0 on a phone with a home button).
    static var windowBottom: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow?.safeAreaInsets.bottom ?? 0
    }

    /// Empties the field and drops any open word.
    func clear() {
        target.textView?.text = ""
        model.reset()
    }

    func focus() {
        target.textView?.becomeFirstResponder()
    }

    /// Puts the keyboard away.
    func unfocus() {
        target.textView?.resignFirstResponder()
    }

    var isFocused: Bool { target.textView?.isFirstResponder ?? false }

    /// Plays a Try it word's strokes on the keys without typing.
    func replay(_ word: TryWord, completion: (@MainActor () -> Void)? = nil) {
        keyboard.surface.replay(word.strokes.map { (side: $0.side, letters: $0.letters) }, completion: completion)
    }

    /// The settings changed in the app: the practice keyboard follows.
    func apply(_ settings: KeyboardSettings) {
        if model.keyboardSettings != settings { model.keyboardSettings = settings }
    }

    /// Pro or the trial changed: the practice keyboard follows (free mode and all).
    /// Compared by status, since the app's entitlement carries a fresh clock each time.
    func apply(entitlement: Entitlement) {
        if model.entitlement.status != entitlement.status { model.entitlement = entitlement }
    }

    func textViewDidBeginEditing(_ textView: UITextView) { onFocusChange?(true) }

    func textViewDidEndEditing(_ textView: UITextView) { onFocusChange?(false) }

    func textViewDidChange(_ textView: UITextView) {
        guard !target.isSwappingWord else { return }
        model.contextChanged()
    }
}

/// The field itself. Put it where the text goes; the keyboard comes up under it.
struct KeyboardField: UIViewRepresentable {
    let session: KeyboardSession
    var font: UIFont = .preferredFont(forTextStyle: .title2)
    /// Brings the keyboard up as soon as the field is on screen (every screen but Home,
    /// whose dock remembers whether it was left open).
    var focusesOnAppear = true

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
        session.fit(width: KeyboardSession.windowWidth)
        textView.inputView = session.inputFrame
        textView.delegate = session
        session.target.textView = textView
        if focusesOnAppear { Task { @MainActor in textView.becomeFirstResponder() } }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if let window = uiView.window { session.fit(width: window.bounds.width, bottom: window.safeAreaInsets.bottom) }
    }
}
