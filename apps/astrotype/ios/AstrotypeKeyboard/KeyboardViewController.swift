import AstrotypeCore
import AstrotypeUI
import UIKit

/// The keyboard extension: the shared `KeyboardView` typing into the text document
/// proxy through the engine. Words and settings live in the extension's own container
/// and, with Full Access, in the App Group and iCloud too (BUILD.md "Data"). The bar's
/// idle note still carries the Phase 1 checks (StoreKit, memory, Full Access) while
/// the phases are measured on a phone.
final class KeyboardViewController: UIInputViewController {
    private var keyboard: KeyboardView?
    private var target: ProxyTarget?
    private var sync: SyncController?
    private var heightConstraint: NSLayoutConstraint?
    private let checks = ExtensionChecks()
    private var edits = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        // No `allowsSelfSizing`: the height comes from the constraint below, and a
        // self-sizing input view is laid out inset on a wide screen (Gabriel, 1 Nov
        // 2026: the split keyboard stopped short of the edges). The system draws the
        // keyboard's backdrop (glass on iOS 26), so nothing here paints a background.
        view.backgroundColor = .clear

        let fullAccess = hasFullAccess
        let dictionary = (try? Lexicon.bundled()) ?? Lexicon(entries: [])
        let (settingsStore, wordStore) = Self.stores(fullAccess: fullAccess)
        let model = KeyboardModel(composer: Composer(dictionary: dictionary, layout: Layout.qwerty(width: 390)),
                                  store: settingsStore, wordStore: wordStore)
        let target = ProxyTarget(controller: self)
        model.target = target
        self.target = target

        let keyboard = KeyboardView(model: model)
        keyboard.backgroundColor = .clear
        keyboard.bar.backgroundColor = .clear
        keyboard.surface.backgroundColor = .clear
        keyboard.onSystemKey = { [weak self] key in
            if key == .globe { self?.advanceToNextInputMode() }
        }
        view.addSubview(keyboard)
        self.keyboard = keyboard

        if fullAccess { startSync(model: model) }

        checks.run(hasFullAccess: fullAccess) { [weak keyboard] note in
            keyboard?.bar.note = note
        }
    }

    /// The extension's own files, which it can always write, mirrored to the App Group's
    /// when Full Access allows. The Phase 3 settings in `UserDefaults` move over once.
    private static func stores(fullAccess: Bool) -> (SettingsStore, WordStore) {
        let own = FileSettingsStore(url: KeyboardFiles.own(KeyboardFiles.settings))
        let legacy = UserDefaultsSettingsStore()
        if own.load() == nil, let old = legacy.load() {
            own.save(old, changed: legacy.lastChanged() ?? .distantPast)
        }
        let ownWords = FileWordStore(url: KeyboardFiles.own(KeyboardFiles.words))
        guard fullAccess,
              let sharedSettings = KeyboardFiles.shared(KeyboardFiles.settings),
              let sharedWords = KeyboardFiles.shared(KeyboardFiles.words) else {
            return (own, ownWords)
        }
        return (MirroredSettingsStore(own: own, shared: FileSettingsStore(url: sharedSettings)),
                MirroredWordStore(own: ownWords, shared: FileWordStore(url: sharedWords)))
    }

    /// With Full Access: tell the app we have it, and keep words and settings in step
    /// with iCloud (now, and after each change).
    private func startSync(model: KeyboardModel) {
        guard let url = KeyboardFiles.shared(KeyboardFiles.status) else { return }
        let statusStore = FileExtensionStatusStore(url: url)
        var status = statusStore.load() ?? ExtensionStatus(fullAccess: true, seen: Date())
        status.fullAccess = true
        status.seen = Date()
        statusStore.save(status)

        let sync = SyncController(model: model, cloud: CloudKitSync())
        sync.onResult = { result in
            var status = statusStore.load() ?? ExtensionStatus(fullAccess: true, seen: Date())
            switch result {
            case .success(let date):
                status.lastSync = date
                status.lastSyncError = nil
            case .failure(let error):
                status.lastSyncError = error.localizedDescription
            }
            statusStore.save(status)
        }
        self.sync = sync
        sync.sync()
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
        // The keyboard fills whatever iOS grants: if that is less than asked (the Duo's
        // inner screen), the keys shrink to fit and the bar stays; if more, the keys
        // sit at the bottom.
        let granted = view.bounds.height
        keyboard.frame = CGRect(x: 0, y: 0, width: width, height: granted > 0 ? granted : height)
        checks.sized(granted: granted, wanted: height, width: width, screenWidth: view.window?.windowScene?.screen.bounds.width ?? 0)
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
    func moveCursor(by offset: Int) { proxy.adjustTextPosition(byCharacterOffset: offset) }
}
