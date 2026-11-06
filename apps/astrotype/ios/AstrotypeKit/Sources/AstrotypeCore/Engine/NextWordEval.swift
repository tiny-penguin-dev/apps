import Foundation

/// How good next-word guesses are on held-back sentences (features/next-word-model):
/// at every word of every sentence, were the guesses offered before it the word that
/// came? The same rules score the shipped word pairs here (`astrotype-tools nexteval`)
/// and the trained model in `ml/nextword/evaluate.py`, so the two numbers compare.
///
///     let eval = NextWordEval.run(sentences: [["thank", "you", "so", "much"]]) { context in
///         NextWords.guesses(after: context.last ?? NgramModel.sentenceStart, models: models,
///                           personal: PersonalIndex(), learned: LearnedWords(), count: 3)
///     }
///     eval.top3   // share of words that were one of the three guesses
///
/// Sentences are folded words as `ml/nextword/make_text.py` writes them: `<unk>` for a
/// word outside the lexicon and `,` for a break. Every word that is offerable (letters
/// only, not a contraction, `NextWords.offerable`) is scored, with the words before it
/// in its sentence as context, breaks and unknown words included (the pairs offer
/// nothing after either, and that counts as a miss).
public struct NextWordEval: Sendable, Equatable {
    /// Words scored.
    public var words = 0
    public var hits1 = 0
    public var hits3 = 0
    /// Letters in the words scored, and in those one of the three guesses had: a tap on
    /// the bar writes the whole word, so that share is roughly the typing saved.
    public var letters = 0
    public var lettersSaved = 0

    public var top1: Double { words == 0 ? 0 : Double(hits1) / Double(words) }
    public var top3: Double { words == 0 ? 0 : Double(hits3) / Double(words) }
    public var saved: Double { letters == 0 ? 0 : Double(lettersSaved) / Double(letters) }

    public init() {}

    /// Scores `guesses` (best first) on every scored word of `sentences`; it gets the
    /// tokens before the word in its sentence.
    public static func run(sentences: some Sequence<[String]>, guesses: ([String]) -> [String]) -> NextWordEval {
        var eval = NextWordEval()
        for sentence in sentences {
            for (i, word) in sentence.enumerated() where NextWords.offerable(word) {
                let offered = guesses(Array(sentence[..<i]))
                eval.words += 1
                eval.letters += word.count
                if offered.first == word { eval.hits1 += 1 }
                if offered.prefix(3).contains(word) {
                    eval.hits3 += 1
                    eval.lettersSaved += word.count
                }
            }
        }
        return eval
    }

    /// The shipped pairs' guesses for a context: nothing after a break or an unknown
    /// word, the sentence start's at the start.
    public static func pairGuesses(_ context: [String], models: [NgramModel]) -> [String] {
        let previous = context.last ?? NgramModel.sentenceStart
        guard previous != ",", previous != "<unk>" else { return [] }
        return NextWords.guesses(after: previous, models: models, personal: PersonalIndex(),
                                 learned: LearnedWords(), count: 3)
    }

    public var summary: String {
        String(format: "%d words · top-1 %.1f%% · top-3 %.1f%% · letters saved %.1f%%",
               words, top1 * 100, top3 * 100, saved * 100)
    }
}
