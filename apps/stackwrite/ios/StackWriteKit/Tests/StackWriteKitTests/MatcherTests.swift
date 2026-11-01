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

    // MARK: Two thumbs (Phase 3)

    /// DESIGN.md "Try it": left taps s and e, right swipes o-m and t-h-i-n-g, overlapping.
    @Test func twoThumbsTypeSomething() {
        var composer = Synth.composer()
        Synth.play(&composer, [
            .tap("s", id: 1, at: 0.00),
            .swipe("om", id: 2, from: 0.15, to: 0.45),
            .tap("e", id: 3, at: 0.40),
            .swipe("thing", id: 4, from: 0.55, to: 1.00),
        ])
        #expect(composer.state.openWord == "something")
        #expect(composer.pieces.count == 4)
    }

    /// A tap that lands while the other thumb's swipe is over a key doubles that letter.
    @Test func aTapInsideASwipeDoublesTheLetter() {
        var composer = Synth.composer()
        Synth.play(&composer, [.swipe("helo", id: 1, from: 0, to: 0.6), .tap("l", id: 2, at: 0.4)])
        #expect(composer.state.openWord == "hello")
        composer = Synth.composer()
        Synth.play(&composer, [.swipe("cofe", id: 1, from: 0, to: 0.6), .tap("f", id: 2, at: 0.3)])
        #expect(composer.state.openWord == "coffee")
    }

    /// Two taps that land within the swap window are read in the order that spells a word.
    @Test func tapsThatLandTogetherAreTriedBothWays() {
        var composer = Synth.composer()
        Synth.play(&composer, [.tap("h", id: 1, at: 0.00), .tap("t", id: 2, at: 0.06), .tap("e", id: 1, at: 0.30)])
        #expect(composer.state.openWord == "the")
        composer = Synth.composer()
        // Spaced out, the taps mean what they say.
        Synth.play(&composer, [.tap("h", id: 1, at: 0.00), .tap("t", id: 2, at: 0.20), .tap("e", id: 1, at: 0.40)])
        #expect(composer.state.openWord == "hte")
    }

    @Test func aTapJustAfterASwipeStartsCanComeFirst() {
        var composer = Synth.composer()
        Synth.play(&composer, [.swipe("hanks", id: 2, from: 0, to: 0.5), .tap("t", id: 1, at: 0.05)])
        #expect(composer.state.openWord == "thanks")
    }

    @Test func piecesKeepTheirTouchDownOrderOtherwise() {
        var composer = Synth.composer()
        Synth.play(&composer, [.swipe("key", id: 1, from: 0, to: 0.3), .swipe("board", id: 2, from: 0.25, to: 0.8)])
        #expect(composer.state.openWord == "keyboard")
    }

    @Test func orderingsSwapOnlyWithinTheWindow() {
        func piece(_ letter: Character, at time: TimeInterval) -> Piece {
            .tap(letter, at: Synth.center(letter), time: time)
        }
        #expect(Matcher.orderings(of: [piece("t", at: 0), piece("h", at: 0.5)], swapWindow: 0.12).count == 1)
        #expect(Matcher.orderings(of: [piece("t", at: 0), piece("h", at: 0.05)], swapWindow: 0.12).count == 2)
        #expect(Matcher.orderings(of: [piece("t", at: 0), piece("h", at: 0.05), piece("e", at: 0.1)], swapWindow: 0.12).count == 4)
    }
}
