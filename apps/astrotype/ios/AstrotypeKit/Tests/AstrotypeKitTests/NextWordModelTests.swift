import AstrotypeCore
import Foundation
import Testing

/// A network that likes one word per previous id, so tests can tell what it read.
private final class FakePredictor: NextWordPredicting, @unchecked Sendable {
    var calls = 0
    var lastInput: [Int32] = []
    let rows: Int
    let answer: ([Int32]) -> [Int: Float]

    init(rows: Int, answer: @escaping ([Int32]) -> [Int: Float]) {
        self.rows = rows
        self.answer = answer
    }

    func logProbabilities(_ ids: [Int32]) -> [Float]? {
        calls += 1
        lastInput = ids
        var out = [Float](repeating: log(1e-6), count: rows)
        for (row, p) in answer(ids) { out[row] = log(p) }
        return out
    }
}

struct NextWordModelTests {
    // ids: 0 <pad>, 1 <s>, 2 <unk>, 3 ",", 4 the, 5 i, 6 left, 7 house, 8 office, 9 dont, 10 same
    let vocabulary = ["<pad>", "<s>", "<unk>", ",", "the", "i", "left", "house", "office", "dont", "same"]

    @Test func tokensAreTheSentenceAsTheModelWasTrained() {
        #expect(WordContext.tokens(before: "Hi. I left it at 5, then ") == ["i", "left", "it", "at", "<unk>", ",", "then"])
        #expect(WordContext.tokens(before: "Hi. ") == [])
        #expect(WordContext.tokens(before: "") == [])
        #expect(WordContext.tokens(before: "Hi. I le") == nil)
        #expect(WordContext.tokens(before: "Don't, ; go ") == ["dont", ",", "go"])
        #expect(WordContext.tokens(before: "Hola. ¿") == [])
        #expect(WordContext.tokens(before: "Mañana ") == ["manana"])
    }

    @Test func windowIsRightAlignedWithTheSentenceStart() {
        let model = NextWordModel(code: "en", vocabulary: vocabulary, predictor: FakePredictor(rows: 64) { _ in [:] })
        let ids = model.window(for: ["i", "left", "zzz", ","])
        #expect(ids.count == NextWordModel.window)
        #expect(Array(ids.suffix(5)) == [1, 5, 6, 2, 3])
        #expect(ids.prefix(NextWordModel.window - 5).allSatisfy { $0 == 0 })
        let long = model.window(for: Array(repeating: "the", count: 40))
        #expect(long.count == NextWordModel.window && long.allSatisfy { $0 == 4 })
    }

    @Test func guessesSkipSpecialsSpareRowsAndContractions() {
        let fake = FakePredictor(rows: 64) { _ in [3: 0.5, 9: 0.2, 7: 0.15, 8: 0.1, 10: 0.05, 40: 0.9] }
        let model = NextWordModel(code: "en", vocabulary: vocabulary, predictor: fake)
        let guesses = model.guesses(before: "I left my phone at the ", limit: 2)
        #expect(guesses.map(\.word) == ["house", "office"])
        #expect(abs(guesses[0].probability - 0.15) < 0.001)
        #expect(model.guesses(before: "I left my phone at the ho", limit: 2).isEmpty)
    }

    @Test func theSameSentenceIsAnsweredFromTheLastAnswer() {
        let fake = FakePredictor(rows: 64) { _ in [7: 0.5] }
        let model = NextWordModel(code: "en", vocabulary: vocabulary, predictor: fake)
        _ = model.guesses(before: "at the ", limit: 3)
        _ = model.guesses(before: "at the ", limit: 3)
        #expect(fake.calls == 1)
        _ = model.guesses(before: "at the house ", limit: 3)
        #expect(fake.calls == 2)
    }

    @Test func theComposerOffersTheModelsWordsAfterAWord() throws {
        let fake = FakePredictor(rows: 64) { ids in ids.last == 4 ? [7: 0.4, 8: 0.3, 10: 0.01] : [5: 0.5] }
        var composer = Composer(language: try Language.bundled(["en"]), layout: Synth.layout)
        composer.nextWordModels = [NextWordModel(code: "en", vocabulary: vocabulary, predictor: fake)]
        composer.setContext(before: "I left my phone at the ")
        guard case .next(let words, _, _) = composer.state.bar else {
            Issue.record("expected next words, got \(composer.state.bar)")
            return
        }
        #expect(Array(words.prefix(2)) == ["house", "office"])
        // At a sentence start the model's first word, capitalised.
        composer.setContext(before: "Done. ")
        guard case .next(let start, _, _) = composer.state.bar else {
            Issue.record("expected next words, got \(composer.state.bar)")
            return
        }
        #expect(start.first == "I")
    }

    @Test func modelGuessesMixWithThePersonsOwnWords() {
        let words = NextWords.guesses(after: "the", models: [], personal: PersonalIndex(), learned: LearnedWords(),
                                      count: 2, fromModel: [("house", 0.4), ("office", 0.3), ("same", 0.1)])
        #expect(words == ["house", "office"])
    }
}
