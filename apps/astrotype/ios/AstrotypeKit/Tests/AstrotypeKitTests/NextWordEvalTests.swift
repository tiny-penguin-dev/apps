import AstrotypeCore
import Testing

struct NextWordEvalTests {
    @Test func scoresOnlyOfferableWordsAgainstTheGuessesBeforeThem() {
        let sentences = [["thank", "you", "so", "much"], ["i", "<unk>", ",", "dont", "go"]]
        let eval = NextWordEval.run(sentences: sentences) { context in
            switch context.last {
            case nil: ["i", "thank", "the"]
            case "thank": ["you", "god"]
            case "you": ["for", "very", "so"]
            default: []
            }
        }
        // Scored: thank, you, so, much, i, go ("dont" is a contraction, <unk> and "," are not words).
        #expect(eval.words == 6)
        #expect(eval.hits1 == 2)   // "you" after "thank", "i" at the start
        #expect(eval.hits3 == 4)   // and "thank", "so"
        #expect(eval.letters == 5 + 3 + 2 + 4 + 1 + 2)
        #expect(eval.lettersSaved == 5 + 3 + 2 + 1)
    }

    @Test func pairsOfferNothingAfterABreakOrAnUnknownWord() throws {
        let models = try Language.bundled(["en"]).ngramModels
        #expect(NextWordEval.pairGuesses(["going", ","], models: models).isEmpty)
        #expect(NextWordEval.pairGuesses(["<unk>"], models: models).isEmpty)
        #expect(NextWordEval.pairGuesses(["thank"], models: models).contains("you"))
        #expect(!NextWordEval.pairGuesses([], models: models).isEmpty)
    }
}
