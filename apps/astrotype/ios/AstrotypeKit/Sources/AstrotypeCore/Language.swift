import Foundation
import Synchronization

/// Everything about the languages the engine types in, so the next language is files
/// under `Resources/<code>/`, not code (features/smart-matching/FEATURE.md "Languages",
/// features/languages/FEATURE.md): the dictionary and the word-pair models. Words with
/// accents sit under their plain letters (`Lexicon.fold`), since the keys are a to z.
///
///     let english = try Language.bundled("en")
///     let both = try Language.bundled(["en", "es"])    // guesses from both at once
///     var composer = Composer(language: both, layout: layout)
public struct Language: Sendable {
    /// One language's code ("en"), or the codes joined with "+" ("en+es") for several.
    public var code: String
    public var lexicon: Lexicon
    /// The word-pair models, one per language that has one; keyed by folded words.
    public var ngramModels: [NgramModel]

    /// The first word-pair model, nil for a language that has none yet.
    public var ngrams: NgramModel? {
        get { ngramModels.first }
        set { ngramModels = newValue.map { [$0] } ?? [] }
    }

    /// The single languages this one is made of.
    public var codes: [String] { code.split(separator: "+").map(String.init) }

    /// For several languages at once, each one on its own (same order as `codes`), so
    /// the keyboard can keep to one once a sentence shows which (`lock(for:)`). Empty
    /// for a single language.
    public var parts: [Language] = []

    public init(code: String, lexicon: Lexicon, ngrams: NgramModel? = nil) {
        self.code = code
        self.lexicon = lexicon
        self.ngramModels = ngrams.map { [$0] } ?? []
    }

    public init(code: String, lexicon: Lexicon, ngramModels: [NgramModel]) {
        self.code = code
        self.lexicon = lexicon
        self.ngramModels = ngramModels
    }

    /// The languages that ship in the package.
    public static let bundledCodes = ["en", "es"]

    /// Each bundled language's name in itself, for pickers.
    public static let names = ["en": "English", "es": "Español"]
    /// Each bundled language's name in English, under its own name in pickers.
    public static let englishNames = ["en": "English", "es": "Spanish"]

    /// The last bundled language loaded, handed out again instead of reading the files
    /// once more. Its word lists are shared, not copied, so every keyboard in the process
    /// types from the same ~7-12 MB. iOS can keep old keyboards alive after they close,
    /// each with its own model; they used to hold a dictionary each (Gabriel, 6 Nov 2026:
    /// "4 keyboards, 7 models, 7 loads" at 110 MB).
    private static let lastLoaded = Mutex<Language?>(nil)

    /// `load` unless the last language loaded was `code`.
    private static func reuse(_ code: String, _ load: () throws -> Language) throws -> Language {
        if let last = lastLoaded.withLock({ $0 }), last.code == code { return last }
        LiveCount.dictionaryLoads.add(1, ordering: .relaxed)
        let language = try load()
        lastLoaded.withLock { $0 = language }
        return language
    }

    /// A language from the package: its lexicon must be there, its word pairs may be.
    public static func bundled(_ code: String = "en") throws -> Language {
        try reuse(code) { try load(code) }
    }

    private static func load(_ code: String) throws -> Language {
        Language(code: code, lexicon: try lexicon([code]), ngrams: ngrams(code))
    }

    /// The word pairs in the package, mapped from the file (`NgramModel(contentsOf:)`).
    private static func ngrams(_ code: String) -> NgramModel? {
        (try? resource("bigrams", "bin", language: code)).flatMap { try? NgramModel(contentsOf: $0) }
    }

    /// Several bundled languages typed at once: one dictionary of all their words, each
    /// language weighing the same (`combined`), and every language's word pairs.
    public static func bundled(_ codes: [String]) throws -> Language {
        guard codes.count > 1 else { return try bundled(codes.first ?? "en") }
        return try reuse(codes.joined(separator: "+")) { try load(codes) }
    }

    private static func load(_ codes: [String]) throws -> Language {
        let parts = try codes.map { try load($0) }
        var both = Language(code: codes.joined(separator: "+"), lexicon: try lexicon(codes),
                            ngramModels: parts.flatMap(\.ngramModels))
        both.parts = parts
        return both
    }

    // MARK: Dictionary files

    /// Where the dictionaries are kept ready to read (`Lexicon.encode`), so they are
    /// mapped from storage instead of held in memory: about 12 MB less for the keyboard
    /// with two languages. Nil keeps them in memory (the app, the tests). Set before the
    /// first language loads; the keyboard uses its own Caches folder.
    public static var cacheFolder: URL? {
        get { cacheFolderLock.withLock { $0 } }
        set { cacheFolderLock.withLock { $0 = newValue } }
    }
    private static let cacheFolderLock = Mutex<URL?>(nil)

    /// The dictionary of `codes` (merged by `combined` when several): mapped from its
    /// file in `cacheFolder`, made there from `lexicon.tsv` the first time and after an
    /// update changes the word lists. In memory when there is no folder or it can't be
    /// written.
    static func lexicon(_ codes: [String], folder: URL? = cacheFolder) throws -> Lexicon {
        let sources = try codes.map { try resource("lexicon", "tsv", language: $0) }
        let entries = {
            let lists = try sources.map(Lexicon.readEntries)
            return lists.count == 1 ? lists[0] : combined(lists)
        }
        guard let folder else { return Lexicon(entries: try entries()) }
        let prefix = "lexicon-\(codes.joined(separator: "+"))-"
        let file = folder.appendingPathComponent(prefix + stamp(sources) + ".aslx")
        if let mapped = try? Lexicon(mapping: file) { return mapped }
        let data = Lexicon.encode(try entries())
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            // Older files for the same languages (an earlier version's words).
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names where name.hasPrefix(prefix) && name != file.lastPathComponent {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
            return try Lexicon(mapping: file)
        } catch {
            return try Lexicon(data: data)
        }
    }

    /// Names a dictionary file by the format and its word lists' sizes and dates, so a
    /// new version of either makes a new file.
    static func stamp(_ sources: [URL]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        var parts = ["v\(Lexicon.formatVersion)"]
        for url in sources {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            parts.append("\(size):\(Int64(date))")
        }
        for byte in parts.joined(separator: "|").utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return String(hash, radix: 16)
    }

    // MARK: Keeping to one language

    /// How many times commoner a word must be in one language than in every other for
    /// it to say which language the sentence is in: "que", "the", "gracias" do; "no",
    /// "me", "a", "come", "real" (common in both) don't.
    public static let sureRatio: Float = 30

    /// The language `word` clearly belongs to (`sureRatio`), or nil when it could be
    /// either, or is in none. Always nil for a single language.
    public func sureLanguage(of word: String) -> String? {
        let key = Lexicon.fold(word)
        guard parts.count > 1, !key.isEmpty else { return nil }
        // log P(word) in each language; a language without the word is -infinity.
        let logs = parts.map { part in
            part.lexicon.logPrior(of: key).map { $0 + part.lexicon.logProbabilityOffset } ?? -.infinity
        }
        guard let best = logs.indices.max(by: { logs[$0] < logs[$1] }), logs[best].isFinite else { return nil }
        let margin = log(Self.sureRatio)
        for (i, other) in logs.enumerated() where i != best && logs[best] - other < margin { return nil }
        return parts[best].code
    }

    /// The language a sentence is in: the first of its words that clearly belongs to
    /// one (`sureLanguage(of:)`). Nil while none does, so the next word may be either.
    /// The first sure word decides: later words don't switch it back and forth
    /// (Gabriel, 3 Nov 2026).
    public func lock(for sentence: [String]) -> String? {
        guard parts.count > 1 else { return nil }
        for word in sentence { if let code = sureLanguage(of: word) { return code } }
        return nil
    }

    /// The single language `code` of this one, or this one when it isn't part of it.
    public func part(_ code: String?) -> Language {
        parts.first { $0.code == code } ?? self
    }

    /// Word lists merged so each language counts the same whatever its counts add up
    /// to: every list is scaled to a total of 1 first, and a word in two lists ("no",
    /// "a") gets both shares.
    public static func combined(_ lists: [[Lexicon.Entry]]) -> [Lexicon.Entry] {
        var out: [Lexicon.Entry] = []
        var index: [String: Int] = [:]
        for list in lists {
            let total = list.reduce(0) { $0 + $1.frequency }
            guard total > 0 else { continue }
            for entry in list {
                let share = entry.frequency / total
                if let i = index[entry.word] {
                    out[i].frequency += share
                } else {
                    index[entry.word] = out.count
                    out.append(Lexicon.Entry(word: entry.word, frequency: share))
                }
            }
        }
        return out
    }

    static func resource(_ name: String, _ ext: String, language code: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: code) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(code)/\(name).\(ext)"])
        }
        return url
    }
}
