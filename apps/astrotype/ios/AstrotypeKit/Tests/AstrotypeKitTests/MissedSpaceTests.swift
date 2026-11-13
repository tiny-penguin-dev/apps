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

    /// Fixing spaces follows the Autocorrect level, with its own switch to turn it off
    /// (Gabriel, 13 Nov 2026); the old slider read as on unless it was at 0.
    @Test func settingsCarryTheSwitch() throws {
        var settings = KeyboardSettings()
        #expect(settings.fixesSpaces)
        #expect(settings.composerSettings().splitStrictness == 0.8)
        settings.autocorrect = .whenSure
        #expect(settings.composerSettings().splitStrictness == 0.3)
        settings.autocorrect = .always
        #expect(settings.composerSettings().splitStrictness == 0.9)
        settings.fixesSpaces = false
        #expect(settings.composerSettings().splitStrictness == 0)
        let old = try JSONDecoder().decode(KeyboardSettings.self, from: Data("{}".utf8))
        #expect(old.fixesSpaces)
        let off = try JSONDecoder().decode(KeyboardSettings.self, from: Data(#"{"splitStrictness":0}"#.utf8))
        #expect(!off.fixesSpaces)
        let saved = try JSONDecoder().decode(KeyboardSettings.self, from: JSONEncoder().encode(settings))
        #expect(!saved.fixesSpaces)
    }

    // MARK: Between swipes and taps

    static func play(_ strokes: [Synth.Stroke]) -> [String] {
        var composer = Composer(language: ContextMatcherTests.english, layout: Synth.layout, settings: Replay.settings)
        Synth.play(&composer, strokes)
        if case .guesses(let words, _) = composer.state.bar { return words.map { $0.lowercased() } }
        return []
    }

    /// `first` swiped, then `second` swiped (or tapped) before autospace.
    static func strokes(_ first: String, _ second: String, tapped: Bool = false) -> [Synth.Stroke] {
        var out: [Synth.Stroke] = [.swipe(first, id: 1, from: 0, to: 0.3)]
        if tapped {
            for (i, letter) in second.enumerated() { out.append(.tap(letter, id: 2 + i, at: 0.45 + 0.15 * Double(i))) }
        } else {
            out.append(.swipe(second, id: 2, from: 0.45, to: 0.75))
        }
        return out
    }

    @Test(arguments: [("text", "separately"), ("about", "time"), ("ice", "cream"), ("good", "morning"), ("in", "the")])
    func twoSwipesGoInSplit(first: String, second: String) {
        #expect(Self.play(Self.strokes(first, second)).first == "\(first) \(second)")
    }

    @Test func aSwipeThenTapsGoInSplit() {
        #expect(Self.play(Self.strokes("going", "to", tapped: true)).first == "going to")
        #expect(Self.play(Self.strokes("look", "at", tapped: true)).first == "look at")
    }

    @Test func tapsThenASwipeGoInSplit() {
        var strokes: [Synth.Stroke] = [.tap("a", id: 2, at: 0)]
        strokes.append(.swipe("lot", id: 1, from: 0.25, to: 0.55))
        #expect(Self.play(strokes).first == "a lot")
    }

    @Test func oneWordInTwoTouchesStaysOneWord() {
        // Two-thumb typing: a word made of two swipes, or a swipe and taps, still wins.
        #expect(Self.play(Self.strokes("some", "thing")).first == "something")
        #expect(Self.play(Self.strokes("with", "out")).first == "without")
        #expect(Self.play(Self.strokes("hel", "lo")).first == "hello")
        #expect(Self.play(Self.strokes("lo", "ve", tapped: true)).first == "love")
        // The split is still there to pick.
        #expect(Self.play(Self.strokes("some", "thing")).contains("some thing"))
    }

    @Test func atZeroSwipesAreNeverSplit() {
        var settings = Replay.settings
        settings.splitStrictness = 0
        var composer = Composer(language: ContextMatcherTests.english, layout: Synth.layout, settings: settings)
        Synth.play(&composer, Self.strokes("text", "separately"))
        #expect(composer.state.openWord?.contains(" ") == false)
    }
}
