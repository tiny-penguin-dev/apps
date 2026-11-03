import Foundation
import Testing
@testable import AstrotypeCore

/// features/languages Phase A: Spanish in the engine, and two languages at once.
@Suite struct LanguagesTests {
    static let spanish: Language = {
        do { return try Language.bundled("es") } catch { fatalError("es missing from the package: \(error)") }
    }()
    static let both: Language = {
        do { return try Language.bundled(["en", "es"]) } catch { fatalError("en+es: \(error)") }
    }()

    /// Common Spanish words, swiped straight through their plain letters.
    static let spanishWords = [
        "canción", "mañana", "año", "también", "está", "quiero", "gracias", "después",
        "corazón", "niño", "español", "trabajo", "pequeño", "siempre", "ciudad", "música",
        "teléfono", "fácil", "aquí", "hermano",
    ]

    static func composer(_ language: Language) -> Composer {
        var settings = Composer.Settings()
        settings.autoCapitalize = false
        return Composer(language: language, layout: Synth.layout, settings: settings)
    }

    @Test func foldTakesAccentsOff() {
        #expect(Lexicon.fold("Mañana") == "manana")
        #expect(Lexicon.fold("pingüino") == "pinguino")
        #expect(Lexicon.fold("CANCIÓN") == "cancion")
        #expect(Lexicon.fold("hello") == "hello")
    }

    @Test func accentedWordsSitUnderTheirPlainLetters() {
        let lexicon = Lexicon(entries: [
            .init(word: "está", frequency: 3), .init(word: "esta", frequency: 2),
            .init(word: "canción", frequency: 1), .init(word: "casa", frequency: 4),
        ])
        #expect(lexicon.contains("cancion"))
        #expect(!lexicon.contains("canción"))
        #expect(lexicon.spellings(of: "cancion").map(\.word) == ["canción"])
        #expect(lexicon.spellings(of: "esta").map(\.word) == ["está", "esta"])
        #expect(lexicon.spellings(of: "casa").map(\.word) == ["casa"])
        // The key counts every spelling: "esta" (3 + 2) is commoner than "casa" (4).
        #expect(lexicon.logPrior(of: "esta")! > lexicon.logPrior(of: "casa")!)
        #expect(lexicon.hasSpellings)
        #expect(!Synth.lexicon.hasSpellings)
    }

    @Test func spanishShipsWithItsWordPairs() {
        #expect(Language.bundledCodes.contains("es"))
        #expect(Self.spanish.lexicon.nodeCount > 50_000)
        let pairs = try! #require(Self.spanish.ngrams)
        #expect(pairs.likelyWords(after: "<s>", limit: 5).contains("el"))
        // Keyed by plain letters, like the trie: "qué" is "que".
        #expect(pairs.likelyWords(after: "por", limit: 5).contains("que"))
    }

    @Test func aSwipeOverThePlainLettersWritesTheAccents() {
        var composer = Self.composer(Self.spanish)
        Synth.swipe(&composer, "cancion")
        #expect(composer.state.openWord == "canción")

        composer = Self.composer(Self.spanish)
        Synth.swipe(&composer, "manana")
        #expect(composer.state.openWord == "mañana")
    }

    @Test func tappedLettersOfferBothSpellings() {
        var composer = Self.composer(Self.spanish)
        Synth.taps(&composer, "esta")
        guard case .guesses(let words, _) = composer.state.bar else { Issue.record("no guesses"); return }
        #expect(words.contains("está"))
        #expect(words.contains("esta"))
    }

    @Test func spanishSwipesComeOutRight() {
        var misses: [String] = []
        for word in Self.spanishWords {
            var composer = Self.composer(Self.spanish)
            Synth.swipe(&composer, Lexicon.fold(word))
            if composer.state.openWord != word { misses.append("\(word) → \(composer.state.bar)") }
        }
        #expect(misses.count <= 2, "misses: \(misses)")
    }

    /// Both at once must not cost English: the 50-word fixture holds to the same bar
    /// as English alone (BUILD.md Phase 2: nine of ten).
    @Test func englishHoldsUpWithBothOn() {
        var misses: [String] = []
        for fixture in Synth.fixtures {
            var composer = Self.composer(Self.both)
            Synth.swipe(&composer, fixture.swipe)
            if composer.state.openWord != fixture.word { misses.append("\(fixture.word) → \(composer.state.bar)") }
        }
        print("en+es: \(misses.count) English misses of \(Synth.fixtures.count): \(misses)")
        #expect(misses.count <= 5, "misses: \(misses)")
    }

    @Test func spanishHoldsUpWithBothOn() {
        var misses: [String] = []
        for word in Self.spanishWords {
            var composer = Self.composer(Self.both)
            Synth.swipe(&composer, Lexicon.fold(word))
            if composer.state.openWord != word { misses.append("\(word) → \(composer.state.bar)") }
        }
        print("en+es: \(misses.count) Spanish misses of \(Self.spanishWords.count): \(misses)")
        #expect(misses.count <= 4, "misses: \(misses)")
    }

    @Test func eachLanguagesPairsSpeakAfterItsOwnWords() {
        var matcher = Matcher(language: Self.both, layout: Synth.layout)
        #expect(matcher.ngramModels.count == 2)
        let lexicon = Self.both.lexicon
        let prior = { (word: String) in lexicon.logPrior(of: word)! }
        matcher.context = WordContext.words(before: "por ")
        let afterPor = matcher.contextBonus(for: "que", prior: prior("que"))
        matcher.context = WordContext.words(before: "thank ")
        #expect(matcher.contextBonus(for: "you", prior: prior("you")) > 1)
        #expect(afterPor > 1)
        // A word from the other language gains nothing after "thank".
        #expect(matcher.contextBonus(for: "que", prior: prior("que")) < 0)
    }

    @Test func contextReadsAccentedWords() {
        #expect(WordContext.words(before: "Hasta mañana ", count: 2) == ["hasta", "manana"])
        #expect(WordContext.words(before: "¿Qué ", count: 2) == ["<s>", "que"])
    }

    @Test func bothAtOnceIsFastEnough() {
        let matcher = Matcher(language: Self.both, layout: Synth.layout)
        var pieces: [[Piece]] = []
        for fixture in Synth.fixtures {
            var composer = Self.composer(Self.both)
            Synth.swipe(&composer, fixture.swipe)
            pieces.append(composer.pieces)
        }
        _ = matcher.candidates(for: pieces[0])
        let start = Date()
        for p in pieces { _ = matcher.candidates(for: p, limit: 3) }
        let mean = Date().timeIntervalSince(start) / Double(pieces.count) * 1000
        print("matcher en+es: \(String(format: "%.2f", mean)) ms per word (debug)")
        #expect(mean < 25, "mean \(mean) ms")
    }

    @Test func combinedWeighsEachLanguageTheSame() {
        let merged = Language.combined([
            [.init(word: "the", frequency: 100), .init(word: "no", frequency: 100)],
            [.init(word: "el", frequency: 1), .init(word: "no", frequency: 1)],
        ])
        let byWord = Dictionary(uniqueKeysWithValues: merged.map { ($0.word, $0.frequency) })
        #expect(byWord["the"] == 0.5)
        #expect(byWord["el"] == 0.5)
        #expect(byWord["no"] == 1.0)
    }
}
