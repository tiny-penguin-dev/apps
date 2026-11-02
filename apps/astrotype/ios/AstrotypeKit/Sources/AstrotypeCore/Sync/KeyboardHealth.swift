import Foundation

/// How the keyboard extension is doing, for catching memory regressions (PRODUCT.md
/// §10b): for each time the keyboard was shown, the most memory it used, the least it
/// had left before iOS's limit, and whether it closed normally. Numbers only, never
/// anything typed. The extension writes it to the App Group (with Full Access and
/// "Share anonymous usage data" on); the app sends it to Sentry and remembers how far
/// it got, so the keyboard itself never sends metrics.
public struct KeyboardHealth: Codable, Sendable, Equatable {
    public static let version = 1
    /// The most sessions kept; older ones drop off, sent or not.
    public static let limit = 30

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

        public init(started: Date, peakMB: Double, lowestHeadroomMB: Double, ended: Bool = false) {
            self.started = started
            self.peakMB = peakMB
            self.lowestHeadroomMB = lowestHeadroomMB
            self.ended = ended
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

    /// The keyboard went away normally.
    public mutating func end(footprintMB: Double, headroomMB: Double) {
        guard !(sessions.last?.ended ?? true) else { return }
        sample(footprintMB: footprintMB, headroomMB: headroomMB)
        sessions[sessions.count - 1].ended = true
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
    /// (MB) for each, and `keyboard.ended_while_showing` for each that did not close
    /// normally. Returns the newest start sent, for the next `toSend(after:)`.
    @discardableResult
    public static func report(_ sessions: [Session], to metrics: Metrics) -> Date? {
        for session in sessions {
            metrics.size("keyboard.memory_peak", megabytes: session.peakMB)
            metrics.size("keyboard.memory_headroom", megabytes: session.lowestHeadroomMB)
            if !session.ended { metrics.count("keyboard.ended_while_showing") }
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
