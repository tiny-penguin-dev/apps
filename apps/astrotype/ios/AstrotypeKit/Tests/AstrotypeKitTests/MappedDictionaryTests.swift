import Foundation
import Testing
@testable import AstrotypeCore

/// The dictionaries and word pairs read in place from files (`MappedBytes`), so the
/// keyboard doesn't hold them in memory.
@Suite struct MappedDictionaryTests {
    func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dictionaries-\(UUID().uuidString)")
    }

    /// A dictionary written and mapped back finds the same words, spellings and priors.
    @Test func aMappedLexiconMatchesTheOneInMemory() throws {
        let entries = [("the", 100.0), ("canción", 5), ("cancion", 1), ("está", 20), ("esta", 30), ("año", 4)]
            .map { Lexicon.Entry(word: $0.0, frequency: $0.1) }
        let memory = Lexicon(entries: entries)
        let file = folder().appendingPathExtension("aslx")
        try Lexicon.encode(entries).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let mapped = try Lexicon(mapping: file)
        #expect(mapped.isMapped && !memory.isMapped)
        #expect(mapped.nodeCount == memory.nodeCount)
        #expect(mapped.logProbabilityOffset == memory.logProbabilityOffset)
        for word in ["the", "cancion", "esta", "ano"] {
            #expect(mapped.logPrior(of: word) == memory.logPrior(of: word))
        }
        #expect(mapped.logPrior(of: "nope") == nil)
        #expect(mapped.spellings(of: "esta").map(\.word) == ["esta", "está"])
        #expect(mapped.spellings(of: "cancion").map(\.word) == memory.spellings(of: "cancion").map(\.word))
        #expect(mapped.completions(of: "th", limit: 3) == ["the"])
    }

    /// A file that is cut short or isn't a dictionary is refused, not read past its end.
    @Test func aBrokenFileIsRefused() throws {
        let data = Lexicon.encode([Lexicon.Entry(word: "hello", frequency: 1)])
        #expect(throws: (any Error).self) { try Lexicon(data: data.prefix(data.count - 8)) }
        #expect(throws: (any Error).self) { try Lexicon(data: Data("not a lexicon at all, really".utf8) + Data(count: 64)) }
    }

    /// With a folder, the bundled dictionary is made there once, then mapped; it reads
    /// like the one built in memory.
    @Test func theBundledDictionaryIsMadeOnceThenMapped() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let memory = try Language.lexicon(["en"], folder: nil)
        let first = try Language.lexicon(["en"], folder: folder)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.count == 1 && files[0].hasPrefix("lexicon-en-"))
        let date = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(files[0]).path)[.modificationDate] as? Date
        let second = try Language.lexicon(["en"], folder: folder)
        let dateAfter = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(files[0]).path)[.modificationDate] as? Date
        #expect(first.isMapped && second.isMapped && !memory.isMapped)
        #expect(date == dateAfter)
        #expect(second.nodeCount == memory.nodeCount)
        for word in ["the", "because", "people", "zebra"] {
            #expect(second.logPrior(of: word) == memory.logPrior(of: word))
        }
    }

    /// Two languages at once get their own file, and an old one for the same languages
    /// is removed when a new one is made.
    @Test func oldFilesForTheSameLanguagesAreRemoved() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: folder.appendingPathComponent("lexicon-en+es-0ld.aslx"))
        try Data("other".utf8).write(to: folder.appendingPathComponent("lexicon-es-0ld.aslx"))
        let both = try Language.lexicon(["en", "es"], folder: folder)
        #expect(both.isMapped)
        #expect(both.logPrior(of: "gracias") != nil && both.logPrior(of: "thanks") != nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(files.count == 2)
        #expect(files.contains("lexicon-es-0ld.aslx"))
        #expect(!files.contains("lexicon-en+es-0ld.aslx"))
    }

    /// A file that went bad on disk is made again.
    @Test func aBadFileIsMadeAgain() throws {
        let folder = folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try Language.lexicon(["es"], folder: folder)
        let name = try FileManager.default.contentsOfDirectory(atPath: folder.path)[0]
        try Data("broken".utf8).write(to: folder.appendingPathComponent(name))
        let again = try Language.lexicon(["es"], folder: folder)
        #expect(again.isMapped && again.logPrior(of: "gracias") != nil)
    }

    /// The word pairs in the package are the current version, read in place.
    @Test func theBundledWordPairsAreMapped() throws {
        for code in Language.bundledCodes {
            let model = try NgramModel(contentsOf: Language.resource("bigrams", "bin", language: code))
            #expect(model.isMapped)
            #expect(model.pairCount > 100_000)
        }
    }
}
