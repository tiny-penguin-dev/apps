import Foundation

/// One touch from one thumb (PRODUCT.md §4): a tap on a key, or a swipe across a few.
/// Built by the `Composer` from the touch stream; read by the `Matcher`.
public struct Piece: Sendable, Equatable {
    /// The touch's identity while it is down, unique among open pieces.
    public var id: Int
    public var side: Side
    /// Touch-down and lift times, in the caller's clock (seconds).
    public var start: TimeInterval
    public var end: TimeInterval
    /// The touch's path, in keyboard coordinates.
    public var points: [CGPoint]
    /// When each point was reached, one per point (empty when unknown).
    public var times: [TimeInterval]
    /// The letters the path crossed, in order, with runs of the same key collapsed.
    public var keys: [Character]
    /// A tap: lifted within the tap threshold of where it landed, on one key.
    public var isTap: Bool
    /// Where the finger first touched, as the screen reported it; `points` are read
    /// through the person's thumb offsets (`PersonalIndex`). Nil when unknown (a piece made by hand).
    public var landing: CGPoint?

    public init(id: Int, side: Side, start: TimeInterval, end: TimeInterval, points: [CGPoint], times: [TimeInterval] = [], keys: [Character], isTap: Bool,
                landing: CGPoint? = nil) {
        self.id = id
        self.side = side
        self.start = start
        self.end = end
        self.points = points
        self.times = times
        self.keys = keys
        self.isTap = isTap
        self.landing = landing
    }

    /// A tap on one letter.
    public static func tap(_ letter: Character, at point: CGPoint, side: Side = .left, time: TimeInterval = 0) -> Piece {
        Piece(id: 0, side: side, start: time, end: time + 0.08, points: [point], times: [time], keys: [letter], isTap: true)
    }

    /// Whether `time` falls while this touch was down.
    func covers(_ time: TimeInterval) -> Bool {
        time > start && time < end
    }

    /// The index of the point the finger was at by `time`, when the times are known.
    func pointIndex(at time: TimeInterval) -> Int? {
        guard times.count == points.count, !times.isEmpty else { return nil }
        var index = 0
        while index + 1 < times.count, times[index + 1] <= time { index += 1 }
        return index
    }
}
