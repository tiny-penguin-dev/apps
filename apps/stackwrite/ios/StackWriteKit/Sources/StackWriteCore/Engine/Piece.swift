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
    /// The letters the path crossed, in order, with runs of the same key collapsed.
    public var keys: [Character]
    /// A tap: lifted within the tap threshold of where it landed, on one key.
    public var isTap: Bool

    public init(id: Int, side: Side, start: TimeInterval, end: TimeInterval, points: [CGPoint], keys: [Character], isTap: Bool) {
        self.id = id
        self.side = side
        self.start = start
        self.end = end
        self.points = points
        self.keys = keys
        self.isTap = isTap
    }

    /// A tap on one letter.
    public static func tap(_ letter: Character, at point: CGPoint, side: Side = .left, time: TimeInterval = 0) -> Piece {
        Piece(id: 0, side: side, start: time, end: time + 0.08, points: [point], keys: [letter], isTap: true)
    }
}
