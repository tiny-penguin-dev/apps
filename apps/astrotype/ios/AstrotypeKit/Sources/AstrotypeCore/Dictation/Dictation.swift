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
    /// The URL the keyboard opens when the mic is off.
    public static let openURL = "astrotype://dictate"
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
public enum DictationPress {
    public static let holdAfter: TimeInterval = 0.3

    public static func how(heldFor seconds: TimeInterval) -> DictationHow {
        seconds < holdAfter ? .tap : .hold
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
    public mutating func update(transcript: String, before: String) -> DictationEdit {
        guard before.hasSuffix(written) else {
            freeze(transcript: transcript)
            return .none
        }
        let context = String(before.dropLast(written.count))
        let wanted = Self.joined(Self.live(transcript, after: frozen), after: context)
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
