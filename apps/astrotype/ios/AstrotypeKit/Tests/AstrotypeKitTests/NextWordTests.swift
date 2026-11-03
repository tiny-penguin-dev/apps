import Foundation
import Testing
@testable import AstrotypeCore

/// features/next-word: after each word the bar offers the likely next ones, from the
/// English word pairs and the person's own, with the FIX chip beside them.
@Suite struct NextWordTests {
    static let english = ContextMatcherTests.english
    static let start = Date(timeIntervalSinceReferenceDate: 815_000_000)

    static func guesses(after previous: String, personal: PersonalIndex = PersonalIndex(),
                        learned: LearnedWords = LearnedWords(), count: Int = 3) -> [String] {
        NextWords.guesses(after: previous, models: english.ngramModels, personal: personal, learned: learned, count: count)
    }

    /// A text field the composer types into, the way `KeyboardModel` applies effects:
    /// marked text shown, then the context passed back after every change.
    struct Field {
        var composer: Composer
        var text = ""
        var marked = ""
        var settled: [SettledWord] = []

        init(autoCapitalize: Bool = true, nextWords: Bool = true, text: String = "") {
            var settings = Replay.settings
            settings.autoCapitalize = autoCapitalize
            settings.nextWords = nextWords
            composer = Composer(language: NextWordTests.english, layout: Synth.layout, settings: settings)
            self.text = text
            composer.setContext(before: text)
        }

        mutating func apply(_ effects: [Composer.Effect]) {
            for effect in effects {
                switch effect {
                case .insert(let s): text += s
                case .deleteBackward(let n): text.removeLast(min(n, text.count))
                case .mark(let s): marked = s
                case .commit(let s): text += s; marked = ""
                case .clearMark: marked = ""
                case .settled(let word): settled.append(word)
                default: break
                }
            }
            composer.setContext(before: text)
        }

        mutating func swipe(_ letters: String, at time: TimeInterval = 0) {
            apply(Synth.swipe(&composer, letters, at: time))
        }

        mutating func press(_ key: Key, at time: TimeInterval = 1) {
            apply(composer.press(key, time: time))
        }

        mutating func choose(_ index: Int) {
            apply(composer.choose(guess: index))
        }

        var next: [String] {
            if case .next(let words, _, _) = composer.state.bar { return words }
            return []
        }
    }

    // MARK: The guesses

    @Test func commonPairsComeFirst() {
        #expect(Self.guesses(after: "going").first == "to")
        #expect(Self.guesses(after: "thank").first == "you")
        #expect(Self.guesses(after: "on").first == "the")
        #expect(Self.guesses(after: NgramModel.sentenceStart).first == "i")
        #expect(Self.guesses(after: "going").count == 3)
    }

    @Test func nothingIsOfferedAfterAnUnknownWord() {
        #expect(Self.guesses(after: "zzqx").isEmpty)
        #expect(Self.guesses(after: "going", count: 0).isEmpty)
    }

    @Test func contractionsAndForgottenWordsAreLeftOut() {
        // "i" is often followed by "dont" and "im" in the pairs: never offered.
        let afterI = Self.guesses(after: "i", count: 10)
        #expect(!afterI.contains("dont") && !afterI.contains("im") && !afterI.isEmpty)
        var learned = LearnedWords()
        learned.forget("to", at: Self.start)
        #expect(!Self.guesses(after: "going", learned: learned).contains("to"))
    }

    @Test func thePersonsOwnPairsJoinIn() {
        var model = PersonalModel()
        for _ in 0..<3 {
            model.learn(SettledWord(word: "ships", previous: "flotilla", source: .tapped), device: "a", at: Self.start)
        }
        let index = PersonalIndex(model, at: Self.start)
        #expect(Self.guesses(after: "flotilla", personal: index).first == "ships")
        // Someone who keeps writing "going home" sees it first.
        for _ in 0..<12 {
            model.learn(SettledWord(word: "home", previous: "going", source: .tapped), device: "a", at: Self.start)
        }
        #expect(Self.guesses(after: "going", personal: PersonalIndex(model, at: Self.start)).first == "home")
    }

    @Test func topNextMatchesAFullSort() throws {
        let model = try #require(Self.english.ngrams)
        for previous in ["the", "to", NgramModel.sentenceStart, "going"] {
            let top = model.topNext(after: previous, limit: 8)
            #expect(top.count == 8)
            #expect(zip(top, top.dropFirst()).allSatisfy { $0.logProbability >= $1.logProbability })
            for item in top {
                #expect(model.logProbability(of: item.word, after: previous) == item.logProbability)
            }
            #expect(model.likelyWords(after: previous, limit: 8) == top.map(\.word))
        }
    }

    /// The bar is worked out after every word, so it has to be quick: "the" has the
    /// most pairs of any word. About 1.5 ms in a debug build on its own; CI runs the
    /// suites side by side, which can make it several times slower, so the bound has
    /// room (the same reason as `MatcherTests.debugBound`).
    @Test func guessesAreFast() {
        _ = Self.guesses(after: "the")
        let start = Date()
        for _ in 0..<200 { _ = Self.guesses(after: "the") }
        let ms = Date().timeIntervalSince(start) / 200 * 1000
        print("next words: \(String(format: "%.3f", ms)) ms after \"the\" (debug)")
        #expect(ms < 15, "mean \(ms) ms")
    }

    // MARK: The bar

    @Test func aNewMessageOffersFirstWords() {
        var field = Field()
        #expect(field.next.first == "I")
        #expect(field.next.count == 3)
        // Capitalised for the sentence start.
        #expect(field.next.allSatisfy { $0.first?.isUppercase == true })
        field.choose(0)
        #expect(field.text == "I ")
        // And then what follows "i", lowercase, a tap at a time.
        #expect(!field.next.isEmpty)
        #expect(field.next.allSatisfy { $0.first?.isLowercase == true })
        let next = field.next[0]
        field.choose(0)
        #expect(field.text == "I \(next) ")
    }

    @Test func aWordWithOtherReadingsKeepsItsFixes() {
        var field = Field(autoCapitalize: false)
        field.swipe("pot")
        field.press(.space)
        #expect(field.text == "put ")
        guard case .next(let words, let fix, let chosen) = field.composer.state.bar else {
            Issue.record("expected next words, got \(field.composer.state.bar)")
            return
        }
        // All three next words: the readings wait behind the pencil (features/guesses-bar).
        #expect(words.count == 3)
        #expect(fix[chosen] == "put")
        let offered = field.composer.state.bar.fixChoice ?? ""
        #expect(!offered.isEmpty && offered != "put")
        // The chip swaps the word; the next words follow it; tapped again, it goes back.
        field.apply(field.composer.chooseFix())
        #expect(field.text == "\(offered) ")
        #expect(field.composer.state.bar.fixChoice == "put")
        #expect(!field.next.isEmpty)
        field.apply(field.composer.chooseFix())
        #expect(field.text == "put ")
        // A reading picked from the pencil's row goes in; the one in the field does nothing.
        guard case .next(_, let readings, let now) = field.composer.state.bar, readings.count > 1 else {
            Issue.record("expected readings, got \(field.composer.state.bar)")
            return
        }
        #expect(field.composer.chooseFix(reading: now).isEmpty)
        let other = readings.indices.last { $0 != now } ?? now
        field.apply(field.composer.chooseFix(reading: other))
        #expect(field.text == "\(readings[other]) ")
    }

    @Test func aTouchClearsTheNextWords() {
        var field = Field()
        #expect(!field.next.isEmpty)
        field.apply(field.composer.touchDown(id: 1, at: Synth.center("h"), time: 0))
        #expect(field.composer.state.bar == .idle)
    }

    @Test func offTheBarBehavesAsBefore() {
        var field = Field(autoCapitalize: false, nextWords: false)
        #expect(field.composer.state.bar == .idle)
        field.swipe("pot")
        field.press(.space)
        guard case .fix = field.composer.state.bar else {
            Issue.record("expected the fix bar, got \(field.composer.state.bar)")
            return
        }
    }

    @Test func nothingAfterACommaOrInsideAWord() {
        var field = Field(text: "Well, ")
        #expect(field.composer.state.bar == .idle)
        field = Field(text: "Going to th")
        #expect(field.composer.state.bar == .idle)
    }

    @Test func afterAPeriodTheSpaceIsAddedFirst() {
        var field = Field(text: "Done.")
        #expect(field.next.first == "I")
        field.choose(0)
        #expect(field.text == "Done. I ")
    }

    @Test func shiftAndCapsLockCaseTheGuesses() {
        var field = Field(autoCapitalize: false, text: "going ")
        #expect(field.next.first == "to")
        field.press(.shift, at: 1)
        #expect(field.next.first == "To")
        field.press(.shift, at: 1.1)
        #expect(field.next.first == "TO")
    }

    @Test func backspaceAfterAPickedWordDeletesALetter() {
        var field = Field(autoCapitalize: false, text: "going ")
        field.choose(0)
        #expect(field.text == "going to ")
        field.press(.backspace)
        #expect(field.text == "going to")
        #expect(field.marked.isEmpty)
    }

    @Test func aPickedWordSettlesAsANextWordAndIsCounted() {
        var field = Field(autoCapitalize: false, text: "thank ")
        field.choose(0)
        field.choose(0)
        let picked = field.settled.first
        #expect(picked?.word == "you")
        #expect(picked?.previous == "thank")
        #expect(picked?.source == .next)
        #expect(picked?.pecked == false)
        var tally = GuessTally()
        #expect(tally.add(try! #require(picked)))
        #expect(tally.next == 1 && tally.words == 0)
        let metrics = RecordingMetrics()
        tally.report(to: metrics)
        #expect(metrics.sent.map(\.name) == ["nextword.picked"])
    }

    // MARK: Settings and the harness

    @Test func theSettingIsOnByDefaultAndReachesTheEngine() throws {
        let old = try JSONDecoder().decode(KeyboardSettings.self, from: Data(#"{"autospace":true}"#.utf8))
        #expect(old.nextWords)
        var settings = KeyboardSettings()
        settings.nextWords = false
        #expect(settings.composerSettings().nextWords == false)
        let back = try JSONDecoder().decode(KeyboardSettings.self, from: JSONEncoder().encode(settings))
        #expect(back.nextWords == false)
    }

    /// The harness says how many words a tap on the bar would have written.
    @Test func theHarnessCountsWordsATapAway() throws {
        let session = ReplayTests.record(["thank", "you", "so", "much"])
        #expect(session.typed == ["thank", "you", "so", "much"])
        let outcome = try Replay.run(session.recording, language: Self.english)
        #expect(outcome.words[1].next.first == "you")
        #expect(outcome.words[1].wasNextWord)
        #expect(outcome.nextWords >= 1)
        #expect(Replay.Report([outcome]).summary.contains("a tap away"))
    }

    // MARK: Two languages

    /// With English and Spanish both on, the language that knows the word before
    /// decides, and accents come back from the dictionary ("dificil" is written "difícil").
    @Test func spanishGuessesComeWithTheirAccents() throws {
        var settings = Replay.settings
        settings.guessCount = 5
        var composer = Composer(language: try Language.bundled(["en", "es"]), layout: Synth.layout, settings: settings)
        composer.setContext(before: "Muchas ")
        guard case .next(let afterMuchas, _, _) = composer.state.bar else {
            Issue.record("expected next words, got \(composer.state.bar)")
            return
        }
        #expect(afterMuchas.contains("gracias"))
        composer.setContext(before: "Muy ")
        guard case .next(let afterEl, _, _) = composer.state.bar else {
            Issue.record("expected next words, got \(composer.state.bar)")
            return
        }
        #expect(afterEl.first == "bien")
        #expect(afterEl.contains("difícil"))
        #expect(!afterEl.contains("dificil"))
        composer.setContext(before: "going ")
        guard case .next(let afterGoing, _, _) = composer.state.bar else {
            Issue.record("expected next words, got \(composer.state.bar)")
            return
        }
        #expect(afterGoing.first == "to")
    }

    /// A language turned on while the bar shows next words: they follow it.
    @Test func switchingLanguagesChangesTheGuesses() throws {
        var composer = Composer(language: Self.english, layout: Synth.layout, settings: Replay.settings)
        composer.setContext(before: "Muy ")
        #expect(composer.state.bar == .idle)
        _ = composer.setLanguage(try Language.bundled(["en", "es"]))
        composer.setContext(before: "Muy ")
        guard case .next(let words, _, _) = composer.state.bar else {
            Issue.record("expected next words, got \(composer.state.bar)")
            return
        }
        #expect(words.first == "bien")
    }
}
