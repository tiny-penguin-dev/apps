import Foundation
import Testing
@testable import AstrotypeCore

/// features/emoji-search: emoji found by name and keyword, in English and Spanish.
@Suite struct EmojiSearchTests {
    static let catalog = try! EmojiCatalog.bundled()
    static let en = EmojiNames.bundled("en")!
    static let es = EmojiNames.bundled("es")!
    static let english = EmojiSearch(catalog: catalog, names: [en])
    static let both = EmojiSearch(catalog: catalog, names: [en, es])

    @Test func everyEmojiHasANameInBothLanguages() {
        let all = Self.catalog.sections.flatMap(\.emoji)
        #expect(all.allSatisfy { Self.en.name(of: $0.text) != nil })
        #expect(all.allSatisfy { Self.es.name(of: $0.text) != nil })
        #expect(Self.en.name(of: "🍕") == "pizza")
    }

    @Test func aNameComesFirst() {
        #expect(Self.english.results(for: "pizza").first?.text == "🍕")
        #expect(Self.english.results(for: "PIZ").first?.text == "🍕")
        #expect(Self.english.results(for: "thumbs up").first?.text == "👍")
        #expect(Self.english.results(for: "penguin").first?.text == "🐧")
        // Keywords find it too, behind names: "cheese" is a keyword of 🍕.
        #expect(Self.english.results(for: "cheese").contains { $0.text == "🍕" })
        #expect(Self.english.results(for: "cheese").first?.text == "🧀")
    }

    @Test func everyWordHasToFit() {
        let hearts = Self.english.results(for: "red heart")
        #expect(hearts.first?.text == "❤️")
        #expect(!hearts.contains { $0.text == "💙" })
        #expect(Self.english.results(for: "pizza zebra").isEmpty)
        #expect(Self.english.results(for: "   ").isEmpty)
        #expect(Self.english.results(for: "zzzz").isEmpty)
    }

    @Test func spanishWorksWithoutAccents() {
        #expect(Self.english.results(for: "corazon rojo").isEmpty)
        #expect(Self.both.results(for: "corazón rojo").first?.text == "❤️")
        #expect(Self.both.results(for: "corazon rojo").first?.text == "❤️")
        #expect(Self.both.results(for: "espana").contains { $0.text == "🇪🇸" })
    }

    @Test func emojiYouUseComeFirstAmongEqualMatches() {
        let plain = Self.english.results(for: "heart")
        let now = Date(timeIntervalSince1970: 1_000_000)
        var history = EmojiHistory()
        let pick = plain[3].text
        history.record(pick, at: now)
        let ranked = Self.english.results(for: "heart", history: history, now: now)
        // Among the emoji whose name starts with "heart", the one used is first.
        #expect(ranked.firstIndex { $0.text == pick }! < 3)
        #expect(Set(ranked.map(\.text)) == Set(plain.map(\.text)))
    }

    @Test func onlyWhatThePhoneDrawsIsFound() {
        // 🫩 (face with bags under eyes) came in Emoji 16.0, with iOS 18.4.
        let old = EmojiSearch(catalog: try! EmojiCatalog.bundled(upTo: 15.1), names: [Self.en])
        #expect(Self.english.results(for: "bags").contains { $0.text == "🫩" })
        #expect(!old.results(for: "bags").contains { $0.text == "🫩" })
    }

    @Test func resultsAreCapped() {
        #expect(Self.english.results(for: "face").count == EmojiSearch.limit)
        #expect(Self.english.results(for: "face", limit: 5).count == 5)
    }

    @Test func theSearchFieldLearnsNothing() {
        #expect(!Field.emojiSearch.learns)
        #expect(!Field.emojiSearch.exactTaps)
        #expect(Field.emojiSearch.returnKey == .done)
        #expect(Field.text.learns)
    }

    /// It runs on every key while searching. About 12 to 25 ms a query in a debug build on its
    /// own (a few in release); CI runs suites side by side, so the bound has room.
    @Test func searchIsQuick() {
        let start = Date()
        for query in ["p", "pi", "piz", "pizz", "pizza", "red heart", "cara"] { _ = Self.both.results(for: query) }
        let ms = Date().timeIntervalSince(start) / 7 * 1000
        print("emoji search: \(String(format: "%.2f", ms)) ms per query (debug)")
        #expect(ms < 150, "mean \(ms) ms")
    }
}
