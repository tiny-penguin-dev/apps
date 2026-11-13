import Foundation
import Testing
@testable import AstrotypeCore

/// How much autocorrect does depends on how and where a word is typed (Gabriel, 13 Nov
/// 2026: "@vady" for a GitHub handle kept turning into "day"): slow pecking only gets
/// one-letter slips fixed, taps right after an @ or a # stay as tapped, and the setting
/// is four levels instead of a slider.
@Suite struct AutocorrectLevelTests {
    /// Pecks `letters` `gap` seconds apart after `before`, then space: what went in.
    static func peck(_ letters: String, gap: TimeInterval = 0.15, before: String = "", strictness: Double = 1) -> String? {
        var composer = StrictnessTests.composer(strictness: strictness)
        composer.setContext(before: before)
        var t: TimeInterval = 0
        for letter in letters {
            Synth.tap(&composer, letter, at: t)
            t += gap
        }
        let effects = composer.press(.space, time: t + 0.1)
        return effects.compactMap { effect -> String? in if case .commit(let w) = effect { w } else { nil } }.first
    }

    // MARK: After @ and #

    @Test func tapsAfterAnAtStayAsTapped() {
        // Fast and at "Always", without the @ the nearest word goes in.
        #expect(Self.peck("vady") != "vady")
        #expect(Self.peck("vady", before: "@") == "vady")
        #expect(Self.peck("vady", before: "hi @") == "vady")
        #expect(Self.peck("bting", before: "#") == "bting")
    }

    @Test func anAtInsideTheWordBeforeDoesNotCount() {
        // The @ must be right before the word.
        #expect(Self.peck("bting", before: "mail @ ") == "bring")
    }

    @Test func tappedHandlesAreNotLearned() {
        var composer = StrictnessTests.composer(strictness: 0.8)
        composer.setContext(before: "@")
        var t: TimeInterval = 0
        for letter in "vadym" {
            Synth.tap(&composer, letter, at: t)
            t += 0.15
        }
        var effects = composer.press(.space, time: t)
        composer.setContext(before: "@vadym ")
        effects += composer.press(.space, time: t + 3)
        #expect(!effects.contains { if case .learn = $0 { true } else { false } })
    }

    // MARK: Slow pecking

    @Test func slowTapsKeepAWordThatIsMoreThanOneSlipAway() {
        #expect(Self.peck("vady", gap: 0.15) != "vady")
        #expect(Self.peck("vady", gap: 0.5) == "vady")
        #expect(Self.peck("kiril", gap: 0.5) == "kiril")
    }

    @Test func slowTapsStillFixAOneLetterSlip() {
        // A key over, two letters swapped, one missing.
        #expect(Self.peck("bting", gap: 0.5) == "bring")
        #expect(Self.peck("hte", gap: 0.5) == "the")
        #expect(Self.peck("brng", gap: 0.5) == "bring")
        #expect(Self.peck("bting", gap: 0.5, strictness: 0.8) == "bring")
    }

    @Test func onePauseDoesNotMakeAWordSlow() {
        let matcher = StrictnessTests.composer().matcher
        let taps = [0, 0.15, 0.3, 1.5].enumerated().map { i, t in
            Piece(id: i, side: .left, start: t, end: t + 0.08, points: [.zero], keys: ["a"], isTap: true)
        }
        #expect(!matcher.isSlow(taps))
        let slow = [0, 0.4, 0.8, 1.2].enumerated().map { i, t in
            Piece(id: i, side: .left, start: t, end: t + 0.08, points: [.zero], keys: ["a"], isTap: true)
        }
        #expect(matcher.isSlow(slow))
    }

    @Test func oneSlip() {
        let matcher = StrictnessTests.composer().matcher
        #expect(matcher.isOneSlip("bting", "bring"))   // t and r are neighbours
        #expect(!matcher.isOneSlip("bping", "bring"))  // p is far from r
        #expect(matcher.isOneSlip("hte", "the"))
        #expect(matcher.isOneSlip("brng", "bring"))
        #expect(matcher.isOneSlip("bringg", "bring"))
        #expect(!matcher.isOneSlip("vady", "day"))
        #expect(!matcher.isOneSlip("vadym", "vary"))
        #expect(!matcher.isOneSlip("kiril", "kill"))
    }

    // MARK: The setting

    @Test func oldSliderValuesReadAsTheClosestLevel() throws {
        func level(_ value: Double) throws -> KeyboardSettings.Autocorrect {
            let data = Data(#"{"wordStrictness":\#(value)}"#.utf8)
            return try JSONDecoder().decode(KeyboardSettings.self, from: data).autocorrect
        }
        #expect(try level(1) == .always)
        #expect(try level(0.95) == .always)
        #expect(try level(0.8) == .mostOfTheTime)
        #expect(try level(0.6) == .mostOfTheTime)
        #expect(try level(0.4) == .whenSure)
        #expect(try level(0) == .never)
        #expect(KeyboardSettings().autocorrect == .mostOfTheTime)
    }

    @Test func eachLevelSetsTheMatcher() {
        var settings = KeyboardSettings()
        for level in KeyboardSettings.Autocorrect.allCases {
            settings.autocorrect = level
            #expect(settings.autocorrect == level)
            #expect(settings.composerSettings().strictness == level.strictness)
        }
        settings.wordStrictness = 0.83
        #expect(settings.composerSettings().strictness == 0.8)
    }
}
