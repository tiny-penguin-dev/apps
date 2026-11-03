import AstrotypeCore
import AstrotypeUI
import UIKit

/// The keyboard extension: the shared `KeyboardView` typing into the text document
/// proxy through the engine. Words and settings live in the extension's own container
/// and, with Full Access, in the App Group and iCloud too (BUILD.md "Data"). Pro is
/// read from StoreKit right here (`EntitlementController`), with the trial counted
/// from the app's first launch when the App Group is readable, else from this
/// extension's own first run. `Flags.extensionReadout` puts the Phase 1 readings in
/// the bar for measuring on a phone. With Full Access and the app's "Share anonymous
/// usage data" on, crashes go to Sentry (`KeyboardTelemetry`) and memory readings go
/// to the app (`KeyboardHealthRecorder`); nothing typed goes anywhere.
final class KeyboardViewController: UIInputViewController {
    private var keyboard: KeyboardView?
    private var target: ProxyTarget?
    private var sync: SyncController?
    private var entitlement: EntitlementController?
    private var heightConstraint: NSLayoutConstraint?
    /// Fresh height constraints sent since the keyboard last appeared (`askAgainIfShort`).
    private var heightRetries = 0
    private var isVisible = false
    private let checks = ExtensionChecks()
    private var health: KeyboardHealthRecorder?
    private var edits = 0
    /// The last appearance the field asked for, and whether it only echoed the phone's
    /// light or dark mode (`followKeyboardAppearance`).
    private var askedAppearance: (asked: UIKeyboardAppearance, echo: Bool)?

    override func viewDidLoad() {
        super.viewDidLoad()
        // No `allowsSelfSizing`: the height comes from the constraint below, and a
        // self-sizing input view is laid out inset on a wide screen (Gabriel, 1 Nov
        // 2026: the split keyboard stopped short of the edges). The system draws the
        // keyboard's backdrop (glass on iOS 26), so nothing here paints a background.
        view.backgroundColor = .clear

        let fullAccess = hasFullAccess
        // First, so a crash while loading is caught.
        KeyboardTelemetry.start(fullAccess: fullAccess)
        health = KeyboardHealthRecorder(fullAccess: fullAccess)
        let (settingsStore, wordStore, personalStore) = Self.stores(fullAccess: fullAccess)
        // The languages turned on, or the phone's (features/languages), with their word
        // pairs. Pro is not known yet, so both load; the model drops to one when the
        // entitlement says the keyboard is free.
        let codes = (settingsStore.load() ?? KeyboardSettings())
            .activeLanguages(preferred: Locale.preferredLanguages, allowsTwo: true)
        let language = (try? Language.bundled(codes)) ?? (try? Language.bundled())
            ?? Language(code: "en", lexicon: Lexicon(entries: []))
        let model = KeyboardModel(composer: Composer(language: language, layout: Layout.qwerty(width: 390)),
                                  store: settingsStore, wordStore: wordStore, personalStore: personalStore,
                                  installID: InstallID.load(from: KeyboardFiles.own(KeyboardFiles.install)))
        let target = ProxyTarget(controller: self)
        target.underlines = { [weak model] in model?.keyboardSettings.underlinesWord ?? false }
        model.target = target
        self.target = target
        if let health { model.onSettled = { [weak health] word in health?.settled(word) } }

        let keyboard = KeyboardView(model: model)
        keyboard.backgroundColor = .clear
        keyboard.bar.backgroundColor = .clear
        // Not `.clear`: the extension drops touches on clear pixels, and taps in the
        // gaps between keys did nothing (Gabriel, 2 Nov 2026). `Layout.key(at:)` gives
        // a gap to the nearest key once the touch arrives.
        keyboard.surface.backgroundColor = Theme.seeThrough
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

        // Light or dark mode changing while the keyboard is up (Gabriel, 3 Nov 2026: the
        // keys stayed white until the app was reopened).
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.followKeyboardAppearance()
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
        heightRetries = 0
        applyHeight(fresh: true)
        health?.appeared()
        askedAppearance = nil
        followKeyboardAppearance()
        keyboard?.model.learningAllowed = fieldAllowsLearning
        keyboard?.model.contextChanged()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        // iOS only takes a new height once the keyboard is on screen; before that it can
        // keep its own, and the keyboard opened short until something laid it out again
        // (Gabriel, 3 Nov 2026: it grew when the 123 menu opened).
        applyHeight(fresh: true)
        view.setNeedsLayout()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        keyboard?.model.savePersonalNow()
        health?.disappeared()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        health?.sample()
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

    /// Light or dark as the app asked for its keyboard, like Apple's keyboard does, and
    /// otherwise the phone's mode, live.
    ///
    /// The override goes on the keyboard view, not on this controller's view, so this
    /// controller's own traits stay the phone's and tell it when the mode changes. A field
    /// often answers with the mode the phone was in when it opened (light in light mode)
    /// and keeps answering that after the mode changes; pinned to that answer, the keys
    /// stayed white in dark mode until the app was reopened. So an answer that only
    /// echoes the phone's mode is not pinned, and stays an echo until the field answers
    /// something else.
    private func followKeyboardAppearance() {
        guard let keyboard else { return }
        let asked = textDocumentProxy.keyboardAppearance ?? .default
        let phone = traitCollection.userInterfaceStyle
        let echo: Bool
        if let last = askedAppearance, last.asked == asked {
            echo = last.echo
        } else {
            switch asked {
            case .dark: echo = phone == .dark
            case .light: echo = phone != .dark
            default: echo = true
            }
        }
        askedAppearance = (asked, echo)
        let style: UIUserInterfaceStyle = echo ? .unspecified : (asked == .dark ? .dark : .light)
        if keyboard.overrideUserInterfaceStyle != style { keyboard.overrideUserInterfaceStyle = style }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let width = view.bounds.width
        guard width > 0, let keyboard else { return }
        let height = applyHeight(fresh: false) ?? keyboard.height(forWidth: width)
        // The keyboard view takes whatever iOS grants, edge to edge (iOS adds the margins
        // around it): the keys sit at the bottom where Apple's are, and shrink if iOS
        // grants less than asked.
        let granted = view.bounds.height
        keyboard.frame = CGRect(x: 0, y: 0, width: width, height: granted > 0 ? granted : height)
        checks.sized(granted: granted, wanted: height, width: width, screenWidth: view.window?.windowScene?.screen.bounds.width ?? 0)
        askAgainIfShort(granted: granted, wanted: height)
    }

    /// Asks iOS for the keyboard's height with a constraint on the view. `fresh` swaps in
    /// a new constraint even when the height is the same, which iOS reads again where it
    /// can ignore a constant that did not change. Returns the height asked for.
    @discardableResult
    private func applyHeight(fresh: Bool) -> CGFloat? {
        let width = view.bounds.width
        guard width > 0, let keyboard else { return nil }
        let height = keyboard.height(forWidth: width)
        if let heightConstraint, !fresh {
            if heightConstraint.constant != height { heightConstraint.constant = height }
        } else {
            heightConstraint?.isActive = false
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
        return height
    }

    /// When the keyboard is on screen but shorter or taller than it asked for, asks
    /// again on the next turn, a few times at most per appearance (iOS may simply not
    /// give more, and then the keys shrink to fit).
    private func askAgainIfShort(granted: CGFloat, wanted: CGFloat) {
        guard isVisible, granted > 0, abs(granted - wanted) > 0.5, heightRetries < 3 else { return }
        heightRetries += 1
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyHeight(fresh: true)
            self.view.setNeedsLayout()
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        followKeyboardAppearance()
        keyboard?.model.learningAllowed = fieldAllowsLearning
        keyboard?.model.contextChanged()
        edits += 1
        if edits % 5 == 0 {
            checks.refresh()
            health?.sample()
        }
    }
}

/// The engine's text target on the extension's document proxy. By default the open
/// word is written as ordinary text and replaced as the guesses change: marked text
/// through the proxy, finished with unmark-then-insert, left the cursor before the word
/// and the space went there (Gabriel, 2 Nov 2026). With "Underline the word you're
/// typing" on, the open word is marked text again, and it is finished by inserting it
/// over the marked text in one step, which leaves the cursor after it.
///
/// Text selected in the field is deleted before anything is typed, so a tap or a swipe
/// replaces it: inserting through the proxy left the selection in place (Gabriel, 3 Nov
/// 2026).
@MainActor
final class ProxyTarget: TextTarget {
    private unowned let controller: UIInputViewController
    /// Whether the open word is shown as marked (underlined) text; read per word.
    var underlines: () -> Bool = { false }
    /// The open word as it stands in the field, right before the cursor.
    private var open = ""
    /// Whether `open` went in as marked text.
    private var openIsMarked = false
    /// Set once the selection is deleted, until the run loop turns: the proxy can still
    /// report the old selection right after, and a second delete would take a letter.
    private var clearedSelection = false

    init(controller: UIInputViewController) {
        self.controller = controller
    }

    private var proxy: UITextDocumentProxy { controller.textDocumentProxy }

    /// The text before the cursor without the open word, as if it were still marked.
    var textBeforeCursor: String? {
        guard let before = proxy.documentContextBeforeInput else { return nil }
        return !open.isEmpty && before.hasSuffix(open) ? String(before.dropLast(open.count)) : before
    }

    func insert(_ text: String) {
        if !text.isEmpty { deleteSelection() }
        proxy.insertText(text)
    }
    func deleteBackward() { proxy.deleteBackward() }

    func mark(_ text: String) {
        guard text != open else { return }
        if open.isEmpty {
            openIsMarked = underlines()
            if !text.isEmpty { deleteSelection() }
        }
        if openIsMarked {
            proxy.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
            open = text
            return
        }
        // Take the old reading out, unless the cursor moved away from it (then it stays
        // as typed). A field that hides its text (nil) is trusted to be where we left it.
        if !open.isEmpty, proxy.documentContextBeforeInput.map({ $0.hasSuffix(open) }) ?? true {
            for _ in 0..<open.count { proxy.deleteBackward() }
        }
        if !text.isEmpty { proxy.insertText(text) }
        open = text
    }

    func unmark() {
        if openIsMarked {
            // Inserting over marked text replaces it and puts the cursor after it.
            if open.isEmpty { proxy.unmarkText() } else { proxy.insertText(open) }
        }
        open = ""
        openIsMarked = false
    }

    func moveCursor(by offset: Int) { proxy.adjustTextPosition(byCharacterOffset: offset) }

    /// Deletes the selected text, if any, so what is typed next takes its place.
    private func deleteSelection() {
        guard !clearedSelection, let selected = proxy.selectedText, !selected.isEmpty else { return }
        proxy.deleteBackward()
        clearedSelection = true
        Task { @MainActor [weak self] in self?.clearedSelection = false }
    }
}
