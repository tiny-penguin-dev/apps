import SwiftUI
import UIKit

/// A real text view whose keyboard is the StackWrite keyboard, the same way a
/// keyboard extension would replace the system one.
struct StackWriteTextView: UIViewRepresentable {
    var controller: KeyboardController
    var box: TextBox

    static let keyboardHeight: CGFloat = 330

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .title3)
        textView.adjustsFontForContentSizeCategory = true
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.keyboardDismissMode = .interactive
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.inputAssistantItem.trailingBarButtonGroups = []

        let keyboard = UIHostingController(rootView: KeyboardView(controller: controller) { [weak textView] in
            textView?.resignFirstResponder()
        })
        keyboard.safeAreaRegions = []
        keyboard.view.backgroundColor = .clear
        keyboard.view.translatesAutoresizingMaskIntoConstraints = false

        let input = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: Self.keyboardHeight), inputViewStyle: .keyboard)
        input.autoresizingMask = [.flexibleWidth]
        input.addSubview(keyboard.view)
        NSLayoutConstraint.activate([
            keyboard.view.leadingAnchor.constraint(equalTo: input.leadingAnchor),
            keyboard.view.trailingAnchor.constraint(equalTo: input.trailingAnchor),
            keyboard.view.topAnchor.constraint(equalTo: input.topAnchor),
            keyboard.view.bottomAnchor.constraint(equalTo: input.safeAreaLayoutGuide.bottomAnchor),
        ])
        textView.inputView = input
        context.coordinator.keyboard = keyboard

        box.textView = textView
        controller.target = box
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var keyboard: UIViewController?
    }
}

/// Connects the keyboard controller to the text view.
@MainActor
final class TextBox: TextTarget {
    weak var textView: UITextView?

    var documentContextBeforeInput: String? {
        guard let textView, let cursor = textView.selectedTextRange,
              let range = textView.textRange(from: textView.beginningOfDocument, to: cursor.start)
        else { return nil }
        return textView.text(in: range)
    }

    func insertText(_ text: String) { textView?.insertText(text) }
    func deleteBackward() { textView?.deleteBackward() }

    func setMarkedText(_ text: String) {
        textView?.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
    }

    func unmarkText() { textView?.unmarkText() }

    func focus() { textView?.becomeFirstResponder() }
    func unfocus() { textView?.resignFirstResponder() }
    func clear() { textView?.text = "" }
    var text: String { textView?.text ?? "" }
}
