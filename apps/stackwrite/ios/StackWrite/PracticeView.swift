import StackWriteCore
import StackWriteUI
import SwiftUI
import UIKit

/// A field to type in with the StackWrite keyboard, inside the app, so the engine can
/// be tried without turning the keyboard on in Settings. Phase 4 grows this into
/// "Try it", the speed test and the drills.
struct PracticeView: View {
    var body: some View {
        PracticeField()
            .ignoresSafeArea(.keyboard)
            .navigationTitle("Try it")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// A text view whose keyboard is the shared `KeyboardView`, driven by its own
/// `KeyboardModel` on the same `Composer` as the extension.
struct PracticeField: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = UIFont.preferredFont(forTextStyle: .title2)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.backgroundColor = Theme.ui(.bg)
        textView.textColor = Theme.ui(.ink)
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.inputView = context.coordinator.keyboard
        textView.delegate = context.coordinator
        context.coordinator.target.textView = textView
        Task { @MainActor in textView.becomeFirstResponder() }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let model: KeyboardModel
        let keyboard: StackWriteUI.KeyboardView
        let target = TextViewTarget()

        override init() {
            let dictionary = (try? Lexicon.bundled()) ?? Lexicon(entries: [])
            model = KeyboardModel(composer: Composer(dictionary: dictionary, layout: Layout.qwerty(width: 390)))
            model.target = target
            keyboard = StackWriteUI.KeyboardView(model: model)
            keyboard.autoresizingMask = [.flexibleWidth]
            super.init()
            keyboard.onHeightChange = { [weak self] height in
                guard let self else { return }
                self.keyboard.frame.size.height = height
                self.target.textView?.reloadInputViews()
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            model.contextChanged()
        }
    }
}
