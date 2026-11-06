import Foundation

/// The words a person taught the keyboard, with how much each is boosted. Kept by a
/// `WordStore`, merged across devices by `CloudSync`, read by the matcher.
///
///     var words = LearnedWords()
///     words.learn("flotilla", at: now)     // once more each time it goes in
///     words.boost("penguin"); words.forget("teh")
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

        public init(weight: Double, changed: Date, uses: Int = 0, added: Bool = false) {
            self.weight = weight
            self.changed = changed
            self.uses = uses
            self.added = added ? true : nil
        }

        /// Entries saved before uses were counted: learning set the weight to 1 and a
        /// boost added 1.5, so a weight of 1, 2.5, 4… was learned once (and boosted).
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            weight = try c.decode(Double.self, forKey: .weight)
            changed = try c.decode(Date.self, forKey: .changed)
            added = try c.decodeIfPresent(Bool.self, forKey: .added)
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
    /// letter the first time, then each time it goes in again. A forgotten word starts over.
    public mutating func learn(_ word: String, at date: Date = Date()) {
        let w = word.lowercased()
        guard let old = entries[w], old.weight >= 0 else {
            entries[w] = Entry(weight: 0, changed: date, uses: 1)
            return
        }
        entries[w] = Entry(weight: old.weight, changed: date, uses: old.uses + 1, added: old.added == true)
    }

    /// The word just learned was deleted straight away: one use fewer, and a word with
    /// none left is forgotten.
    public mutating func unlearn(_ word: String, at date: Date = Date()) {
        let w = word.lowercased()
        guard let old = entries[w], old.uses > 1 else {
            forget(w, at: date)
            return
        }
        entries[w] = Entry(weight: old.weight, changed: date, uses: old.uses - 1, added: old.added == true)
    }

    /// Typed in by hand (Settings → Learned words, +): learned and kept, as if pecked
    /// out and boosted, and marked as added. A forgotten word comes back.
    public mutating func add(_ word: String, at date: Date = Date()) {
        let w = word.lowercased()
        let old = entries[w]
        entries[w] = Entry(weight: max(old?.weight ?? 0, 0) + 1.5, changed: date, uses: max(old?.uses ?? 0, 1), added: true)
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
        entries[w] = Entry(weight: max(old?.weight ?? 0, 0) + 1.5, changed: date, uses: old?.uses ?? 0, added: old?.added == true)
    }

    /// Stop offering a guess (slide down on the bar).
    public mutating func forget(_ word: String, at date: Date = Date()) {
        entries[word.lowercased()] = Entry(weight: -10, changed: date, uses: 0)
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
