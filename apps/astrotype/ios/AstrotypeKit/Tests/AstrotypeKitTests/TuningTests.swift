import Foundation
import Testing
@testable import AstrotypeCore

/// features/smart-matching Phase D: the practice prompts, near-miss keys, the synthetic
/// benchmark and the tuning search.
@Suite struct TuningTests {
    static let english = ContextMatcherTests.english

    @Test func promptsAreCommonTypeableAndRepeatable() {
        var a = PracticeWords(language: Self.english, seed: 7)
        var b = PracticeWords(language: Self.english, seed: 7)
        let first = (0..<60).map { _ in a.next() }
        #expect(first == (0..<60).map { _ in b.next() })
        // No prompt twice within the memory.
        #expect(Set(first.prefix(40)).count == 40)
        for prompt in first {
            let words = prompt.split(separator: " ").map(String.init)
            #expect((1...3).contains(words.count), "\(prompt)")
            #expect(words.allSatisfy(PracticeWords.isTypeable), "\(prompt)")
            #expect(words.allSatisfy { Self.english.lexicon.contains($0) }, "\(prompt)")
        }
        #expect(!PracticeWords.isTypeable("dont"))
        #expect(!PracticeWords.isTypeable("x"))
        #expect(PracticeWords.isTypeable("i"))
    }

    /// A swipe for "the" whose end slid past "e" onto "r" still finds "the": "r" was
    /// crossed, "e" was close, and the path decides.
    @Test func aSwipeThatEndsOnTheNextKeyStillFindsTheWord() {
        let e = Synth.center("e"), r = Synth.center("r")
        let end = CGPoint(x: e.x + (r.x - e.x) * 0.6, y: e.y)
        #expect(Synth.layout.key(at: end) == .letter("r"))
        let points = Geometry.walk([Synth.center("t"), Synth.center("h"), end], step: 6)
        var composer = Synth.composer()
        _ = composer.touchDown(id: 1, at: points[0], time: 0)
        for (i, point) in points.enumerated().dropFirst() { _ = composer.touchMoved(id: 1, to: point, time: 0.3 * Double(i) / Double(points.count)) }
        _ = composer.touchUp(id: 1, at: points[points.count - 1], time: 0.3)
        #expect(composer.state.openWord == "the")

        // With stand-ins off, the old matcher could not reach it.
        composer = Synth.composer()
        composer.matcher.nearRadius = 0
        _ = composer.touchDown(id: 1, at: points[0], time: 0)
        for (i, point) in points.enumerated().dropFirst() { _ = composer.touchMoved(id: 1, to: point, time: 0.3 * Double(i) / Double(points.count)) }
        _ = composer.touchUp(id: 1, at: points[points.count - 1], time: 0.3)
        #expect(composer.state.openWord != "the")
    }

    @Test func cleanSyntheticTypingReplaysAlmostPerfectly() throws {
        var typing = SyntheticTyping(layout: Synth.layout, noise: 0, seed: 3)
        let words = ["going", "to", "the", "store", "thank", "you", "so", "much", "see", "you", "soon"]
        let recording = typing.record(words)
        #expect(recording.commits.map(\.word) == words)
        let outcome = try Replay.run(recording, language: Self.english)
        #expect(outcome.firstGuessRate >= 0.9, "\(outcome.misses)")
    }

    @Test func noisierTypingMissesMore() {
        var prompts = PracticeWords(language: Self.english, seed: 5)
        var text: [String] = []
        while text.count < 60 { text += prompts.next().split(separator: " ").map(String.init) }
        func rate(_ noise: Double) -> Double {
            var typing = SyntheticTyping(layout: Synth.layout, noise: noise, seed: 9)
            let items = SharedWord.words(of: typing.record(text)).map(Replay.Item.word)
            return Replay.report(items, language: Self.english).firstGuessRate
        }
        #expect(rate(0.05) > rate(0.4))
    }

    @Test func theSearchOnlyEverImproves() {
        var typing = SyntheticTyping(layout: Synth.layout, noise: 0.2, seed: 4)
        let recording = typing.record(["we", "will", "see", "if", "the", "store", "is", "open", "today"])
        let items = SharedWord.words(of: recording).map(Replay.Item.word)
        let steps = Tuning.search(items, language: Self.english, rounds: 1)
        #expect(steps.first?.weights == Matcher.Weights())
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0.score < $1.score })
        #expect(steps.last!.words == 9)
    }

    @Test func weightsRoundTripThroughTheMatcher() {
        var matcher = Matcher(language: Self.english, layout: Synth.layout)
        let weights = Matcher.Weights(path: 1, prior: 0.09, context: 0.2, length: 0.1, near: 0.3, standIn: 0.25)
        matcher.weights = weights
        #expect(matcher.weights == weights)
        #expect(matcher.priorWeight == 0.09 && matcher.nearRadius == 0.3 && matcher.nearPenalty == 0.25)
    }
}
