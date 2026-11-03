import Foundation

/// The emoji page's sections, in Apple's order (features/emoji/FEATURE.md).
public enum EmojiCategory: String, CaseIterable, Sendable, Codable {
    case smileys, nature, food, activity, travel, objects, symbols, flags

    /// The section's name, as on Apple's keyboard.
    public var title: String {
        switch self {
        case .smileys: "Smileys & People"
        case .nature: "Animals & Nature"
        case .food: "Food & Drink"
        case .activity: "Activity"
        case .travel: "Travel & Places"
        case .objects: "Objects"
        case .symbols: "Symbols"
        case .flags: "Flags"
        }
    }
}

/// One emoji as the page shows it: the default (yellow) form and, for hands and
/// people, its five skin tone forms from light to dark.
public struct Emoji: Hashable, Sendable {
    public let text: String
    /// The Unicode emoji version it came in, to leave out what the system can't draw.
    public let version: Double
    /// Empty, or exactly five forms, light to dark.
    public let tones: [String]

    public init(_ text: String, version: Double = 0.6, tones: [String] = []) {
        self.text = text
        self.version = version
        self.tones = tones
    }

    public var hasTones: Bool { !tones.isEmpty }
}

/// Every emoji the page offers, by category: Unicode's list (`Resources/emoji/emoji.tsv`,
/// built by `ml/emoji/build_emoji.py`), cut to the emoji versions the running iOS draws.
/// Read once, when the page first opens.
///
///     let catalog = try EmojiCatalog.bundled(upTo: EmojiCatalog.version(forOS: 18, 4))
///     catalog.sections.first?.category   // .smileys
///     catalog.emoji(for: "👍🏽")?.text      // "👍", the default form
public struct EmojiCatalog: Sendable {
    public struct Section: Sendable, Equatable {
        public let category: EmojiCategory
        public let emoji: [Emoji]
    }

    /// The non-empty categories, in order.
    public let sections: [Section]
    private let byForm: [String: Emoji]

    public init(sections: [Section]) {
        self.sections = sections
        var byForm: [String: Emoji] = [:]
        for emoji in sections.flatMap(\.emoji) {
            byForm[emoji.text] = emoji
            for tone in emoji.tones { byForm[tone] = emoji }
        }
        self.byForm = byForm
    }

    /// Reads the list: `category<TAB>version<TAB>emoji<TAB>tones`, tones being five forms
    /// separated by spaces or nothing. Lines it can't read are skipped, and so are
    /// emoji newer than `maxVersion`.
    public init(tsv: String, upTo maxVersion: Double = .infinity) {
        var lists: [EmojiCategory: [Emoji]] = [:]
        for line in tsv.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3, let category = EmojiCategory(rawValue: String(fields[0])),
                  let version = Double(fields[1]), version <= maxVersion, !fields[2].isEmpty else { continue }
            let tones = fields.count > 3 ? fields[3].split(separator: " ").map(String.init) : []
            lists[category, default: []].append(Emoji(String(fields[2]), version: version,
                                                      tones: tones.count == 5 ? tones : []))
        }
        self.init(sections: EmojiCategory.allCases.compactMap { category in
            lists[category].map { Section(category: category, emoji: $0) }
        })
    }

    /// The bundled list, up to `maxVersion`.
    public static func bundled(upTo maxVersion: Double = .infinity) throws -> EmojiCatalog {
        guard let url = Bundle.module.url(forResource: "emoji", withExtension: "tsv", subdirectory: "emoji") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "emoji/emoji.tsv"])
        }
        return EmojiCatalog(tsv: try String(contentsOf: url, encoding: .utf8), upTo: maxVersion)
    }

    /// The newest emoji version an iOS release draws. Kept a step behind when unsure,
    /// so the page never shows an emoji as an empty box.
    public static func version(forOS major: Int, _ minor: Int = 0) -> Double {
        switch (major, minor) {
        case (27..., _): 17.0
        case (19..., _), (18, 4...): 16.0
        case (17, 4...), (18, _): 15.1
        case (17, _): 15.0
        default: 14.0
        }
    }

    /// The emoji a form belongs to: itself, or the default form of a skin tone form.
    public func emoji(for form: String) -> Emoji? { byForm[form] }

    /// How many emoji the page offers.
    public var count: Int { sections.reduce(0) { $0 + $1.emoji.count } }
}

/// What the person uses on the emoji page, kept with the keyboard's files: how often
/// each emoji was typed (fading, so Frequently used follows what they use now) and the
/// skin tone they picked for each emoji that has them.
///
///     var history = EmojiHistory()
///     history.setTone("👍🏽", for: "👍")   // picked on the tone picker
///     history.record("👍", at: now)
///     history.frequent(now: now)          // ["👍🏽", ...]: in the tone they use
///     history.tone(for: "👍")              // "👍🏽"
public struct EmojiHistory: Codable, Sendable, Equatable {
    struct Use: Codable, Sendable, Equatable {
        /// The count as of `last`.
        var count: Double
        var last: Date
    }

    /// Uses by default form.
    private var uses: [String: Use] = [:]
    /// The form picked last for an emoji with skin tones, by its default form.
    private var tones: [String: String] = [:]

    /// Counts halve every this many days.
    public static let halfLifeDays = 30.0
    /// How many Frequently used shows.
    public static let frequentCount = 30
    /// How many emoji the history remembers; the least used go first.
    static let keep = 100
    /// What Frequently used shows before anything is used (the most used emoji).
    public static let starters = ["😂", "❤️", "🤣", "👍", "😭", "🙏", "😘", "🥰", "😍", "😊", "🎉", "😁", "💕",
                                  "🥺", "😅", "🔥", "☺️", "🤦", "♥️", "🤷", "🙄", "😆", "🤗", "😉", "🎂",
                                  "🤔", "👏", "🙂", "😳", "🥳"]

    public init() {}

    /// The person typed `base` (in whatever skin tone: the count is per emoji).
    public mutating func record(_ base: String, at time: Date) {
        var use = uses[base] ?? Use(count: 0, last: time)
        use.count = Self.faded(use, at: time) + 1
        use.last = max(use.last, time)
        uses[base] = use
        if uses.count > Self.keep {
            let drop = uses.min { Self.faded($0.value, at: time) < Self.faded($1.value, at: time) }!.key
            uses[drop] = nil
        }
    }

    /// Remembers `form` as the skin tone for `base`; the default form clears it.
    public mutating func setTone(_ form: String, for base: String) {
        tones[base] = form == base ? nil : form
    }

    /// The form to show and type for `base`: its picked tone, else itself.
    public func tone(for base: String) -> String {
        tones[base] ?? base
    }

    /// The most used emoji, most first, in the forms the person picked; the starters
    /// fill it until there are enough. Ties go to the most recent.
    public func frequent(now: Date, count: Int = frequentCount) -> [String] {
        let used = uses.sorted {
            let (a, b) = (Self.faded($0.value, at: now), Self.faded($1.value, at: now))
            return a != b ? a > b : $0.value.last > $1.value.last
        }.map(\.key)
        var bases = Array(used.prefix(count))
        for starter in Self.starters where bases.count < count && !bases.contains(starter) {
            bases.append(starter)
        }
        return bases.map(tone(for:))
    }

    /// How much `base` is used now (its fading count), 0 when never: search ranks by it.
    public func weight(of base: String, now: Date) -> Double {
        uses[base].map { Self.faded($0, at: now) } ?? 0
    }

    private static func faded(_ use: Use, at time: Date) -> Double {
        let days = max(0, time.timeIntervalSince(use.last) / 86_400)
        return use.count * pow(0.5, days / halfLifeDays)
    }
}

/// Where the emoji history is kept.
public protocol EmojiStore: Sendable {
    func load() -> EmojiHistory?
    func save(_ history: EmojiHistory)
}

/// The emoji history as a JSON file in the keyboard's own container (it doesn't sync).
public struct FileEmojiStore: EmojiStore {
    private let file: JSONFile<EmojiHistory>

    public init(url: URL) {
        file = JSONFile(url)
    }

    public func load() -> EmojiHistory? { file.read() }
    public func save(_ history: EmojiHistory) { file.write(history) }
}

/// The emoji history in memory, for tests, previews and the app's practice fields.
public final class MemoryEmojiStore: EmojiStore, @unchecked Sendable {
    private let lock = NSLock()
    private var history: EmojiHistory?

    public init(_ history: EmojiHistory? = nil) {
        self.history = history
    }

    public func load() -> EmojiHistory? { lock.withLock { history } }
    public func save(_ history: EmojiHistory) { lock.withLock { self.history = history } }
}
