import Foundation

/// Everything about one language the engine needs, so the next language is files under
/// `Resources/<code>/`, not code (features/smart-matching/FEATURE.md "Languages"):
/// the dictionary and the word-pair model. The alphabet is a to z for now, which the
/// trie assumes; a language with more letters widens `Lexicon` when it comes.
///
///     let english = try Language.bundled("en")
///     var composer = Composer(language: english, layout: layout)
public struct Language: Sendable {
    public var code: String
    public var lexicon: Lexicon
    /// The word-pair model, nil for a language that has none yet.
    public var ngrams: NgramModel?

    public init(code: String, lexicon: Lexicon, ngrams: NgramModel? = nil) {
        self.code = code
        self.lexicon = lexicon
        self.ngrams = ngrams
    }

    /// The languages that ship in the package.
    public static let bundledCodes = ["en"]

    /// A language from the package: its lexicon must be there, its word pairs may be.
    public static func bundled(_ code: String = "en") throws -> Language {
        let lexicon = try Lexicon(contentsOf: resource("lexicon", "tsv", language: code))
        let ngrams = (try? resource("bigrams", "bin", language: code)).flatMap { try? NgramModel(contentsOf: $0) }
        return Language(code: code, lexicon: lexicon, ngrams: ngrams)
    }

    static func resource(_ name: String, _ ext: String, language code: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: code) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(code)/\(name).\(ext)"])
        }
        return url
    }
}
