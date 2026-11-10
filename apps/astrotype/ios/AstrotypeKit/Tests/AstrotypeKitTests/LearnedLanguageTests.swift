import Foundation
import Testing
@testable import AstrotypeCore

/// Learned words per language (Gabriel, 10 Nov 2026): a word learned in a sentence of
/// one language is offered only in that language; words learned before, words written
/// in both, and words set to both by hand are offered in every language. With one
/// language on, nothing changes.
@Suite struct LearnedLanguageTests {
    static let start = Date(timeIntervalSince1970: 1_000)

    @Test func aWordBelongsToTheLanguageItWasLearnedIn() {
        var words = LearnedWords()
        words.learn("zorbo", language: "es", at: Self.start)
        #expect(words.language(of: "zorbo") == "es")
        #expect(words.contains("zorbo", in: "es") && !words.contains("zorbo", in: "en"))
        #expect(words.contains("zorbo", in: nil))
        // Written again where the language wasn't clear: still Spanish.
        words.learn("zorbo", at: Self.start)
        #expect(words.language(of: "zorbo") == "es")
        // Written in an English sentence too: both from then on.
        words.learn("zorbo", language: "en", at: Self.start)
        #expect(words.language(of: "zorbo") == nil)
        #expect(words.contains("zorbo", in: "en") && words.contains("zorbo", in: "es"))
        #expect(words.uses(of: "zorbo") == 3)
        // Learned with no clear language: every language.
        words.learn("flotilla", at: Self.start)
        #expect(words.language(of: "flotilla") == nil && words.contains("flotilla", in: "en"))
    }

    @Test func boostsAndFixesKeepTheLanguage() {
        var words = LearnedWords()
        words.learn("zorbo", language: "es", at: Self.start)
        words.learn("zorbo", language: "es", at: Self.start)
        words.boost("zorbo", at: Self.start)
        words.teach("zorbo", at: Self.start)
        words.unlearn("zorbo", at: Self.start)
        #expect(words.language(of: "zorbo") == "es")
        words.add("anker", language: "en", at: Self.start)
        #expect(words.language(of: "anker") == "en" && words.isAdded("anker"))
        words.add("astro", at: Self.start)
        #expect(words.language(of: "astro") == nil)
    }

    @Test func movingAWordReachesOtherDevices() throws {
        var phone = LearnedWords()
        phone.learn("zorbo", language: "es", at: Self.start)
        var duo = phone
        duo.setLanguage("zorbo", to: nil, at: Self.start.addingTimeInterval(5))
        #expect(phone.merged(with: duo).language(of: "zorbo") == nil)
        duo.setLanguage("zorbo", to: "en", at: Self.start.addingTimeInterval(9))
        #expect(phone.merged(with: duo).language(of: "zorbo") == "en")

        // Saved and read back; words saved before languages were told apart are both.
        let data = try JSONEncoder().encode(duo)
        #expect(try JSONDecoder().decode(LearnedWords.self, from: data).language(of: "zorbo") == "en")
        let old = #"{"entries":{"flotilla":{"weight":0,"changed":0,"uses":2}}}"#
        let read = try JSONDecoder().decode(LearnedWords.self, from: Data(old.utf8))
        #expect(read.language(of: "flotilla") == nil && read.contains("flotilla", in: "es"))
    }

    @Test func theMatcherSearchesOnlyTheSentencesLanguage() {
        var words = LearnedWords()
        words.learn("zorbo", language: "es", at: Self.start)
        words.learn("flotz", language: "en", at: Self.start)
        words.learn("anyz", at: Self.start)
        let en = Matcher.lexicon(of: words, language: "en")
        #expect(en.contains("flotz") && en.contains("anyz") && !en.contains("zorbo"))
        let es = Matcher.lexicon(of: words, language: "es")
        #expect(es.contains("zorbo") && es.contains("anyz") && !es.contains("flotz"))
        let open = Matcher.lexicon(of: words)
        #expect(open.contains("zorbo") && open.contains("flotz"))

        // The composer keeps the matcher to the sentence's language.
        var settings = Composer.Settings()
        settings.autoCapitalize = false
        var composer = Composer(language: LanguagesTests.both, layout: Synth.layout, settings: settings)
        composer.learned = words
        composer.setContext(before: "No, gracias ")
        #expect(composer.matcher.learnedLanguage == "es")
        composer.setContext(before: "Thank you ")
        #expect(composer.matcher.learnedLanguage == "en")
        composer.setContext(before: "")
        #expect(composer.matcher.learnedLanguage == nil)

        // One language on: every learned word, always.
        var single = Composer(language: LanguagesTests.spanish, layout: Synth.layout, settings: settings)
        single.learned = words
        single.setContext(before: "No, gracias ")
        #expect(single.matcher.learnedLanguage == nil)
    }
}
