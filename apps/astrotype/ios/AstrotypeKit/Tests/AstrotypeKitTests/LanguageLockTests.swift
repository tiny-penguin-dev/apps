import Foundation
import Testing
@testable import AstrotypeCore

/// features/languages: with two languages on, the first word may be either, and once a
/// word shows which language the sentence is in, the rest of it keeps to that one
/// (Gabriel, 3 Nov 2026). "Mix in one sentence" keeps both for every word.
@Suite struct LanguageLockTests {
    static var both: Language { LanguagesTests.both }

    static func composer(mixing: Bool = false) -> Composer {
        var settings = Composer.Settings()
        settings.autoCapitalize = false
        settings.mixesLanguages = mixing
        return Composer(language: both, layout: Synth.layout, settings: settings)
    }

    @Test func aWordCommonInOneLanguageOnlyIsSure() {
        #expect(Self.both.sureLanguage(of: "the") == "en")
        #expect(Self.both.sureLanguage(of: "you") == "en")
        #expect(Self.both.sureLanguage(of: "que") == "es")
        #expect(Self.both.sureLanguage(of: "Gracias") == "es")
        #expect(Self.both.sureLanguage(of: "mañana") == "es")
        // Common in both: could be either.
        for word in ["no", "a", "me", "real", "general"] {
            #expect(Self.both.sureLanguage(of: word) == nil, "\(word)")
        }
        // In neither: says nothing.
        #expect(Self.both.sureLanguage(of: "zzqx") == nil)
        // One language has nothing to choose between.
        #expect(LanguagesTests.spanish.sureLanguage(of: "que") == nil)
    }

    @Test func theFirstSureWordDecides() {
        #expect(Self.both.lock(for: []) == nil)
        #expect(Self.both.lock(for: ["no", "me"]) == nil)
        #expect(Self.both.lock(for: ["no", "que", "the"]) == "es")
        #expect(Self.both.lock(for: ["the", "casa"]) == "en")
    }

    @Test func theSentenceIsItsFinishedWords() {
        #expect(WordContext.sentence(before: "") == [])
        #expect(WordContext.sentence(before: "Hi. Gracias por ") == ["gracias", "por"])
        #expect(WordContext.sentence(before: "Gracias, amig") == ["gracias"])
        #expect(WordContext.sentence(before: "Thanks!\n¿Qué ") == ["que"])
        #expect(WordContext.sentence(before: "Done. ") == [])
    }

    @Test func aSentenceLocksAndTheNextOneIsOpenAgain() {
        var composer = Self.composer()
        composer.setContext(before: "")
        #expect(composer.lockedLanguage == nil)
        #expect(composer.matcher.dictionary.contains("the") && composer.matcher.dictionary.contains("que"))

        composer.setContext(before: "No, gracias ")
        #expect(composer.lockedLanguage == "es")
        #expect(!composer.matcher.dictionary.contains("the"))
        #expect(composer.matcher.dictionary.nodeCount == Self.both.part("es").lexicon.nodeCount)
        #expect(composer.matcher.ngramModels.count == 1)

        // An English word later in the sentence doesn't switch it.
        composer.setContext(before: "No, gracias the ")
        #expect(composer.lockedLanguage == "es")

        composer.setContext(before: "No, gracias. ")
        #expect(composer.lockedLanguage == nil)
        #expect(composer.matcher.ngramModels.count == 2)

        composer.setContext(before: "No, gracias. Thank you ")
        #expect(composer.lockedLanguage == "en")
        #expect(composer.matcher.dictionary.nodeCount == Self.both.part("en").lexicon.nodeCount)
    }

    @Test func mixingKeepsBothForEveryWord() {
        var composer = Self.composer(mixing: true)
        composer.setContext(before: "Gracias ")
        #expect(composer.lockedLanguage == nil)
        #expect(composer.matcher.dictionary.contains("the"))

        // Turning it off locks at once, and on again unlocks.
        composer.settings.mixesLanguages = false
        #expect(composer.lockedLanguage == "es")
        composer.settings.mixesLanguages = true
        #expect(composer.lockedLanguage == nil)
        #expect(composer.matcher.dictionary.contains("the"))
    }

    @Test func oneLanguageNeverLocks() {
        var settings = Composer.Settings()
        settings.autoCapitalize = false
        var composer = Composer(language: LanguagesTests.spanish, layout: Synth.layout, settings: settings)
        composer.setContext(before: "Gracias ")
        #expect(composer.lockedLanguage == nil)
    }

    @Test func aLockedSentenceGuessesOnlyItsLanguage() {
        // A Spanish word's swipe in an English sentence doesn't come out Spanish...
        var composer = Self.composer()
        composer.setContext(before: "Thanks, ")
        Synth.swipe(&composer, "quiero")
        #expect(composer.state.openWord != "quiero")

        // ...unless mixing is on.
        composer = Self.composer(mixing: true)
        composer.setContext(before: "Thanks, ")
        Synth.swipe(&composer, "quiero")
        #expect(composer.state.openWord == "quiero")
    }

    /// Locked, each language types as well as it does on its own.
    @Test func lockedSentencesHoldUp() {
        var spanishMisses: [String] = []
        for word in LanguagesTests.spanishWords {
            var composer = Self.composer()
            composer.setContext(before: "Gracias, ")
            Synth.swipe(&composer, Lexicon.fold(word))
            if composer.state.openWord != word { spanishMisses.append("\(word) → \(composer.state.bar)") }
        }
        var englishMisses: [String] = []
        for fixture in Synth.fixtures {
            var composer = Self.composer()
            composer.setContext(before: "Thanks, ")
            Synth.swipe(&composer, fixture.swipe)
            if composer.state.openWord != fixture.word { englishMisses.append("\(fixture.word) → \(composer.state.bar)") }
        }
        print("locked: \(spanishMisses.count) Spanish misses, \(englishMisses.count) English misses")
        #expect(spanishMisses.count <= 2, "misses: \(spanishMisses)")
        #expect(englishMisses.count <= 5, "misses: \(englishMisses)")
    }
}
