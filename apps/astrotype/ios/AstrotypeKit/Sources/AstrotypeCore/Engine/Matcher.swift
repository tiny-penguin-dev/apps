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
/// crossed key may stand for a doubled letter), where each crossed key may also be read
/// as a neighbour the path passed close to (`nearRadius`), so a swipe that cut a corner
/// or landed on the next key still finds the word. A tap that lands while a swipe is
/// still moving is also tried at the point the swipe had reached, so the other thumb
/// can drop a letter into a swipe ("hel|l|o"). Each match is scored by dynamic time
/// warping between the swipe and the path through the word's keys, the swipe's length,
/// the word's frequency, how well it follows the words before it (`context`, the
/// language's word pairs), what the person taught the keyboard, and what it learned
/// from how they write (`personal`: their words and pairs).
///
///     let matcher = Matcher(language: try Language.bundled(), layout: layout)
///     matcher.context = WordContext.words(before: "going to the ")
///     matcher.candidates(for: pieces, limit: 3)
public struct Matcher: Sendable {
    public var dictionary: Lexicon
    /// The language's word pairs, nil to rank by frequency alone.
    public var ngrams: NgramModel?
    /// The words before the open word, oldest first (`WordContext.words`), empty for none.
    public var context: [String] = []
    public var layout: Layout
    /// What the person taught the keyboard: a weight on dictionary words, and words of
    /// their own, which a swipe can land on like any other (`learnedPrior`).
    public var learned: LearnedWords {
        didSet { learnedLexicon = Self.lexicon(of: learned) }
    }
    /// What the keyboard learned from the person's typing (features/smart-matching
    /// Phase B): words they use more than most people and the pairs they write.
    public var personal = PersonalIndex()
    /// The person's own words as a small trie, searched beside the dictionary.
    private var learnedLexicon: Lexicon
    /// The log frequency a word of the person's own counts as the first time they write
    /// it (rare, like a word near the end of the dictionary); each use lifts it
    /// (`LearnedWords.logPrior`), and a boost from the bar on top.
    public var learnedPrior: Float = -10
    /// Score per key width of mean path distance.
    public var pathWeight = 1.0
    /// Score per unit of log frequency (0 for the most common word, about -9 for rare).
    public var priorWeight = 0.12
    /// Score per unit of context bonus (`NgramModel.contextBonus`): how much the words
    /// before count against the swipe's shape. The same scale as `priorWeight`, so a
    /// pair ten times likelier than the word alone is worth a word ten times as common.
    public var contextWeight = 0.12
    /// Score per unit of log ratio between the person's use of a word and the
    /// dictionary's (`personalBonus`): the same scale as `priorWeight`, so a word the
    /// person uses ten times more than most people gains what a word ten times as
    /// common would.
    public var personalWordWeight = 0.12
    /// Score per unit of `log(1 + times the person wrote this pair)`.
    public var personalPairWeight = 0.15
    /// The most the personal terms together add.
    public var personalCap = 0.8
    /// Score per key width of difference between the swipe's length and the word's path
    /// length, so "the" does not win a swipe that went on to "there".
    public var lengthWeight = 0.15
    /// The weights the harness tunes (features/smart-matching Phase D), as one value.
    public struct Weights: Sendable, Equatable, Codable, CustomStringConvertible {
        public var path: Double
        public var prior: Double
        public var context: Double
        public var length: Double
        /// `nearRadius`, in key widths, and `nearPenalty`.
        public var near: Double
        public var standIn: Double

        public init(path: Double = 1.0, prior: Double = 0.12, context: Double = 0.12, length: Double = 0.15,
                    near: Double = 0.5, standIn: Double = 0.2) {
            self.path = path
            self.prior = prior
            self.context = context
            self.length = length
            self.near = near
            self.standIn = standIn
        }

        public var description: String {
            String(format: "path %.3f · prior %.3f · context %.3f · length %.3f · near %.2f · stand-in %.2f",
                   path, prior, context, length, near, standIn)
        }
    }

    public var weights: Weights {
        get {
            Weights(path: pathWeight, prior: priorWeight, context: contextWeight, length: lengthWeight,
                    near: Double(nearRadius), standIn: nearPenalty)
        }
        set {
            nearPenalty = newValue.standIn
            nearRadius = CGFloat(newValue.near)
            pathWeight = newValue.path
            priorWeight = newValue.prior
            contextWeight = newValue.context
            lengthWeight = newValue.length
        }
    }

    /// A key the path passed within this many key widths of (but did not cross) may
    /// stand in for the crossed key beside it; 0 reads only the keys crossed. The path
    /// distance still scores the stand-in, so a near miss costs what it should.
    public var nearRadius: CGFloat = 0.5
    /// Score per stand-in letter, on top of what the path distance says, so a word the
    /// keys actually crossed wins a close call.
    public var nearPenalty = 0.2
    /// How sure the keyboard must be of a real word before it writes it in place of
    /// pecked letters that spell none ("bting" for "bring"), 0 to 1: at 0.5 it switches
    /// when it is at least 50% sure; at 1 it never writes letters that are not a word
    /// (the dictionary's or the person's); at 0 it writes what was tapped. A swipe that
    /// fits no word comes out as the nearest real word at any strictness.
    public var strictness = 0.8
    /// The log prior that letters spelling no word count as: below the dictionary's
    /// rarest word (about -11.6), so a real word close by wins a close call.
    public var unknownPrior: Float = -13
    /// Score per natural log of odds, for turning a score gap into how sure the
    /// keyboard is: the prior's scale, where a word e times as common scores 0.12 more.
    public var confidenceScale = 0.12
    /// The most a real word may differ from the letters (`EditCosts`) to be offered
    /// for them: about three slips.
    public var maxEditCost = 1.4
    /// Two pieces that landed this close together are tried in both orders.
    public var swapWindow: TimeInterval = 0.12
    /// How many trie states a search may expand before it stops.
    public var budget = 40_000

    public init(dictionary: Lexicon, ngrams: NgramModel? = nil, layout: Layout, learned: LearnedWords = LearnedWords()) {
        self.dictionary = dictionary
        self.ngrams = ngrams
        self.layout = layout
        self.learned = learned
        self.learnedLexicon = Self.lexicon(of: learned)
    }

    public init(language: Language, layout: Layout, learned: LearnedWords = LearnedWords()) {
        self.init(dictionary: language.lexicon, ngrams: language.ngrams, layout: layout, learned: learned)
    }

    /// The word right before the open one, for the pair model; nil without context.
    var previousWord: String? { context.last }

    /// The context's say on `word`, given the word's log prior from the dictionary.
    func contextBonus(for word: String, prior: Float) -> Double {
        guard let ngrams, let previous = previousWord else { return 0 }
        return Double(ngrams.contextBonus(for: word, after: previous, unigramLogProbability: prior + dictionary.logProbabilityOffset))
    }

    /// The person's say on `word`: how much more they use it than the dictionary
    /// expects, and how often they wrote it after the previous word. Never negative, so
    /// a word they have not used yet loses nothing.
    func personalBonus(for word: String, prior: Float) -> Double {
        guard !personal.isEmpty else { return 0 }
        var bonus = 0.0
        let count = Double(personal.wordCount(word))
        if count > 0, personal.totalWords > 0 {
            // Their count against what their total would give the word in general.
            let expected = Double(personal.totalWords) * exp(Double(prior + dictionary.logProbabilityOffset))
            bonus += personalWordWeight * min(4, max(0, log((count + 1) / (expected + 1))))
        }
        if let previous = previousWord {
            bonus += personalPairWeight * log(1 + Double(personal.pairCount(previous, word)))
        }
        return min(bonus, personalCap)
    }

    static func lexicon(of learned: LearnedWords) -> Lexicon {
        Lexicon(entries: learned.entries.keys.filter { learned.contains($0) }.map { Lexicon.Entry(word: $0, frequency: 1) })
    }

    /// The guesses, best first. `final` is false while the word is still being typed:
    /// pecked letters that begin a word ("bri" on the way to "bring") then stay as they
    /// are; when it is true (on space) they too must make a word, as `strictness` says.
    public func candidates(for pieces: [Piece], limit: Int = 3, final: Bool = true) -> [Candidate] {
        let ordered = pieces.sorted { $0.start < $1.start }.filter { !$0.keys.isEmpty }
        guard !ordered.isEmpty, limit > 0 else { return [] }
        let orderings = Self.orderings(of: ordered, swapWindow: swapWindow)

        if ordered.allSatisfy(\.isTap) {
            // Exact typing wins when it spells a word (in the order that spells one, if
            // two taps landed almost together), or begins one while typing goes on.
            let strings = orderings.map { String($0.flatMap(\.keys)) }
            let index = strings.firstIndex(where: isKnown) ?? 0
            let typed = strings[index]
            if isKnown(typed) || typed.count < 2 || (!final && !dictionary.completions(of: typed, limit: 1).isEmpty) {
                return exactly(typed, limit: limit)
            }
            return resolve(typed, points: orderings[index].map { $0.points.first }, limit: limit, pecked: true)
        }

        var best: [String: Double] = [:]
        for ordering in orderings {
            for segments in segmentations(of: ordering) {
                for (word, score) in search(segments, in: dictionary, prior: nil) {
                    best[word] = max(best[word] ?? -.infinity, score)
                }
                guard learnedLexicon.nodeCount > 1 else { continue }
                for (word, score) in search(segments, in: learnedLexicon, prior: ownPrior) {
                    best[word] = max(best[word] ?? -.infinity, score)
                }
            }
        }
        let out = Self.ranked(best)
        if out.isEmpty {
            // Nothing fits the keys as crossed: the nearest real words to the keys the
            // swipes started and ended on, and those keys themselves only when no word
            // is near (and strictness allows letters at all).
            return resolve(Self.fallback(ordered), points: [], limit: limit, pecked: false)
        }
        return Array(out.prefix(limit))
    }

    /// The log prior of a word of the person's own, from how often they wrote it.
    func ownPrior(_ word: String) -> Float {
        learned.logPrior(of: word, base: learnedPrior)
    }

    /// Words and scores as guesses, best first (ties alphabetical, so runs repeat).
    static func ranked(_ scores: [String: Double]) -> [Candidate] {
        let candidates: [Candidate] = scores.map { (word: String, score: Double) in Candidate(word: word, score: score) }
        return candidates.sorted { (a: Candidate, b: Candidate) -> Bool in
            if a.score != b.score { return a.score > b.score }
            return a.word < b.word
        }
    }

    /// In the dictionary or the person's own words.
    func isKnown(_ word: String) -> Bool {
        dictionary.contains(word) || learned.contains(word)
    }

    /// What was tapped, then common words that continue it, the context deciding among them.
    private func exactly(_ typed: String, limit: Int) -> [Candidate] {
        let prior = priorWeight * Double(dictionary.logPrior(of: typed) ?? (learned.contains(typed) ? ownPrior(typed) : unknownPrior))
        var out = [Candidate(word: typed, score: prior + learned.weight(of: typed))]
        let completions = dictionary.completions(of: typed, limit: limit + 2)
            .filter { $0 != typed }
            .map { word in
                let own = dictionary.logPrior(of: word) ?? -20
                return Candidate(word: word, score: priorWeight * Double(own) + contextWeight * contextBonus(for: word, prior: own)
                                 + personalBonus(for: word, prior: own) - 1)
            }
            .sorted { $0.score > $1.score }
        out += completions.prefix(limit - 1)
        return Array(out.prefix(limit))
    }

    /// Letters that spell no word, against the real words nearest them: the nearest
    /// goes first when the keyboard is sure enough of it (`strictness`), the letters
    /// stay in the bar behind it (unless strictness is 1), so they can still be chosen.
    /// Letters a swipe fell back to (`pecked` false) were never spelled on purpose, so
    /// any near word beats them.
    private func resolve(_ letters: String, points: [CGPoint?], limit: Int, pecked: Bool) -> [Candidate] {
        let near = nearestWords(to: letters, points: points, limit: limit)
        let literal = Candidate(word: letters, score: priorWeight * Double(unknownPrior))
        guard strictness < 1 else { return near }
        guard let best = near.first else { return [literal] }
        let sure = !pecked || (strictness > 0 && confidence(of: best, over: literal) >= 1 - strictness)
        var ordered: [Candidate] = sure ? [best, literal] : [literal, best]
        ordered.append(contentsOf: near.dropFirst())
        return Array(ordered.prefix(limit))
    }

    /// How sure the keyboard is of `word` rather than `other`, 0 to 1, from their scores.
    func confidence(of word: Candidate, over other: Candidate) -> Double {
        1 / (1 + exp(-(word.score - other.score) / confidenceScale))
    }

    // MARK: Nearest words

    /// What a slip costs, in score units (the prior's scale: 0.12 is a word e times as
    /// common). A tap on the key next door costs `substitution` plus `distance` per
    /// squared key width between where it landed and the meant key's centre, so a tap
    /// on the edge between two keys costs little and one two keys away a lot.
    public struct EditCosts: Sendable, Equatable {
        public var substitution = 0.2
        public var distance = 0.25
        /// A letter of the word with no tap for it, and a tap for no letter.
        public var missing = 0.45
        public var extra = 0.6
        /// Two letters in the wrong order, which two thumbs make easily.
        public var swapped = 0.3
        public init() {}
    }

    public var editCosts = EditCosts()

    /// The real words (the dictionary's and the person's) within `maxEditCost` of
    /// `letters`, scored like any guess less what their slips cost, best first.
    /// `points` are where each letter was tapped, when known.
    func nearestWords(to letters: String, points: [CGPoint?], limit: Int) -> [Candidate] {
        let typed = letters.utf8.map { Int($0) - 96 }
        guard !typed.isEmpty, typed.allSatisfy({ (1...26).contains($0) }), limit > 0 else { return [] }
        let unit = Double(layout.distanceUnit)
        // What putting each letter of the alphabet in for each tap costs.
        var substitute = [[Double]](repeating: [Double](repeating: 0, count: 27), count: typed.count)
        for (i, label) in typed.enumerated() {
            let key = Self.alphabet[label - 1]
            let from = (points.indices.contains(i) ? points[i] : nil) ?? layout.frame(of: .letter(key)).map { CGPoint(x: $0.midX, y: $0.midY) }
            for (l, letter) in Self.alphabet.enumerated() where letter != key {
                guard let from, let frame = layout.frame(of: .letter(letter)) else { substitute[i][l + 1] = .infinity; continue }
                let d = Double(Geometry.distance(from, CGPoint(x: frame.midX, y: frame.midY))) / unit
                substitute[i][l + 1] = editCosts.substitution + editCosts.distance * d * d
            }
        }
        var best: [String: Double] = [:]
        func collect(_ lexicon: Lexicon, prior fixed: ((String) -> Float)?) {
            for (node, cost) in nearest(typed, in: lexicon, substitute: substitute) {
                guard let own = lexicon.logPrior(at: node) else { continue }
                let word = lexicon.word(at: node)
                guard word != letters else { continue }
                let prior = fixed?(word) ?? own
                let ranking: Double = priorWeight * Double(prior) + contextWeight * contextBonus(for: word, prior: prior)
                let value: Double = ranking + personalBonus(for: word, prior: prior) + learned.weight(of: word) - cost
                best[word] = max(best[word] ?? -.infinity, value)
            }
        }
        collect(dictionary, prior: nil)
        if learnedLexicon.nodeCount > 1 { collect(learnedLexicon, prior: ownPrior) }
        return Array(Self.ranked(best).prefix(limit))
    }

    /// Weighted edit distance from `typed` to every word in the trie, walking it depth
    /// first with one row of costs per node and dropping a branch once every cost in
    /// its row is over `maxEditCost`. Returns the word nodes within it.
    private func nearest(_ typed: [Int], in lexicon: Lexicon, substitute: [[Double]]) -> [(Int32, Double)] {
        let n = typed.count
        let costs = editCosts
        let root = (0...n).map { Double($0) * costs.extra }
        var out: [(Int32, Double)] = []
        // Each node with its letter, its parent's row and letter, and the row above that.
        var stack: [(node: Int32, label: Int, above: [Double], aboveLabel: Int, twoAbove: [Double])] = []
        lexicon.forEachChild(of: 0) { label, child in stack.append((child, label, root, 0, [])) }
        var visited = 0
        while let (node, label, above, aboveLabel, twoAbove) = stack.popLast(), visited < 200_000 {
            visited += 1
            var row = [Double](repeating: 0, count: n + 1)
            row[0] = above[0] + costs.missing
            for j in 1...n {
                let take = typed[j - 1] == label ? 0 : substitute[j - 1][label]
                var value = min(above[j] + costs.missing, row[j - 1] + costs.extra, above[j - 1] + take)
                // "ab" tapped for "ba": this letter and the one before it, swapped.
                if j >= 2, !twoAbove.isEmpty, label != aboveLabel, typed[j - 1] == aboveLabel, typed[j - 2] == label {
                    value = min(value, twoAbove[j - 2] + costs.swapped)
                }
                row[j] = value
            }
            guard let low = row.min(), low <= maxEditCost else { continue }
            if row[n] <= maxEditCost, lexicon.logPrior(at: node) != nil { out.append((node, row[n])) }
            lexicon.forEachChild(of: node) { childLabel, child in stack.append((child, childLabel, row, label, above)) }
        }
        return out
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
        /// Per key, the neighbours the path passed close to, which may stand in for it.
        var near: [[Character]]
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

        init(_ piece: Piece, source: Int, near: [[Character]]) {
            keys = piece.keys
            self.near = near
            points = piece.points
            isTap = piece.isTap
            self.source = source
        }

        init(keys: [Character], near: [[Character]], of piece: Piece, source: Int, anchoredStart: Bool, anchoredEnd: Bool, skippable: Bool) {
            self.keys = keys
            self.near = near
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
        let nears = pieces.map(nearKeys(of:))
        let plain = pieces.enumerated().map { Segment($0.element, source: $0.offset, near: nears[$0.offset]) }
        var split: [Segment] = []
        var placed = Set<Int>()
        var didSplit = false
        for (index, piece) in pieces.enumerated() where !placed.contains(index) {
            guard !piece.isTap else {
                split.append(Segment(piece, source: index, near: nears[index]))
                continue
            }
            let inner = pieces.enumerated().filter { $0.offset > index && $0.element.isTap && piece.covers($0.element.start) }
            guard !inner.isEmpty, piece.times.count == piece.points.count else {
                split.append(Segment(piece, source: index, near: nears[index]))
                continue
            }
            var cutKey = 0
            var cutPoint = 0
            var parts: [Segment] = []
            for (offset, tap) in inner {
                guard let pointIndex = piece.pointIndex(at: tap.start), pointIndex >= cutPoint else { continue }
                let keyIndex = keyIndex(of: piece, upTo: pointIndex, from: cutKey)
                parts.append(Segment(keys: Array(piece.keys[cutKey...keyIndex]), near: Array(nears[index][cutKey...keyIndex]),
                                     of: piece, source: index,
                                     anchoredStart: parts.isEmpty, anchoredEnd: false, skippable: !parts.isEmpty))
                parts.append(Segment(tap, source: offset, near: nears[offset]))
                placed.insert(offset)
                cutKey = keyIndex
                cutPoint = pointIndex
            }
            guard !parts.isEmpty else {
                split.append(Segment(piece, source: index, near: nears[index]))
                continue
            }
            let tail = Array(piece.keys[cutKey...])
            parts.append(Segment(keys: tail, near: Array(nears[index][cutKey...]), of: piece, source: index,
                                 anchoredStart: false, anchoredEnd: true, skippable: tail.count == 1))
            split += parts
            didSplit = true
        }
        return didSplit ? [plain, split] : [plain]
    }

    /// For each key the piece crossed, the neighbouring letters (centres within 1.5 key
    /// widths of it) that its stretch of path came within `nearRadius` of a key's edge
    /// of: the letters it may stand for besides its own. A tap's are the keys around
    /// where it landed.
    func nearKeys(of piece: Piece) -> [[Character]] {
        guard nearRadius > 0, let unit = layout.frame(of: .letter("q")), !piece.points.isEmpty else {
            return piece.keys.map { _ in [] }
        }
        let walked = piece.points.count > 1 ? Geometry.walk(piece.points, step: 4) : piece.points
        // Which crossed key each walked point belongs to, in order.
        var owner: [Int] = []
        var reached = 0
        for point in walked {
            if let letter = layout.key(at: point)?.character,
               let next = piece.keys[reached...].firstIndex(of: letter), next <= reached + 1 {
                reached = next
            }
            owner.append(reached)
        }
        let margin = nearRadius * unit.width
        var out = Array(repeating: [Character](), count: piece.keys.count)
        for (index, key) in piece.keys.enumerated() {
            guard let home = layout.frame(of: .letter(key), on: piece.side) else { continue }
            let stretch = walked.indices.filter { owner[$0] == index }.map { walked[$0] }
            let points = stretch.isEmpty ? [walked[index == 0 ? 0 : walked.count - 1]] : stretch
            for letter in Self.alphabet where letter != key {
                guard let frame = layout.frame(of: .letter(letter), on: piece.side),
                      Geometry.distance(CGPoint(x: frame.midX, y: frame.midY), CGPoint(x: home.midX, y: home.midY)) < unit.width * 1.5,
                      !piece.keys.contains(letter) || piece.isTap else { continue }
                let grown = frame.insetBy(dx: -margin, dy: -margin * frame.height / frame.width)
                if points.contains(where: { grown.contains($0) }) { out[index].append(letter) }
            }
        }
        return out
    }

    static let alphabet = Array("abcdefghijklmnopqrstuvwxyz")

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
        /// The trie label of the letter taken for `lastKey` (it or a neighbour).
        var letter: Int
    }

    /// The words in `lexicon` that the segments can spell, with their scores. `prior`
    /// stands in for the lexicon's own word frequencies when given.
    private func search(_ segments: [Segment], in lexicon: Lexicon, prior fixedPrior: ((String) -> Float)?) -> [String: Double] {
        // The best score per word: two paths through the keys can spell the same word.
        var best: [String: Double] = [:]
        var seen = Set<SearchState>()
        // Each queue entry carries how many letters each segment has contributed so far.
        // And how many of its letters were stand-ins for a crossed key.
        var queue: [(SearchState, [Int], Int)] = [(SearchState(segment: 0, lastKey: -1, node: 0, doubled: false, letter: 0), [0], 0)]
        var expanded = 0
        var index = 0
        while index < queue.count, expanded < budget {
            let (state, counts, standIns) = queue[index]
            index += 1
            if !seen.insert(state).inserted { continue }
            expanded += 1
            let segment = segments[state.segment]
            let keys = segment.keys
            // The same crossed key again, for a doubled letter in a swipe ("hello", "coffee").
            if state.lastKey >= 0, !state.doubled, !segment.isTap,
               let child = lexicon.child(of: state.node, label: state.letter) {
                var next = counts
                next[next.count - 1] += 1
                queue.append((SearchState(segment: state.segment, lastKey: state.lastKey, node: child, doubled: true, letter: state.letter), next, standIns))
            }
            // Done with this segment: finish the word or go on to the next segment.
            let canLeave = state.lastKey >= 0
                ? (!segment.anchoredEnd || state.lastKey == keys.count - 1)
                : segment.skippable
            if canLeave {
                if state.segment == segments.count - 1 {
                    if let own = lexicon.logPrior(at: state.node) {
                        let word = lexicon.word(at: state.node)
                        let prior = fixedPrior?(word) ?? own
                        let value = score(word: word, prior: prior, counts: counts, segments: segments) - nearPenalty * Double(standIns)
                        best[word] = max(best[word] ?? -.infinity, value)
                    }
                } else {
                    queue.append((SearchState(segment: state.segment + 1, lastKey: -1, node: state.node, doubled: false, letter: 0), counts + [0], standIns))
                }
            }
            // Next letter: the segment's first key to begin (any key, for a segment that
            // continues a swipe after a tap), then any later crossed key.
            let range: Range<Int> = state.lastKey < 0
                ? (segment.anchoredStart ? 0..<min(1, keys.count) : 0..<keys.count)
                : (state.lastKey + 1)..<keys.count
            for j in range {
                for (n, letter) in ([keys[j]] + (segment.near.indices.contains(j) ? segment.near[j] : [])).enumerated() {
                    let label = Self.index(of: letter)
                    guard let child = lexicon.child(of: state.node, label: label) else { continue }
                    var next = counts
                    next[next.count - 1] += 1
                    queue.append((SearchState(segment: state.segment, lastKey: j, node: child, doubled: false, letter: label), next,
                                   standIns + (n > 0 ? 1 : 0)))
                }
            }
        }
        return best
    }

    private func score(word: String, prior: Float, counts: [Int], segments: [Segment]) -> Double {
        let letters = Array(word)
        let unit = Double(layout.distanceUnit)
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
            // On a split keyboard a middle letter is on both halves: the swipe's own.
            let side = layout.side(at: swipe.points[0])
            let centers = swipe.letters.compactMap { layout.frame(of: .letter($0), on: side).map { CGPoint(x: $0.midX, y: $0.midY) } }
            let ideal = Geometry.resample(centers, count: 32)
            let actual = Geometry.resample(swipe.points, count: 32)
            let lengths = abs(Geometry.length(centers) - Geometry.length(swipe.points))
            distance += Double(Geometry.dtw(actual, ideal) + CGFloat(lengthWeight) * lengths) / unit * Double(count)
            weight += count
        }
        let path = weight > 0 ? distance / Double(weight) : 0
        return -pathWeight * path + priorWeight * Double(prior) + contextWeight * contextBonus(for: word, prior: prior)
            + personalBonus(for: word, prior: prior) + learned.weight(of: word)
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
