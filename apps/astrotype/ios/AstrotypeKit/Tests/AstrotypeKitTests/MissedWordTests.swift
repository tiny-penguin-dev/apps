import Foundation
import Testing
@testable import AstrotypeCore

/// features/missed-words Phase A: "Not it?" after a swiped word, the word meant typed
/// into the bar, written in place of the guess, learned, and settled as a miss to keep
/// and share.
@Suite struct MissedWordTests {
    /// The field's text after the effects, as a host would apply them.
    struct Field {
        var text = ""
        var marked = ""

        mutating func apply(_ effects: [Composer.Effect]) {
            for effect in effects {
                switch effect {
                case .insert(let s): text += s
                case .deleteBackward(let n): text = String(text.dropLast(n))
                case .mark(let s): marked = s
                case .commit(let s): text += s; marked = ""
                case .clearMark: marked = ""
                default: break
                }
            }
        }

        var shown: String { text + marked }
    }

    static func taps(_ composer: inout Composer, _ letters: String, at time: TimeInterval) -> [Composer.Effect] {
        var effects: [Composer.Effect] = []
        for (i, letter) in letters.enumerated() {
            effects += Synth.tap(&composer, letter, id: 10 + i, at: time + 0.15 * Double(i))
        }
        return effects
    }

    static func settled(_ effects: [Composer.Effect]) -> SettledWord? {
        effects.compactMap { effect -> SettledWord? in
            if case .settled(let word) = effect { word } else { nil }
        }.first
    }

    @Test func notItReplacesTheOpenWord() throws {
        var composer = Synth.composer()
        var field = Field()
        field.apply(Synth.swipe(&composer, "sold"))
        let guess = try #require(composer.state.openWord)
        #expect(composer.state.canCorrect)

        composer.beginCorrection()
        #expect(composer.state.bar == .correcting(""))
        #expect(!composer.state.canCorrect)
        // The keys type into the bar, not the text.
        field.apply(Self.taps(&composer, "secom", at: 1))
        field.apply(composer.press(.backspace, time: 2))
        field.apply(Self.taps(&composer, "nd", at: 2.1))
        #expect(composer.state.bar == .correcting("second"))
        #expect(field.shown == guess)
        // Autospace waits while the field is open.
        #expect(composer.tick(time: 10).isEmpty)

        field.apply(composer.saveCorrection(time: 3))
        #expect(field.shown == "second ")
        #expect(composer.state.bar == .idle)
        #expect(!composer.state.canCorrect)

        // The next word settles it as a miss, from the guess to the word meant.
        let word = try #require(Self.settled(Synth.swipe(&composer, "the", at: 4)))
        #expect(word.word == "second")
        #expect(word.missed)
        #expect(word.fixedFrom == guess.lowercased())
        let miss = try #require(SharedWord.correction(word, layout: Synth.layout, now: Date()))
        #expect(miss.kind == SharedWord.missKind)
        #expect(miss.isMiss && miss.isCorrection)
        #expect(miss.word == "second")
        #expect(miss.typed == guess.lowercased())
        // It replays through the engine, the swipe against the word meant.
        let replayed = try Replay.run(miss, language: ContextMatcherTests.english)
        #expect(replayed.words.first?.expected == "second")
    }

    @Test func notItFixesTheWordJustWritten() throws {
        var composer = Synth.composer(autoCapitalize: true)
        var field = Field()
        composer.setContext(before: "")
        field.apply(Synth.swipe(&composer, "sold"))
        field.apply(composer.press(.space, time: 1))
        composer.setContext(before: field.text)
        let written = field.text
        #expect(written.first?.isUppercase == true)
        #expect(composer.state.canCorrect)

        composer.beginCorrection()
        _ = Self.taps(&composer, "second", at: 2)
        field.apply(composer.press(.space, time: 3))
        // Cased like the word it replaced, with its space.
        #expect(field.text == "Second ")
        #expect(!composer.state.canCorrect)
    }

    @Test func cancelLeavesEverythingAsItWas() {
        var composer = Synth.composer()
        var field = Field()
        field.apply(Synth.swipe(&composer, "sold"))
        let bar = composer.state.bar
        composer.beginCorrection()
        _ = Self.taps(&composer, "sec", at: 1)
        composer.cancelCorrection(time: 2)
        #expect(composer.state.bar == bar)
        #expect(composer.state.canCorrect)
        // Autospace is back on.
        #expect(!composer.tick(time: 10).isEmpty)
    }

    @Test func aWordTheDictionaryLacksIsLearned() {
        var composer = Synth.composer()
        _ = Synth.swipe(&composer, "sold")
        composer.beginCorrection()
        _ = Self.taps(&composer, "zorbly", at: 1)
        let effects = composer.saveCorrection(time: 2)
        #expect(effects.contains(.learn("zorbly")))
    }

    @Test func peckedWordsOfferNoNotIt() {
        var composer = Synth.composer()
        Synth.taps(&composer, "cat")
        #expect(!composer.state.canCorrect)
        composer.beginCorrection()
        #expect(composer.state.bar != .correcting(""))
    }

    @Test func missesAreCounted() {
        var tally = GuessTally()
        tally.add(SettledWord(word: "second", previous: nil, source: .fixed, fixedFrom: "song", firstGuess: "song",
                              pecked: false, missed: true))
        #expect(tally.missed == 1)
        #expect(tally.swiped == 1 && tally.swipedFirst == 0)
    }
}
