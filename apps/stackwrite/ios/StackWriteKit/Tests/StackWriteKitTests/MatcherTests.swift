import Foundation
import Testing
@testable import StackWriteCore

@Suite struct MatcherTests {
    /// BUILD.md Phase 2: the first guess is right for 9 of 10 words in a 50-word fixture.
    @Test func firstGuessIsRightForNineOfTen() {
        var misses: [String] = []
        for fixture in Synth.fixtures {
            var composer = Synth.composer()
            Synth.swipe(&composer, fixture.swipe)
            if composer.state.openWord != fixture.word {
                misses.append("\(fixture.word) → \(composer.state.bar)")
            }
        }
        #expect(Synth.fixtures.count == 50)
        #expect(misses.count <= 5, "misses: \(misses)")
    }

    /// BUILD.md Phase 2: a candidate list takes under 5 ms on a phone. Here, in a debug
    /// build on the CI machine, the bound is loose; the phone's number goes in BUILD.md.
    @Test func candidatesAreFast() {
        let matcher = Matcher(dictionary: Synth.lexicon, layout: Synth.layout)
        var pieces: [[Piece]] = []
        for fixture in Synth.fixtures {
            var composer = Synth.composer()
            Synth.swipe(&composer, fixture.swipe)
            pieces.append(composer.pieces)
        }
        _ = matcher.candidates(for: pieces[0]) // warm up
        let start = Date()
        for p in pieces { _ = matcher.candidates(for: p, limit: 3) }
        let mean = Date().timeIntervalSince(start) / Double(pieces.count) * 1000
        print("matcher: \(String(format: "%.2f", mean)) ms per word (debug, \(pieces.count) words)")
        #expect(mean < 20, "mean \(mean) ms")
    }

    @Test func swipingThereWritesThere() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there")
        #expect(composer.state.openWord == "there")
    }

    @Test func aSwipeCanDoubleALetter() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "helo")
        #expect(composer.state.openWord == "hello")
        composer = Synth.composer()
        Synth.swipe(&composer, "cofe")
        #expect(composer.state.openWord == "coffee")
    }

    @Test func tapsTypeExactlyAndOfferCompletions() {
        var composer = Synth.composer()
        Synth.taps(&composer, "the")
        guard case .guesses(let words, let chosen) = composer.state.bar else { Issue.record("no guesses"); return }
        #expect(words[chosen] == "the")
        #expect(words.count == 3)
        #expect(words.dropFirst().allSatisfy { $0.hasPrefix("the") && $0.count > 3 })

        composer = Synth.composer()
        Synth.taps(&composer, "someth")
        guard case .guesses(let more, _) = composer.state.bar else { Issue.record("no guesses"); return }
        #expect(more.first == "someth")
        #expect(more.contains("something"))
    }

    @Test func unknownTapsStillType() {
        var composer = Synth.composer()
        Synth.taps(&composer, "flotilla")
        #expect(composer.state.openWord == "flotilla")
    }

    @Test func nothingMatchingFallsBackToTheEndsOfTheSwipe() {
        let tiny = Lexicon(entries: [.init(word: "the", frequency: 10), .init(word: "there", frequency: 5)])
        var composer = Composer(dictionary: tiny, layout: Synth.layout)
        composer.settings.autoCapitalize = false
        Synth.swipe(&composer, "qwp")
        #expect(composer.state.openWord == "qp")
    }

    @Test func forgottenWordsSinkAndLearnedWordsRise() {
        var learned = LearnedWords()
        learned.forget("there")
        var composer = Synth.composer()
        Synth.swipe(&composer, "there")
        let plain = Matcher(dictionary: Synth.lexicon, layout: Synth.layout).candidates(for: composer.pieces)
        let forgotten = Matcher(dictionary: Synth.lexicon, layout: Synth.layout, learned: learned).candidates(for: composer.pieces)
        #expect(plain.first?.word == "there")
        #expect(forgotten.first?.word != "there")

        var boosted = LearnedWords()
        boosted.boost("three")
        boosted.boost("three")
        let risen = Matcher(dictionary: Synth.lexicon, layout: Synth.layout, learned: boosted).candidates(for: composer.pieces)
        #expect(risen.first?.word == "three")
    }
}
