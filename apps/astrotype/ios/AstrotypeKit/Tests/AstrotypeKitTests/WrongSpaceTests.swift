import Foundation
import Testing
@testable import AstrotypeCore

/// Autospace with a short wait writes spaces the person did not mean (Gabriel, 3 Nov
/// 2026): a pause inside a word ("some" … "thing") is taken out again when the two
/// pieces are clearly one word, and punctuation after a word goes before its space.
@Suite struct WrongSpaceTests {
    /// The composer with a host field that applies its effects and passes the text back.
    struct Typist {
        var composer: Composer
        var text = ""
        var marked = ""
        var time: TimeInterval = 0

        init(split: Double = 0.8, delay: TimeInterval = 0.4) {
            var settings = Replay.settings
            settings.autoCapitalize = false
            settings.nextWords = false
            settings.autospaceDelay = delay
            settings.splitStrictness = split
            composer = Composer(language: ContextMatcherTests.english, layout: Synth.layout, settings: settings)
            composer.setContext(before: "")
        }

        var shown: String { text + marked }

        mutating func apply(_ effects: [Composer.Effect]) {
            for effect in effects {
                switch effect {
                case .insert(let s): text += s
                case .deleteBackward(let n): text.removeLast(min(n, text.count))
                case .mark(let s): marked = s
                case .commit(let s): text += s; marked = ""
                case .clearMark: marked = ""
                default: break
                }
            }
            composer.setContext(before: text)
        }

        /// Swipes `letters`, or taps them one by one when `tapped`.
        mutating func type(_ letters: String, tapped: Bool = false) {
            if tapped {
                for (i, letter) in letters.enumerated() {
                    apply(Synth.tap(&composer, letter, id: 10 + i, at: time))
                    time += 0.15
                }
            } else {
                apply(Synth.swipe(&composer, letters, at: time))
                time += 0.35
            }
        }

        /// Waits long enough for autospace, then a moment more.
        mutating func pause() {
            time += composer.settings.autospaceDelay ?? 0
            apply(composer.tick(time: time))
            time += 0.2
        }

        mutating func press(_ key: Key) {
            apply(composer.press(key, time: time))
            time += 0.2
        }

        mutating func press(_ character: Character) {
            apply(composer.press(character: character, time: time))
            time += 0.2
        }
    }

    /// `first`, a pause long enough for autospace, then `second` and space.
    static func paused(_ first: String, _ second: String, firstTapped: Bool = false, secondTapped: Bool = false,
                       before: String? = nil, split: Double = 0.8) -> Typist {
        var typist = Typist(split: split)
        if let before {
            for word in before.split(separator: " ") {
                typist.type(String(word))
                typist.press(.space)
            }
        }
        typist.type(first, tapped: firstTapped)
        typist.pause()
        typist.type(second, tapped: secondTapped)
        typist.press(.space)
        return typist
    }

    // MARK: A pause inside a word

    @Test(arguments: [
        ("some", "thing", "something"), ("with", "out", "without"), ("be", "cause", "because"),
        ("to", "day", "today"), ("every", "thing", "everything"), ("key", "board", "keyboard"),
        ("sepa", "rately", "separately"), ("to", "gether", "together"), ("week", "end", "weekend"),
    ])
    func aPauseInsideAWordIsTakenOut(first: String, second: String, word: String) {
        #expect(Self.paused(first, second).text == word + " ")
    }

    @Test func peckedHalvesJoinToo() {
        #expect(Self.paused("beau", "tiful", firstTapped: true, secondTapped: true).text == "beautiful ")
        #expect(Self.paused("hel", "lo", firstTapped: true, secondTapped: true).text == "hello ")
    }

    @Test(arguments: [
        ("it", "may", "be"), ("to", "set", "up"), ("go", "in", "to"), ("i walk", "every", "day"), ("and", "so", "on"),
        ("give", "me", "an"), ("to", "log", "in"), ("for", "some", "time"), ("will", "be", "at"),
    ])
    func twoRealWordsStayApart(before: String, first: String, second: String) {
        #expect(Self.paused(first, second, before: before).text == "\(before) \(first) \(second) ")
    }

    @Test func wordsThatMakeNoWordStayApart() {
        #expect(Self.paused("good", "morning").text == "good morning ")
        #expect(Self.paused("thank", "you").text == "thank you ")
        // One letter is a word of its own: "a way" may well be meant.
        #expect(Self.paused("a", "way", firstTapped: true).text == "a way ")
    }

    @Test func theTwoWordsWaitInTheBar() {
        var typist = Self.paused("some", "thing")
        #expect(typist.text == "something ")
        guard case .fix(let words, let chosen) = typist.composer.state.bar else {
            Issue.record("no fix bar: \(typist.composer.state.bar)")
            return
        }
        #expect(words[chosen] == "something")
        let apart = try? #require(words.firstIndex(of: "some thing"))
        typist.apply(typist.composer.choose(guess: apart ?? 1))
        #expect(typist.text == "some thing ")
    }

    @Test func aSentenceStartKeepsItsCapital() {
        var typist = Typist()
        typist.composer.settings.autoCapitalize = true
        typist.composer.setContext(before: "")
        typist.type("some")
        typist.pause()
        typist.type("thing")
        typist.press(.space)
        #expect(typist.text == "Something ")
    }

    @Test func punctuationEndsTheJoinedWord() {
        var typist = Typist()
        typist.type("with")
        typist.pause()
        typist.type("out")
        typist.press(".")
        #expect(typist.text == "without.")
        // And autospace can end it too.
        var other = Typist()
        other.type("to")
        other.pause()
        other.type("day")
        other.pause()
        #expect(other.text == "today ")
    }

    @Test func onlyAutospaceIsTakenOut() {
        // The person's own space between the two stays.
        var typist = Typist()
        typist.type("some")
        typist.press(.space)
        typist.type("thing")
        typist.press(.space)
        #expect(typist.text == "some thing ")
        // A word picked from the bar was meant as it is.
        var picked = Typist()
        picked.type("some")
        picked.pause()
        picked.type("thing")
        picked.apply(picked.composer.choose(guess: 0, time: picked.time))
        #expect(picked.text == "some thing ")
    }

    @Test func aSpacePressedRightAfterAutospaceIsKept() {
        // Autospace beat the thumb to it: the person's space still means two words
        // (Gabriel, 6 Nov 2026, spaces missed when typing fast).
        var typist = Typist()
        typist.type("some")
        typist.pause()
        typist.press(.space)
        typist.type("thing")
        typist.press(.space)
        #expect(typist.text == "some thing ")
    }

    @Test func aLongPauseIsANewWord() {
        var typist = Typist()
        typist.type("some")
        typist.pause()
        typist.time += Composer.joinWindow + 0.5
        typist.type("thing")
        typist.press(.space)
        #expect(typist.text == "some thing ")
    }

    @Test func atZeroItNeverJoins() {
        #expect(Self.paused("some", "thing", split: 0).text == "some thing ")
    }

    // MARK: Punctuation after a word

    @Test func aSpacePressedAfterAutospaceStillGivesWayToTheDot() {
        // Autospace wrote the space, the person pressed space too: still one space,
        // and the dot goes before it (Gabriel, 3 Nov 2026).
        var typist = Typist()
        typist.type("there")
        typist.pause()
        typist.press(.space)
        #expect(typist.text == "there ")
        typist.time += 0.5
        typist.press(".")
        #expect(typist.text == "there. ")
    }

    @Test(arguments: [".", ",", "?", "!", ":", ";"] as [Character])
    func punctuationGoesBeforeTheSpaceAfterAWord(mark: Character) {
        var typist = Typist()
        typist.type("there")
        typist.press(.space)
        typist.press(mark)
        #expect(typist.text == "there\(mark) ")
    }

    @Test func punctuationAfterTheSpaceOfAJoinedWord() {
        var typist = Self.paused("some", "thing")
        typist.press("?")
        #expect(typist.text == "something? ")
    }

    @Test func otherCharactersKeepTheSpace() {
        var typist = Typist()
        typist.type("there")
        typist.pause()
        typist.press("(")
        #expect(typist.text == "there (")
    }

    @Test func aMovedCursorKeepsItsSpace() {
        var typist = Typist()
        typist.type("there")
        typist.pause()
        // The cursor went somewhere else that also has a space before it.
        typist.text = "hello  "
        typist.apply([])
        typist.text = "hello"
        typist.apply([])
        typist.text = "hello "
        typist.apply([])
        typist.press(".")
        #expect(typist.text == "hello .")
    }
}
