import Foundation

/// A guess for an open word.
public struct Candidate: Sendable, Equatable {
    public var word: String
    /// Higher is better. Around 0 for a clean match of a common word.
    public var score: Double

    public init(word: String, score: Double) {
        self.word = word
        self.score = score
    }
}

/// Turns the pieces of one open word into ranked guesses (BUILD.md "Core pieces").
/// A word must start on each piece's first key and end on its last; between them the
/// word's letters are a subsequence of the keys a swipe crossed (a crossed key may
/// stand for a doubled letter). Each match is then scored by dynamic time warping
/// between the swipe and the path through the word's keys, the word's frequency, and
/// what the person taught the keyboard.
///
///     let matcher = Matcher(dictionary: try Lexicon.bundled(), layout: layout)
///     matcher.candidates(for: pieces, limit: 3)
public struct Matcher: Sendable {
    public var dictionary: Lexicon
    public var layout: Layout
    public var learned: LearnedWords
    /// Score per key width of mean path distance.
    public var pathWeight = 1.0
    /// Score per unit of log frequency (0 for the most common word, about -9 for rare).
    public var priorWeight = 0.12
    /// Score per key width of difference between the swipe's length and the word's path
    /// length, so "the" does not win a swipe that went on to "there".
    public var lengthWeight = 0.15
    /// How many trie states a search may expand before it stops.
    public var budget = 40_000

    public init(dictionary: Lexicon, layout: Layout, learned: LearnedWords = LearnedWords()) {
        self.dictionary = dictionary
        self.layout = layout
        self.learned = learned
    }

    public func candidates(for pieces: [Piece], limit: Int = 3) -> [Candidate] {
        let ordered = pieces.sorted { $0.start < $1.start }.filter { !$0.keys.isEmpty }
        guard !ordered.isEmpty, limit > 0 else { return [] }
        let typed = String(ordered.flatMap(\.keys))
        let allTaps = ordered.allSatisfy(\.isTap)

        var matches = search(ordered)
        var out: [Candidate] = []
        if allTaps {
            // Exact typing wins: what the person tapped, then common words that continue it.
            let exactScore = matches.first { $0.word == typed }?.score ?? -1
            out.append(Candidate(word: typed, score: exactScore))
            matches.removeAll { $0.word == typed }
            for word in dictionary.completions(of: typed, limit: limit - 1) where !out.contains(where: { $0.word == word }) {
                out.append(Candidate(word: word, score: priorWeight * Double(dictionary.logPrior(of: word) ?? -20) - 1))
            }
        } else {
            matches.sort { $0.score > $1.score }
            out = Array(matches.prefix(limit))
            if out.isEmpty {
                // Nothing fits: type the keys the swipe started and ended on, so a
                // word still comes out and can be fixed.
                out.append(Candidate(word: fallback(ordered), score: -10))
            }
        }
        return Array(out.prefix(limit))
    }

    // MARK: Search

    private struct SearchState: Hashable {
        var piece: Int
        var lastKey: Int
        var node: Int32
        var doubled: Bool
    }

    private struct Match {
        var word: String
        var score: Double
    }

    private func search(_ pieces: [Piece]) -> [Match] {
        // The best score per word: two paths through the keys can spell the same word.
        var best: [String: Double] = [:]
        var seen = Set<SearchState>()
        // Each queue entry carries how many letters each piece has contributed so far.
        var queue: [(SearchState, [Int])] = [(SearchState(piece: 0, lastKey: -1, node: 0, doubled: false), [0])]
        var expanded = 0
        var index = 0
        while index < queue.count, expanded < budget {
            let (state, segments) = queue[index]
            index += 1
            if !seen.insert(state).inserted { continue }
            expanded += 1
            let piece = pieces[state.piece]
            let keys = piece.keys
            // The same crossed key again, for a doubled letter in a swipe ("hello", "coffee").
            if state.lastKey >= 0, !state.doubled, !piece.isTap,
               let child = dictionary.child(of: state.node, label: Self.index(of: keys[state.lastKey])) {
                var next = segments
                next[next.count - 1] += 1
                queue.append((SearchState(piece: state.piece, lastKey: state.lastKey, node: child, doubled: true), next))
            }
            if state.lastKey == keys.count - 1 {
                // This piece is spent: finish the word or go on to the next piece.
                if state.piece == pieces.count - 1 {
                    if let prior = dictionary.logPrior(at: state.node) {
                        let word = dictionary.word(at: state.node)
                        let value = score(word: word, prior: prior, segments: segments, pieces: pieces)
                        best[word] = max(best[word] ?? -.infinity, value)
                    }
                } else {
                    queue.append((SearchState(piece: state.piece + 1, lastKey: -1, node: state.node, doubled: false), segments + [0]))
                }
                continue
            }
            // Next letter: the piece's first key to begin, then any later crossed key.
            let range = state.lastKey < 0 ? 0...0 : (state.lastKey + 1)...(keys.count - 1)
            for j in range {
                guard let child = dictionary.child(of: state.node, label: Self.index(of: keys[j])) else { continue }
                var next = segments
                next[next.count - 1] += 1
                queue.append((SearchState(piece: state.piece, lastKey: j, node: child, doubled: false), next))
            }
        }
        return best.map { Match(word: $0.key, score: $0.value) }
    }

    private func score(word: String, prior: Float, segments: [Int], pieces: [Piece]) -> Double {
        let letters = Array(word)
        let unit = Double(layout.frame(of: .letter("q"))?.width ?? 33)
        var distance = 0.0
        var weight = 0
        var offset = 0
        for (i, piece) in pieces.enumerated() {
            let count = segments[i]
            defer { offset += count }
            guard !piece.isTap, count > 1 else { continue }
            let centers = letters[offset..<(offset + count)].compactMap { layout.frame(of: .letter($0)).map { CGPoint(x: $0.midX, y: $0.midY) } }
            let ideal = Geometry.resample(centers, count: 32)
            let actual = Geometry.resample(piece.points, count: 32)
            let lengths = abs(Geometry.length(centers) - Geometry.length(piece.points))
            distance += Double(Geometry.dtw(actual, ideal) + CGFloat(lengthWeight) * lengths) / unit * Double(count)
            weight += count
        }
        let path = weight > 0 ? distance / Double(weight) : 0
        return -pathWeight * path + priorWeight * Double(prior) + learned.weight(of: word)
    }

    private func fallback(_ pieces: [Piece]) -> String {
        var out = ""
        for piece in pieces {
            if piece.isTap || piece.keys.count <= 2 {
                out += String(piece.keys)
            } else {
                out += String([piece.keys[0], piece.keys[piece.keys.count - 1]])
            }
        }
        return out
    }

    /// The trie's letter index (1...26) for a lowercase letter, 0 otherwise.
    static func index(of letter: Character) -> Int {
        guard let ascii = letter.asciiValue, ascii >= 97, ascii <= 122 else { return 0 }
        return Int(ascii) - 96
    }
}
