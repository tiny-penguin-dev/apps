import Foundation

/// What each emoji is called in one language, and the words it goes by: Unicode's CLDR
/// names and keywords (`Resources/emoji/names-<language>.tsv`, built by
/// `ml/emoji/build_names.py`). Read when search first opens (features/emoji-search).
///
///     let names = try EmojiNames.bundled("es")
///     names.name(of: "🍕")   // "pizza"
public struct EmojiNames: Sendable {
    struct Entry: Sendable {
        let name: String
        let keywords: [String]
    }

    private let entries: [String: Entry]

    /// Reads `emoji<TAB>name<TAB>keyword|keyword`; lines it can't read are skipped.
    public init(tsv: String) {
        var entries: [String: Entry] = [:]
        for line in tsv.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2, !fields[0].isEmpty, !fields[1].isEmpty else { continue }
            let keywords = fields.count > 2 ? fields[2].split(separator: "|").map(String.init) : []
            entries[String(fields[0])] = Entry(name: String(fields[1]), keywords: keywords)
        }
        self.entries = entries
    }

    /// The bundled names for a language ("en", "es"); nil for a language that has none.
    public static func bundled(_ language: String) -> EmojiNames? {
        guard let url = Bundle.module.url(forResource: "names-\(language)", withExtension: "tsv", subdirectory: "emoji"),
              let tsv = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return EmojiNames(tsv: tsv)
    }

    /// The emoji's name, as written (its default form).
    public func name(of emoji: String) -> String? { entries[emoji]?.name }

    func entry(for emoji: String) -> Entry? { entries[emoji] }

    /// How many emoji have a name.
    public var count: Int { entries.count }
}

/// Finds emoji by what they're called, in the languages being typed
/// (features/emoji-search). Every word of the search has to begin a word of an emoji's
/// name or one of its keywords; accents and capitals don't matter. The best come first:
/// a match on the name's first word, then elsewhere in the name, then a keyword, then
/// the emoji used most, then the list's own order.
///
///     let search = EmojiSearch(catalog: catalog, names: [en, es])
///     search.results(for: "pizza")                        // [🍕]
///     search.results(for: "corazon", history: history)    // [❤️, ...]
public struct EmojiSearch: Sendable {
    /// Where a word sits for an emoji: the name's first word counts most.
    enum Place: Int, Sendable {
        case keyword = 1, name = 2, first = 3
    }

    private let emoji: [Emoji]
    /// Every word, folded, to the emoji it belongs to and where it sits there (the best
    /// place when it sits in several).
    private let index: [String: [Int: Place]]

    /// The most results it gives.
    public static let limit = 60

    /// The emoji are the catalog's (so only what the phone draws), named in `names`.
    public init(catalog: EmojiCatalog, names: [EmojiNames]) {
        var emoji: [Emoji] = []
        var index: [String: [Int: Place]] = [:]
        func add(_ word: String, _ item: Int, _ place: Place) {
            if let old = index[word]?[item], old.rawValue >= place.rawValue { return }
            index[word, default: [:]][item] = place
        }
        for each in catalog.sections.flatMap(\.emoji) {
            let item = emoji.count
            var named = false
            for language in names {
                guard let entry = language.entry(for: each.text) else { continue }
                named = true
                for (n, word) in Self.words(entry.name).enumerated() { add(word, item, n == 0 ? .first : .name) }
                for keyword in entry.keywords { for word in Self.words(keyword) { add(word, item, .keyword) } }
            }
            if named { emoji.append(each) }
        }
        self.emoji = emoji
        self.index = index
    }

    /// The emoji that match `query`, best first, at most `limit`. An empty query finds
    /// nothing (the page shows Frequently used then).
    public func results(for query: String, history: EmojiHistory = EmojiHistory(), now: Date = Date(),
                        limit: Int = EmojiSearch.limit) -> [Emoji] {
        let terms = Self.words(query)
        guard !terms.isEmpty else { return [] }
        // Every word of the search has to fit: keep the emoji all of them fit, adding up.
        var total = scores(terms[0])
        for term in terms.dropFirst() {
            let scores = self.scores(term)
            var both: [Int: Int] = [:]
            for (item, sum) in total { if let score = scores[item] { both[item] = sum + score } }
            total = both
        }
        let ranked = total.map { (item: $0.key, score: $0.value, use: history.weight(of: emoji[$0.key].text, now: now)) }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.use != b.use { return a.use > b.use }
                return a.item < b.item
            }
        return ranked.prefix(limit).map { emoji[$0.item] }
    }

    /// How well one word of the search fits each emoji it fits: a whole word beats the
    /// start of one, and the name's first word beats the rest of the name, which beats
    /// a keyword (6 down to 1).
    func scores(_ term: String) -> [Int: Int] {
        var scores: [Int: Int] = [:]
        for (word, items) in index where word.hasPrefix(term) {
            let whole = word.count == term.count
            for (item, place) in items {
                let score = place.rawValue * 2 - (whole ? 0 : 1)
                if score > scores[item, default: 0] { scores[item] = score }
            }
        }
        return scores
    }

    /// Lowercase, accent-free words: "Flag: España" is ["flag", "espana"].
    static func words(_ text: String) -> [String] {
        Lexicon.fold(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}
