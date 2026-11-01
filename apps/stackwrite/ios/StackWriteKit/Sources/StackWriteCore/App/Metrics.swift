import Foundation

/// Anonymous counts and timings (docs/telemetry.md). The app's live one sends to
/// Sentry; the keyboard extension never has one. Names are lowercase and dotted;
/// attributes are small fixed values, never anything typed.
public protocol Metrics: Sendable {
    func count(_ name: String, _ attributes: [String: String])
    func duration(_ name: String, seconds: Double)
}

public extension Metrics {
    func count(_ name: String) { count(name, [:]) }
}

/// Remembers what was sent, for tests.
public final class RecordingMetrics: Metrics, @unchecked Sendable {
    public struct Entry: Equatable, Sendable {
        public var name: String
        public var attributes: [String: String]
        public var seconds: Double?
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
        entries.append(Entry(name: name, attributes: attributes, seconds: nil))
    }

    public func duration(_ name: String, seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        entries.append(Entry(name: name, attributes: [:], seconds: seconds))
    }
}
