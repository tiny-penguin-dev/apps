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

    /// At "Words only", letters with no word near them stay in the field as they are
    /// tapped, rather than vanishing mid-word (Gabriel, 7 Nov 2026: "overwritten",
    /// which the dictionary doesn't have, disappeared from "overwri" on).
    @Test func atFullLettersWithNothingNearStayWhileTyping() {
        var composer = Self.composer(strictness: 1)
        Synth.taps(&composer, "overwrit")
        #expect(composer.state.openWord == "overwrit")
    }

    /// At "Words only", a long made-up word swiped fast (two thumbs, short swipes) stays
    /// in the field and goes in on space, even once no word is near its keys (Gabriel,
    /// 9 Nov 2026: it vanished and every swipe after it typed nothing).
    @Test func atFullSwipesWithNothingNearStay() {
        var composer = Self.composer(strictness: 1)
        let swipes = ["kj", "dew", "ji", "de", "nji", "xdew", "nju", "dew", "juy", "de"]
        var t = 0.0
        for (i, keys) in swipes.enumerated() {
            Synth.play(&composer, [.swipe(keys, id: i + 1, from: t, to: t + 0.12)])
            t += 0.3
            #expect(composer.state.openWord?.isEmpty == false, "after \(i + 1) swipes")
        }
        let effects = composer.press(.space, time: t)
        #expect(effects.contains { if case .commit(let w) = $0 { !w.isEmpty } else { false } })
    }

    @Test func atZeroWhatWasTappedGoesIn() {
        let typed = Self.peck("bting", strictness: 0)
        #expect(typed.word == "bting")
        #expect(typed.bar.contains("bring"))
    }

    @Test func atFullOnlyRealWordsGoIn() {
        let typed = Self.peck("bting", strictness: 1)
        #expect(typed.word == "bring")
        // What was tapped stays last in the bar, to pick or to hold and learn
        // (Gabriel, 7 Nov 2026), but never goes in by itself.
        #expect(typed.bar.last == "bting")
        // Nothing near: a word it doesn't know, so the letters go in as typed.
        #expect(Self.peck("qzxqzv", strictness: 1).word == "qzxqzv")
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
        // A walk that forgot its budget takes many seconds; a debug build on a busy CI
        // runner, every suite going at once, took 1.06 s for these five (8 Nov 2026).
        #expect(Date().timeIntervalSince(start) < 3)
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

    /// A pecked word is learned when it settles (the next word starts, the keyboard
    /// goes away), so one fixed before that never is (Gabriel, 7 Nov 2026: "it's
    /// learning more than that when I type and correct a word").
    @Test func aWordIsLearnedOnlyOnceItSettles() {
        func learns(_ effects: [Composer.Effect]) -> [String] {
            effects.compactMap { if case .learn(let w) = $0 { w } else { nil } }
        }
        // Left in: learned as the next word starts.
        var composer = Self.composer(strictness: 0)
        var t = Synth.taps(&composer, "qzxqzv")
        var effects = composer.press(.space, time: t + 0.1)
        #expect(learns(effects).isEmpty)
        effects = Synth.tap(&composer, "a", at: t + 0.5)
        #expect(learns(effects) == ["qzxqzv"])

        // Swiped away right after it went in: never learned.
        composer = Self.composer(strictness: 0)
        t = Synth.taps(&composer, "qzxqzv")
        effects = composer.press(.space, time: t + 0.1)
        effects += composer.deleteWord(time: t + 0.3)
        effects += composer.keyboardWillHide()
        #expect(learns(effects).isEmpty)

        // Backspaced into and fixed ("qzxqzv" to "qzxqzq"): only the fix is learned.
        composer = Self.composer(strictness: 0)
        t = Synth.taps(&composer, "qzxqzv")
        effects = composer.press(.space, time: t + 0.1)
        effects += composer.press(.backspace, time: t + 0.2)
        effects += composer.press(.backspace, time: t + 0.3)
        Synth.tap(&composer, "q", at: t + 0.4)
        effects += composer.press(.space, time: t + 0.6)
        effects += composer.keyboardWillHide()
        #expect(learns(effects) == ["qzxqzq"])

        // Backspaced into and fixed to a real word: nothing is learned.
        composer = Self.composer(strictness: 0)
        t = Synth.taps(&composer, "helo")
        effects = composer.press(.space, time: t + 0.1)
        effects += composer.press(.backspace, time: t + 0.2)
        effects += composer.press(.backspace, time: t + 0.3)
        Synth.tap(&composer, "l", at: t + 0.4)
        Synth.tap(&composer, "o", at: t + 0.55)
        effects += composer.press(.space, time: t + 0.8)
        effects += composer.keyboardWillHide()
        #expect(!learns(effects).contains("helo"))
        #expect(learns(effects).isEmpty)
    }

    /// Letters that read as two words with the space missed are a slip, not a word.
    @Test func runTogetherWordsAreNotLearned() {
        var composer = Self.composer(strictness: 0)
        composer.settings.splitStrictness = 0
        let t = Synth.taps(&composer, "thecat")
        var effects = composer.press(.space, time: t + 0.1)
        effects += composer.keyboardWillHide()
        #expect(!effects.contains { if case .learn = $0 { true } else { false } })
    }

    /// Never suggest: a blocked word is not offered, but tapping it out still types it,
    /// and that does not unblock it.
    @Test func aBlockedWordIsNeverOffered() {
        var words = LearnedWords()
        words.block("bring")
        var composer = Self.composer()
        composer.learned = words
        let t = Synth.taps(&composer, "bting")
        let effects = composer.press(.space, time: t + 0.1)
        #expect(!effects.contains(.commit("bring")))

        var exact = Self.composer()
        exact.learned = words
        let u = Synth.taps(&exact, "bring")
        #expect(exact.press(.space, time: u + 0.1).contains(.commit("bring")))
        #expect(exact.learned.isBlocked("bring"))
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
