import Foundation

// Dictation (features/dictation/FEATURE.md). iOS doesn't let a keyboard use the
// microphone, so the Astrotype app listens and turns speech into text, and the keyboard
// asks it to and writes the words. The two talk through the App Group:
//
// - The keyboard sends a `DictationCommand` (a Darwin notification, no payload), after
//   writing a `DictationRequest` for the details.
// - The app writes `DictationState` (the transcript so far, the phase, a heartbeat) and
//   posts `DictationLink.stateChanged`.
//
//     // Keyboard: start listening.
//     DictationLink.write(DictationRequest(language: "en-US", how: .tap))
//     DictationLink.post(.listen)
//     // Keyboard: when the state changes, bring the field up to date.
//     let edit = text.update(transcript: state.transcript, before: proxy.textBeforeCursor ?? "")
//     edit.apply(deleteBackward:, insert:)

/// Where the app's dictation stands.
public enum DictationPhase: String, Codable, Sendable {
    /// No mic: the next dictation has to open the app.
    case off
    /// The mic is on and the app is waiting for the keyboard.
    case ready
    /// Hearing words now.
    case listening
}

/// Why the app couldn't listen, for the keyboard's note.
public enum DictationProblem: String, Codable, Sendable {
    /// The person hasn't allowed the microphone.
    case micDenied
    /// Speech to text isn't available for this language on this phone.
    case noSpeech
    /// The mic or speech to text failed.
    case failed
}

/// What the app tells the keyboard. Written to the App Group by the app only.
public struct DictationState: Codable, Equatable, Sendable {
    public var phase: DictationPhase
    /// Everything heard since this listen started: the final words and the end that may
    /// still change.
    public var transcript: String
    /// Counts up with every listen, so the keyboard tells one dictation from the next.
    public var listen: Int
    /// Whether `transcript` is final (listening stopped and the last words are in).
    public var finished: Bool
    /// How loud it is now, 0 to 1, for the bar's wave.
    public var level: Double
    /// When the app last wrote. A state older than `DictationLink.staleAfter` is off:
    /// iOS ended the app without it saying so.
    public var alive: Date
    /// When the mic turns off unless it is used again.
    public var readyUntil: Date?
    public var problem: DictationProblem?

    public init(phase: DictationPhase = .off, transcript: String = "", listen: Int = 0, finished: Bool = false,
                level: Double = 0, alive: Date = .distantPast, readyUntil: Date? = nil, problem: DictationProblem? = nil) {
        self.phase = phase
        self.transcript = transcript
        self.listen = listen
        self.finished = finished
        self.level = level
        self.alive = alive
        self.readyUntil = readyUntil
        self.problem = problem
    }

    public static let off = DictationState()

    /// The phase as it really is at `now`: off when the app stopped writing.
    public func phase(at now: Date) -> DictationPhase {
        now.timeIntervalSince(alive) < DictationLink.staleAfter ? phase : .off
    }
}

/// How a dictation was started on the keyboard's mic button (`DictationPress`).
public enum DictationHow: String, Codable, Sendable {
    case tap, hold
}

/// The mic on the bar, as the keyboard draws it.
public enum MicStatus: Equatable, Sendable {
    /// No mic: dictation is off in Settings, or this isn't the keyboard.
    case hidden
    /// The mic is off: a tap opens the app to turn it on.
    case off
    /// The mic is on (a small mint dot): a tap listens at once.
    case ready
    /// Waiting for the app to start listening.
    case starting
    /// Listening: the bar is the listening strip. `held`: the finger is on the mic,
    /// and letting go stops.
    case listening(held: Bool)

    public var isListening: Bool {
        switch self {
        case .starting, .listening: true
        case .hidden, .off, .ready: false
        }
    }
}

/// What the person did to the mic or the listening strip.
public enum MicAction: String, Equatable, Sendable {
    /// A finger down on the mic, and up.
    case down, up
    /// ✕ on the strip: stop and take back the words.
    case cancel
    /// ✓ on the strip: stop and keep them.
    case done
}

/// What the keyboard asks for with its next command.
public struct DictationRequest: Codable, Equatable, Sendable {
    /// The language to listen for, a BCP 47 identifier ("en-US").
    public var language: String
    public var how: DictationHow
    public var sent: Date

    public init(language: String, how: DictationHow, sent: Date = Date()) {
        self.language = language
        self.how = how
        self.sent = sent
    }
}

/// What the keyboard asks the app to do.
public enum DictationCommand: String, CaseIterable, Sendable {
    /// Start listening (the mic is already on).
    case listen
    /// Stop listening and keep the words.
    case stop
    /// Stop listening; the keyboard takes the words back.
    case cancel
    /// Turn the mic off now.
    case end

    /// The Darwin notification's name.
    public var name: String { "com.tinypenguin.astrotype.dictation.\(rawValue)" }
}

/// The App Group files and notification names both sides use.
public enum DictationLink {
    /// Posted by the app after it writes a new `DictationState`.
    public static let stateChanged = "com.tinypenguin.astrotype.dictation.state"
    public static let stateFile = "dictation.json"
    public static let requestFile = "dictation-request.json"
    /// The app's page the keyboard opens when the mic is off (`astrotype://dictate`).
    public static let openPage = "dictate"
    /// How often the app writes while the mic is on, so the keyboard can tell it's alive.
    public static let heartbeat: TimeInterval = 2
    /// A state this old means the app is gone.
    public static let staleAfter: TimeInterval = 6

    public static func read<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public static func write<T: Encodable>(_ value: T, to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    public static var stateURL: URL? { KeyboardFiles.shared(stateFile) }
    public static var requestURL: URL? { KeyboardFiles.shared(requestFile) }

    /// Posts a Darwin notification (both processes see it while they run).
    public static func post(_ name: String) {
        #if canImport(Darwin)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(name as CFString), nil, nil, true)
        #endif
    }
}

/// How long the mic stays on after a dictation (Settings → Dictation).
public enum DictationWindow {
    public static let choices = [1, 5, 15]
    public static let defaultMinutes = 5

    /// When the mic turns off, `minutes` after it was last used (a choice outside
    /// `choices` counts as the default).
    public static func endsAt(lastUsed: Date, minutes: Int) -> Date {
        let minutes = choices.contains(minutes) ? minutes : defaultMinutes
        return lastUsed.addingTimeInterval(TimeInterval(minutes * 60))
    }
}

/// The keyboard's mic button: a short tap toggles listening, a longer press listens
/// while held.
///
/// - Mic off: letting go opens the app (`openApp`).
/// - Mic ready: touching down starts listening at once (`listen`), so a hold hears
///   from the start; letting go after a tap keeps listening, after a hold stops.
/// - Listening: letting go stops (`stop`).
public enum DictationPress {
    public static let holdAfter: TimeInterval = 0.3

    public static func how(heldFor seconds: TimeInterval) -> DictationHow {
        seconds < holdAfter ? .tap : .hold
    }

    public enum Step: Equatable, Sendable {
        case none, listen, stop, openApp
    }

    /// What touching the mic down does, in `phase`.
    public static func down(in phase: DictationPhase) -> Step {
        phase == .ready ? .listen : .none
    }

    /// What letting go does: `phase` is what it was when the finger went down.
    public static func up(heldFor seconds: TimeInterval, phaseAtDown phase: DictationPhase) -> Step {
        switch phase {
        case .off: .openApp
        case .ready: how(heldFor: seconds) == .hold ? .stop : .none
        case .listening: .stop
        }
    }
}

/// The app's side of dictation, without the mic itself: what the state is after each
/// thing that happens, and when the mic should turn off. `DictationModel` in the app
/// runs the mic and speech to text and writes `state` for the keyboard.
///
///     var session = DictationSession(minutes: 5)
///     session.micOn(at: now)                     // ready
///     session.listen(at: now)                    // listening, listen 1
///     session.heard("Hello", level: 0.4, at: now)
///     session.finished("Hello there", at: now)   // ready, finished
///     session.shouldTurnOff(at: now + 301)       // true
public struct DictationSession: Equatable, Sendable {
    public private(set) var state = DictationState()
    /// When the mic was turned on or last finished listening.
    public private(set) var lastUsed: Date?
    /// Settings → Dictation → Keep the mic ready.
    public var minutes: Int

    public init(minutes: Int = DictationWindow.defaultMinutes) {
        self.minutes = minutes
    }

    public var isOn: Bool { state.phase != .off }
    public var isListening: Bool { state.phase == .listening }

    /// The mic is on and waiting.
    public mutating func micOn(at now: Date) {
        state.phase = .ready
        state.problem = nil
        state.level = 0
        lastUsed = now
        touch(at: now)
    }

    /// Start a new listen. Returns false when the mic isn't on or it already listens.
    @discardableResult
    public mutating func listen(at now: Date) -> Bool {
        guard state.phase == .ready else { return false }
        state.phase = .listening
        state.listen += 1
        state.transcript = ""
        state.finished = false
        state.problem = nil
        state.level = 0
        touch(at: now)
        return true
    }

    /// Words heard so far in this listen (`transcript` is all of them, from its start).
    public mutating func heard(_ transcript: String, level: Double, at now: Date) {
        guard state.phase == .listening else { return }
        state.transcript = transcript
        state.level = min(1, max(0, level))
        touch(at: now)
    }

    /// The listen ended and these are its final words; back to ready.
    public mutating func finished(_ transcript: String, at now: Date) {
        guard state.phase == .listening else { return }
        state.transcript = transcript
        state.finished = true
        state.phase = .ready
        state.level = 0
        lastUsed = now
        touch(at: now)
    }

    /// Speech to text failed: the listen ends with what it had, the mic stays on, and
    /// the keyboard says why.
    public mutating func failed(_ problem: DictationProblem, at now: Date) {
        if state.phase == .listening {
            state.finished = true
            state.phase = .ready
        }
        state.problem = problem
        state.level = 0
        touch(at: now)
    }

    /// The mic went off (the window ended, the person turned it off, iOS stopped it, or
    /// it failed with `problem`).
    public mutating func off(problem: DictationProblem? = nil, at now: Date) {
        if state.phase == .listening { state.finished = true }
        state.phase = .off
        state.problem = problem
        state.level = 0
        state.readyUntil = nil
        touch(at: now)
    }

    /// A heartbeat: the state is rewritten so the keyboard knows the app is alive.
    public mutating func touch(at now: Date) {
        state.alive = now
        if state.phase == .off {
            state.readyUntil = nil
        } else if let lastUsed {
            state.readyUntil = DictationWindow.endsAt(lastUsed: lastUsed, minutes: minutes)
        }
    }

    /// Whether the window has run out: ready, and unused for `minutes`.
    public func shouldTurnOff(at now: Date) -> Bool {
        guard state.phase == .ready, let end = state.readyUntil else { return false }
        return now >= end
    }
}

/// A change to the text before the cursor: delete this many characters, then type this.
public struct DictationEdit: Equatable, Sendable {
    public var delete: Int
    public var insert: String

    public init(delete: Int = 0, insert: String = "") {
        self.delete = delete
        self.insert = insert
    }

    public static let none = DictationEdit()
    public var isEmpty: Bool { delete == 0 && insert.isEmpty }

    /// The edit that turns `old` (just before the cursor) into `new`, keeping what they
    /// start with in common.
    public static func between(_ old: String, _ new: String) -> DictationEdit {
        let shared = zip(old, new).prefix { $0 == $1 }.count
        return DictationEdit(delete: old.count - shared, insert: String(new.dropFirst(shared)))
    }
}

/// The keyboard's side of the words (features/dictation, "Talk and type together"):
/// what it has written for the part still being heard, and how a newer transcript
/// changes the field. A key the person types freezes what's there; the words heard
/// after it go after what they typed.
///
///     var text = DictationText()
///     let edit = text.update(transcript: "Hello how", before: "Yes! ")   // insert "Hello how"
///     text.freeze(transcript: "Hello how")                              // the person types " r"
///     text.update(transcript: "Hello how are you", before: "Yes! Hello how r")  // insert " are you"
public struct DictationText: Equatable, Sendable {
    /// How many words of the transcript are already kept in the field. Words, not
    /// characters, so a late comma or capital in the kept part doesn't shift the rest.
    public private(set) var frozen = 0
    /// What the keyboard wrote for the rest, right before the cursor (with the space it
    /// put in front).
    public private(set) var written = ""

    public init() {}

    /// The edit that brings the field up to date with `transcript`. `before` is the text
    /// before the cursor as the field has it now. If it no longer ends with what was
    /// written (the person moved the cursor), what's there is kept and the words from
    /// here on go at the new spot.
    ///
    /// A field may tell only the last part of its text (`before` shorter than what was
    /// written, and the end of it): then the words keep the space and capital they
    /// started with.
    public mutating func update(transcript: String, before: String) -> DictationEdit {
        let live = Self.live(transcript, after: frozen)
        let wanted: String
        if before.hasSuffix(written) {
            wanted = Self.joined(live, after: String(before.dropLast(written.count)))
        } else if !before.isEmpty, before.count < written.count, written.hasSuffix(before) {
            wanted = Self.rejoined(live, like: written)
        } else {
            freeze(transcript: transcript)
            return .none
        }
        let edit = DictationEdit.between(written, wanted)
        written = wanted
        return edit
    }

    /// The last words are in: write them with a space after, and keep them.
    public mutating func finish(transcript: String, before: String) -> DictationEdit {
        var edit = update(transcript: transcript, before: before)
        if !written.isEmpty, written.last?.isWhitespace == false {
            edit.insert += " "
        }
        freeze(transcript: transcript)
        return edit
    }

    /// The person typed a key (or moved the cursor): keep what's written as it is.
    public mutating func freeze(transcript: String) {
        frozen = max(frozen, Self.wordCount(transcript))
        written = ""
    }

    /// ✕: take back what was written for the part still being heard.
    public mutating func discard(transcript: String) -> DictationEdit {
        let edit = DictationEdit(delete: written.count)
        freeze(transcript: transcript)
        return edit
    }

    /// The transcript after its first `frozen` words, as it was said.
    static func live(_ transcript: String, after frozen: Int) -> String {
        var rest = Substring(transcript)
        for _ in 0..<frozen {
            rest = rest.drop { $0.isWhitespace }.drop { !$0.isWhitespace }
        }
        return String(rest.drop { $0.isWhitespace })
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// `words` with the leading space and first capital of `old`.
    static func rejoined(_ words: String, like old: String) -> String {
        guard let first = words.first else { return "" }
        let space = old.first?.isWhitespace == true ? " " : ""
        let capital = old.first { !$0.isWhitespace }?.isUppercase == true
        return space + (capital ? first.uppercased() + words.dropFirst() : words)
    }

    /// `words` as they go in after `context`: a space between them unless the context
    /// ends with one, and a capital at a sentence start.
    static func joined(_ words: String, after context: String) -> String {
        guard let first = words.first else { return "" }
        let space = context.isEmpty || context.last?.isWhitespace == true ? "" : " "
        let start = context.trimmingCharacters(in: .whitespaces)
        let sentenceStart = start.isEmpty || start.last.map { ".!?\n".contains($0) } == true
        let text = sentenceStart ? first.uppercased() + words.dropFirst() : words
        return space + text
    }
}
