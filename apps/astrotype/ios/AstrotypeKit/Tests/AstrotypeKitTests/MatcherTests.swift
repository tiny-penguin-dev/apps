import Foundation
import Testing
@testable import AstrotypeCore

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

    /// Split (the Duo open): G is on both halves, so the right thumb swipes "high"
    /// through the right half's own G.
    @Test func aSplitKeyboardSwipesThroughTheRightHalfsG() {
        let layout = Layout.qwerty(width: 951, split: true)
        var composer = Composer(dictionary: Synth.lexicon, layout: layout)
        let points = Geometry.walk("high".map { c in
            let frame = layout.frame(of: .letter(c), on: .right)!
            return CGPoint(x: frame.midX, y: frame.midY)
        }, step: 6)
        #expect(points.allSatisfy { layout.side(at: $0) == .right })
        _ = composer.touchDown(id: 1, at: points[0], time: 0)
        for (i, point) in points.enumerated().dropFirst() {
            _ = composer.touchMoved(id: 1, to: point, time: 0.3 * Double(i) / Double(points.count))
        }
        _ = composer.touchUp(id: 1, at: points[points.count - 1], time: 0.3)
        #expect(composer.state.openWord?.lowercased() == "high")
    }

    /// With the extra letters, "went" is the left thumb's w-e and the right thumb's
    /// n-t through the right half's own T.
    @Test func extraLettersLetAThumbSwipeAcrossTheMiddle() {
        let layout = Layout.qwerty(width: 951, split: true, extraLetters: true)
        var composer = Composer(dictionary: Synth.lexicon, layout: layout)
        func swipe(_ letters: String, _ side: Side, id: Int, from start: TimeInterval) {
            let points = Geometry.walk(letters.map { c in
                let frame = layout.frame(of: .letter(c), on: side)!
                return CGPoint(x: frame.midX, y: frame.midY)
            }, step: 6)
            #expect(points.allSatisfy { layout.side(at: $0) == side })
            _ = composer.touchDown(id: id, at: points[0], time: start)
            for (i, point) in points.enumerated().dropFirst() {
                _ = composer.touchMoved(id: id, to: point, time: start + 0.3 * Double(i) / Double(points.count))
            }
            _ = composer.touchUp(id: id, at: points[points.count - 1], time: start + 0.3)
        }
        swipe("we", .left, id: 1, from: 0)
        swipe("nt", .right, id: 2, from: 0.35)
        #expect(composer.state.openWord?.lowercased() == "went")
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
        // Spaced out, the taps mean what they say (with no real word put in for them).
        composer.settings.strictness = 0
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

/// features/smart-matching Phase A: the words before the open one rank the guesses.
@Suite struct ContextMatcherTests {
    static let english: Language = {
        do { return try Language.bundled("en") } catch { fatalError("English is missing from the package: \(error)") }
    }()

    static func composer() -> Composer {
        Composer(language: english, layout: Synth.layout, settings: Replay.settings)
    }

    /// One straight swipe p→o→t fits "put", "pot" and "pit" alike: the sentence before
    /// it (set by the host before the touch, as the field is) decides.
    @Test func theSentenceDecidesAnAmbiguousSwipe() {
        var composer = Self.composer()
        Synth.swipe(&composer, "pot")
        #expect(composer.state.openWord == "put")
        composer = Self.composer()
        composer.setContext(before: "I left it on the ")
        Synth.swipe(&composer, "pot")
        #expect(composer.state.openWord == "pot")
        composer = Self.composer()
        composer.setContext(before: "Where do I ")
        Synth.swipe(&composer, "pot")
        #expect(composer.state.openWord == "put")
    }

    @Test func aStrongPairOutranksTheDictionaryOrder() {
        var composer = Self.composer()
        Synth.swipe(&composer, "our")
        #expect(composer.state.openWord == "or")
        composer = Self.composer()
        composer.setContext(before: "Thanks to ")
        Synth.swipe(&composer, "our")
        #expect(composer.state.openWord == "our")
    }

    @Test func contextRanksTapCompletions() {
        var composer = Self.composer()
        composer.setContext(before: "thank ")
        Synth.taps(&composer, "yo")
        guard case .guesses(let words, let chosen) = composer.state.bar else { Issue.record("no guesses"); return }
        #expect(words[chosen] == "yo", "taps type exactly")
        #expect(words.contains("you"))
    }

    @Test func noContextOrNoModelChangesNothing() {
        var plain = Synth.composer()
        Synth.swipe(&plain, "pot")
        var english = Self.composer()
        Synth.swipe(&english, "pot")
        #expect(plain.state.bar == english.state.bar)
        english.setContext(before: "yes, ")
        #expect(plain.state.bar == english.state.bar)
        plain.setContext(before: "on the ")
        #expect(plain.state.openWord == "put", "no model, no change")
    }

    @Test func aBonusIsBoundedSoShapeStillWins() {
        var builder = NgramModel.Builder()
        builder.add(previous: "very", word: "were", count: 1000)
        let model = try! NgramModel(data: builder.build())
        let language = Language(code: "test", lexicon: Synth.lexicon, ngrams: model)
        var composer = Composer(language: language, layout: Synth.layout, settings: Replay.settings)
        composer.setContext(before: "very ")
        Synth.swipe(&composer, "store")
        #expect(composer.state.openWord == "store")
    }
}

/// Long words: a long swipe crosses many keys and cuts many corners, so the search must
/// not need every letter to be a key it crossed cleanly, or short words win by default.
@Suite struct LongWordTests {
    /// Sloppy swipes (aims off by 0.35 key widths) of common long words: most come out
    /// right (14 of these 20; 7 when every letter had to be a key the swipe crossed).
    @Test func sloppyLongSwipesMostlyComeOutRight() throws {
        let words = ["everything", "understand", "department", "themselves", "production",
                     "management", "difference", "population", "completely", "individual",
                     "particular", "additional", "association", "interesting", "immediately",
                     "significant", "established", "responsible", "application", "conversation"]
        var right = 0
        var misses: [String] = []
        for (index, word) in words.enumerated() {
            var typing = SyntheticTyping(layout: .qwerty(width: 390), noise: 0.35, seed: UInt64(index + 1))
            let outcome = try Replay.run(typing.record([word]), language: ContextMatcherTests.english)
            if outcome.firstGuesses == 1 { right += 1 } else { misses.append("\(word) → \(outcome.words.first?.guesses ?? [])") }
        }
        #expect(right >= 13, "\(right) of \(words.count); misses: \(misses)")
    }
}
