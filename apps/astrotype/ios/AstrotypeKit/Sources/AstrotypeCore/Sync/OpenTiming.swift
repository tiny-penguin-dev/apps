import Foundation

/// How long the keyboard takes to open, for the typing log's `open` line: each step
/// from `viewDidLoad` to the keys on screen, in ms, so the slow one shows.
///
///     var timing = OpenTiming(now: uptime)
///     timing.step("telemetry", now: uptime)     // Sentry started
///     timing.step("model", now: uptime)         // settings, words, language
///     timing.line(now: uptime)                  // "telemetry 12 · model 40 · … · 180 ms in all"
public struct OpenTiming: Sendable {
    public private(set) var steps: [(name: String, millis: Int)] = []
    public let start: Double
    private var last: Double

    public init(now: Double) {
        start = now
        last = now
    }

    /// Ends the step called `name` now; it began when the step before ended.
    public mutating func step(_ name: String, now: Double) {
        steps.append((name, Self.millis(now - last)))
        last = now
    }

    /// "telemetry 12 · model 40 · keys 35 · layout 8 · 180 ms in all", with `notes`
    /// (work that ran off the main thread) after.
    public func line(now: Double, notes: [String] = []) -> String {
        var parts = steps.map { "\($0.name) \($0.millis)" }
        parts.append("\(Self.millis(now - start)) ms in all")
        return (parts + notes).joined(separator: " · ")
    }

    private static func millis(_ seconds: Double) -> Int { Int((seconds * 1000).rounded()) }
}
