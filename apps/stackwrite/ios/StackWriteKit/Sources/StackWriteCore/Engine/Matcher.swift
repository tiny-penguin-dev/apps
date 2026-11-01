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
/// Pieces are read in touch-down order; two that landed within the swap window are
/// tried both ways. A word must start on each piece's first key and end on its last;
/// between them the word's letters are a subsequence of the keys a swipe crossed (a
/// crossed key may stand for a doubled letter). A tap that lands while a swipe is
/// still moving is also tried at the point the swipe had reached, so the other thumb
/// can drop a letter into a swipe ("hel|l|o"). Each match is scored by dynamic time
/// warping between the swipe and the path through the word's keys, the swipe's length,
/// the word's frequency, and what the person taught the keyboard.
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
    /// Two pieces that landed this close together are tried in both orders.
    public var swapWindow: TimeInterval = 0.12
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
        let orderings = Self.orderings(of: ordered, swapWindow: swapWindow)

        var out: [Candidate] = []
        if ordered.allSatisfy(\.isTap) {
            // Exact typing wins: what the person tapped (in the order that spells a word,
            // if two taps landed almost together), then common words that continue it.
            let strings = orderings.map { String($0.flatMap(\.keys)) }
            let typed = strings.first { dictionary.contains($0) || learned.contains($0) } ?? strings[0]
            let prior = dictionary.logPrior(of: typed).map { priorWeight * Double($0) } ?? -1
            out.append(Candidate(word: typed, score: prior + learned.weight(of: typed)))
            for word in dictionary.completions(of: typed, limit: limit - 1) where !out.contains(where: { $0.word == word }) {
                out.append(Candidate(word: word, score: priorWeight * Double(dictionary.logPrior(of: word) ?? -20) - 1))
            }
            return Array(out.prefix(limit))
        }

        var best: [String: Double] = [:]
        for ordering in orderings {
            for segments in segmentations(of: ordering) {
                for (word, score) in search(segments) {
                    best[word] = max(best[word] ?? -.infinity, score)
                }
            }
        }
        out = best.map { Candidate(word: $0.key, score: $0.value) }
            .sorted { $0.score > $1.score || ($0.score == $1.score && $0.word < $1.word) }
        if out.isEmpty {
            // Nothing fits: type the keys the swipe started and ended on, so a
            // word still comes out and can be fixed.
            out.append(Candidate(word: Self.fallback(ordered), score: -10))
        }
        return Array(out.prefix(limit))
    }

    // MARK: Orderings and segments

    /// The touch-down order, plus each way of swapping two pieces that landed within
    /// the swap window (at most four orderings).
    static func orderings(of pieces: [Piece], swapWindow: TimeInterval) -> [[Piece]] {
        var out = [pieces]
        guard pieces.count > 1 else { return out }
        for i in 0..<(pieces.count - 1) where pieces[i + 1].start - pieces[i].start < swapWindow {
            for ordering in out {
                var swapped = ordering
                swapped.swapAt(i, i + 1)
                out.append(swapped)
            }
            if out.count >= 4 { break }
        }
        return Array(out.prefix(4))
    }

    /// A stretch of one piece that the word's letters are matched against.
    struct Segment {
        var keys: [Character]
        /// The whole path of the piece this segment came from: the parts of a split
        /// swipe are scored together, as one path through the letters they contribute.
        var points: [CGPoint]
        var isTap: Bool
        /// Which piece (in the ordering) this segment came from.
        var source: Int
        /// The word must take this segment's first key.
        var anchoredStart = true
        /// The word must take this segment's last key.
        var anchoredEnd = true
        /// The segment may contribute no letter at all.
        var skippable = false

        init(_ piece: Piece, source: Int) {
            keys = piece.keys
            points = piece.points
            isTap = piece.isTap
            self.source = source
        }

        init(keys: [Character], of piece: Piece, source: Int, anchoredStart: Bool, anchoredEnd: Bool, skippable: Bool) {
            self.keys = keys
            self.points = piece.points
            self.isTap = false
            self.source = source
            self.anchoredStart = anchoredStart
            self.anchoredEnd = anchoredEnd
            self.skippable = skippable
        }
    }

    /// The pieces as segments, in order. When a tap landed while a swipe was moving, a
    /// second reading splits the swipe where the finger was and drops the tap in there.
    func segmentations(of pieces: [Piece]) -> [[Segment]] {
        let plain = pieces.enumerated().map { Segment($0.element, source: $0.offset) }
        var split: [Segment] = []
        var placed = Set<Int>()
        var didSplit = false
        for (index, piece) in pieces.enumerated() where !placed.contains(index) {
            guard !piece.isTap else {
                split.append(Segment(piece, source: index))
                continue
            }
            let inner = pieces.enumerated().filter { $0.offset > index && $0.element.isTap && piece.covers($0.element.start) }
            guard !inner.isEmpty, piece.times.count == piece.points.count else {
                split.append(Segment(piece, source: index))
                continue
            }
            var cutKey = 0
            var cutPoint = 0
            var parts: [Segment] = []
            for (offset, tap) in inner {
                guard let pointIndex = piece.pointIndex(at: tap.start), pointIndex >= cutPoint else { continue }
                let keyIndex = keyIndex(of: piece, upTo: pointIndex, from: cutKey)
                parts.append(Segment(keys: Array(piece.keys[cutKey...keyIndex]), of: piece, source: index,
                                     anchoredStart: parts.isEmpty, anchoredEnd: false, skippable: !parts.isEmpty))
                parts.append(Segment(tap, source: offset))
                placed.insert(offset)
                cutKey = keyIndex
                cutPoint = pointIndex
            }
            guard !parts.isEmpty else {
                split.append(Segment(piece, source: index))
                continue
            }
            let tail = Array(piece.keys[cutKey...])
            parts.append(Segment(keys: tail, of: piece, source: index,
                                 anchoredStart: false, anchoredEnd: true, skippable: tail.count == 1))
            split += parts
            didSplit = true
        }
        return didSplit ? [plain, split] : [plain]
    }

    /// The index in the swipe's keys of the key the finger had reached by `pointIndex`,
    /// no earlier than `from`. The points are walked in order against the crossed keys,
    /// so a key the swipe crosses twice ("h" in h-e-l-o) resolves to the right crossing.
    private func keyIndex(of piece: Piece, upTo pointIndex: Int, from: Int) -> Int {
        let keys = piece.keys
        var reached = -1
        for index in 0...pointIndex {
            guard let letter = layout.key(at: piece.points[index])?.character else { continue }
            if reached >= 0, keys[reached] == letter { continue }
            if let next = keys[(reached + 1)...].firstIndex(of: letter) { reached = next }
        }
        return max(reached, from)
    }

    // MARK: Search

    private struct SearchState: Hashable {
        var segment: Int
        var lastKey: Int
        var node: Int32
        var doubled: Bool
    }

    private func search(_ segments: [Segment]) -> [String: Double] {
        // The best score per word: two paths through the keys can spell the same word.
        var best: [String: Double] = [:]
        var seen = Set<SearchState>()
        // Each queue entry carries how many letters each segment has contributed so far.
        var queue: [(SearchState, [Int])] = [(SearchState(segment: 0, lastKey: -1, node: 0, doubled: false), [0])]
        var expanded = 0
        var index = 0
        while index < queue.count, expanded < budget {
            let (state, counts) = queue[index]
            index += 1
            if !seen.insert(state).inserted { continue }
            expanded += 1
            let segment = segments[state.segment]
            let keys = segment.keys
            // The same crossed key again, for a doubled letter in a swipe ("hello", "coffee").
            if state.lastKey >= 0, !state.doubled, !segment.isTap,
               let child = dictionary.child(of: state.node, label: Self.index(of: keys[state.lastKey])) {
                var next = counts
                next[next.count - 1] += 1
                queue.append((SearchState(segment: state.segment, lastKey: state.lastKey, node: child, doubled: true), next))
            }
            // Done with this segment: finish the word or go on to the next segment.
            let canLeave = state.lastKey >= 0
                ? (!segment.anchoredEnd || state.lastKey == keys.count - 1)
                : segment.skippable
            if canLeave {
                if state.segment == segments.count - 1 {
                    if let prior = dictionary.logPrior(at: state.node) {
                        let word = dictionary.word(at: state.node)
                        let value = score(word: word, prior: prior, counts: counts, segments: segments)
                        best[word] = max(best[word] ?? -.infinity, value)
                    }
                } else {
                    queue.append((SearchState(segment: state.segment + 1, lastKey: -1, node: state.node, doubled: false), counts + [0]))
                }
            }
            // Next letter: the segment's first key to begin (any key, for a segment that
            // continues a swipe after a tap), then any later crossed key.
            let range: Range<Int> = state.lastKey < 0
                ? (segment.anchoredStart ? 0..<min(1, keys.count) : 0..<keys.count)
                : (state.lastKey + 1)..<keys.count
            for j in range {
                guard let child = dictionary.child(of: state.node, label: Self.index(of: keys[j])) else { continue }
                var next = counts
                next[next.count - 1] += 1
                queue.append((SearchState(segment: state.segment, lastKey: j, node: child, doubled: false), next))
            }
        }
        return best
    }

    private func score(word: String, prior: Float, counts: [Int], segments: [Segment]) -> Double {
        let letters = Array(word)
        let unit = Double(layout.frame(of: .letter("q"))?.width ?? 33)
        // The letters each swipe contributed, across all of its segments.
        var swipes: [(points: [CGPoint], letters: [Character])] = []
        var sources: [Int: Int] = [:]
        var offset = 0
        for (i, segment) in segments.enumerated() {
            let count = counts[i]
            defer { offset += count }
            guard !segment.isTap, count > 0 else { continue }
            if let slot = sources[segment.source] {
                swipes[slot].letters += letters[offset..<(offset + count)]
            } else {
                sources[segment.source] = swipes.count
                swipes.append((segment.points, Array(letters[offset..<(offset + count)])))
            }
        }
        var distance = 0.0
        var weight = 0
        for swipe in swipes where swipe.letters.count > 1 && swipe.points.count > 1 {
            let count = swipe.letters.count
            let centers = swipe.letters.compactMap { layout.frame(of: .letter($0)).map { CGPoint(x: $0.midX, y: $0.midY) } }
            let ideal = Geometry.resample(centers, count: 32)
            let actual = Geometry.resample(swipe.points, count: 32)
            let lengths = abs(Geometry.length(centers) - Geometry.length(swipe.points))
            distance += Double(Geometry.dtw(actual, ideal) + CGFloat(lengthWeight) * lengths) / unit * Double(count)
            weight += count
        }
        let path = weight > 0 ? distance / Double(weight) : 0
        return -pathWeight * path + priorWeight * Double(prior) + learned.weight(of: word)
    }

    static func fallback(_ pieces: [Piece]) -> String {
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
