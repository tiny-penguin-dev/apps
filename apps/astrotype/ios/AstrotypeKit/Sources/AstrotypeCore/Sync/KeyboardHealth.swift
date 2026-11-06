import Foundation

/// How the keyboard extension is doing, for catching memory regressions (PRODUCT.md
/// §10b): for each time the keyboard was shown, the most memory it used, the least it
/// had left before iOS's limit, whether it closed normally, and how many words went in
/// as the first guess (`GuessTally`). Numbers only, never anything typed. The extension writes it to the App Group (with Full Access and
/// "Share anonymous usage data" on); the app sends it to Sentry and remembers how far
/// it got, so the keyboard itself never sends metrics.
public struct KeyboardHealth: Codable, Sendable, Equatable {
    public static let version = 1
    /// The most sessions kept; older ones drop off, sent or not.
    public static let limit = 30

    /// What was open or loaded while the keyboard was up, so a memory peak points at
    /// what caused it. Sent as one fixed label (`label(_:)`), never anything typed.
    public enum Part: String, Codable, Sendable, CaseIterable, Comparable {
        case emoji
        case emojiSearch = "emoji_search"
        case settings
        /// The Metal effects (sky or letters) are loaded.
        case metal

        public static func < (a: Part, b: Part) -> Bool {
            allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
        }
    }

    /// The parts as one attribute value: "emoji+settings", or "keys" for none.
    public static func label(_ parts: Set<Part>) -> String {
        parts.isEmpty ? "keys" : parts.sorted().map(\.rawValue).joined(separator: "+")
    }

    /// One time the keyboard was on screen.
    public struct Session: Codable, Sendable, Equatable {
        public var started: Date
        /// The most memory the extension used (its physical footprint), in MB.
        public var peakMB: Double
        /// The least memory left before iOS ends the extension, in MB.
        public var lowestHeadroomMB: Double
        /// The keyboard went away normally. False means it was ended while showing:
        /// a crash, or iOS's memory limit (which no crash report sees).
        public var ended: Bool
        /// How many words went in, and how many as the first guess.
        public var guesses: GuessTally
        /// What was open or loaded while it was up.
        public var parts: Set<Part>
        /// For one ended while showing: whether it crashed (a crash report went to
        /// Sentry) or not (iOS ended it, most likely for memory). Nil when unknown.
        public var crashed: Bool?

        public init(started: Date, peakMB: Double, lowestHeadroomMB: Double, ended: Bool = false,
                    guesses: GuessTally = GuessTally(), parts: Set<Part> = [], crashed: Bool? = nil) {
            self.started = started
            self.peakMB = peakMB
            self.lowestHeadroomMB = lowestHeadroomMB
            self.ended = ended
            self.guesses = guesses
            self.parts = parts
            self.crashed = crashed
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            started = try c.decode(Date.self, forKey: .started)
            peakMB = try c.decode(Double.self, forKey: .peakMB)
            lowestHeadroomMB = try c.decode(Double.self, forKey: .lowestHeadroomMB)
            ended = try c.decode(Bool.self, forKey: .ended)
            guesses = try c.decodeIfPresent(GuessTally.self, forKey: .guesses) ?? GuessTally()
            // Unknown parts (from a newer build) are dropped, not the whole session.
            let names = try c.decodeIfPresent([String].self, forKey: .parts) ?? []
            parts = Set(names.compactMap(Part.init(rawValue:)))
            crashed = try c.decodeIfPresent(Bool.self, forKey: .crashed)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(started, forKey: .started)
            try c.encode(peakMB, forKey: .peakMB)
            try c.encode(lowestHeadroomMB, forKey: .lowestHeadroomMB)
            try c.encode(ended, forKey: .ended)
            try c.encode(guesses, forKey: .guesses)
            try c.encode(parts.sorted().map(\.rawValue), forKey: .parts)
            try c.encodeIfPresent(crashed, forKey: .crashed)
        }

        private enum CodingKeys: String, CodingKey {
            case started, peakMB, lowestHeadroomMB, ended, guesses, parts, crashed
        }
    }

    public var version = KeyboardHealth.version
    /// Oldest first.
    public var sessions: [Session] = []

    public init(sessions: [Session] = []) {
        self.sessions = sessions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.version
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
    }

    /// The keyboard came on screen. A session left open before this one stays open:
    /// it was ended while showing.
    public mutating func begin(at date: Date, footprintMB: Double, headroomMB: Double) {
        sessions.append(Session(started: date, peakMB: footprintMB, lowestHeadroomMB: headroomMB))
        if sessions.count > Self.limit { sessions.removeFirst(sessions.count - Self.limit) }
    }

    /// A new reading for the open session. Returns whether its peak grew by at least
    /// `step` MB or its headroom shrank by as much, which is when it is worth writing.
    @discardableResult
    public mutating func sample(footprintMB: Double, headroomMB: Double, step: Double = 1) -> Bool {
        guard var last = sessions.last, !last.ended else { return false }
        let worth = footprintMB >= last.peakMB + step || headroomMB <= last.lowestHeadroomMB - step
        last.peakMB = max(last.peakMB, footprintMB)
        last.lowestHeadroomMB = min(last.lowestHeadroomMB, headroomMB)
        sessions[sessions.count - 1] = last
        return worth
    }

    /// Something was opened or loaded while the keyboard is up. Returns whether it is
    /// new for this session, which is when it is worth writing.
    @discardableResult
    public mutating func use(_ part: Part) -> Bool {
        guard var last = sessions.last, !last.ended, !last.parts.contains(part) else { return false }
        last.parts.insert(part)
        sessions[sessions.count - 1] = last
        return true
    }

    /// A new process started: a session still open was ended while showing. `crashed`
    /// says whether that process crashed (nil when unknown). Returns whether one was.
    @discardableResult
    public mutating func restarted(crashed: Bool?) -> Bool {
        guard let last = sessions.last, !last.ended, last.crashed == nil else { return false }
        sessions[sessions.count - 1].crashed = crashed
        return crashed != nil
    }

    /// The keyboard went away normally.
    public mutating func end(footprintMB: Double, headroomMB: Double) {
        guard !(sessions.last?.ended ?? true) else { return }
        sample(footprintMB: footprintMB, headroomMB: headroomMB)
        sessions[sessions.count - 1].ended = true
    }

    /// A word went in while the keyboard was showing (`GuessTally.add`). Returns whether
    /// it is worth writing now: every tenth word, so a keyboard ended while showing
    /// loses only a few.
    @discardableResult
    public mutating func settled(_ word: SettledWord) -> Bool {
        guard var last = sessions.last, !last.ended, last.guesses.add(word) else { return false }
        sessions[sessions.count - 1] = last
        return (last.guesses.words + last.guesses.next) % 10 == 0
    }

    /// The sessions the app should send now: started after `sent`, and finished. One
    /// still open counts as finished once it is `openFor` old, since it was never going
    /// to end normally. Stops at the first one that is not finished yet (the keyboard
    /// may still be up), so it goes next time with the ones after it.
    public func toSend(after sent: Date?, now: Date, openFor: TimeInterval = 10 * 60) -> [Session] {
        var due: [Session] = []
        for session in sessions where session.started > (sent ?? .distantPast) {
            guard session.ended || now.timeIntervalSince(session.started) >= openFor else { break }
            due.append(session)
        }
        return due
    }

    /// Sends `sessions` as metrics: `keyboard.memory_peak` and `keyboard.memory_headroom`
    /// (MB) for each, `keyboard.ended_while_showing` for each that did not close
    /// normally, and the session's words (`GuessTally.report`). The memory ones carry
    /// `parts` (what was open, `label(_:)`); the ended one also `how`: `crash`, `killed`
    /// (no crash, so most likely iOS's memory limit) or `unknown`. Returns the newest
    /// start sent, for the next `toSend(after:)`.
    @discardableResult
    public static func report(_ sessions: [Session], to metrics: Metrics) -> Date? {
        for session in sessions {
            let parts = ["parts": label(session.parts)]
            metrics.size("keyboard.memory_peak", megabytes: session.peakMB, parts)
            metrics.size("keyboard.memory_headroom", megabytes: session.lowestHeadroomMB, parts)
            if !session.ended {
                let how = session.crashed.map { $0 ? "crash" : "killed" } ?? "unknown"
                metrics.count("keyboard.ended_while_showing", parts.merging(["how": how]) { a, _ in a })
            }
            session.guesses.report(to: metrics)
        }
        return sessions.map(\.started).max()
    }
}

/// The keyboard's health as a file in the App Group: the extension writes, the app reads.
public struct FileKeyboardHealthStore: Sendable {
    private let file: JSONFile<KeyboardHealth>

    public init(url: URL) {
        file = JSONFile(url)
    }

    public func load() -> KeyboardHealth? { file.read() }
    public func save(_ health: KeyboardHealth) { file.write(health) }
}

/// Whether the person lets Astrotype share anonymous usage data, written by the app
/// (its Settings switch) to the App Group for the keyboard, which turns its crash
/// reports and readings on only with this on. No file means off.
public struct UsageSharing: Codable, Sendable, Equatable {
    public var enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    public static func load(from url: URL?) -> Bool {
        guard let url else { return false }
        return JSONFile<UsageSharing>(url).read()?.enabled ?? false
    }

    public static func save(_ enabled: Bool, to url: URL?) {
        guard let url else { return }
        JSONFile<UsageSharing>(url).write(UsageSharing(enabled: enabled))
    }
}
