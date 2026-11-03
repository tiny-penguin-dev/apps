import Foundation

/// Anonymous counts and timings (docs/telemetry.md). The app's live one sends to
/// Sentry; the keyboard extension never has one (its readings go through the app,
/// `KeyboardHealth`). Names are lowercase and dotted;
/// attributes are small fixed values, never anything typed.
public protocol Metrics: Sendable {
    func count(_ name: String, _ attributes: [String: String])
    /// Counts several at once, like the words in a session.
    func count(_ name: String, by amount: Int, _ attributes: [String: String])
    func duration(_ name: String, seconds: Double)
    /// A current value, like a speed test's words per minute.
    func gauge(_ name: String, value: Double, _ attributes: [String: String])
    /// An amount of memory in MB, like the keyboard's peak, as a distribution.
    func size(_ name: String, megabytes: Double)
}

public extension Metrics {
    func count(_ name: String) { count(name, [:]) }
    func gauge(_ name: String, value: Double) { gauge(name, value: value, [:]) }
}

/// Remembers what was sent, for tests.
public final class RecordingMetrics: Metrics, @unchecked Sendable {
    public struct Entry: Equatable, Sendable {
        public var name: String
        public var attributes: [String: String]
        public var seconds: Double?
        public var value: Double?
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    public init() {}

    public var sent: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    public func count(_ name: String, _ attributes: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        entries.append(Entry(name: name, attributes: attributes, seconds: nil, value: nil))
    }

    public func count(_ name: String, by amount: Int, _ attributes: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        entries.append(Entry(name: name, attributes: attributes, seconds: nil, value: Double(amount)))
    }

    public func duration(_ name: String, seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        entries.append(Entry(name: name, attributes: [:], seconds: seconds, value: nil))
    }

    public func gauge(_ name: String, value: Double, _ attributes: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        entries.append(Entry(name: name, attributes: attributes, seconds: nil, value: value))
    }

    public func size(_ name: String, megabytes: Double) {
        lock.lock(); defer { lock.unlock() }
        entries.append(Entry(name: name, attributes: [:], seconds: nil, value: megabytes))
    }
}
