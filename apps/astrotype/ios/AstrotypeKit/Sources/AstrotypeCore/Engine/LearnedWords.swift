import Foundation

/// The words a person taught the keyboard, with how much each is boosted. Kept by a
/// `WordStore`, merged across devices by `CloudSync`, read by the matcher.
///
///     var words = LearnedWords()
///     words.learn("flotilla", at: now)     // once more each time it goes in
///     words.boost("penguin"); words.block("teh"); words.allow("teh")
public struct LearnedWords: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        /// Added to a candidate's score from the bar: positive after a boost, negative
        /// hides the word.
        public var weight: Double
        public var changed: Date
        /// How many times the person put the word in themselves: a word written once
        /// is offered like a rare word, one written often like a common one (`logPrior`).
        public var uses: Int
        /// Added by hand in Settings → Learned words; nil otherwise.
        public var added: Bool?
        /// The language the word belongs to ("en", "es"): it is offered only in a
        /// sentence in that language. Nil for every language: words learned while the
        /// sentence's language wasn't clear, written in two languages, set to both by
        /// hand, or kept from before languages were told apart (10 Nov 2026).
        public var language: String?

        public init(weight: Double, changed: Date, uses: Int = 0, added: Bool = false, language: String? = nil) {
            self.weight = weight
            self.changed = changed
            self.uses = uses
            self.added = added ? true : nil
            self.language = language
        }

        /// Entries saved before uses were counted: learning set the weight to 1 and a
        /// boost added 1.5, so a weight of 1, 2.5, 4… was learned once (and boosted).
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            weight = try c.decode(Double.self, forKey: .weight)
            changed = try c.decode(Date.self, forKey: .changed)
            added = try c.decodeIfPresent(Bool.self, forKey: .added)
            language = try c.decodeIfPresent(String.self, forKey: .language)
            if let uses = try c.decodeIfPresent(Int.self, forKey: .uses) {
                self.uses = uses
            } else {
                let boosts = (weight - 1) / 1.5
                let wasLearned = weight >= 1 && boosts == boosts.rounded()
                uses = wasLearned ? 1 : 0
                if wasLearned { weight -= 1 }
            }
        }
    }

    public static let version = 1
    public private(set) var entries: [String: Entry] = [:]

    public init() {}

    /// A word the person put in that the dictionary does not know: typed letter by
    /// letter the first time, then each time it goes in again. A blocked word stays
    /// blocked (Never suggest); only `allow`, `teach` or `add` bring it back.
    /// `language` is the sentence's language when it was clear (nil otherwise): a new
    /// word belongs to it, and a word of one language written in the other belongs to
    /// both from then on.
    public mutating func learn(_ word: String, language: String? = nil, at date: Date = Date()) {
        let w = word.lowercased()
        guard let old = entries[w] else {
            entries[w] = Entry(weight: 0, changed: date, uses: 1, language: language)
            return
        }
        guard old.weight >= 0 else { return }
        let both = old.uses == 0 && old.weight == 0 ? language : (old.language == language ? language : nil)
        entries[w] = Entry(weight: old.weight, changed: date, uses: old.uses + 1, added: old.added == true,
                           language: language == nil ? old.language : both)
    }

    /// The word just learned was deleted straight away: one use fewer, and a word with
    /// none left is forgotten.
    public mutating func unlearn(_ word: String, at date: Date = Date()) {
        let w = word.lowercased()
        guard let old = entries[w], old.uses > 1 else {
            forget(w, at: date)
            return
        }
        entries[w] = Entry(weight: old.weight, changed: date, uses: old.uses - 1, added: old.added == true, language: old.language)
    }

    /// Typed in by hand (Settings → Learned words, +): learned and kept, as if pecked
    /// out and boosted, and marked as added, in `language` (nil: every language). A
    /// forgotten word comes back.
    public mutating func add(_ word: String, language: String? = nil, at date: Date = Date()) {
        let w = word.lowercased()
        let old = entries[w]
        entries[w] = Entry(weight: max(old?.weight ?? 0, 0) + 1.5, changed: date, uses: max(old?.uses ?? 0, 1), added: true,
                           language: language)
    }

    /// The language `word` is offered in, nil for every language.
    public func language(of word: String) -> String? {
        entries[word.lowercased()]?.language
    }

    /// Moves a learned word to one language, or to every language with nil
    /// (Settings → Learned words). Dated, so the move reaches every device.
    public mutating func setLanguage(_ word: String, to language: String?, at date: Date = Date()) {
        let w = word.lowercased()
        guard var entry = entries[w], entry.language != language else { return }
        entry.language = language
        entry.changed = date
        entries[w] = entry
    }

    /// Whether the keyboard offers `word` in a sentence in `language` (nil: any).
    public func contains(_ word: String, in language: String?) -> Bool {
        guard contains(word) else { return false }
        guard let language, let own = entries[word]?.language else { return true }
        return own == language
    }

    /// What `add` takes: one word of letters (an apostrophe or hyphen inside is fine),
    /// trimmed and lowercased; nil for anything else.
    public static func addable(_ text: String) -> String? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (1...24).contains(word.count), let first = word.first, let last = word.last,
              first.isLetter, last.isLetter,
              word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }) else { return nil }
        return word
    }

    /// Whether `word` was added by hand.
    public func isAdded(_ word: String) -> Bool {
        entries[word]?.added == true && contains(word)
    }

    /// Make a guess stick (slide up on the bar).
    public mutating func boost(_ word: String, at date: Date = Date()) {
        let w = word.lowercased()
        let old = entries[w]
        entries[w] = Entry(weight: max(old?.weight ?? 0, 0) + 1.5, changed: date, uses: old?.uses ?? 0, added: old?.added == true,
                           language: old?.language)
    }

    /// "Suggest more" or "Learn it" from the bar's word menu (features/word-control):
    /// learned now if it was not, unblocked, and boosted.
    public mutating func teach(_ word: String, at date: Date = Date()) {
        let w = word.lowercased()
        let old = entries[w]
        entries[w] = Entry(weight: max(old?.weight ?? 0, 0) + 1.5, changed: date, uses: max(old?.uses ?? 0, 1), added: old?.added == true,
                           language: old?.language)
    }

    /// Stop offering a guess (slide down on the bar).
    public mutating func forget(_ word: String, at date: Date = Date()) {
        entries[word.lowercased()] = Entry(weight: -10, changed: date, uses: 0)
    }

    /// "Never suggest": the word is never offered or typed again, as a guess, a fix or
    /// a next word, in any language (features/word-control).
    public mutating func block(_ word: String, at date: Date = Date()) {
        forget(word, at: date)
    }

    /// Back from Never suggest: offered again like any word, learned or not (the
    /// entry goes back to plain, so a word the dictionary has ranks as it does there,
    /// and one it does not is learned again the next time it is tapped out).
    public mutating func allow(_ word: String, at date: Date = Date()) {
        let w = word.lowercased()
        guard isBlocked(w) else { return }
        entries[w] = Entry(weight: 0, changed: date, uses: 0)
    }

    /// The entry for `word` as it stands, to put back with `restore` (Undo on the bar).
    public func entry(for word: String) -> Entry? {
        entries[word.lowercased()]
    }

    /// Undo on the bar: the word as it was before the last change, dated now so the
    /// undo wins over the change on every device (`merged`).
    public mutating func restore(_ word: String, to old: Entry?, at date: Date = Date()) {
        var entry = old ?? Entry(weight: 0, changed: date, uses: 0)
        entry.changed = date
        entries[word.lowercased()] = entry
    }

    /// Whether `word` is on Never suggest.
    public func isBlocked(_ word: String) -> Bool {
        (entries[word.lowercased()]?.weight ?? 0) < 0
    }

    /// A word on Never suggest and when it went on.
    public struct Blocked: Sendable, Equatable, Identifiable {
        public var word: String
        public var since: Date
        public var id: String { word }
    }

    /// The words on Never suggest, the newest first.
    public var blocked: [Blocked] {
        entries.filter { $0.value.weight < 0 }
            .sorted { $0.value.changed > $1.value.changed || ($0.value.changed == $1.value.changed && $0.key < $1.key) }
            .map { Blocked(word: $0.key, since: $0.value.changed) }
    }

    /// Whether `word` is one the keyboard learned by itself and has seen written once:
    /// what Learned words' "Used once" filter shows, where old typos hide.
    public func isUsedOnce(_ word: String) -> Bool {
        guard let entry = entries[word], contains(word) else { return false }
        return entry.uses <= 1 && entry.weight <= 0 && entry.added != true
    }

    public func weight(of word: String) -> Double {
        entries[word]?.weight ?? 0
    }

    public func uses(of word: String) -> Int {
        entries[word]?.uses ?? 0
    }

    /// Whether the keyboard offers `word` as one of the person's: learned or boosted,
    /// and not forgotten.
    public func contains(_ word: String) -> Bool {
        guard let entry = entries[word] else { return false }
        return entry.weight > 0 || (entry.weight >= 0 && entry.uses > 0)
    }

    /// How common a word of the person's own counts as: `base` (a rare word) the
    /// first time, `perUse` more per e-fold of uses, so after about 20 uses it ranks
    /// like a fairly common word, never above `ceiling`.
    public func logPrior(of word: String, base: Float, perUse: Float = 1.5, ceiling: Float = -3) -> Float {
        min(ceiling, base + perUse * Float(log(Double(max(1, uses(of: word))))))
    }

    /// The words the keyboard knows from the person (not the forgotten ones), the most
    /// recently changed first.
    public var recent: [String] {
        entries.filter { contains($0.key) }
            .sorted { $0.value.changed > $1.value.changed || ($0.value.changed == $1.value.changed && $0.key < $1.key) }
            .map(\.key)
    }

    /// Whether `word` was boosted from the bar (beyond being learned).
    public func isBoosted(_ word: String) -> Bool {
        (entries[word]?.weight ?? 0) > 0
    }

    /// Both devices' words, the later change winning per word.
    public func merged(with other: LearnedWords) -> LearnedWords {
        var out = self
        for (word, entry) in other.entries {
            if let mine = out.entries[word], mine.changed >= entry.changed { continue }
            out.entries[word] = entry
        }
        return out
    }
}
