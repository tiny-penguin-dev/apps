import Foundation

/// The words a person taught the keyboard, with how much each is boosted. Kept by a
/// `WordStore`, merged across devices by `CloudSync`, read by the matcher.
///
///     var words = LearnedWords()
///     words.learn("flotilla", at: now)
///     words.boost("penguin"); words.forget("teh")
public struct LearnedWords: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        /// Added to a candidate's score; negative hides the word.
        public var weight: Double
        public var changed: Date
    }

    public static let version = 1
    public private(set) var entries: [String: Entry] = [:]

    public init() {}

    /// A word typed letter by letter that the dictionary did not know.
    public mutating func learn(_ word: String, at date: Date = Date()) {
        let w = word.lowercased()
        let weight = entries[w].map { max($0.weight, 1) } ?? 1
        entries[w] = Entry(weight: weight, changed: date)
    }

    /// Make a guess stick (slide up on the bar).
    public mutating func boost(_ word: String, at date: Date = Date()) {
        let w = word.lowercased()
        entries[w] = Entry(weight: (entries[w]?.weight ?? 0) + 1.5, changed: date)
    }

    /// Stop offering a guess (slide down on the bar).
    public mutating func forget(_ word: String, at date: Date = Date()) {
        entries[word.lowercased()] = Entry(weight: -10, changed: date)
    }

    public func weight(of word: String) -> Double {
        entries[word]?.weight ?? 0
    }

    public func contains(_ word: String) -> Bool {
        (entries[word]?.weight ?? 0) > 0
    }

    /// The words the keyboard knows from the person (not the forgotten ones), the most
    /// recently changed first.
    public var recent: [String] {
        entries.filter { $0.value.weight > 0 }
            .sorted { $0.value.changed > $1.value.changed || ($0.value.changed == $1.value.changed && $0.key < $1.key) }
            .map(\.key)
    }

    /// Whether `word` was boosted from the bar (beyond being learned).
    public func isBoosted(_ word: String) -> Bool {
        (entries[word]?.weight ?? 0) > 1
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
