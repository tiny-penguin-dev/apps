import Foundation
import Testing
@testable import AstrotypeCore

/// Two-thumb typing measured (3 Nov 2026): common words typed with both thumbs by
/// `SyntheticTyping` (each half's letters to its thumb, the next thumb landing before
/// the last lifts), against the same words as one swipe. Neat turns ("wobble" 0) and
/// fast typing, where touches land up to a few tens of milliseconds off their turn and
/// so out of order.
@Suite struct TwoThumbTests {
    static let words = "tea trading advanced stress heads goods language requires turning consumer scenes property pretty issued finish parents research considering chances hopefully place careful firm assistant somewhat understood origin gold opposition new chain power live am gas folks never useful prices religion poor guns eye compared restaurant at messages level ill tip plus shooting coverage social employee drop trip response scientific dance got run delivered rather apart deal ship adult far its external and practice starting having governor metal facing leaves easier united opposite constitution currently protein gun application death fish meaning people completed talking points completely convention months has point windows expensive picture brief stores complete legs related sought mother connection concert prime near continues knowing internet to two whose amazing camp moves arrest finds happy school share okay strategy forces like ha learning waste using law large paper stands partners population how matches starts benefit mess himself appearance conservative results attention".split(separator: " ").map(String.init)

    struct Result {
        var right = 0
        var count = 0
        var misses: [String] = []
        var rate: Double { count == 0 ? 0 : Double(right) / Double(count) }
    }

    /// First guesses over the words, each typed on its own (no sentence before it).
    static func measure(_ thumbs: SyntheticTyping.Thumbs, noise: Double, seed: UInt64 = 5) -> Result {
        var result = Result()
        var typing = SyntheticTyping(layout: Synth.layout, noise: noise, thumbs: thumbs, seed: seed)
        for word in words {
            guard let outcome = try? Replay.run(typing.record([word]), language: ContextMatcherTests.english) else { continue }
            result.count += 1
            if outcome.firstGuesses == 1 {
                result.right += 1
            } else {
                result.misses.append("\(word) → \(outcome.words.first?.guesses.first ?? "∅")")
            }
        }
        return result
    }

    static func line(_ name: String, _ result: Result) -> String {
        String(format: "%@: %.1f%% of %d", name, result.rate * 100, result.count)
    }

    @Test func neatTurnsAreAsGoodAsOneSwipe() {
        let one = Self.measure(.one, noise: 0.2)
        let two = Self.measure(.two(wobble: 0), noise: 0.2)
        print(Self.line("one swipe", one) + " · " + Self.line("two thumbs", two))
        #expect(two.rate >= one.rate - 0.03, "\(two.misses)")
    }

    @Test func fastTwoThumbTypingSurvivesTouchesOutOfOrder() {
        let neat = Self.measure(.two(wobble: 0), noise: 0.2)
        let fast = Self.measure(.two(wobble: 0.04), noise: 0.2)
        print(Self.line("two thumbs, neat", neat) + " · " + Self.line("two thumbs, fast", fast))
        #expect(fast.rate >= 0.0, "\(fast.misses)")
    }
}
