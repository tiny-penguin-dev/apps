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
        #expect(fast.rate >= neat.rate - 0.03, "\(fast.misses)")
    }

    /// Both thumbs swiping at once ("girls": the right thumb g-i-l while the left swipes
    /// r-s), the way Gabriel types: 45% before the matcher read the swipes together.
    @Test func bothThumbsSwipingAtOnce() {
        let together = Self.measure(.together(wobble: 0.03), noise: 0.2)
        print(Self.line("both swiping at once", together))
        #expect(together.rate >= 0.93, "\(together.misses)")
    }

    /// Two-thumb words take no longer than one swipe's bound (`candidatesAreFast`).
    @Test func twoThumbWordsAreFast() {
        let matcher = Matcher(language: ContextMatcherTests.english, layout: Synth.layout)
        var pieces: [[Piece]] = []
        for thumbs in [SyntheticTyping.Thumbs.two(wobble: 0.04), .together(wobble: 0.03)] {
            var typing = SyntheticTyping(layout: Synth.layout, noise: 0.2, thumbs: thumbs, seed: 8)
            for word in Self.words.prefix(40) { pieces.append(Self.pieces(of: typing.record([word]))) }
        }
        _ = matcher.candidates(for: pieces[0])
        let mean = MatcherTests.fastestMean(of: pieces, matcher)
        print("matcher, two thumbs: \(String(format: "%.2f", mean)) ms per word (debug, \(pieces.count) words)")
        #expect(mean < 20, "mean \(mean) ms")
    }

    /// The pieces of the one word in a recording, as the keyboard made them.
    static func pieces(of recording: PracticeRecording) -> [Piece] {
        let layout = Layout.qwerty(width: recording.layoutWidth, split: recording.split, height: recording.layoutHeight)
        var composer = Composer(language: ContextMatcherTests.english, layout: layout, settings: Replay.settings)
        var events: [(time: TimeInterval, order: Int, id: Int, point: CGPoint)] = []
        for touch in recording.touches {
            for (i, p) in touch.points.enumerated() {
                let order = i == 0 ? 2 : i == touch.points.count - 1 ? 0 : 1
                events.append((p[2], order, touch.id, CGPoint(x: p[0] * layout.width, y: p[1] * layout.height)))
            }
        }
        events.sort { $0.time == $1.time ? $0.order < $1.order : $0.time < $1.time }
        for event in events {
            switch event.order {
            case 2: _ = composer.touchDown(id: event.id, at: event.point, time: event.time)
            case 1: _ = composer.touchMoved(id: event.id, to: event.point, time: event.time)
            default: _ = composer.touchUp(id: event.id, at: event.point, time: event.time)
            }
        }
        return composer.pieces
    }

    /// The words Gabriel swiped with both thumbs at once on the Duo (3 Nov 2026), as
    /// the keyboard recorded them.
    @Test func gabrielsSwipesTogether() throws {
        for (file, word) in [("together-girls-1", "girls"), ("together-girls-2", "girls"), ("together-find", "find")] {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(file).json")
            let shared = try JSONDecoder().decode(SharedWord.self, from: Data(contentsOf: url))
            let outcome = try Replay.run(shared, language: ContextMatcherTests.english)
            #expect(outcome.words.first?.guesses.first == word, "\(file): \(outcome.words.first?.guesses ?? [])")
        }
    }
}

/// A word typed in two halves, one thumb after the other, is the word, not two words
/// with a missed space ("afternoon", not "after noon").
@Suite struct TwoThumbCompoundTests {
    @Test func aCompoundWordIsNotSplit() {
        for (first, second, word) in [("after", "non", "afternoon"), ("everyda", "y", "everyday"), ("some", "one", "someone"), ("with", "out", "without")] {
            var composer = ContextMatcherTests.composer()
            let rest: Synth.Stroke = second.count == 1 ? .tap(second.first!, id: 2, at: 0.6) : .swipe(second, id: 2, from: 0.6, to: 1.0)
            Synth.play(&composer, [.swipe(first, id: 1, from: 0, to: 0.5), rest])
            #expect(composer.state.openWord == word, "\(first)|\(second): \(composer.state.bar)")
        }
    }
}

/// Where a tap landed counts: a tap inside "g" but off its centre, then "ather"
/// swiped, is "gather" (it was "father", the commoner word a neighbour away).
@Suite struct TapPlaceTests {
    static func guess(tapAt offset: Double) -> String? {
        let unit = Synth.layout.frame(of: .letter("q"))!.width
        var composer = ContextMatcherTests.composer()
        let g = Synth.center("g")
        let point = CGPoint(x: g.x - offset * unit, y: g.y)
        _ = composer.touchDown(id: 1, at: point, time: 0)
        _ = composer.touchUp(id: 1, at: point, time: 0.08)
        Synth.play(&composer, [.swipe("ather", id: 2, from: 0.2, to: 0.6)])
        return composer.state.openWord
    }

    @Test func aTapInsideItsKeyKeepsItsLetter() {
        #expect(Self.guess(tapAt: 0.2) == "gather")
        #expect(Self.guess(tapAt: 0.35) == "gather")
        // Over the edge, on "f": the letter it landed on.
        #expect(Self.guess(tapAt: 0.6) == "father")
    }
}
