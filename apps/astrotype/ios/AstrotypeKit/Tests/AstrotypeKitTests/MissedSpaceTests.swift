import Foundation
import Testing
@testable import AstrotypeCore

/// Pecked letters that read as two words with the space missed go in split, when that
/// is obvious (Gabriel, 3 Nov 2026: "textseparately"), as `splitStrictness` says.
@Suite struct MissedSpaceTests {
    static func peck(_ letters: String, split: Double = 0.8) -> (word: String?, bar: [String], effects: [Composer.Effect]) {
        var settings = Replay.settings
        settings.splitStrictness = split
        var composer = Composer(language: ContextMatcherTests.english, layout: Synth.layout, settings: settings)
        let end = Synth.taps(&composer, letters)
        let effects = composer.press(.space, time: end + 0.1)
        let word = effects.compactMap { effect -> String? in if case .commit(let w) = effect { w } else { nil } }.first
        if case .fix(let words, _) = composer.state.bar { return (word, words, effects) }
        return (word, word.map { [$0] } ?? [], effects)
    }

    @Test(arguments: [
        ("textseparately", "text separately"), ("inthe", "in the"), ("seeyou", "see you"),
        ("goingto", "going to"), ("itis", "it is"), ("thisis", "this is"), ("letme", "let me"),
        ("helloworld", "hello world"), ("goodmorning", "good morning"), ("forthe", "for the"),
        ("withyou", "with you"), ("bestfriend", "best friend"), ("icecream", "ice cream"),
    ])
    func twoWordsGoInSplit(typed: String, meant: String) {
        let result = Self.peck(typed)
        #expect(result.word?.lowercased() == meant)
        // What was tapped stays in the bar, to put back.
        #expect(result.bar.map { $0.lowercased() }.contains(typed))
    }

    @Test func aSplitIsNeverLearnedAsAWord() {
        let result = Self.peck("textseparately")
        #expect(!result.effects.contains { if case .learn = $0 { true } else { false } })
    }

    @Test(arguments: ["nowhere", "carpet", "outside", "texts", "penguin"])
    func realWordsAreLeftAlone(word: String) {
        #expect(Self.peck(word).word?.lowercased() == word)
    }

    @Test func slipsStillBecomeTheWord() {
        #expect(Self.peck("bting").word?.lowercased() == "bring")
        #expect(Self.peck("hte").word?.lowercased() == "the")
        #expect(Self.peck("somethign").word?.lowercased() == "something")
    }

    @Test func namesAndRareBitsAreNotSplit() {
        // Short halves must be common words: "tex" + "tsep" and the like never split.
        #expect(Self.peck("qzxqzv").word?.lowercased() == "qzxqzv")
        #expect(Self.peck("larissa").word?.lowercased() == "larissa")
        #expect(Self.peck("aam").word?.contains(" ") != true)
    }

    @Test func atZeroItNeverSplitsButOffersIt() {
        let result = Self.peck("textseparately", split: 0)
        #expect(result.word?.lowercased() == "textseparately")
        #expect(result.bar.map { $0.lowercased() }.contains("text separately"))
    }

    @Test func settingsCarryTheSlider() throws {
        var settings = KeyboardSettings()
        #expect(settings.splitStrictness == 0.8)
        settings.splitStrictness = 0.3
        #expect(settings.composerSettings().splitStrictness == 0.3)
        let old = try JSONDecoder().decode(KeyboardSettings.self, from: Data("{}".utf8))
        #expect(old.splitStrictness == 0.8)
    }
}
