import AstrotypeCore
import Foundation
import Observation

/// The app's side of dictation (features/dictation): it turns the mic on when the
/// keyboard opens the app (`astrotype://dictate`), keeps it on for the window in
/// Settings → Dictation, listens when the keyboard asks, and writes the words for it.
/// The rules of what happens when live in `DictationSession`; this runs the mic
/// (`SpeechListener`), talks to the keyboard (`DictationChannel`) and counts.
///
///     model.openedFromKeyboard()   // the go-back screen, the mic on, listening
///     model.wentToBackground()     // the person swiped back
@MainActor
@Observable
final class DictationModel {
    /// The go-back screen (DESIGN "Go back"), while the app is open for dictation.
    enum Screen: Equatable {
        /// First time: why the mic, and a button that asks for it.
        case askMic
        /// The mic isn't allowed: a way to Settings.
        case micDenied
        /// Getting speech to text ready (it may download the language the first time).
        case preparing
        /// The mic is on: swipe back and talk.
        case micOn
        /// It didn't work (`problem`), or this phone can't dictate.
        case failed(DictationProblem)
    }

    private(set) var screen: Screen?
    private(set) var session: DictationSession
    var isMicOn: Bool { session.isOn }

    /// Settings → Dictation → Keep the mic ready, in minutes.
    var minutes: Int {
        get { session.minutes }
        set { session.minutes = newValue }
    }

    @ObservationIgnored private let listener: SpeechListener?
    @ObservationIgnored private let channel: DictationChannel
    @ObservationIgnored private let metrics: Metrics
    /// A Sentry breadcrumb: the step, never the words.
    @ObservationIgnored private let note: (String) -> Void
    /// An error worth a Sentry report (with the iOS error code).
    @ObservationIgnored private let report: (Error) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var listenStarted: Date?
    @ObservationIgnored private var firstWordsCounted = false
    /// When the keyboard opened the app, for `dictation.returned`.
    @ObservationIgnored private var openedAt: Date?
    @ObservationIgnored private var lastPublish = Date.distantPast
    @ObservationIgnored private var publishSoon: Task<Void, Never>?

    /// `listener` is nil where dictation can't work (before iOS 26).
    init(listener: SpeechListener?, channel: DictationChannel, metrics: Metrics, minutes: Int,
         note: @escaping (String) -> Void = { _ in }, report: @escaping (Error) -> Void = { _ in },
         now: @escaping () -> Date = { Date() }) {
        self.listener = listener
        self.channel = channel
        self.metrics = metrics
        self.note = note
        self.report = report
        self.now = now
        session = DictationSession(minutes: minutes)
        channel.listen { [weak self] command in self?.handle(command) }
        listener?.onMicLost = { [weak self] in self?.turnOff(why: "system") }
        // A state left from before (the app was ended) says off.
        channel.publish(session.state)
    }

    // MARK: The keyboard opened the app

    /// The keyboard's mic with the mic off: the go-back screen, and the mic on and
    /// listening as soon as it can be.
    func openedFromKeyboard() async {
        openedAt = now()
        note("opened by the keyboard")
        guard let listener else {
            screen = .failed(.noSpeech)
            fail(DictationFailure(step: .speech))
            return
        }
        if session.isOn {
            screen = .micOn
            await startListening(openedApp: true)
            return
        }
        switch listener.micAllowed {
        case nil:
            screen = .askMic
        case false?:
            screen = .micDenied
            fail(DictationFailure(step: .permission))
        case true?:
            await turnOnAndListen()
        }
    }

    /// "Allow the mic" on the first-time screen.
    func allowMic() async {
        guard let listener else { return }
        if await listener.askForMic() {
            await turnOnAndListen()
        } else {
            screen = .micDenied
            fail(DictationFailure(step: .permission))
        }
    }

    /// "Not now": the mic goes off and the screen goes.
    func notNow() {
        screen = nil
        openedAt = nil
        turnOff(why: "user")
    }

    /// The person left the app (swiped back to where they were typing).
    func wentToBackground() {
        if let openedAt, session.isOn {
            metrics.duration("dictation.returned", seconds: now().timeIntervalSince(openedAt))
        }
        openedAt = nil
        screen = nil
    }

    private func turnOnAndListen() async {
        guard let listener else { return }
        screen = .preparing
        do {
            try await listener.prepare(language: language)
            try await listener.micOn()
        } catch {
            let failure = error as? DictationFailure ?? DictationFailure(step: .mic, code: (error as NSError).code)
            fail(failure)
            screen = .failed(failure.problem)
            return
        }
        session.micOn(at: now())
        note("mic on")
        startHeartbeat()
        publish()
        screen = .micOn
        await startListening(openedApp: true)
    }

    // MARK: Listening

    private func handle(_ command: DictationCommand) {
        note("keyboard: \(command.rawValue)")
        switch command {
        case .listen: Task { await startListening(openedApp: false) }
        case .stop: Task { await stopListening(how: channel.request()?.how.rawValue ?? "tap") }
        case .cancel: Task { await stopListening(how: "cancel") }
        case .end: turnOff(why: "user")
        }
    }

    private func startListening(openedApp: Bool) async {
        guard let listener, session.listen(at: now()) else {
            // Off (or already listening): the keyboard learns where things stand.
            publish()
            return
        }
        listenStarted = now()
        firstWordsCounted = false
        metrics.count("dictation.started", ["mic": openedApp ? "opened_app" : "ready"])
        note("listening")
        publish()
        do {
            try await listener.listen(language: language, onWords: { [weak self] words in
                self?.heard(words: words)
            }, onLevel: { [weak self] level in
                self?.heard(level: level)
            })
        } catch {
            let failure = error as? DictationFailure ?? DictationFailure(step: .speech, code: (error as NSError).code)
            fail(failure)
            session.failed(failure.problem, at: now())
            publish()
        }
    }

    private func heard(words: String? = nil, level: Double? = nil) {
        session.heard(words ?? session.state.transcript, level: level ?? session.state.level, at: now())
        if words != nil, let listenStarted, !firstWordsCounted {
            // How long the first words took, to see where a slow start comes from.
            firstWordsCounted = true
            metrics.duration("dictation.first_words", seconds: now().timeIntervalSince(listenStarted))
        }
        publishThrottled()
    }

    private func stopListening(how: String) async {
        guard let listener, session.isListening else { return }
        let words = await listener.stop()
        session.finished(words, at: now())
        metrics.count("dictation.finished", ["how": how])
        if let listenStarted {
            metrics.duration("dictation.length", seconds: now().timeIntervalSince(listenStarted))
        }
        listenStarted = nil
        note("stopped (\(how))")
        publish()
    }

    // MARK: The mic

    /// The mic goes off: the window ran out (`idle`), the person said so (`user`), or
    /// iOS took it (`system`).
    func turnOff(why: String) {
        guard session.isOn else { return }
        listener?.micOff()
        heartbeat?.cancel()
        heartbeat = nil
        session.off(at: now())
        metrics.count("dictation.session_ended", ["why": why])
        note("mic off (\(why))")
        publish()
    }

    /// Every `DictationLink.heartbeat` seconds while the mic is on: the keyboard sees the
    /// app is alive, and the mic turns off when its window runs out.
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(DictationLink.heartbeat))
                guard let self, !Task.isCancelled else { return }
                if self.session.shouldTurnOff(at: self.now()) {
                    self.turnOff(why: "idle")
                    return
                }
                self.session.touch(at: self.now())
                self.publish()
            }
        }
    }

    // MARK: Telling the keyboard

    private func publish() {
        publishSoon?.cancel()
        publishSoon = nil
        lastPublish = now()
        channel.publish(session.state)
    }

    /// Words and levels come fast: at most ten writes a second.
    private func publishThrottled() {
        let wait = 0.1 - now().timeIntervalSince(lastPublish)
        guard wait > 0 else { return publish() }
        guard publishSoon == nil else { return }
        publishSoon = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }

    /// The language the keyboard asked for, or the phone's.
    private var language: String {
        channel.request()?.language ?? Locale.preferredLanguages.first ?? "en-US"
    }

    private func fail(_ failure: DictationFailure) {
        metrics.count("dictation.failed", ["step": failure.step.rawValue])
        note("failed: \(failure.step.rawValue) \(failure.code.map(String.init) ?? "")")
        if let code = failure.code {
            report(NSError(domain: "astrotype.dictation.\(failure.step.rawValue)", code: code))
        }
    }
}
