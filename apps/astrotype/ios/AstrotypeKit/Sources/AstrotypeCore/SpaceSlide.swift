import Foundation

/// A finger on space, deciding whether it is a tap or a slide that moves the cursor.
///
/// A quick tap drifts a little, and a slide used to start at the first 12 pt, so taps
/// moved the cursor instead of typing a space; at the end of the text that did nothing
/// at all (Gabriel, 6 Nov 2026). Now the finger has to stay down `holdTime` and travel
/// `startDistance` sideways before the slide starts. Once it has, every `step` further
/// is one more character, and the first step comes as the slide starts.
///
///     var slide = SpaceSlide(at: start, time: t)
///     let steps = slide.move(to: point, time: now)   // cursor steps since the last move
///     if !slide.isSliding { /* a tap: type the space when the finger lifts */ }
public struct SpaceSlide: Sendable {
    /// How long the finger stays down before it can slide.
    public static let holdTime: TimeInterval = 0.15
    /// How far sideways the finger travels before the slide starts.
    public static let startDistance: CGFloat = 20
    /// How far the finger travels for each further cursor step.
    public static let step: CGFloat = 12

    public let start: CGPoint
    public let startTime: TimeInterval
    /// The slide started: the finger lifting types no space.
    public private(set) var isSliding = false
    private var reported = 0

    public init(at start: CGPoint, time: TimeInterval) {
        self.start = start
        self.startTime = time
    }

    /// The finger moved to `point` at `time`: how many characters to move the cursor
    /// since the last call (negative is left).
    public mutating func move(to point: CGPoint, time: TimeInterval) -> Int {
        let dx = point.x - start.x
        let distance = abs(dx)
        if !isSliding {
            guard time - startTime >= Self.holdTime, distance >= Self.startDistance else { return 0 }
            isSliding = true
        }
        let magnitude = distance >= Self.startDistance ? 1 + Int((distance - Self.startDistance) / Self.step) : 0
        let steps = dx < 0 ? -magnitude : magnitude
        defer { reported = steps }
        return steps - reported
    }
}
