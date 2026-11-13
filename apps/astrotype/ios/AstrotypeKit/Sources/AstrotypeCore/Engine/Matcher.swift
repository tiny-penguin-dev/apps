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
/// crossed key may stand for a doubled letter, or for itself and a neighbour it brushed),
/// where each crossed key may also be read as a neighbour the path passed close to
/// (`nearRadius`, `mayStandIn`), so a swipe that cut a corner
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
    /// The languages' word pairs (one model per language, on folded words), empty to
    /// rank by frequency alone.
    public var ngramModels: [NgramModel]
    /// The first word-pair model; setting it leaves just that one.
    public var ngrams: NgramModel? {
        get { ngramModels.first }
        set { ngramModels = newValue.map { [$0] } ?? [] }
    }
    /// The words before the open word, oldest first (`WordContext.words`), empty for none.
    public var context: [String] = []
    public var layout: Layout
    /// What the person taught the keyboard: a weight on dictionary words, and words of
    /// their own, which a swipe can land on like any other (`learnedPrior`).
    public var learned: LearnedWords {
        didSet { learnedLexicon = Self.lexicon(of: learned, shortcuts: shortcuts, language: learnedLanguage) }
    }
    /// The sentence's language when it is clear (`Composer.lockedLanguage`): only the
    /// person's words of that language, or of every language, are searched. Nil: all.
    public var learnedLanguage: String? {
        didSet { if learnedLanguage != oldValue { learnedLexicon = Self.lexicon(of: learned, shortcuts: shortcuts, language: learnedLanguage) } }
    }
    /// The text replacements' shortcuts (features/text-replacements), lowercase: searched
    /// with the person's own words, so a swipe or taps can land on one, ranked like a
    /// word they write often (`shortcutPrior`).
    public var shortcuts: Set<String> = [] {
        didSet { if shortcuts != oldValue { learnedLexicon = Self.lexicon(of: learned, shortcuts: shortcuts, language: learnedLanguage) } }
    }
    /// The log frequency a shortcut counts as: a fairly common word.
    public var shortcutPrior: Float = -5
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
    /// What the next-word models said could follow the words before the open word
    /// (features/next-word-model), one per language loaded; empty leaves the context
    /// to the word pairs. A word a model knows is ranked by it instead of by the pairs:
    /// it reads the whole sentence, so it can tell a swipe that fits the shape but
    /// makes no sense there from the one that fits both.
    public var nextWords: [NextWordScores] = []
    /// Score per unit of the next-word model's bonus (`modelBonus`), on the same scale
    /// as `contextWeight`.
    public var modelWeight = 0.12
    /// How much of the model's guess goes into the bonus, the rest the word's plain
    /// frequency, so a word the model finds unlikely loses at most `-log(1 - modelMix)`.
    public var modelMix: Float = 0.9
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
    /// Taps this far apart or more (the middle gap of the word's) are slow pecking: each
    /// letter was meant, so only a one-letter slip (`isOneSlip`) is fixed, whatever
    /// `strictness` says; otherwise the letters stay as tapped (Gabriel, 13 Nov 2026:
    /// "autocorrect less intensely when typing slow").
    public var slowTapGap: TimeInterval = 0.3
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
    /// Score per squared key width between where a tap landed and the centre of the
    /// key its letter is on, as for pecked letters (`EditCosts.distance`).
    public var tapWeight = 0.25
    /// What a letter taken a whole `swapWindow` after its finger had moved on costs,
    /// when both thumbs swipe at once (`together`): less for less.
    public var latePenalty = 0.2
    /// How many trie states a search may expand before it stops. The search goes one
    /// letter deeper at a time, so a cut-off search loses the longest words first. A
    /// real, wiggly 33-key swipe of "separated" needed about 48,000 and lost it to
    /// "separate" and "spayed" at 40,000 (Gabriel, 10 Nov 2026); clean swipes need
    /// under 10,000.
    public var budget = 100_000

    public init(dictionary: Lexicon, ngrams: NgramModel? = nil, layout: Layout, learned: LearnedWords = LearnedWords()) {
        self.dictionary = dictionary
        self.ngramModels = ngrams.map { [$0] } ?? []
        self.layout = layout
        self.learned = learned
        self.learnedLexicon = Self.lexicon(of: learned)
    }

    public init(language: Language, layout: Layout, learned: LearnedWords = LearnedWords()) {
        self.init(dictionary: language.lexicon, ngrams: nil, layout: layout, learned: learned)
        ngramModels = language.ngramModels
    }

    /// The word right before the open one, for the pair model; nil without context.
    var previousWord: String? { context.last.map(Lexicon.fold) }

    /// The words before's say on `word` as score, given its log prior from the
    /// dictionary: the next-word model's when one knows the word, else the pairs'.
    func contextScore(for word: String, prior: Float) -> Double {
        if !nextWords.isEmpty, let bonus = modelBonus(for: word, prior: prior) { return modelWeight * bonus }
        return contextWeight * contextBonus(for: word, prior: prior)
    }

    /// The next-word models' say on `word`: the log ratio of how likely they find it
    /// here (mixed with its plain frequency) to its plain frequency, the best of the
    /// models that know it; nil when none does.
    func modelBonus(for word: String, prior: Float) -> Double? {
        let unigram = exp(prior + dictionary.logProbabilityOffset)
        guard unigram > 0 else { return nil }
        var best: Float?
        for scores in nextWords {
            guard let logP = scores.logProbability(of: word) else { continue }
            let mixed = modelMix * exp(logP) + (1 - modelMix) * unigram
            best = max(best ?? -.infinity, min(NgramModel.maximumBonus, log(mixed) - log(unigram)))
        }
        return best.map(Double.init)
    }

    /// The word pairs' say on `word`, given the word's log prior from the dictionary.
    func contextBonus(for word: String, prior: Float) -> Double {
        guard let previous = previousWord else { return 0 }
        return pairModelsBonus(word, after: previous, prior: prior)
    }

    /// The word-pair models' say on `word` after `previous`: from each language whose
    /// model knows `previous`, the best of them (so after "el" Spanish decides and after
    /// "the" English does); 0 when none knows it.
    private func pairModelsBonus(_ word: String, after previous: String, prior: Float) -> Double {
        var best: Float?
        let unigram = prior + dictionary.logProbabilityOffset
        for model in ngramModels where model.id(of: previous) != nil {
            let bonus = model.contextBonus(for: word, after: previous, unigramLogProbability: unigram)
            best = max(best ?? -.infinity, bonus)
        }
        return Double(best ?? 0)
    }

    /// How well `next` follows `reading`, as score (features/look-back): the next-word
    /// models' say on it after the sentence with `reading` in it (`models`, one per
    /// language, read after `reading`), or the word pairs' without them, plus how often
    /// the person wrote the two together. Nil when no dictionary knows `next`.
    func followBonus(_ next: String, after reading: String, models: [NextWordScores]) -> Double? {
        let key = Lexicon.fold(next.lowercased())
        guard let prior = dictionary.logPrior(of: key) else { return nil }
        var bonus: Double
        if !models.isEmpty {
            let unigram = exp(prior + dictionary.logProbabilityOffset)
            var best: Float?
            for scores in models {
                guard let logP = scores.logProbability(of: key) else { continue }
                let mixed = modelMix * exp(logP) + (1 - modelMix) * unigram
                best = max(best ?? -.infinity, min(NgramModel.maximumBonus, log(mixed) - log(unigram)))
            }
            bonus = modelWeight * Double(best ?? 0)
        } else {
            bonus = contextWeight * pairModelsBonus(key, after: Lexicon.fold(reading.lowercased()), prior: prior)
        }
        if !personal.isEmpty {
            bonus += personalPairWeight * log(1 + Double(personal.pairCount(Lexicon.fold(reading.lowercased()), key)))
        }
        return bonus
    }

    /// Pecked letters that spell a word, and the real words their taps were close to,
    /// scored alike (the context before them included), for looking back at the word
    /// once the next one is in (features/look-back).
    func tappedReadings(of letters: String, points: [CGPoint?], limit: Int) -> [Candidate] {
        guard isKnown(letters), let own = dictionary.logPrior(of: letters) ?? (learnedLexicon.contains(letters) ? ownPrior(letters) : nil) else { return [] }
        let typed = Candidate(word: letters, score: priorWeight * Double(own) + contextScore(for: letters, prior: own)
                              + personalBonus(for: letters, prior: own) + learned.weight(of: letters))
        return [typed] + nearestWords(to: letters, points: points, limit: limit)
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

    static func lexicon(of learned: LearnedWords, shortcuts: Set<String> = [], language: String? = nil) -> Lexicon {
        let own = Set(learned.entries.keys.filter { learned.contains($0, in: language) })
            .union(shortcuts.filter { !learned.isBlocked($0) })
        return Lexicon(entries: own.sorted().map { Lexicon.Entry(word: $0, frequency: 1) })
    }

    /// The guesses, best first. `final` is false while the word is still being typed:
    /// pecked letters that begin a word ("bri" on the way to "bring") then stay as they
    /// are; when it is true (on space) they too must make a word, as `strictness` says.
    public func candidates(for pieces: [Piece], limit: Int = 3, final: Bool = true) -> [Candidate] {
        let all = allCandidates(for: pieces, limit: limit, final: final)
        guard !learned.entries.isEmpty else { return all }
        // Blocked words (Never suggest) are never offered or written. While the word is
        // still being typed, the letters exactly as tapped stay ("thr" on the way to
        // "three"); on space a blocked word gives way to the next reading ("thr" goes
        // in as "the"). Gabriel, 10 Nov 2026: blocking "thr" still typed "thr".
        let tapped = !final && pieces.allSatisfy(\.isTap)
            ? String(pieces.sorted { $0.start < $1.start }.flatMap(\.keys)).lowercased() : nil
        let kept = all.filter { !learned.isBlocked($0.word) || $0.word.lowercased() == tapped }
        if !kept.isEmpty { return kept }
        guard final else { return Array(all.prefix(1)) }
        // Every reading in the short list is blocked: look further for one that isn't.
        let wider = allCandidates(for: pieces, limit: limit + 6, final: final)
            .filter { !learned.isBlocked($0.word) }
        return wider.isEmpty ? Array(all.prefix(1)) : Array(wider.prefix(limit))
    }

    private func allCandidates(for pieces: [Piece], limit: Int, final: Bool) -> [Candidate] {
        // Letters picked from a held key ("ñ") search as their plain key and must come
        // out as picked.
        let picked = pieces.sorted { $0.start < $1.start }.flatMap(\.keys).filter { $0.unicodeScalars.contains { $0.value >= 0x80 } }
        guard !picked.isEmpty else {
            let keyed = keyedCandidates(for: pieces, limit: limit, final: final)
            return dictionary.hasSpellings || learnedLexicon.hasSpellings ? spelled(keyed, limit: limit) : keyed
        }
        let plain = pieces.map { piece in
            var piece = piece
            piece.keys = piece.keys.map { Character(Lexicon.fold(String($0))) }
            return piece
        }
        let wide = spelled(keyedCandidates(for: plain, limit: limit + 3, final: final), limit: limit + 6)
        let kept = wide.filter { Self.has(picked, in: $0.word) }
        if !kept.isEmpty { return Array(kept.prefix(limit)) }
        // No word has them: the letters as typed, when every piece was a tap.
        guard pieces.allSatisfy(\.isTap) else { return Array(wide.prefix(limit)) }
        let typed = String(pieces.sorted { $0.start < $1.start }.flatMap(\.keys))
        return [Candidate(word: typed, score: priorWeight * Double(unknownPrior))] + wide.prefix(limit - 1)
    }

    /// Whether `word` has the `letters`, in this order.
    static func has(_ letters: [Character], in word: String) -> Bool {
        var rest = Substring(word)
        for letter in letters {
            guard let i = rest.firstIndex(of: letter) else { return false }
            rest = rest[rest.index(after: i)...]
        }
        return true
    }

    /// The guesses as the keys spell them ("cancion"), before `spelled` writes them.
    private func keyedCandidates(for pieces: [Piece], limit: Int, final: Bool) -> [Candidate] {
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
            return resolve(typed, points: orderings[index].map { $0.points.first }, limit: limit, pecked: true,
                           slow: isSlow(orderings[index]))
        }

        let out = remembered(Self.ranked(matches(orderings)), for: ordered)
        let split = split(ordered)
        guard let split else {
            if out.isEmpty {
                // Nothing fits the keys as crossed: the nearest real words to the keys the
                // swipes started and ended on, and those keys themselves only when no word
                // is near (and strictness allows letters at all).
                return resolve(Self.fallback(ordered), points: [], limit: limit, pecked: false)
            }
            return Array(out.prefix(limit))
        }
        // Two words with the space missed between a swipe and the touch next to it: the
        // split goes first when it reads clearly better than any one word does (or no
        // word fits at all), as sure as `splitStrictness` asks; otherwise it waits in
        // the bar behind the first guess.
        let joined = out.first ?? Candidate(word: "", score: priorWeight * Double(unknownPrior))
        // The two halves are one common word the pieces also fit ("after" then "noon" is
        // "afternoon"): two thumbs type a word in halves, so the word goes first. A
        // rare run-together ("alot") still splits.
        let together = split.word.replacingOccurrences(of: " ", with: "")
        let oneWord = out.contains { $0.word == together } && (dictionary.logPrior(of: together) ?? -.infinity) >= compoundPrior
        let sure = !oneWord && splitStrictness > 0 && split.score > joined.score + splitMargin
            && confidence(of: split, over: joined) >= 1 - splitStrictness
        guard !out.isEmpty else { return [split] }
        let rest = Array(out.prefix(limit - 1))
        return Array((sure ? [split] + rest : [rest[0], split] + rest.dropFirst()).prefix(limit))
    }

    /// Guesses written as the words are ("canción" for the keys "cancion"): each takes
    /// its likeliest spelling, and a second spelling of the same keys ("esta" behind
    /// "está") follows it, scored lower by the difference in their priors. Letters
    /// that are no word stay as they are.
    func spelled(_ keyed: [Candidate], limit: Int) -> [Candidate] {
        var out: [Candidate] = []
        var seen = Set<String>()
        func add(_ candidate: Candidate) {
            if seen.insert(candidate.word).inserted { out.append(candidate) }
        }
        for candidate in keyed {
            let parts = candidate.word.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 1 else {
                // A split: each half written as it is.
                add(Candidate(word: parts.map { spellings(of: $0).first?.word ?? $0 }.joined(separator: " "),
                              score: candidate.score))
                continue
            }
            let options = spellings(of: candidate.word)
            guard let best = options.first else { add(candidate); continue }
            add(Candidate(word: best.word, score: candidate.score))
            for other in options.dropFirst().prefix(1) {
                add(Candidate(word: other.word, score: candidate.score - priorWeight * Double(best.logPrior - other.logPrior)))
            }
        }
        return Array(out.prefix(limit))
    }

    /// A key's spellings from the dictionary, else from the person's own words.
    private func spellings(of key: String) -> [(word: String, logPrior: Float)] {
        let own = dictionary.spellings(of: key)
        return own.isEmpty ? learnedLexicon.spellings(of: key) : own
    }

    /// Every word the pieces fit (in any of the orderings), with its best score.
    private func matches(_ orderings: [[Piece]]) -> [String: Double] {
        var best: [String: Double] = [:]
        // Thumbs that were down at the same time: their letters, in the order the
        // fingers reached them. That reading covers the other orders and a tap inside
        // a swipe, so only the touch-down order is read one piece after another.
        var orderings = orderings
        if let pieces = orderings.first, Self.overlap(pieces) {
            orderings = [pieces]
            for (word, score) in together(pieces, in: dictionary, prior: nil) {
                best[word] = max(best[word] ?? -.infinity, score)
            }
            if learnedLexicon.nodeCount > 1 {
                for (word, score) in together(pieces, in: learnedLexicon, prior: ownPrior) {
                    best[word] = max(best[word] ?? -.infinity, score)
                }
            }
        }
        for ordering in orderings {
            for segments in segmentations(of: ordering).prefix(orderings.count == 1 && Self.overlap(ordering) ? 1 : 2) {
                for (word, score) in search(segments, in: dictionary, prior: nil) {
                    best[word] = max(best[word] ?? -.infinity, score)
                }
                guard learnedLexicon.nodeCount > 1 else { continue }
                for (word, score) in search(segments, in: learnedLexicon, prior: ownPrior) {
                    best[word] = max(best[word] ?? -.infinity, score)
                }
            }
        }
        return best
    }

    /// The log prior of a word of the person's own, from how often they wrote it.
    func ownPrior(_ word: String) -> Float {
        let written = learnedLexicon.spellings(of: word).first?.word ?? word
        let prior = learned.logPrior(of: written, base: learnedPrior)
        return shortcuts.contains(written) ? max(prior, shortcutPrior) : prior
    }

    /// Words and scores as guesses, best first (ties alphabetical, so runs repeat).
    static func ranked(_ scores: [String: Double]) -> [Candidate] {
        let candidates: [Candidate] = scores.map { (word: String, score: Double) in Candidate(word: word, score: score) }
        return candidates.sorted { (a: Candidate, b: Candidate) -> Bool in
            if a.score != b.score { return a.score > b.score }
            return a.word < b.word
        }
    }

    /// Whether `word` (as written, any case) is in the dictionary or the person's own
    /// words: the bar's word menu says "Suggest more" for these, "Learn it" otherwise.
    public func knows(_ word: String) -> Bool {
        let lower = word.lowercased()
        if learned.contains(lower) { return true }
        return dictionary.spellings(of: Lexicon.fold(lower)).contains { $0.word == lower }
    }

    /// In the dictionary or the person's own words.
    /// A word the keyboard knows and may write: in the dictionary or the person's own,
    /// and not blocked (Never suggest), so a blocked "thr" reads like a slip for "the".
    func isKnown(_ word: String) -> Bool {
        (dictionary.contains(word) || learnedLexicon.contains(word)) && !learned.isBlocked(word)
    }

    /// What was tapped, then common words that continue it, the context deciding among them.
    private func exactly(_ typed: String, limit: Int) -> [Candidate] {
        let prior = priorWeight * Double(dictionary.logPrior(of: typed) ?? (learnedLexicon.contains(typed) ? ownPrior(typed) : unknownPrior))
        var out = [Candidate(word: typed, score: prior + learned.weight(of: typed))]
        let completions = dictionary.completions(of: typed, limit: limit + 2)
            .filter { $0 != typed }
            .map { word in
                let own = dictionary.logPrior(of: word) ?? -20
                return Candidate(word: word, score: priorWeight * Double(own) + contextScore(for: word, prior: own)
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
    private func resolve(_ letters: String, points: [CGPoint?], limit: Int, pecked: Bool, slow: Bool = false) -> [Candidate] {
        var near = nearestWords(to: letters, points: points, limit: limit)
        let literal = Candidate(word: letters, score: priorWeight * Double(unknownPrior))
        let split = pecked ? split(letters) : nil
        var splitSure = false
        if let split {
            near = Array(Self.ranked(Dictionary(uniqueKeysWithValues: (near + [split]).map { ($0.word, $0.score) })).prefix(limit))
            splitSure = splitStrictness > 0 && confidence(of: split, over: literal) >= 1 - splitStrictness
            // Not sure enough to split: the split waits behind what else there is.
            if !splitSure, near.first == split {
                near = Array(near.dropFirst()) + [split]
            }
        }
        // Slow pecking: the letters were meant. A word one slip away (or the letters
        // split into two words, when sure) may still go in as strictness says;
        // anything that rewrites more of them only waits in the bar, behind the letters.
        if slow {
            let fixes = near.filter { ($0 == split && splitSure) || isOneSlip(letters, $0.word) }
            guard !fixes.isEmpty else { return Array(([literal] + near).prefix(limit)) }
            near = fixes + near.filter { !fixes.contains($0) }
        }
        // "Words only": the nearest word always goes in, but the letters as pecked stay
        // last in the bar, so they can still be picked or held and learned
        // (Gabriel, 7 Nov 2026). Pecked letters with no word near them are a word the
        // keyboard doesn't know ("overwritten"), not a slip: they stay as typed rather
        // than vanishing from the field mid-word (Gabriel, 7 Nov 2026). The same goes
        // for swipes: a long made-up word swiped fast reaches a point where no word is
        // near its keys, and it must not vanish there either (Gabriel, 9 Nov 2026).
        guard strictness < 1 else {
            guard pecked else { return near.isEmpty ? [literal] : near }
            guard !near.isEmpty else { return [literal] }
            guard limit > 1 else { return near }
            return Array(near.prefix(limit - 1)) + [literal]
        }
        guard let best = near.first else { return [literal] }
        let threshold = best == split ? splitStrictness : strictness
        let sure = !pecked || (threshold > 0 && confidence(of: best, over: literal) >= 1 - threshold)
        var ordered: [Candidate] = sure ? [best, literal] : [literal, best]
        ordered.append(contentsOf: near.dropFirst())
        return Array(ordered.prefix(limit))
    }

    /// Whether these taps came slowly enough to be pecking (`slowTapGap`): the middle
    /// gap between one tap and the next, so one pause to think doesn't make a word slow.
    func isSlow(_ taps: [Piece]) -> Bool {
        guard taps.count >= 2 else { return false }
        let starts = taps.map(\.start).sorted()
        let gaps = zip(starts.dropFirst(), starts).map { $0 - $1 }.sorted()
        return gaps[gaps.count / 2] >= slowTapGap
    }

    /// Whether `word` is `letters` with one slip fixed: one letter for a key next to
    /// it, two letters side by side swapped, or one letter missing or extra.
    func isOneSlip(_ letters: String, _ word: String) -> Bool {
        let a = Array(letters), b = Array(Lexicon.fold(word.lowercased()))
        guard a != b else { return true }
        if a.count == b.count {
            let differ = a.indices.filter { a[$0] != b[$0] }
            if differ.count == 1 { return areNeighbours(a[differ[0]], b[differ[0]]) }
            return differ.count == 2 && differ[1] == differ[0] + 1 && a[differ[0]] == b[differ[1]] && a[differ[1]] == b[differ[0]]
        }
        let (long, short) = a.count > b.count ? (a, b) : (b, a)
        guard long.count == short.count + 1 else { return false }
        let i = zip(long, short).prefix { $0 == $1 }.count
        return Array(long[(i + 1)...]) == Array(short[i...])
    }

    /// Keys next to each other on the layout, diagonals included.
    private func areNeighbours(_ a: Character, _ b: Character) -> Bool {
        guard let one = layout.frame(of: .letter(a)), let other = layout.frame(of: .letter(b)),
              let q = layout.frame(of: .letter("q")), let w = layout.frame(of: .letter("w")),
              let row = layout.frame(of: .letter("a")) else { return false }
        // One key along (centre to centre) and one row up or down, with a little slack.
        let across = (w.midX - q.midX) * 1.1, down = abs(row.midY - q.midY) * 1.1
        return abs(one.midX - other.midX) <= across && abs(one.midY - other.midY) <= down
    }

    /// How sure the keyboard is of `word` rather than `other`, 0 to 1, from their scores.
    func confidence(of word: Candidate, over other: Candidate) -> Double {
        1 / (1 + exp(-(word.score - other.score) / confidenceScale))
    }

    // MARK: Remembered shapes

    /// How close a swipe must come to one the person fixed with "Not it?" to give that
    /// word, in key widths of mean distance (`Geometry.dtw`).
    public var shapeRadius = 0.5
    /// How far a remembered word goes ahead of the best guess, at a perfect match; less
    /// as the swipe strays, down to just ahead at the edge of `shapeRadius`.
    public var shapeLift = 0.3
    /// How far a swipe may start or end from where a remembered one did, in key widths:
    /// under one key, so "seconds" (ending on s) is not "second" (ending on d).
    public var shapeEnds: CGFloat = 0.7

    /// The guesses with the words of remembered shapes (`PersonalIndex.shapes`) that the
    /// pieces come close to put first (features/missed-words Phase B): the person told
    /// the keyboard what this swipe means. A shape of two thumbs matches the same number
    /// of touches, each against its own in touch-down order, on the same keyboard
    /// (split or whole).
    func remembered(_ ranked: [Candidate], for pieces: [Piece]) -> [Candidate] {
        guard !personal.shapes.isEmpty, (1...PersonalModel.maxShapePieces).contains(pieces.count),
              pieces.contains(where: { !$0.isTap }), layout.width > 0, layout.height > 0 else { return ranked }
        let unit = layout.distanceUnit
        let actual = pieces.sorted { $0.start < $1.start }.map { Geometry.resample($0.points, count: PersonalModel.shapePoints) }
        var near: [String: Double] = [:]
        for shape in personal.shapes where shape.split == layout.split {
            let stored = shape.pieces
            guard stored.count == actual.count else { continue }
            var total = 0.0
            var close = true
            for (mine, kept) in zip(actual, stored) {
                let points = kept.map { CGPoint(x: $0.x * layout.width, y: $0.y * layout.height) }
                guard let first = points.first, let last = points.last, let start = mine.first, let end = mine.last,
                      Geometry.distance(first, start) < unit * shapeEnds, Geometry.distance(last, end) < unit * shapeEnds else {
                    close = false
                    break
                }
                total += Double(Geometry.dtw(mine, points, band: 4) / unit)
            }
            guard close else { continue }
            let distance = total / Double(actual.count)
            if distance < shapeRadius { near[shape.word] = min(near[shape.word] ?? .infinity, distance) }
        }
        guard !near.isEmpty else { return ranked }
        var scores: [String: Double] = [:]
        for candidate in ranked { scores[candidate.word] = max(scores[candidate.word] ?? -.infinity, candidate.score) }
        let top = ranked.first?.score ?? priorWeight * Double(unknownPrior)
        for (word, distance) in near {
            scores[word] = max(scores[word] ?? -.infinity, top + 0.01 + shapeLift * (1 - distance / shapeRadius))
        }
        return Self.ranked(scores)
    }

    // MARK: Missed spaces

    /// What the space a split puts back costs, in score units, like a missing letter.
    public var splitCost = 0.45
    /// How sure the keyboard must be of a split before it writes it in place of the
    /// letters, 0 to 1, like `strictness`: at 0 it never writes one (it stays in the
    /// bar), at 1 it writes every split it finds.
    public var splitStrictness = 0.8
    /// The rarest a word may be (log prior) to be one half of a split: short words need
    /// to be common ("in", "of", "the"), since the dictionary also holds rare bits
    /// like "ep" and "xt" that would split almost anything.
    public var splitLongPrior: Float = -10
    public var splitShortPrior: Float = -7
    /// The rarest (log prior) the halves of a split run together may be and still be
    /// written as one word ("afternoon" at -6.9 and "everyday" at -7.5 are; "alot" at
    /// -8.7 is not).
    public var compoundPrior: Float = -8
    /// How much better the best split must score than the next one to be offered: two
    /// readings that close are not an obvious missed space.
    public var splitMargin = 0.1

    /// Letters that spell no word but two real words with the space between them
    /// missed ("textseparately" for "text separately"), when that is obvious: both
    /// halves are common enough real words (the dictionary's or the person's), and
    /// no other place for the space reads nearly as well. Scored like a guess for the
    /// rarer half, plus what the word pairs say of the two together, less the space.
    func split(_ letters: String) -> Candidate? {
        let chars = Array(letters)
        guard chars.count >= 3, letters.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 }) else { return nil }
        var splits: [Candidate] = []
        for cut in 1..<chars.count {
            let first = String(chars[..<cut]), second = String(chars[cut...])
            guard let p1 = splitPrior(first), let p2 = splitPrior(second) else { continue }
            splits.append(Candidate(word: first + " " + second,
                                    score: priorWeight * Double(min(p1, p2)) + pairBonus(first, p1, second, p2) - splitCost))
        }
        return Self.obvious(splits, margin: splitMargin)
    }

    /// Pieces of one open word that read as two words with the space missed between a
    /// swipe and the touch beside it: "text" swiped then "separately" swiped, or "going"
    /// swiped then "to" tapped (Gabriel, 3 Nov 2026). Only between touches one after
    /// the other (two thumbs down together are one word), and both halves must be
    /// common enough real words, as for pecked letters. Scored like a guess for the
    /// weaker half, plus what the word pairs say of the two together, less the space.
    func split(_ pieces: [Piece]) -> Candidate? {
        guard pieces.count >= 2, !pieces.allSatisfy(\.isTap), splitStrictness > 0 else { return nil }
        var splits: [Candidate] = []
        for cut in 1..<pieces.count where !(pieces[cut - 1].isTap && pieces[cut].isTap)
            && pieces[..<cut].allSatisfy({ $0.end <= pieces[cut].start }) {
            guard let first = bestWord(Array(pieces[..<cut])), let p1 = splitPrior(first.word) else { continue }
            var after = self
            after.context.append(first.word)
            guard let second = after.bestWord(Array(pieces[cut...])), let p2 = splitPrior(second.word) else { continue }
            splits.append(Candidate(word: first.word + " " + second.word,
                                    score: min(first.score, second.score) + pairBonus(first.word, p1, second.word, p2) - splitCost))
        }
        return Self.obvious(splits, margin: splitMargin)
    }

    // MARK: Wrong spaces

    /// What taking out a space autospace wrote costs, in score units, on top of
    /// `splitMargin`: the pause was there, so two words stay two unless one word reads
    /// clearly better. Tuned on word pairs (WrongSpaceTests): "some thing", "with out"
    /// and "to day" join; "may be", "set up", "in to" and "every day" stay apart.
    public var joinCost = 0.05

    /// Two words autospace wrote apart, `written` from the `first` pieces and the word
    /// from the `second` typed right after, that are one word with a pause in it
    /// ("some" then "thing" for "something", Gabriel 3 Nov 2026): the one word, when it
    /// is obvious. The reverse of `split`, as sure as `splitStrictness` says (never at
    /// 0). The word must be a real word at least as common as half of a split may be,
    /// neither half may be one letter ("a" + "way" may well be "a way"), and it must
    /// beat the two words as written, each scored for its own pieces and the second
    /// after the first, by `joinCost` and `splitMargin`. The matcher's context is the
    /// words before the first one.
    func join(_ first: [Piece], _ second: [Piece], written: (String, String)) -> Candidate? {
        let a = Lexicon.fold(written.0.lowercased()), b = Lexicon.fold(written.1.lowercased())
        guard splitStrictness > 0, a.count >= 2, b.count >= 2, !first.isEmpty, !second.isEmpty,
              first.allSatisfy({ !$0.keys.isEmpty }), second.allSatisfy({ !$0.keys.isEmpty }) else { return nil }
        let all = (first + second).sorted { $0.start < $1.start }
        guard let whole = bestWord(all), !whole.word.contains(" "), whole.word != a + " " + b,
              whole.word.count >= 4, isKnown(whole.word),
              (dictionary.logPrior(of: whole.word) ?? ownPrior(whole.word)) >= splitLongPrior else { return nil }
        // The two words as they went in: the first for its pieces after the words
        // before it, the second for its own after the first, together (each must
        // happen); a half that is no real word scores as letters do.
        let letters = priorWeight * Double(unknownPrior)
        let firstScore = score(of: a, for: first) ?? letters
        var after = self
        after.context.append(a)
        let secondScore = after.score(of: b, for: second) ?? letters
        let apart = Candidate(word: a + " " + b, score: firstScore + secondScore)
        let joined = Candidate(word: whole.word, score: whole.score - joinCost)
        guard joined.score > apart.score + splitMargin, confidence(of: joined, over: apart) >= 1 - splitStrictness else { return nil }
        return joined
    }

    /// How `word` scores for `pieces` on their own: as tapped letters (only when they
    /// spell it), or as a swipe's match. Nil when the pieces do not give it.
    private func score(of word: String, for pieces: [Piece]) -> Double? {
        if pieces.allSatisfy(\.isTap) {
            guard let typed = bestWord(pieces), typed.word == word else { return nil }
            return typed.score
        }
        let ordered = pieces.sorted { $0.start < $1.start }
        return matches(Self.orderings(of: ordered, swapWindow: swapWindow))[word]
    }

    /// The one real word some pieces make on their own, for half of a split: tapped
    /// letters exactly as they are, or the best word for a swipe (and what goes with it).
    private func bestWord(_ pieces: [Piece]) -> Candidate? {
        if pieces.allSatisfy(\.isTap) {
            let typed = String(pieces.flatMap(\.keys))
            guard isKnown(typed) else { return nil }
            let prior = dictionary.logPrior(of: typed) ?? ownPrior(typed)
            return Candidate(word: typed, score: priorWeight * Double(prior) + contextScore(for: typed, prior: prior))
        }
        return Self.ranked(matches([pieces])).first
    }

    /// A word's log prior when it may be half of a split, nil when it may not: short
    /// words must be common, single letters only "a" and "i".
    private func splitPrior(_ part: String) -> Float? {
        if part.count == 1 { return part == "a" || part == "i" ? dictionary.logPrior(of: part) : nil }
        let own = dictionary.logPrior(of: part) ?? (learnedLexicon.contains(part) ? ownPrior(part) : nil)
        guard let own, own >= (part.count <= 3 ? splitShortPrior : splitLongPrior) else { return nil }
        return own
    }

    /// What the words before and the word pairs say of `first` then `second`.
    private func pairBonus(_ first: String, _ p1: Float, _ second: String, _ p2: Float) -> Double {
        contextScore(for: first, prior: p1) + contextWeight * pairModelsBonus(second, after: first, prior: p2)
    }

    /// The best split, when no other place for the space reads nearly as well.
    private static func obvious(_ splits: [Candidate], margin: Double) -> Candidate? {
        let ranked = splits.sorted { $0.score > $1.score }
        guard let best = ranked.first else { return nil }
        if ranked.count > 1, best.score - ranked[1].score < margin { return nil }
        return best
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
                let ranking: Double = priorWeight * Double(prior) + contextScore(for: word, prior: prior)
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

    /// The touch-down order first, then the other orders the pieces may have been meant
    /// in, likeliest first, at most `limit`. Two thumbs that land close together land
    /// in either order, so a piece may come before any that landed less than
    /// `swapWindow` before it, however many there are ("the" tapped t-e with one thumb
    /// and h with the other, all within a blink). An order is as unlikely as the time
    /// its swapped pieces landed apart, added up.
    static func orderings(of pieces: [Piece], swapWindow: TimeInterval, limit: Int = 8) -> [[Piece]] {
        guard pieces.count > 1, limit > 1 else { return [pieces] }
        var found: [(cost: TimeInterval, order: [Int])] = []
        var order: [Int] = []
        var used = [Bool](repeating: false, count: pieces.count)
        var visits = 0
        // Depth first: the next piece is any unused one that landed within the window
        // of the earliest unused one; the cost is how long after it that one landed.
        func extend(_ cost: TimeInterval) {
            visits += 1
            guard visits < 2000 else { return }
            guard order.count < pieces.count else { found.append((cost, order)); return }
            guard let earliest = used.firstIndex(of: false) else { return }
            for next in earliest..<pieces.count where !used[next] {
                let late = pieces[next].start - pieces[earliest].start
                guard late < swapWindow else { break }
                used[next] = true
                order.append(next)
                extend(cost + late)
                order.removeLast()
                used[next] = false
            }
        }
        extend(0)
        found.sort { $0.cost == $1.cost ? $0.order.lexicographicallyPrecedes($1.order) : $0.cost < $1.cost }
        return found.prefix(limit).map { $0.order.map { pieces[$0] } }
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
                      piece.isTap || mayStandIn(letter, at: index, of: piece.keys) else { continue }
                let grown = frame.insetBy(dx: -margin, dy: -margin * frame.height / frame.width)
                if points.contains(where: { grown.contains($0) }) { out[index].append(letter) }
            }
        }
        return out
    }

    static let alphabet = Array("abcdefghijklmnopqrstuvwxyz")

    /// Whether a neighbouring `letter` may stand in for the swipe's key at `index`. A
    /// letter the swipe never crossed always may. One it crossed somewhere else may too,
    /// unless it is the key just before or after (the search takes that one as itself),
    /// and at the swipe's first and last key always: the word must start and end there,
    /// so a long swipe that ends on "h" beside a "g" it crossed earlier can still be
    /// "everything". Long words have the most letters and the longest paths, so ruling
    /// out every letter crossed anywhere made them the words most often unreachable.
    func mayStandIn(_ letter: Character, at index: Int, of keys: [Character]) -> Bool {
        guard keys.contains(letter) else { return true }
        if index == 0 || index == keys.count - 1 { return true }
        return keys[index - 1] != letter && keys[index + 1] != letter
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
        /// The trie label of the letter taken for `lastKey` (it or a neighbour).
        var letter: Int
    }

    /// The words in `lexicon` that the segments can spell, with their scores. `prior`
    /// stands in for the lexicon's own word frequencies when given.
    private func search(_ segments: [Segment], in lexicon: Lexicon, prior fixedPrior: ((String) -> Float)?) -> [String: Double] {
        // The best score per word: two paths through the keys can spell the same word.
        var best: [String: Double] = [:]
        // The fewest stand-ins each state was reached with: a state reached again with
        // fewer is searched again, so a word is not scored by its worst spelling.
        var fewestStandIns: [SearchState: Int] = [:]
        // Per segment and crossed key, the trie labels it may give: its own, then its
        // neighbours (`near`), worked out once rather than at every state.
        let options: [[[Int]]] = segments.map { segment in
            segment.keys.indices.map { j in
                ([segment.keys[j]] + (segment.near.indices.contains(j) ? segment.near[j] : [])).map(Self.index(of:))
            }
        }
        // The same turned around: per segment and trie label, the crossed keys that may
        // give it, in order, and whether as a stand-in. The search walks a node's
        // children (a few) rather than every later key and its neighbours (dozens).
        let keysFor: [[[(key: Int, standIn: Bool)]]] = options.map { segment in
            var out = Array(repeating: [(key: Int, standIn: Bool)](), count: 27)
            for (j, labels) in segment.enumerated() {
                for (n, label) in labels.enumerated() { out[label].append((j, n > 0)) }
            }
            return out
        }
        // A word's path score depends only on the word and how many letters each
        // segment gave it, and many spellings reach the same word: score it once.
        var scored: [String: [([Int], Double)]] = [:]
        // Each queue entry carries how many letters the segments before this one gave
        // (`done`, shared, copied only when a segment ends), how many this one has given
        // so far, and how many of its letters were stand-ins for a crossed key. Nothing
        // is copied per letter: the search makes many entries and this is its hot loop.
        struct Entry {
            var state: SearchState
            var done: [Int]
            var letters: Int
            var standIns: Int
        }
        var queue = [Entry(state: SearchState(segment: 0, lastKey: -1, node: 0, doubled: false, letter: 0), done: [], letters: 0, standIns: 0)]
        queue.reserveCapacity(4096)
        var expanded = 0
        var index = 0
        while index < queue.count, expanded < budget {
            let entry = queue[index]
            let state = entry.state
            index += 1
            if let fewest = fewestStandIns[state], fewest <= entry.standIns { continue }
            fewestStandIns[state] = entry.standIns
            expanded += 1
            let segment = segments[state.segment]
            let keys = segment.keys
            // A second letter from the same crossed key: the same one, for a doubled
            // letter ("hello", "coffee"), or the key and a neighbour it passed, when the
            // swipe brushed two keys at one corner ("po" on a quick turn at "o").
            if state.lastKey >= 0, !state.doubled, !segment.isTap {
                let here = options[state.segment][state.lastKey]
                let own = here[0]
                for n in -1..<here.count {
                    let label = n < 0 ? state.letter : here[n]
                    guard n < 0 || label != state.letter, let child = lexicon.child(of: state.node, label: label) else { continue }
                    let extra = (label == state.letter || label == own) ? 0 : 1
                    queue.append(Entry(state: SearchState(segment: state.segment, lastKey: state.lastKey, node: child, doubled: true, letter: label),
                                       done: entry.done, letters: entry.letters + 1, standIns: entry.standIns + extra))
                }
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
                        let counts = entry.done + [entry.letters]
                        let path: Double
                        if let known = scored[word]?.first(where: { $0.0 == counts })?.1 {
                            path = known
                        } else {
                            path = score(word: word, prior: prior, counts: counts, segments: segments)
                            scored[word, default: []].append((counts, path))
                        }
                        let value = path - nearPenalty * Double(entry.standIns)
                        best[word] = max(best[word] ?? -.infinity, value)
                    }
                } else {
                    queue.append(Entry(state: SearchState(segment: state.segment + 1, lastKey: -1, node: state.node, doubled: false, letter: 0),
                                       done: entry.done + [entry.letters], letters: 0, standIns: entry.standIns))
                }
            }
            // Next letter: the segment's first key to begin (any key, for a segment that
            // continues a swipe after a tap), then any later crossed key.
            let first = state.lastKey < 0 ? 0 : state.lastKey + 1
            let end = state.lastKey < 0 && segment.anchoredStart ? min(1, keys.count) : keys.count
            guard first < end else { continue }
            let table = keysFor[state.segment]
            let edges = lexicon.edges(of: state.node)
            for edge in edges {
                let label = lexicon.edgeLabel(edge)
                let ways = table[label]
                guard !ways.isEmpty else { continue }
                let child = lexicon.edgeTarget(edge)
                for way in ways where way.key >= first && way.key < end {
                    queue.append(Entry(state: SearchState(segment: state.segment, lastKey: way.key, node: child, doubled: false, letter: label),
                                       done: entry.done, letters: entry.letters + 1, standIns: entry.standIns + (way.standIn ? 1 : 0)))
                }
            }
        }
        return best
    }

    private func score(word: String, prior: Float, counts: [Int], segments: [Segment]) -> Double {
        let letters = Array(word)
        // The letters each swipe contributed, across all of its segments.
        var swipes: [(points: [CGPoint], letters: [Character])] = []
        var taps: [(point: CGPoint, letter: Character)] = []
        var sources: [Int: Int] = [:]
        var offset = 0
        for (i, segment) in segments.enumerated() {
            let count = counts[i]
            defer { offset += count }
            if segment.isTap, count > 0, let point = segment.points.first { taps.append((point, letters[offset])) }
            guard !segment.isTap, count > 0 else { continue }
            if let slot = sources[segment.source] {
                swipes[slot].letters += letters[offset..<(offset + count)]
            } else {
                sources[segment.source] = swipes.count
                swipes.append((segment.points, Array(letters[offset..<(offset + count)])))
            }
        }
        return score(word: word, prior: prior, swipes: swipes, taps: taps)
    }

    /// A word's score from the letters each swipe gave it: how far each swipe strayed
    /// from the path through its letters, and what the word is worth on its own.
    func score(word: String, prior: Float, swipes: [(points: [CGPoint], letters: [Character])],
               taps: [(point: CGPoint, letter: Character)] = []) -> Double {
        let unit = Double(layout.distanceUnit)
        var distance = 0.0
        var weight = 0
        // A swipe that gave one letter is scored too, against a path that stays on it:
        // otherwise a word that drops the rest of a swipe pays nothing for it.
        for swipe in swipes where !swipe.letters.isEmpty && swipe.points.count > 1 {
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
        // Where each tap landed against the key its letter is on: a tap at the edge of
        // "g" reads as "f" more easily than one in the middle.
        var missed = 0.0
        for tap in taps {
            guard let frame = layout.frame(of: .letter(tap.letter), on: layout.side(at: tap.point)) else { continue }
            let d = Double(Geometry.distance(tap.point, CGPoint(x: frame.midX, y: frame.midY))) / unit
            missed += tapWeight * d * d
        }
        return -pathWeight * path - missed + priorWeight * Double(prior) + contextScore(for: word, prior: prior)
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
