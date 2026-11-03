import Foundation

/// How often the keyboard's first guess was the word the person kept, for one time the
/// keyboard was shown (PRODUCT.md §10b; the goal is 9 in 10). Counts only, never the
/// words. Swiped and pecked words are kept apart, since a pecked word's first guess is
/// usually just its letters.
///
/// A word counts as the first guess when it settled as the word the keyboard put first
/// on the bar: not fixed from the bar after it went in, and not a later guess picked
/// before. A word deleted and typed again is not seen as a miss, so the share reads a
/// little high.
public struct GuessTally: Codable, Sendable, Equatable {
    /// Swiped words, and how many of them went in as the first guess.
    public var swiped = 0
    public var swipedFirst = 0
    /// Pecked words (every touch a tap), and how many went in as the first guess.
    public var pecked = 0
    public var peckedFirst = 0
    /// Words typed with "Not it?" because the swipe missed them (features/missed-words).
    public var missed = 0

    public init(swiped: Int = 0, swipedFirst: Int = 0, pecked: Int = 0, peckedFirst: Int = 0, missed: Int = 0) {
        self.swiped = swiped
        self.swipedFirst = swipedFirst
        self.pecked = pecked
        self.peckedFirst = peckedFirst
        self.missed = missed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        swiped = try c.decodeIfPresent(Int.self, forKey: .swiped) ?? 0
        swipedFirst = try c.decodeIfPresent(Int.self, forKey: .swipedFirst) ?? 0
        pecked = try c.decodeIfPresent(Int.self, forKey: .pecked) ?? 0
        peckedFirst = try c.decodeIfPresent(Int.self, forKey: .peckedFirst) ?? 0
        missed = try c.decodeIfPresent(Int.self, forKey: .missed) ?? 0
    }

    public var words: Int { swiped + pecked }

    /// Counts a settled word. Returns false for one the keyboard made no guess for.
    @discardableResult
    public mutating func add(_ word: SettledWord) -> Bool {
        if word.missed { missed += 1 }
        guard let first = word.firstGuess else { return false }
        let right = first == word.word
        if word.pecked {
            pecked += 1
            if right { peckedFirst += 1 }
        } else {
            swiped += 1
            if right { swipedFirst += 1 }
        }
        return true
    }

    /// The least words in a session for its share to be sent as a gauge; fewer give a
    /// noisy share (the counts still go).
    public static let shareMinimum = 10

    /// Sends `guess.words` and `guess.first` (counts, `kind`: `swipe` or `tap`) for the
    /// words there were, so the share is `guess.first` over `guess.words`, and
    /// `guess.first_share` (a gauge, 0 to 100) for a kind with at least `shareMinimum`
    /// words, to read at a glance. `miss.saved` counts the words typed with "Not it?".
    public func report(to metrics: Metrics) {
        if missed > 0 { metrics.count("miss.saved", by: missed, [:]) }
        for (kind, words, first) in [("swipe", swiped, swipedFirst), ("tap", pecked, peckedFirst)] where words > 0 {
            metrics.count("guess.words", by: words, ["kind": kind])
            if first > 0 { metrics.count("guess.first", by: first, ["kind": kind]) }
            if words >= Self.shareMinimum {
                metrics.gauge("guess.first_share", value: Double(first) * 100 / Double(words), ["kind": kind])
            }
        }
    }
}
