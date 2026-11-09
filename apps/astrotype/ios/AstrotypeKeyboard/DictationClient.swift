import AstrotypeCore
import AstrotypeUI
import Foundation

/// The keyboard's side of dictation (features/dictation). iOS doesn't let a keyboard use
/// the microphone, so the app listens; this asks it to (`DictationCommand`, a Darwin
/// notification), reads what it heard (`DictationState` in the App Group) and hands
/// the words to the model, which writes them into the field. One per process, like the
/// model (`KeyboardShared`).
///
/// - The mic is off (the app hasn't turned it on in the last few minutes): a tap opens
///   the app, which turns the mic on, starts listening and shows how to go back.
/// - The mic is ready: touching it down starts listening at once; a short tap keeps
///   listening until the next tap, a hold listens until the finger lets go
///   (`DictationPress`).
/// - Ready, but the app doesn't start within `answerWithin`: iOS ended it without it
///   saying so, so the app opens as if the mic were off.
@MainActor
final class DictationClient {
    /// How long the app has to say it's listening before the keyboard opens it.
    static let answerWithin: TimeInterval = 1.5

    private let model: KeyboardModel
    /// Opens the app at `astrotype://dictate` (`KeyboardViewController.openApp`).
    private let openApp: () -> Void
    private let fullAccess: Bool
    /// The app's last word.
    private var state = DictationState.off
    /// The mic is down: when, and how the mic stood then.
    private var press: (at: Date, phase: DictationPhase)?
    /// Asked the app to listen, and waiting for it to say it does.
    private var asked: Date?
    private var answer: Task<Void, Never>?
    /// While the keyboard shows: the state is looked at once a second, so a mic whose
    /// window ran out (or whose app went away) shows as off.
    private var ticker: Task<Void, Never>?
    /// When this keyboard last opened the app for dictation; its disappearing then is
    /// the trip to the app, not the person leaving.
    private var openedApp: Date?
    private var observing = false

    init(model: KeyboardModel, fullAccess: Bool, openApp: @escaping () -> Void) {
        self.model = model
        self.fullAccess = fullAccess
        self.openApp = openApp
        model.onMic = { [weak self] action in self?.handle(action) }
    }

    /// Dictation needs iOS 26 (Apple's on-device speech to text) and the mic on in
    /// Settings → Dictation.
    private var offered: Bool {
        guard #available(iOS 26, *) else { return false }
        return model.keyboardSettings.dictation
    }

    // MARK: Showing

    func appeared() {
        observe()
        read()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }

    /// The keyboard went away. Listening stops unless this is the trip to the app.
    func disappeared() {
        ticker?.cancel()
        ticker = nil
        press = nil
        let trip = openedApp.map { Date().timeIntervalSince($0) < 3 } ?? false
        if !trip, state.phase(at: Date()) == .listening || asked != nil {
            send(.stop)
        }
        cancelAsk()
        refresh()
    }

    // MARK: The mic and the strip

    private func handle(_ action: MicAction) {
        let now = Date()
        switch action {
        case .down:
            guard fullAccess else {
                model.flashNote("Turn on Full Access to dictate")
                return
            }
            let phase = asked != nil ? .listening : state.phase(at: now)
            press = (now, phase)
            if DictationPress.down(in: phase) == .listen { listen(how: .hold) }
            // Still down after a tap's time: the strip says "Let go to stop".
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(DictationPress.holdAfter))
                self?.refresh()
            }
        case .up:
            guard let press else { return }
            self.press = nil
            let step = DictationPress.up(heldFor: now.timeIntervalSince(press.at), phaseAtDown: press.phase)
            switch step {
            case .openApp: open()
            case .stop: stop()
            case .listen: listen(how: .tap)
            case .none:
                // A tap that started listening: it keeps on until the next one.
                DictationLink.write(DictationRequest(language: Self.language(model.activeLanguages), how: .tap),
                                    to: DictationLink.requestURL)
            }
        case .done:
            stop()
        case .cancel:
            // The model has taken the words back.
            cancelAsk()
            send(.cancel)
        }
        refresh()
    }

    private func listen(how: DictationHow) {
        DictationLink.write(DictationRequest(language: Self.language(model.activeLanguages), how: how),
                            to: DictationLink.requestURL)
        send(.listen)
        asked = Date()
        answer?.cancel()
        answer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.answerWithin))
            guard !Task.isCancelled, let self, self.asked != nil else { return }
            // No answer: iOS ended the app. Open it.
            self.model.logDictation("stale")
            self.cancelAsk()
            self.open()
        }
    }

    private func stop() {
        cancelAsk()
        send(.stop)
    }

    private func open() {
        DictationLink.write(DictationRequest(language: Self.language(model.activeLanguages), how: .tap),
                            to: DictationLink.requestURL)
        model.logDictation("open")
        openedApp = Date()
        openApp()
    }

    private func cancelAsk() {
        asked = nil
        answer?.cancel()
        answer = nil
    }

    private func send(_ command: DictationCommand) {
        DictationLink.post(command.name)
    }

    // MARK: The app's state

    /// The state file changed, or a second went by.
    private func read() {
        guard fullAccess else { return refresh() }
        let fresh = DictationLink.read(DictationState.self, from: DictationLink.stateURL) ?? .off
        let old = state
        state = fresh
        if fresh.phase == .listening, asked != nil { cancelAsk() }
        if let problem = fresh.problem, problem != old.problem {
            model.logDictation("fail", why: problem.rawValue)
            model.flashNote(Self.note(for: problem))
        }
        // Words of a listen, still coming or final.
        if fresh.listen > 0, fresh.phase == .listening || fresh.finished {
            model.dictationHeard(listen: fresh.listen, transcript: fresh.transcript, finished: fresh.finished)
        }
        model.onLevel?(fresh.phase == .listening ? fresh.level : 0)
        refresh()
    }

    /// The mic as the bar should draw it now.
    private func refresh() {
        let now = Date()
        guard offered else {
            model.mic = .hidden
            return
        }
        if asked != nil {
            let held = press.map { now.timeIntervalSince($0.at) >= DictationPress.holdAfter } ?? false
            model.mic = held ? .listening(held: true) : .starting
            return
        }
        switch state.phase(at: now) {
        case .off: model.mic = .off
        case .ready: model.mic = .ready
        case .listening:
            let held = press.map { $0.phase != .listening && now.timeIntervalSince($0.at) >= DictationPress.holdAfter } ?? false
            model.mic = .listening(held: held)
        }
    }

    private func observe() {
        guard !observing, fullAccess else { return }
        observing = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let pointer = UInt(bitPattern: observer)
                DispatchQueue.main.async {
                    guard let raw = UnsafeRawPointer(bitPattern: pointer) else { return }
                    MainActor.assumeIsolated {
                        Unmanaged<DictationClient>.fromOpaque(raw).takeUnretainedValue().read()
                    }
                }
            },
            DictationLink.stateChanged as CFString,
            nil,
            .deliverImmediately
        )
    }

    // MARK: Helpers

    /// The language to listen for: the keyboard's first, as the phone writes it
    /// ("en" → "en-US" when the phone prefers American English).
    static func language(_ codes: [String]) -> String {
        let code = codes.first ?? "en"
        return Locale.preferredLanguages.first { $0.lowercased().hasPrefix(code) } ?? code
    }

    static func note(for problem: DictationProblem) -> String {
        switch problem {
        case .micDenied: "Allow the mic for Astrotype in Settings"
        case .noSpeech: "Dictation isn't available in this language yet"
        case .failed: "Dictation stopped. Tap the mic to try again"
        }
    }
}
