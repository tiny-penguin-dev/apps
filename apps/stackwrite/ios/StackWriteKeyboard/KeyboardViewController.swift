import StackWriteCore
import StackWriteUI
import UIKit

/// The keyboard extension. Phase 1: a plain tap keyboard on the shared key surface,
/// with a note in the bar that reports the two checks (StoreKit, haptics) and memory.
/// The engine (pieces, swipes, the bar's guesses) arrives in Phase 2.
final class KeyboardViewController: UIInputViewController, KeySurfaceDelegate {
    private let bar = UILabel()
    private let surface = KeySurfaceView()
    private var heightConstraint: NSLayoutConstraint?
    private let checks = ExtensionChecks()
    private var shifted = false
    private var capsLock = false
    private var lastShiftTap: Date?

    static let barHeight: CGFloat = 44

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView?.allowsSelfSizing = true
        view.backgroundColor = Theme.ui(.kb)

        bar.font = Theme.uiFont(size: 13, weight: .bold)
        bar.textColor = Theme.ui(.muted)
        bar.textAlignment = .center
        bar.adjustsFontSizeToFitWidth = true
        bar.minimumScaleFactor = 0.7
        bar.text = "Both thumbs, one word"
        view.addSubview(bar)

        surface.delegate = self
        view.addSubview(surface)

        checks.run(hasFullAccess: hasFullAccess) { [weak self] note in
            self?.bar.text = note
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateShiftForContext()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let width = view.bounds.width
        guard width > 0 else { return }
        if surface.layout.width != width {
            surface.layout = Layout.qwerty(width: width)
        }
        let height = Self.barHeight + surface.layout.height
        if let heightConstraint {
            if heightConstraint.constant != height { heightConstraint.constant = height }
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
        bar.frame = CGRect(x: 8, y: 0, width: width - 16, height: Self.barHeight)
        surface.frame = CGRect(x: 0, y: Self.barHeight, width: width, height: surface.layout.height)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateShiftForContext()
    }

    // MARK: Keys

    func keySurface(_ surface: KeySurfaceView, didTap key: Key, side: Side) {
        checks.keyTapped()
        switch key {
        case .letter(let c):
            textDocumentProxy.insertText(shifted || capsLock ? String(c).uppercased() : String(c))
            if shifted, !capsLock { setShift(false) }
        case .space:
            textDocumentProxy.insertText(" ")
            updateShiftForContext()
        case .returnKey:
            textDocumentProxy.insertText("\n")
            updateShiftForContext()
        case .backspace:
            textDocumentProxy.deleteBackward()
            updateShiftForContext()
        case .shift:
            if let last = lastShiftTap, Date().timeIntervalSince(last) < 0.35 {
                capsLock.toggle()
                setShift(capsLock)
            } else {
                capsLock = false
                setShift(!shifted)
            }
            lastShiftTap = Date()
        case .numbers:
            break // The numbers page comes in Phase 3.
        case .globe:
            advanceToNextInputMode()
        }
    }

    private func setShift(_ on: Bool) {
        shifted = on
        surface.shifted = on || capsLock
    }

    /// Capital at the start of a sentence, like Apple's keyboard.
    private func updateShiftForContext() {
        guard !capsLock else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        let startsSentence = trimmed.isEmpty || trimmed.hasSuffix(".") || trimmed.hasSuffix("?") || trimmed.hasSuffix("!") || before.hasSuffix("\n")
        setShift(startsSentence && (before.isEmpty || before.last!.isWhitespace || before.last!.isNewline))
    }
}
