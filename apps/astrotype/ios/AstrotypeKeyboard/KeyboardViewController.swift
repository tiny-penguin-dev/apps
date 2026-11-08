import AstrotypeCore
import AstrotypeUI
import SwiftUI
import Synchronization
import UIKit

/// The keyboard extension: the shared `KeyboardView` typing into the text document
/// proxy through the engine. Words and settings live in the extension's own container
/// and, with Full Access, in the App Group and iCloud too (BUILD.md "Data"). Pro is
/// read from StoreKit right here (`EntitlementController`), with the trial counted
/// from the app's first launch when the App Group is readable, else from this
/// extension's own first run. `Flags.extensionReadout` puts the Phase 1 readings in
/// the bar for measuring on a phone. With Full Access and the app's "Share anonymous
/// usage data" on, crashes go to Sentry (`KeyboardTelemetry`) and memory readings go
/// to the app (`KeyboardHealthRecorder`); nothing typed goes anywhere. With Full Access
/// its memory readings also go to the App Group for the app's Debug page
/// (`KeyboardDebugRecorder`), and Settings → Debug can turn on a tiny readout on the
/// keys (`KeyboardView.stats`). With Full Access and Settings → Debug → "Keep recording"
/// on, it keeps the last half hour of typing in the App Group (`TypingRecorder`) for the
/// app to send when the person asks; a red dot on the keys shows while it does.
/// Every controller in the process types through one model (`KeyboardShared`).
final class KeyboardViewController: UIInputViewController {
    private var keyboard: KeyboardView?
    private var target: ProxyTarget?
    private var heightConstraint: NSLayoutConstraint?
    /// Fresh height constraints sent since the keyboard last appeared (`askAgainIfShort`).
    private var heightRetries = 0
    private var isVisible = false
    /// What iOS gave when the keyboard last opened, for the settings panel's note.
    private var openedAt: (got: CGFloat, asked: CGFloat)?
    /// Bumped on each appearance, so re-asks left over from the last one stop.
    private var appearance = 0
    private let checks = ExtensionChecks()
    private(set) var health: KeyboardHealthRecorder?
    /// The memory readings for the app's Debug page (with Full Access, never sent).
    private var debug: KeyboardDebugRecorder?
    /// Where the typing recording goes, with Full Access (`KeyboardFiles.typing`).
    private var typingFolder: URL?
    private var edits = 0
    /// The last appearance the field asked for, and whether it only echoed the phone's
    /// light or dark mode (`followKeyboardAppearance`).
    private var askedAppearance: (asked: UIKeyboardAppearance, echo: Bool)?

    /// Counted live once loaded (`LiveCount`), uncounted when freed.
    private var counted = false
    private let sampler = MemorySampler()
    /// Readings taken, so the overlay walks the memory regions every fifth one.
    private var ticks = 0
    private var memoryLog = MemoryLogPacer()
    /// The steps of this opening, from load to the keys on screen, for the typing log.
    private var opening: OpenTiming?
    /// Whether this keyboard has had its sync (one per keyboard iOS shows).
    private var synced = false
    private var uptime: Double { ProcessInfo.processInfo.systemUptime }
    /// The dictation test panel (throwaway spike, DictationTest/).
    private var dictationProbe: UIHostingController<DictationProbePanel>?

    deinit {
        if counted { LiveCount.controllers.subtract(1, ordering: .relaxed) }
        // iOS can free a controller without ever calling `viewDidDisappear`, and keeps
        // its view in a window: the keys stayed behind, one per keyboard (Gabriel, 7 Nov
        // 2026: "5 key views" with 1 keyboard). Taken out here, they go with it.
        MainActor.assumeIsolated {
            keyboard?.rest()
            keyboard?.removeFromSuperview()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        LiveCount.controllers.add(1, ordering: .relaxed)
        counted = true
        // No `allowsSelfSizing`: the height comes from the constraint below, and a
        // self-sizing input view is laid out inset on a wide screen (Gabriel, 1 Nov
        // 2026: the split keyboard stopped short of the edges). The system draws the
        // keyboard's backdrop (glass on iOS 26), so nothing here paints a background.
        view.backgroundColor = .clear
        opening = OpenTiming(now: uptime)

        // Everything else waits until the keyboard is about to show (`makeKeyboard`):
        // iOS makes keyboards it never shows.

        // Light or dark mode changing while the keyboard is up (Gabriel, 3 Nov 2026: the
        // keys stayed white until the app was reopened).
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.followKeyboardAppearance()
        }
    }


    /// The keys, made the first time this keyboard is about to show. Not in
    /// `viewDidLoad`: iOS makes a keyboard for a field it may never show (Gabriel,
    /// 7 Nov 2026: closed for 15 minutes, "1 keyboard" became "4 keyboards · 5 key
    /// views" and 38 MB became 78), and every one built its keys with their drawing
    /// and Metal surfaces, took the shared model's output, and started a sync.
    private func makeKeyboard() -> KeyboardView {
        if let keyboard { return keyboard }
        let fullAccess = hasFullAccess
        // First, so a crash while loading is caught.
        KeyboardTelemetry.start(fullAccess: fullAccess)
        opening?.step("telemetry", now: uptime)
        health = KeyboardHealthRecorder(fullAccess: fullAccess)
        debug = KeyboardDebugRecorder(fullAccess: fullAccess)
        typingFolder = fullAccess ? KeyboardFiles.shared(KeyboardFiles.typing) : nil
        opening?.step("recorders", now: uptime)
        // One model for the whole process, whichever keyboard iOS shows (`KeyboardShared`).
        let shared = KeyboardShared.get(fullAccess: fullAccess)
        opening?.step("model", now: uptime)
        let model = shared.model
        let target = ProxyTarget(controller: self)
        self.target = target

        let keyboard = KeyboardView(model: model)
        keyboard.usesSystemBackdrop = true
        keyboard.bar.backgroundColor = .clear
        // Not `.clear`: the extension drops touches on clear pixels, and taps in the
        // gaps between keys did nothing (Gabriel, 2 Nov 2026). `Layout.key(at:)` gives
        // a gap to the nearest key once the touch arrives.
        keyboard.surface.backgroundColor = Theme.seeThrough
        // Haptics do nothing in an extension without Full Access (Phase 1), so the
        // generators are not even prepared then.
        keyboard.hapticsAvailable = fullAccess
        // iOS's own globe handling: a tap goes to the next keyboard, a hold shows the
        // list. `advanceToNextInputMode()` crashed the app being typed in on iOS 27.2,
        // every time (`KeyboardView.onGlobeTouch`).
        keyboard.onGlobeTouch = { [weak self] view, event in
            self?.handleInputModeList(from: view, with: event)
        }
        // The guesses bar going on or off, or the split, changes the height to ask for.
        keyboard.onHeightChange = { [weak self] _ in self?.view.setNeedsLayout() }
        keyboard.onPart = { [weak self] part in self?.health?.used(part) }
        // One memory reading a second while the keyboard shows, for the overlay, the
        // Debug page, the health numbers (a peak is caught even when nothing is typed,
        // on the emoji page or the settings panel) and the typing log.
        sampler.root = { [weak keyboard] in keyboard }
        sampler.onSample = { [weak self] sample in self?.took(sample) }
        self.keyboard = keyboard
        opening?.step("keys", now: uptime)

        if Flags.extensionReadout {
            keyboard.usesDefaultNote = false
            checks.run(hasFullAccess: fullAccess) { [weak keyboard] note in
                keyboard?.bar.note = note
            }
        }
        return keyboard
    }

    /// Puts the keys in the controller's view.
    ///
    /// Pinned with constraints, not placed by frame: iOS works the keyboard's height
    /// out from the constraints inside its view, and ignored the height constraint
    /// below while the keys were frame-based. It took it only when the settings panel
    /// (built with constraints) was added (Gabriel, 3 Nov 2026: "Opened at 224 of the
    /// 264 pt asked, still 224 after asking again", then it grew when 123 was held).
    private func mount(_ keyboard: KeyboardView) {
        guard keyboard.superview !== view else { return }
        view.addSubview(keyboard)
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // From load to here is iOS's time, and from the last appearance on a reopen.
        if opening == nil { opening = OpenTiming(now: uptime) } else { opening?.step("wait", now: uptime) }
        let keyboard = makeKeyboard()
        mount(keyboard)
        keyboard.wake()
        heightRetries = 0
        // The process's one model types into whichever keyboard is showing.
        KeyboardShared.current?.showing = self
        keyboard.model.target = target
        keyboard.attachToModel()
        // Our globe key only where iOS draws none (Home button phones); elsewhere the
        // emoji key takes its place, as on Apple's keyboard (features/emoji).
        keyboard.showsGlobe = needsInputModeSwitchKey
        applyHeight(fresh: true)
        health?.appeared()
        debug?.appeared()
        sampler.start()
        askedAppearance = nil
        followKeyboardAppearance()
        let model = keyboard.model
        if let store = model.store, let saved = store.load(), let changed = store.lastChanged() {
            // Settings → Debug may have changed them since the keyboard last showed.
            model.adopt(saved, changed: changed)
        }
        model.field = field
        // Each appearance starts with a snapshot (a new recorder writes its own first).
        let recording = model.recorder != nil
        updateRecorder()
        if recording { model.snapshot() }
        logMemory("show")
        model.contextChanged()
        updateDictationProbe(&dictationProbe)
    }

    /// Starts or stops the typing recorder with the setting (Full Access only).
    func updateRecorder() {
        guard let model = keyboard?.model else { return }
        let wanted = model.keyboardSettings.recordsTyping ? typingFolder : nil
        if let wanted, model.recorder?.files.folder != wanted {
            model.recorder = TypingRecorder(files: TypingLogFiles(folder: wanted))
        } else if wanted == nil, let recorder = model.recorder {
            model.recorder = nil
            // Turned off: what was kept goes too.
            if !model.keyboardSettings.recordsTyping { recorder.files.removeAll() }
        }
        keyboard?.setNeedsLayout()
    }

    /// "1.0 (202611060412)", the extension's own version and build.
    static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }()

    /// The hardware model, "iPhone17,1".
    static let hardware: String = {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }()

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        appearance += 1
        logOpening()
        // The Core ML models and the first sync, once the keys have been on screen a
        // moment, so they don't compete with the opening (`KeyboardShared.settleIn`); a
        // sync on each new keyboard after that, as when each one had its own model.
        if !synced {
            synced = true
            if KeyboardShared.current?.hasSettledIn == true {
                KeyboardShared.current?.sync?.sync()
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    KeyboardShared.current?.settleIn()
                }
            }
        }
        openedAt = nil
        keyboard?.heightStory = nil
        // iOS only takes a new height once the keyboard is on screen, and seems to drop
        // one sent while it is still sliding the keyboard in; the keyboard opened short
        // until something laid it out again (Gabriel, 3 Nov 2026: it grew when the 123
        // menu opened, and asking again right away was not enough). So ask now, and
        // again after the slide has ended, as long as the height is still off.
        applyHeight(fresh: true)
        nudgeLayout()
        let this = appearance
        for delay in [0.15, 0.4, 0.8, 1.5] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.askAgainIfOff(appearance: this, last: delay == 1.5)
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        logMemory("hide")
        sampler.stop()
        // The model is the process's (`KeyboardShared`): only the keyboard it types
        // into settles its word, not an older one closing after a new one opened.
        if KeyboardShared.current?.showing === self { keyboard?.model.keyboardWillHide() }
        health?.disappeared()
        debug?.disappeared()
    }

    /// Takes the keys out of the controller's view once it has gone. iOS keeps the old
    /// controllers' views in its own windows after it frees the controllers, and every
    /// one held its keys with their drawing and Metal surfaces, about 9 MB each
    /// (Gabriel, 7 Nov 2026: "1 keyboard · 13 key views" at 140 MB, IOSurface 91 MB).
    /// Taken out, the keys go with their controller; they come back if this one shows
    /// again.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !isVisible else { return }
        keyboard?.removeFromSuperview()
        // And its drawing surfaces go: one key view stayed alive after its keyboard
        // went (Gabriel, 7 Nov 2026: "1 keyboard · 2 key views"), holding ~7 MB.
        keyboard?.rest()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        health?.sample()
        debug?.memoryWarning()
        logMemory("warning")
        // The word pairs carry on alone; the models come back with the next language load.
        keyboard?.model.dropNextWordModels()
        NextWordModels.drop()
    }

    /// The field as the app describes it (features/field-types): its keyboard type,
    /// content, return key, capitals and corrections, read into `Field`, which decides
    /// the bottom row, the return key, exact taps, autospace and whether to learn.
    private var field: Field {
        let proxy = textDocumentProxy
        let keyboard: Field.KeyboardType = switch proxy.keyboardType ?? .default {
        case .emailAddress: .email
        case .URL: .url
        case .webSearch: .webSearch
        case .twitter: .twitter
        case .numberPad, .decimalPad, .asciiCapableNumberPad, .numbersAndPunctuation: .numbers
        case .phonePad, .namePhonePad: .phone
        default: .default
        }
        let type = proxy.textContentType.flatMap { $0 }
        let codes: Set<UITextContentType> = [.oneTimeCode, .creditCardNumber, .telephoneNumber, .postalCode]
        let content: Field.Content =
            type == .emailAddress ? .email
            : type == .URL ? .url
            : type == .username ? .username
            : type == .password || type == .newPassword ? .password
            : type.map(codes.contains) == true ? .code
            : .other
        let returnKey: Field.ReturnKey = switch proxy.returnKeyType ?? .default {
        case .go: .go
        case .google, .yahoo, .search: .search
        case .join: .join
        case .next: .next
        case .route: .route
        case .send: .send
        case .done: .done
        case .emergencyCall: .emergencyCall
        case .continue: .continue
        default: .return
        }
        let capitals: Field.Capitals = switch proxy.autocapitalizationType ?? .sentences {
        case .none: .none
        case .words: .words
        case .allCharacters: .all
        default: .sentences
        }
        return Field(keyboard: keyboard, content: content, returnKey: returnKey, capitals: capitals,
                     corrects: proxy.autocorrectionType != .no,
                     returnNeedsText: proxy.enablesReturnKeyAutomatically ?? false,
                     secure: proxy.isSecureTextEntry ?? false)
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
        keyboard.showsGlobe = needsInputModeSwitchKey
        let height = applyHeight(fresh: false) ?? keyboard.height(forWidth: width)
        // The keyboard view takes whatever iOS grants, edge to edge (pinned in
        // `viewDidLoad`; iOS adds the margins around it): the keys sit at the bottom where
        // Apple's are, and shrink if iOS grants less than asked.
        let granted = view.bounds.height
        checks.sized(granted: granted, wanted: height, width: width, screenWidth: view.window?.windowScene?.screen.bounds.width ?? 0)
        askAgainIfShort(granted: granted, wanted: height)
        if isVisible, openedAt == nil, granted > 0 { openedAt = (granted, height) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if opening != nil, opening?.steps.last?.name != "layout" { opening?.step("layout", now: uptime) }
    }

    /// A timed re-ask after the keyboard appeared: asks again if iOS still gives a
    /// different height, and on the last one writes down how the opening went.
    private func askAgainIfOff(appearance: Int, last: Bool) {
        guard appearance == self.appearance, isVisible, let keyboard else { return }
        let got = view.bounds.height
        let asked = keyboard.height(forWidth: view.bounds.width)
        if abs(got - asked) > 0.5 {
            applyHeight(fresh: true)
            nudgeLayout()
        }
        guard last, let openedAt, abs(openedAt.got - openedAt.asked) > 0.5 else { return }
        keyboard.heightStory = "Opened at \(Int(openedAt.got)) of the \(Int(openedAt.asked.rounded())) pt asked, "
            + (abs(got - asked) > 0.5 ? "still \(Int(got)) after asking again." : "then grew to it.")
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

    /// Does what opening the settings panel did, the one thing that made iOS take the
    /// height: a change to the constraints inside the view. Tells the keys their size
    /// changed and adds and removes an empty view held by constraints.
    private func nudgeLayout() {
        keyboard?.invalidateIntrinsicContentSize()
        let probe = UIView()
        probe.isHidden = true
        probe.isUserInteractionEnabled = false
        probe.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(probe)
        NSLayoutConstraint.activate([
            probe.topAnchor.constraint(equalTo: view.topAnchor),
            probe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            probe.widthAnchor.constraint(equalToConstant: 0),
            probe.heightAnchor.constraint(equalToConstant: 0),
        ])
        view.setNeedsUpdateConstraints()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        probe.removeFromSuperview()
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

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        keyboard?.model.contextChanged("selection")
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        followKeyboardAppearance()
        keyboard?.model.field = field
        keyboard?.model.contextChanged("change")
        edits += 1
        if edits % 5 == 0 { checks.refresh() }
    }

    /// The once-a-second reading (`MemorySampler`), to everything that shows or keeps one.
    private func took(_ sample: MemorySample) {
        var sample = sample
        ticks += 1
        if keyboard?.stats.isRunning == true, ticks % 5 == 1 { sample.regions = MemoryRegions.current().map { MemoryRegions.line($0) } }
        health?.sample(sample.reading)
        if sample.metal { health?.used(.metal) }
        debug?.sample(sample.reading)
        keyboard?.stats.show(sample)
        if let why = memoryLog.reason(for: sample, at: ProcessInfo.processInfo.systemUptime) {
            keyboard?.model.logMemory(sample, why: why)
        }
    }

    /// A reading for the typing log now, for its own reason (shown, hidden, a warning).
    /// Writes how this opening went into the typing log, once the keys are on screen.
    private func logOpening() {
        guard var timing = opening else { return }
        opening = nil
        if timing.steps.last?.name != "layout" { timing.step("shown", now: uptime) }
        var notes: [String] = []
        if KeyboardView.metalLoadMillis > 0 { notes.append("metal \(KeyboardView.metalLoadMillis) off the main thread") }
        keyboard?.model.logOpen(timing.line(now: uptime, notes: notes))
    }

    private func logMemory(_ why: String) {
        guard let model = keyboard?.model, model.recorder != nil, var sample = sampler.take() else { return }
        sample.regions = MemoryRegions.current().map { MemoryRegions.line($0) }
        memoryLog.logged(sample, at: ProcessInfo.processInfo.systemUptime)
        model.logMemory(sample, why: why)
    }
}

/// The engine's text target on the extension's document proxy. The open word is written
/// as ordinary text and replaced as the guesses change. It used to be marked
/// (underlined) text, first always and then as a setting: through the proxy that put the
/// space before the word (2 Nov 2026), and while a word was marked the field hid taps and
/// selections from the keyboard (typing recordings, 6 Nov 2026). Gabriel turned it off
/// and had it removed (8 Nov 2026), so the keyboard can always see where the cursor is.
///
/// Text selected in the field is deleted before anything is typed, so a tap or a swipe
/// replaces it: inserting through the proxy left the selection in place (Gabriel, 3 Nov
/// 2026).
@MainActor
final class ProxyTarget: TextTarget {
    private unowned let controller: UIInputViewController
    /// The open word as it stands in the field, right before the cursor.
    private var open = ""
    /// The field `open` was typed in (`documentIdentifier`): another field means the
    /// person moved on, and the word stays behind.
    private var openDocument: UUID?
    /// Set once the selection is deleted, until the run loop turns: the proxy can still
    /// report the old selection right after, and a second delete would take a letter.
    private var clearedSelection = false

    init(controller: UIInputViewController) {
        self.controller = controller
    }

    private var proxy: UITextDocumentProxy { controller.textDocumentProxy }

    /// The field's `documentIdentifier`, or nil when there is none. Swift calls it a
    /// non-optional UUID, but iOS can hand back nil (say, while a field goes away), and
    /// reading it directly then crashes (ASTROTYPE-3). Asking through Objective-C lets
    /// the nil through.
    private var documentID: UUID? {
        let getter = #selector(getter: UITextDocumentProxy.documentIdentifier)
        guard proxy.responds(to: getter) else { return nil }
        return (proxy.perform(getter)?.takeUnretainedValue() as? NSUUID) as UUID?
    }

    /// The text before the cursor without the open word.
    var textBeforeCursor: String? {
        guard let before = proxy.documentContextBeforeInput else { return nil }
        return !open.isEmpty && before.hasSuffix(open) ? String(before.dropLast(open.count)) : before
    }

    func insert(_ text: String) {
        if !text.isEmpty { deleteSelection() }
        proxy.insertText(text)
    }
    func deleteBackward() {
        proxy.deleteBackward()
    }
    var hasText: Bool { proxy.hasText }

    func mark(_ text: String) {
        guard text != open else { return }
        if open.isEmpty {
            openDocument = documentID
            if !text.isEmpty { deleteSelection() }
        }
        // Take the old reading out, unless the cursor moved away from it (then it stays
        // as typed). A field that hides its text (nil) is trusted to be where we left it.
        if !open.isEmpty, proxy.documentContextBeforeInput.map({ $0.hasSuffix(open) }) ?? true {
            for _ in 0..<open.count { proxy.deleteBackward() }
        }
        if !text.isEmpty { proxy.insertText(text) }
        open = text
    }

    /// The open word is already in the field as ordinary text: just let go of it.
    func unmark() {
        open = ""
    }

    func moveCursor(by offset: Int) {
        proxy.adjustTextPosition(byCharacterOffset: offset)
    }

    /// The open word is lost when the field changed under it (submit, or a tap on
    /// another field) or text is selected: the next key is meant for the selection, not
    /// for the word. Our own selection delete is ignored while the proxy catches up.
    var lostOpenWord: Bool {
        guard !open.isEmpty else { return false }
        if documentID != openDocument { return true }
        guard !clearedSelection, let selected = proxy.selectedText else { return false }
        return !selected.isEmpty
    }

    var textAfterCursor: String? { proxy.documentContextAfterInput }

    var selectedText: String? { clearedSelection ? nil : proxy.selectedText }

    var hasSelection: Bool {
        guard !clearedSelection, let selected = proxy.selectedText else { return false }
        return !selected.isEmpty
    }

    var fieldState: String? {
        func show(_ text: String?) -> String { text.map { $0.debugDescription } ?? "nil" }
        let before = proxy.documentContextBeforeInput.map { String($0.suffix(30)) }
        let after = proxy.documentContextAfterInput.map { String($0.prefix(30)) }
        return "\(show(before)) ⟦\(show(proxy.selectedText))⟧ \(show(after))"
            + " open \(show(open))\(documentID == openDocument ? "" : " other field")"
    }

    /// The word stays in the field as typed.
    func dropOpenWord() {
        open = ""
        openDocument = nil
    }

    /// Deletes the selected text, if any, so what is typed next takes its place.
    ///
    /// Deleting a selected word also takes the space before it in most fields (iOS's
    /// smart delete), so typing over "sentence" in "This is a sentence" gave "This is
    /// ahello" (a typing recording, Gabriel, 7 Nov 2026). The word is being replaced,
    /// so that space is put back.
    private func deleteSelection() {
        guard !clearedSelection, let selected = proxy.selectedText, !selected.isEmpty else { return }
        let spaceBefore = proxy.documentContextBeforeInput?.last?.isWhitespace == true
            && selected.first?.isWhitespace != true
        proxy.deleteBackward()
        if spaceBefore, let before = proxy.documentContextBeforeInput,
           let last = before.last, !last.isWhitespace {
            proxy.insertText(" ")
        }
        clearedSelection = true
        Task { @MainActor [weak self] in self?.clearedSelection = false }
    }
}
