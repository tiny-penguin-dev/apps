import Foundation

/// Runs the trained network: window ids in, log-probabilities of every vocabulary row
/// out (features/next-word-model). The live one is `CoreMLNextWordPredictor`; tests
/// pass a fake.
public protocol NextWordPredicting: AnyObject, Sendable {
    /// `ids` has exactly `NextWordModel.window` entries, padding (0) on the left.
    /// Nil when the model can't answer (not loaded, an error).
    func logProbabilities(_ ids: [Int32]) -> [Float]?
}

/// One language's next-word model: its vocabulary and the network, read the way it was
/// trained (`ml/nextword/`). It guesses from the whole current sentence, not only the
/// word before, so "I left my phone at the" gets "house" and "office", not "same".
///
///     let model = NextWordModel(code: "en", vocabulary: lines, predictor: coreML)
///     model.guesses(before: "I left my phone at the ", limit: 8)
///     // [("house", 0.09), ("office", 0.07), ...]
///
/// The words come back folded ("manana"), as the pairs' do; the composer writes the
/// accents back. Contractions and other words the bar never offers are left out.
public final class NextWordModel: @unchecked Sendable {
    /// The window the network reads, `<s>` included (`model.py`'s `context`).
    public static let window = 32
    static let pad: Int32 = 0, start: Int32 = 1, unknown: Int32 = 2, breakID: Int32 = 3

    public let code: String
    public let words: [String]
    private let ids: [String: Int32]
    private let offerable: [Bool]
    private let predictor: NextWordPredicting
    private let lock = NSLock()
    private var cache: (ids: [Int32], limit: Int, guesses: [(String, Float)])?

    /// `vocabulary` is `nextword-vocab.txt`: one word per line, the line number its id,
    /// the four specials (`<pad>`, `<s>`, `<unk>`, `,`) first.
    public init(code: String, vocabulary: [String], predictor: NextWordPredicting) {
        self.code = code
        self.words = vocabulary
        var ids: [String: Int32] = [:]
        for (i, word) in vocabulary.enumerated() where ids[word] == nil { ids[word] = Int32(i) }
        self.ids = ids
        self.offerable = vocabulary.enumerated().map { $0.offset > 3 && NextWords.offerable($0.element) }
        self.predictor = predictor
    }

    /// The network's input for these sentence tokens (`WordContext.tokens(before:)`):
    /// `<s>` then the words, the last `window` of them, right-aligned on padding.
    public func window(for tokens: [String]) -> [Int32] {
        var seq: [Int32] = [Self.start] + tokens.map { token in
            token == "," ? Self.breakID : ids[token] ?? Self.unknown
        }
        if seq.count > Self.window { seq = Array(seq.suffix(Self.window)) }
        return Array(repeating: Self.pad, count: Self.window - seq.count) + seq
    }

    /// The likeliest next words after `text` (the text before the cursor), best first,
    /// with their probabilities. Empty inside a word or when the network can't answer.
    /// The last answer is kept, so asking again for the same sentence costs nothing.
    public func guesses(before text: String, limit: Int) -> [(word: String, probability: Float)] {
        guard limit > 0, let tokens = WordContext.tokens(before: text) else { return [] }
        let input = window(for: tokens)
        lock.lock()
        if let cache, cache.ids == input, cache.limit == limit {
            lock.unlock()
            return cache.guesses
        }
        lock.unlock()
        guard let scores = predictor.logProbabilities(input) else { return [] }
        let top = Self.top(scores, limit: limit, offerable: offerable, words: words)
        lock.lock()
        cache = (input, limit, top)
        lock.unlock()
        return top
    }

    /// The `limit` best offerable rows, as words with probabilities.
    static func top(_ scores: [Float], limit: Int, offerable: [Bool], words: [String]) -> [(String, Float)] {
        var best: [(Int, Float)] = []
        best.reserveCapacity(limit + 1)
        for i in 0..<min(scores.count, offerable.count) where offerable[i] {
            let s = scores[i]
            if best.count == limit, let worst = best.last, s <= worst.1 { continue }
            let at = best.firstIndex { s > $0.1 } ?? best.count
            best.insert((i, s), at: at)
            if best.count > limit { best.removeLast() }
        }
        return best.map { (words[$0.0], exp($0.1)) }
    }
}

extension NextWordModel {
    /// Reads `nextword-vocab.txt`.
    public static func vocabulary(contentsOf url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).filter { !$0.isEmpty }
    }
}
