import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct EmojiTests {
    // MARK: Catalog

    @Test func bundledListHasApplesCategoriesInOrder() throws {
        let catalog = try EmojiCatalog.bundled()
        #expect(catalog.sections.map(\.category) == EmojiCategory.allCases)
        #expect(catalog.count > 1_800)
        #expect(catalog.sections[0].emoji.first?.text == "😀")
        #expect(catalog.sections.last!.emoji.contains { $0.text == "🇺🇸" })
        // No skin tone form is an emoji of its own, and none is listed twice.
        let all = catalog.sections.flatMap(\.emoji).map(\.text)
        #expect(Set(all).count == all.count)
        #expect(!all.contains("👍🏽"))
    }

    @Test func handsAndPeopleHaveFiveTones() throws {
        let catalog = try EmojiCatalog.bundled()
        let thumbs = try #require(catalog.emoji(for: "👍"))
        #expect(thumbs.tones == ["👍🏻", "👍🏼", "👍🏽", "👍🏾", "👍🏿"])
        #expect(catalog.emoji(for: "👍🏽") == thumbs)
        // An emoji written with a variation selector keeps it, and still finds its tones.
        #expect(catalog.emoji(for: "☝️")?.tones.first == "☝🏻")
        #expect(catalog.emoji(for: "🐶")?.hasTones == false)
    }

    @Test func emojiNewerThanTheSystemAreLeftOut() throws {
        let all = try EmojiCatalog.bundled()
        let ios18 = try EmojiCatalog.bundled(upTo: EmojiCatalog.version(forOS: 18, 0))
        #expect(ios18.count < all.count)
        #expect(ios18.sections.allSatisfy { $0.emoji.allSatisfy { $0.version <= 15.1 } })
        // 🫩 (face with bags under eyes) came in Emoji 16.0, with iOS 18.4.
        #expect(ios18.emoji(for: "🫩") == nil)
        #expect(try EmojiCatalog.bundled(upTo: EmojiCatalog.version(forOS: 18, 4)).emoji(for: "🫩") != nil)
    }

    @Test func versionTableCoversTheSupportedSystems() {
        #expect(EmojiCatalog.version(forOS: 18, 0) == 15.1)
        #expect(EmojiCatalog.version(forOS: 18, 4) == 16.0)
        #expect(EmojiCatalog.version(forOS: 26, 0) == 16.0)
        #expect(EmojiCatalog.version(forOS: 26, 2) == 16.0)
        // Never newer than the list itself is.
        #expect(EmojiCatalog.version(forOS: 30) <= 18.0)
    }

    @Test func badLinesAreSkipped() {
        let catalog = EmojiCatalog(tsv: "smileys\t0.6\t😀\t\nnope\t1.0\t😃\t\nfood\tx\t🍕\t\nfood\t1.0\t🍕\tA B\n")
        #expect(catalog.sections.map(\.category) == [.smileys, .food])
        #expect(catalog.emoji(for: "🍕")?.tones == [])
    }

    // MARK: History

    @Test func frequentlyUsedStartsFromTheStartersAndPutsUsedFirst() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var history = EmojiHistory()
        #expect(history.frequent(now: now) == EmojiHistory.starters)

        history.record("🍕", at: now)
        history.record("🍕", at: now)
        history.record("🐧", at: now.addingTimeInterval(1))
        let frequent = history.frequent(now: now.addingTimeInterval(2))
        #expect(frequent.prefix(2) == ["🍕", "🐧"])
        #expect(frequent.count == EmojiHistory.frequentCount)
        #expect(Set(frequent).count == frequent.count)
    }

    @Test func oldUsesFadeBehindNewOnes() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var history = EmojiHistory()
        for _ in 0..<4 { history.record("🎄", at: start) }
        let later = start.addingTimeInterval(90 * 86_400) // three half-lives: 4 fades to 0.5
        history.record("🌞", at: later)
        #expect(history.frequent(now: later).first == "🌞")
    }

    @Test func pickedTonesShowInFrequentlyUsedAndCanBeCleared() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var history = EmojiHistory()
        history.setTone("👍🏽", for: "👍")
        history.record("👍", at: now)
        #expect(history.tone(for: "👍") == "👍🏽")
        #expect(history.frequent(now: now).first == "👍🏽")
        history.setTone("👍", for: "👍")
        #expect(history.tone(for: "👍") == "👍")

        // It saves and loads as it was.
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(EmojiHistory.self, from: data) == history)
    }

    @Test func historyKeepsAHundredEmoji() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var history = EmojiHistory()
        history.record("🥇", at: now)
        history.record("🥇", at: now)
        for i in 0..<150 { history.record("x\(i)", at: now) }
        #expect(history.frequent(now: now, count: 200).filter { $0.hasPrefix("x") }.count < 100)
        #expect(history.frequent(now: now).first == "🥇")
    }

    // MARK: Layout

    @Test func emojiKeyTakesTheGlobesPlace() {
        let plain = Layout.qwerty(width: 390)
        #expect(plain.frame(of: .globe) == nil)
        let emoji = try! #require(plain.frame(of: .emoji))
        #expect(emoji.minX > plain.frame(of: .numbers)!.maxX)
        #expect(emoji.maxX < plain.frame(of: .space)!.minX)

        // With a globe (Home button phones) both are there, and space is shorter.
        let withGlobe = Layout.qwerty(width: 390, globe: true)
        let globe = try! #require(withGlobe.frame(of: .globe))
        #expect(globe.minX == emoji.minX)
        #expect(withGlobe.frame(of: .emoji)!.minX > globe.maxX)
        #expect(withGlobe.frame(of: .space)!.width < plain.frame(of: .space)!.width)
        #expect(withGlobe.frame(of: .returnKey) == plain.frame(of: .returnKey))
        #expect(Key.emoji.isFunction)

        for page in [Layout.Page.numbers, .symbols] {
            #expect(Layout.qwerty(width: 390, page: page).frame(of: .emoji) != nil)
        }
        let split = Layout.qwerty(width: 800, split: true, globe: true)
        #expect(split.frame(of: .emoji)!.minX > split.frame(of: .globe)!.maxX)
    }

    // MARK: Composer

    @Test func anEmojiAfterAnOpenWordWritesTheWordFirst() {
        var composer = Synth.composer()
        let lifted = Synth.taps(&composer, "the")
        let effects = composer.insert(emoji: "🍕", time: lifted + 0.1)
        #expect(effects.contains(.commit("the")))
        #expect(effects.contains(.insert(" 🍕")))
        #expect(composer.state.openWord == nil)
    }

    @Test func anEmojiOnItsOwnGoesInWithNoSpace() {
        var composer = Synth.composer()
        let effects = composer.insert(emoji: "👍🏽", time: 1)
        #expect(effects == [.haptic(.key), .insert("👍🏽")])
        // A second one right after, and the emoji key itself does nothing in the engine.
        #expect(composer.insert(emoji: "🎉", time: 1.2).contains(.insert("🎉")))
        #expect(composer.press(.emoji, time: 1.3).isEmpty)
    }
}
