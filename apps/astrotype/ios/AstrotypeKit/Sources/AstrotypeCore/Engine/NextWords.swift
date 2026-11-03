import Foundation

/// The words likely to come next, offered on the bar after each word before anything
/// is typed (features/next-word). Pure: the language's word pairs and what the person
/// writes after each word in, a few words out, best first.
///
///     NextWords.guesses(after: "going", models: language.ngramModels, personal: index, learned: words, count: 3)
///     // ["to", "on", "out"]
///     NextWords.guesses(after: NgramModel.sentenceStart, ...)   // ["i", "the", "he"]
///
/// A candidate's chance is the shipped pair's `P(word | previous)` mixed with the
/// person's own share after that word, `(1 − trust)·P + trust·mine`, where `trust`
/// grows with how many words the person has written after `previous`
/// (`total / (total + personalTrust)`). So "going" → "home" climbs for someone who
/// writes it, and a word the model has never seen ("flotilla" → "ships") still shows
/// once the person writes it. Words the person forgot from the bar are never offered,
/// and nor are contractions while the keyboard has no apostrophes ("dont").
///
/// With two languages each model that knows `previous` has its say and the likelier
/// wins (after "el" Spanish decides, after "the" English does). The models and the
/// person's pairs are keyed by plain letters (`Lexicon.fold`), so the caller writes
/// the accents back (`Composer` does, from the dictionary's spellings).
public enum NextWords {
    /// How many words after a previous word the person writes before their own habit
    /// weighs as much as the shipped pairs.
    public static let personalTrust: Float = 5

    /// Up to `count` words, lowercase, best first. Empty when neither the pairs nor the
    /// person know anything after `previous`.
    public static func guesses(after previous: String, models: [NgramModel], personal: PersonalIndex,
                               learned: LearnedWords, count: Int) -> [String] {
        guard count > 0 else { return [] }
        let mine = personal.following[previous] ?? [:]
        let total = mine.values.reduce(0, +)
        let trust = total > 0 ? total / (total + personalTrust) : 0
        var chance: [String: Float] = [:]
        // A few spare, since some are dropped below.
        for model in models {
            for (word, logP) in model.topNext(after: previous, limit: count + 8) {
                chance[word] = max(chance[word] ?? 0, (1 - trust) * exp(logP))
            }
        }
        for (word, n) in mine where n > 0 {
            chance[word, default: 0] += trust * n / total
        }
        return chance
            .filter { offerable($0.key) && learned.weight(of: $0.key) >= 0 }
            .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(count)
            .map(\.key)
    }

    /// Letters only, not a dropped-apostrophe contraction, and "a" and "i" the only
    /// single letters. The sentence start is never a word.
    static func offerable(_ word: String) -> Bool {
        guard !word.isEmpty, word.utf8.count <= 24, word.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 }),
              !PracticeWords.contractions.contains(word) else { return false }
        return word.count > 1 || word == "a" || word == "i"
    }
}
