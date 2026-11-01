import Foundation

/// Strokes written so far, in order. Strokes come in with `t` on any shared
/// clock; `strokes` rebases them so the first touch is `t = 0`.
public struct Recording: Sendable, Equatable {
    private var raw: [[StrokePoint]] = []

    public init() {}

    public var isEmpty: Bool { raw.isEmpty }
    public var count: Int { raw.count }

    public mutating func add(_ stroke: [StrokePoint]) {
        guard !stroke.isEmpty else { return }
        raw.append(stroke)
    }

    public mutating func removeLast() {
        if !raw.isEmpty { raw.removeLast() }
    }

    /// Drops the first `n` strokes (words that have been locked in).
    public mutating func removeFirst(_ n: Int) {
        raw.removeFirst(min(n, raw.count))
    }

    public mutating func removeAll() {
        raw.removeAll()
    }

    /// Seconds since the last stroke ended, on the same clock as the strokes.
    public func idle(at now: Double) -> Double? {
        raw.last?.last.map { now - $0.t }
    }

    public var strokes: [[StrokePoint]] {
        guard let t0 = raw.first?.first?.t else { return [] }
        return raw.map { $0.map { StrokePoint(x: $0.x, y: $0.y, t: $0.t - t0) } }
    }

    public var lifts: [Double] { Features.lifts(raw) }
}
