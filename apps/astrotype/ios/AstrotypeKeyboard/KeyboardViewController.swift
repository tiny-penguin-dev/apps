import AstrotypeCore
import AstrotypeUI
import UIKit

/// The keyboard extension: the shared `KeyboardView` typing into the text document
/// proxy through the engine. Words and settings live in the extension's own container
/// and, with Full Access, in the App Group and iCloud too (BUILD.md "Data"). Pro is
/// read from StoreKit right here (`EntitlementController`), with the trial counted
/// from the app's first launch when the App Group is readable, else from this
/// extension's own first run. `Flags.extensionReadout` puts the Phase 1 readings in
/// the bar for measuring on a phone.
final class KeyboardViewController: UIInputViewController {
    private var keyboard: KeyboardView?
    private var target: ProxyTarget?
    private var sync: SyncController?
    private var entitlement: EntitlementController?
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
        // English, with its word pairs when they shipped (features/smart-matching).
        let language = (try? Language.bundled()) ?? Language(code: "en", lexicon: Lexicon(entries: []))
        let (settingsStore, wordStore, personalStore) = Self.stores(fullAccess: fullAccess)
        let model = KeyboardModel(composer: Composer(language: language, layout: Layout.qwerty(width: 390)),
                                  store: settingsStore, wordStore: wordStore, personalStore: personalStore,
                                  installID: InstallID.load(from: KeyboardFiles.own(KeyboardFiles.install)))
        let target = ProxyTarget(controller: self)
        model.target = target
        self.target = target

        let keyboard = KeyboardView(model: model)
        keyboard.backgroundColor = .clear
        keyboard.bar.backgroundColor = .clear
        keyboard.surface.backgroundColor = .clear
        // Haptics do nothing in an extension without Full Access (Phase 1), so the
        // generators are not even prepared then.
        keyboard.hapticsAvailable = fullAccess
        keyboard.onSystemKey = { [weak self] key in
            if key == .globe { self?.advanceToNextInputMode() }
        }
        // The guesses bar going on or off, or the split, changes the height to ask for.
        keyboard.onHeightChange = { [weak self] _ in self?.view.setNeedsLayout() }
        view.addSubview(keyboard)
        self.keyboard = keyboard

        if fullAccess {
            startSync(model: model)
            // Fixes go where the app can send them, only if the person said so (the
            // model checks the setting); without Full Access there is nowhere to put them.
            if let folder = KeyboardFiles.shared(KeyboardFiles.sharing) {
                let store = SharedWordStore(folder: folder)
                model.onCorrection = { word in store.save([word]) }
            }
        }
        startEntitlement(model: model, fullAccess: fullAccess)

        if Flags.extensionReadout {
            keyboard.usesDefaultNote = false
            checks.run(hasFullAccess: fullAccess) { [weak keyboard] note in
                keyboard?.bar.note = note
            }
        }
    }

    /// Pro from StoreKit, the trial from the earliest start we can see: the app's (in
    /// the App Group, with Full Access) or this extension's own first run.
    private func startEntitlement(model: KeyboardModel, fullAccess: Bool) {
        let now = Date()
        let own = TrialStore(url: KeyboardFiles.own(KeyboardFiles.trial))
        let shared = fullAccess ? KeyboardFiles.shared(KeyboardFiles.trial).flatMap { TrialStore(url: $0).load() } : nil
        let trial = TrialStore.earliest(shared, own.loadOrStart(now: now)) ?? Trial(start: now)
        if let shared, shared.start < (own.load()?.start ?? .distantFuture) { own.save(shared) }
        let controller = EntitlementController(model: model, store: StoreKitProStore(),
                                               cache: ProCache(url: KeyboardFiles.own(KeyboardFiles.pro)), trial: trial)
        controller.start()
        entitlement = controller
    }

    /// The extension's own files, which it can always write, mirrored to the App Group's
    /// when Full Access allows. The Phase 3 settings in `UserDefaults` move over once.
    private static func stores(fullAccess: Bool) -> (SettingsStore, WordStore, PersonalStore) {
        let own = FileSettingsStore(url: KeyboardFiles.own(KeyboardFiles.settings))
        let legacy = UserDefaultsSettingsStore()
        if own.load() == nil, let old = legacy.load() {
            own.save(old, changed: legacy.lastChanged() ?? .distantPast)
        }
        let ownWords = FileWordStore(url: KeyboardFiles.own(KeyboardFiles.words))
        let ownPersonal = FilePersonalStore(url: KeyboardFiles.own(KeyboardFiles.personal))
        guard fullAccess,
              let sharedSettings = KeyboardFiles.shared(KeyboardFiles.settings),
              let sharedWords = KeyboardFiles.shared(KeyboardFiles.words),
              let sharedPersonal = KeyboardFiles.shared(KeyboardFiles.personal) else {
            return (own, ownWords, ownPersonal)
        }
        return (MirroredSettingsStore(own: own, shared: FileSettingsStore(url: sharedSettings)),
                MirroredWordStore(own: ownWords, shared: FileWordStore(url: sharedWords)),
                MirroredPersonalStore(own: ownPersonal, shared: FilePersonalStore(url: sharedPersonal)))
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
        keyboard?.model.learningAllowed = fieldAllowsLearning
        keyboard?.model.contextChanged()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keyboard?.model.savePersonalNow()
    }

    /// Whether this field may teach the keyboard (features/smart-matching): never a
    /// password, an address, a code or a number, nor a field that turned
    /// autocorrection off.
    private var fieldAllowsLearning: Bool {
        let proxy = textDocumentProxy
        if proxy.isSecureTextEntry == true || proxy.autocorrectionType == .no { return false }
        switch proxy.keyboardType ?? .default {
        case .URL, .emailAddress, .numberPad, .phonePad, .namePhonePad, .decimalPad, .asciiCapableNumberPad, .numbersAndPunctuation:
            return false
        default:
            break
        }
        let quiet: Set<UITextContentType> = [.username, .password, .newPassword, .oneTimeCode, .emailAddress, .URL,
                                             .creditCardNumber, .telephoneNumber, .postalCode]
        if let type = proxy.textContentType.flatMap({ $0 }), quiet.contains(type) { return false }
        return true
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
        let height = keyboard.height(forWidth: width)
        if let heightConstraint {
            if heightConstraint.constant != height { heightConstraint.constant = height }
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
        // The keyboard fills whatever iOS grants, edge to edge (iOS adds the margins
        // around it): the keys shrink or grow to the height, and the guesses stay.
        let granted = view.bounds.height
        keyboard.frame = CGRect(x: 0, y: 0, width: width, height: granted > 0 ? granted : height)
        checks.sized(granted: granted, wanted: height, width: width, screenWidth: view.window?.windowScene?.screen.bounds.width ?? 0)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        followKeyboardAppearance()
        keyboard?.model.learningAllowed = fieldAllowsLearning
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
