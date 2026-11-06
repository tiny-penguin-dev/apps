import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct LanguageReuseTests {
    /// Asking again for the languages just loaded hands back the same ones (shared
    /// word lists, not a second copy), and other languages still load.
    @Test func reusesTheLastLoadedLanguage() throws {
        let first = try Language.bundled(["en", "es"])
        let again = try Language.bundled(["en", "es"])
        #expect(again.code == "en+es")
        #expect(again.lexicon.nodeCount == first.lexicon.nodeCount)
        #expect(again.parts.map(\.code) == ["en", "es"])
        #expect(try Language.bundled("es").code == "es")
    }
}
