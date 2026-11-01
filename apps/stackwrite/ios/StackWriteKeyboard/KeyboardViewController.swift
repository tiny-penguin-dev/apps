import StackWriteCore
import StackWriteUI
import UIKit

/// The keyboard extension: the shared `KeyboardView` typing into the text document
/// proxy through the engine. The bar's idle note still carries the Phase 1 checks
/// (StoreKit, memory, Full Access) until they are read on a phone.
final class KeyboardViewController: UIInputViewController {
    private var keyboard: KeyboardView?
    private var target: ProxyTarget?
    private var heightConstraint: NSLayoutConstraint?
    private let checks = ExtensionChecks()
    private var edits = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView?.allowsSelfSizing = true
        view.backgroundColor = Theme.ui(.kb)

        let dictionary = (try? Lexicon.bundled()) ?? Lexicon(entries: [])
        let model = KeyboardModel(composer: Composer(dictionary: dictionary, layout: Layout.qwerty(width: 390)))
        let target = ProxyTarget(controller: self)
        model.target = target
        self.target = target

        let keyboard = KeyboardView(model: model)
        keyboard.onSystemKey = { [weak self] key in
            if key == .globe { self?.advanceToNextInputMode() }
            // The numbers page comes in Phase 3.
        }
        view.addSubview(keyboard)
        self.keyboard = keyboard

        checks.run(hasFullAccess: hasFullAccess) { [weak keyboard] note in
            keyboard?.bar.note = note
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        followKeyboardAppearance()
        keyboard?.model.contextChanged()
    }

    /// Light or dark as the app asked for its keyboard, like Apple's keyboard does.
    private func followKeyboardAppearance() {
        switch textDocumentProxy.keyboardAppearance ?? .default {
        case .dark: view.overrideUserInterfaceStyle = .dark
        case .light: view.overrideUserInterfaceStyle = .light
        default: view.overrideUserInterfaceStyle = .unspecified
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let width = view.bounds.width
        guard width > 0, let keyboard else { return }
        let height = KeyboardView.height(forWidth: width)
        if let heightConstraint {
            if heightConstraint.constant != height { heightConstraint.constant = height }
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
        // Pinned to the bottom: if iOS grants less height than asked, the bar gives way
        // and the keys stay whole (the first build's bottom row was clipped).
        let granted = view.bounds.height
        keyboard.frame = CGRect(x: 0, y: granted > 0 ? granted - height : 0, width: width, height: height)
        checks.sized(granted: granted, wanted: height)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        followKeyboardAppearance()
        keyboard?.model.contextChanged()
        edits += 1
        if edits % 5 == 0 { checks.refresh() }
    }
}

/// The engine's text target on the extension's document proxy.
@MainActor
final class ProxyTarget: TextTarget {
    private unowned let controller: UIInputViewController

    init(controller: UIInputViewController) {
        self.controller = controller
    }

    private var proxy: UITextDocumentProxy { controller.textDocumentProxy }

    var textBeforeCursor: String? { proxy.documentContextBeforeInput }
    func insert(_ text: String) { proxy.insertText(text) }
    func deleteBackward() { proxy.deleteBackward() }
    func mark(_ text: String) {
        proxy.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
    }
    func unmark() { proxy.unmarkText() }
}
