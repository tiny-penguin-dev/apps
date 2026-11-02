import Foundation

/// The prompts for "Practice words" (features/smart-matching Phase D): one common word or
/// a short phrase at a time, drawn from the language itself so recordings cover far more
/// than the speed test's sentences. Phrases follow the word-pair model ("going to the",
/// "thank you"), single words come from the dictionary by a random opening, so the keys
/// and pairs people practise spread across the keyboard. A seed makes the run repeat.
///
///     var words = PracticeWords(language: english, seed: 7)
///     words.next()    // "see you"
///     words.next()    // "probably"
public struct PracticeWords: Sendable {
    public let language: Language
    /// How many prompts back a word may not come again.
    public var memory = 40
    private var generator: SeededGenerator
    private var recent: [String] = []

    public init(language: Language, seed: UInt64? = nil) {
        self.language = language
        generator = SeededGenerator(seed: seed ?? UInt64.random(in: 0...UInt64.max))
    }

    /// The next prompt: one to three lowercase words, space separated.
    public mutating func next() -> String {
        for _ in 0..<20 {
            let prompt = Double.random(in: 0..<1, using: &generator) < 0.5 ? phrase() : word()
            guard let prompt, !recent.contains(prompt) else { continue }
            recent.append(prompt)
            if recent.count > memory { recent.removeFirst() }
            return prompt
        }
        return "the"
    }

    /// A short phrase that follows the word pairs, from a sentence start.
    private mutating func phrase() -> String? {
        guard let model = language.ngrams else { return word() }
        var words: [String] = []
        var previous = NgramModel.sentenceStart
        let length = Int.random(in: 1...3, using: &generator)
        while words.count < length {
            let options = model.likelyWords(after: previous, limit: words.isEmpty ? 60 : 12).filter(Self.isTypeable)
            guard let pick = options.randomElement(using: &generator) else { break }
            words.append(pick)
            previous = pick
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// A common word with a random opening: two letters, then the dictionary's commonest
    /// words that start with them.
    private mutating func word() -> String? {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let opening = String([letters.randomElement(using: &generator)!, letters.randomElement(using: &generator)!])
        let options = language.lexicon.completions(of: opening, limit: 4).filter { word in
            word.count >= 3 && Self.isTypeable(word) && (language.lexicon.logPrior(of: word) ?? -.infinity) > Self.commonPrior
        }
        return options.randomElement(using: &generator)
    }

    /// Single words come from about the commonest 4,500 (log frequency against "the").
    static let commonPrior: Float = -8

    /// Contractions with the apostrophe dropped, as the dictionary and the pairs keep
    /// them: not words to ask anyone to type.
    static let contractions: Set<String> = [
        "dont", "doesnt", "didnt", "cant", "couldnt", "wouldnt", "shouldnt", "wont", "isnt", "arent", "wasnt",
        "werent", "havent", "hasnt", "hadnt", "im", "ive", "id", "youre", "youve", "youll", "youd", "theyre",
        "theyve", "theyll", "theyd", "hes", "shes", "thats", "whats", "wheres", "theres", "weve", "itll", "whos",
        "aint", "lets", "ill", "wed", "hed", "shed",
    ]

    /// Letters only, no dropped-apostrophe contraction, and "a" and "i" the only
    /// one-letter words.
    static func isTypeable(_ word: String) -> Bool {
        guard word.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 }), !word.isEmpty, !contractions.contains(word) else { return false }
        return word.count > 1 || word == "a" || word == "i"
    }
}
