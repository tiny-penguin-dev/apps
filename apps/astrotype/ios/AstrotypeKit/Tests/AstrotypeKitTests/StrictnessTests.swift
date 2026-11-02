import Foundation
import Testing
@testable import AstrotypeCore

/// Real words over letters that spell none (Gabriel, 2 Nov 2026: "Bhrg" for "bring").
/// Pecked letters give way to the nearest real word when the keyboard is sure enough
/// of it (`strictness`); a swipe that fits no word comes out as the nearest real word.
@Suite struct StrictnessTests {
    static func composer(strictness: Double = 0.8) -> Composer {
        var settings = Replay.settings
        settings.strictness = strictness
        return Composer(language: ContextMatcherTests.english, layout: Synth.layout, settings: settings)
    }

    /// Pecks `letters` and presses space: what went in.
    static func peck(_ letters: String, strictness: Double = 0.8) -> (word: String?, bar: [String]) {
        var composer = composer(strictness: strictness)
        let end = Synth.taps(&composer, letters)
        let effects = composer.press(.space, time: end + 0.1)
        let word = effects.compactMap { effect -> String? in if case .commit(let w) = effect { w } else { nil } }.first
        if case .fix(let words, _) = composer.state.bar { return (word, words) }
        return (word, word.map { [$0] } ?? [])
    }

    @Test func aSlipBecomesTheWord() {
        // t for r, a key over.
        let typed = Self.peck("bting")
        #expect(typed.word == "bring")
        // What was tapped stays in the bar, to put back.
        #expect(typed.bar.contains("bting"))
    }

    @Test func aMissedOrSwappedLetterBecomesTheWord() {
        #expect(Self.peck("brng").word == "bring")
        #expect(Self.peck("brign").word == "bring")
        #expect(Self.peck("hte").word == "the")
    }

    @Test func aRealWordIsLeftAlone() {
        // "fir" is a word: exact typing of a word always wins.
        #expect(Self.peck("fir").word == "fir")
    }

    @Test func lettersThatBeginAWordStayWhileTyping() {
        var composer = Self.composer()
        Synth.taps(&composer, "bri")
        #expect(composer.state.openWord == "bri")
    }

    @Test func atZeroWhatWasTappedGoesIn() {
        let typed = Self.peck("bting", strictness: 0)
        #expect(typed.word == "bting")
        #expect(typed.bar.contains("bring"))
    }

    @Test func atFullOnlyRealWordsGoIn() {
        let typed = Self.peck("bting", strictness: 1)
        #expect(typed.word == "bring")
        #expect(!typed.bar.contains("bting"))
        // Nothing near: nothing goes in rather than letters that are not a word.
        #expect(Self.peck("qzxqzv", strictness: 1).word == nil)
    }

    @Test func lettersFarFromAnyWordStayBelowFull() {
        // A name the keyboard does not know: no word is near, so it goes in as tapped.
        #expect(Self.peck("qzxqzv").word == "qzxqzv")
    }

    @Test func aSwipeThatFitsNoWordBecomesARealWord() {
        // Two swipes in an order no word's keys follow: the old fallback typed the
        // keys they started and ended on ("bhrg").
        var composer = Self.composer()
        Synth.play(&composer, [.swipe("bnh", id: 1, from: 0, to: 0.2), .swipe("rtg", id: 2, from: 0.4, to: 0.6)])
        let word = composer.state.openWord?.lowercased()
        #expect(word != nil)
        #expect(word.map { ContextMatcherTests.english.lexicon.contains($0) } == true)
    }

    @Test func confidenceFollowsTheScoreGap() {
        let matcher = Matcher(language: ContextMatcherTests.english, layout: Synth.layout)
        let a = Candidate(word: "a", score: -1), b = Candidate(word: "b", score: -1)
        #expect(abs(matcher.confidence(of: a, over: b) - 0.5) < 1e-9)
        #expect(matcher.confidence(of: Candidate(word: "a", score: -0.5), over: b) > 0.95)
    }

    @Test func nearestWordsAreQuick() {
        let matcher = Matcher(language: ContextMatcherTests.english, layout: Synth.layout)
        let start = Date()
        for word in ["bting", "qwertyuiop", "abcdefghij", "thrre", "becuase"] {
            _ = matcher.nearestWords(to: word, points: [], limit: 3)
        }
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(matcher.nearestWords(to: "becuase", points: [], limit: 1).first?.word == "because")
    }

    @Test func oldSettingsReadAsEightyPercent() throws {
        let old = #"{"version":1,"autospace":true}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(KeyboardSettings.self, from: old)
        #expect(settings.wordStrictness == 0.8)
        var strict = settings
        strict.wordStrictness = 1
        #expect(strict.composerSettings().strictness == 1)
    }

    /// A word learned when it went in and deleted straight away was a slip: forgotten.
    @Test func deletingAWordJustLearnedForgetsIt() {
        // Swipe-left delete right after the word went in.
        var composer = Self.composer(strictness: 0)
        var t = Synth.taps(&composer, "qzxqzv")
        #expect(composer.press(.space, time: t + 0.1).contains(.learn("qzxqzv")))
        #expect(composer.deleteWord(time: t + 0.3).contains(.unlearn("qzxqzv")))

        // Backspace into it and on through every letter.
        composer = Self.composer(strictness: 0)
        t = Synth.taps(&composer, "qzxqzv")
        _ = composer.press(.space, time: t + 0.1)
        var effects: [Composer.Effect] = []
        for i in 0..<7 { effects += composer.press(.backspace, time: t + 0.2 + Double(i) * 0.1) }
        #expect(effects.filter { $0 == .unlearn("qzxqzv") }.count == 1)

        // Fixed by backspace and typed on: kept.
        composer = Self.composer(strictness: 0)
        t = Synth.taps(&composer, "qzxqzv")
        _ = composer.press(.space, time: t + 0.1)
        effects = composer.press(.backspace, time: t + 0.2)
        effects += composer.press(.backspace, time: t + 0.3)
        Synth.tap(&composer, "q", at: t + 0.4)
        effects += composer.press(.space, time: t + 0.6)
        #expect(!effects.contains(.unlearn("qzxqzv")))

        // A word it knew is never unlearned.
        composer = Self.composer(strictness: 0)
        t = Synth.taps(&composer, "the")
        _ = composer.press(.space, time: t + 0.1)
        #expect(!composer.deleteWord(time: t + 0.3).contains { if case .unlearn = $0 { true } else { false } })
    }

    /// A word of your own written once ranks like a rare word; written often, like a
    /// common one (Gabriel, 2 Nov 2026).
    @Test func learnedWordsRiseWithUse() throws {
        var words = LearnedWords()
        words.learn("zorb")
        #expect(words.uses(of: "zorb") == 1)
        let once = words.logPrior(of: "zorb", base: -10)
        for _ in 0..<19 { words.learn("zorb") }
        let often = words.logPrior(of: "zorb", base: -10)
        #expect(once == -10)
        #expect(often > -6 && often <= -3)
        // A slip deleted straight away takes its use back; the last one forgets it.
        words.unlearn("zorb")
        #expect(words.uses(of: "zorb") == 19)
        var single = LearnedWords()
        single.learn("zorb")
        single.unlearn("zorb")
        #expect(!single.contains("zorb"))

        // Words saved before uses were counted read as learned once.
        let old = #"{"entries":{"flotilla":{"weight":1,"changed":0},"penguin":{"weight":1.5,"changed":0},"zorb":{"weight":2.5,"changed":0}}}"#
        let read = try JSONDecoder().decode(LearnedWords.self, from: Data(old.utf8))
        #expect(read.uses(of: "flotilla") == 1 && read.weight(of: "flotilla") == 0 && read.contains("flotilla"))
        #expect(read.uses(of: "penguin") == 0 && read.isBoosted("penguin"))
        #expect(read.uses(of: "zorb") == 1 && read.isBoosted("zorb"))
    }

    @Test func aWordWrittenOnceDoesNotBeatTheDictionary() {
        // "brinng" fits a swipe for "bring" exactly as well (a doubled letter), so only
        // how common each is decides. Written once it stays behind the dictionary's…
        func first(after uses: Int) -> String? {
            var composer = Self.composer()
            var words = LearnedWords()
            for _ in 0..<uses { words.learn("brinng") }
            composer.learned = words
            Synth.swipe(&composer, "bring")
            #expect(composer.candidates.contains { $0.word == "brinng" })
            return composer.state.openWord
        }
        #expect(first(after: 1) == "bring")
        // …written often, it is the guess.
        #expect(first(after: 60) == "brinng")
    }
}
