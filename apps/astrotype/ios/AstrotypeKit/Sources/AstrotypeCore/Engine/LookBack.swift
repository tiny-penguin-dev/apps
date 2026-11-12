import Foundation

/// Looking back at a word once the next one is in (features/look-back): which of its
/// readings fits best with the word that came after it.
///
///     // "thai" went in, then "is": "this is" fits far better.
///     LookBack.choose(readings: [("thai", -1.1), ("this", -1.3)], current: 0,
///                     margin: LookBack.margin) { reading in bonus("is", after: reading) }
///     // 1
///
/// Each reading's score (how it matched the swipe or taps and the words before it) gets
/// how well the next word follows it (`follow`, already weighted as score). Another
/// reading wins only by at least `margin`, so a close call keeps what was written.
public enum LookBack {
    /// How much better, in score, another reading must fit to replace the one written:
    /// a word's readings are a few tenths apart, and the next word's say is worth at
    /// most 0.72 (`Matcher.modelWeight` times `NgramModel.maximumBonus`). Set from
    /// `LookBackTests.measure`.
    public static let margin = 0.3

    /// The index of the reading to swap to, nil to keep `current`. `follow` returns how
    /// well the next word follows a reading, nil when that can't be told; a reading it
    /// can't tell about is never swapped to, and nothing is when it can't tell about
    /// `current`.
    public static func choose(readings: [Candidate], current: Int, margin: Double,
                              follow: (String) -> Double?) -> Int? {
        guard readings.indices.contains(current), readings.count > 1,
              let kept = follow(readings[current].word) else { return nil }
        let base = readings[current].score + kept
        var best: (index: Int, total: Double)?
        for (index, reading) in readings.enumerated() where index != current {
            guard let bonus = follow(reading.word) else { continue }
            let total = reading.score + bonus
            if total > (best?.total ?? -.infinity) { best = (index, total) }
        }
        guard let best, best.total - base >= margin else { return nil }
        return best.index
    }
}
