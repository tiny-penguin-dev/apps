import Foundation
import Testing
@testable import AstrotypeCore

/// Text replacements (features/text-replacements): a shortcut typed or swiped as a word
/// goes in as its phrase, with the date and time variables filled in.
@Suite struct TextReplacementTests {
    /// Sunday 8 Nov 2026, 08:51 in UTC.
    static let day = Date(timeIntervalSince1970: 1_794_127_860)
    static let locale = Locale(identifier: "en_US")
    static let utc = TimeZone(identifier: "UTC")!

    static func composer(_ items: [(String, String)], autoCapitalize: Bool = false) -> Composer {
        var composer = Synth.composer(autoCapitalize: autoCapitalize)
        composer.wallClock = { day }
        composer.replacementLocale = locale
        composer.replacementTimeZone = utc
        composer.settings.replacements = TextReplacements(own: items.map { TextReplacement(shortcut: $0.0, phrase: $0.1) })
        return composer
    }

    @Test func variablesFillIn() {
        let expand = { (phrase: String) in TextReplacements.expand(phrase, at: Self.day, locale: Self.locale, timeZone: Self.utc) }
        #expect(expand("{date}") == "Nov 8, 2026")
        #expect(expand("{day}, {month} {year}") == "Sunday, November 2026")
        #expect(expand("{tomorrow} / {yesterday}") == "Nov 9, 2026 / Nov 7, 2026")
        #expect(expand("at {TIME}").hasPrefix("at 8:51"))
        // Not a variable, or not closed: left as written.
        #expect(expand("{name} {date") == "{name} {date")
        #expect(expand("{ {date}") == "{ Nov 8, 2026")
        #expect(expand("plain") == "plain")
    }

    @Test func shortcutsAreOneWordOfLetters() {
        #expect(TextReplacements.shortcut(" OMW ") == "omw")
        #expect(TextReplacements.shortcut("añoq") == "añoq")
        #expect(TextReplacements.shortcut("a") == nil)
        #expect(TextReplacements.shortcut("on my") == nil)
        #expect(TextReplacements.shortcut("@@") == nil)
        #expect(TextReplacements.shortcut("addr1") == nil)
    }

    @Test func ownReplacementsWinOverThePhones() {
        let r = TextReplacements(own: [TextReplacement(shortcut: "omw", phrase: "Mine")],
                                 phone: [TextReplacement(shortcut: "OMW", phrase: "Phone's"),
                                         TextReplacement(shortcut: "brb", phrase: "Be right back"),
                                         TextReplacement(shortcut: ";;", phrase: "skipped")])
        #expect(r.phrase(for: "Omw") == "Mine")
        #expect(r.phrase(for: "brb") == "Be right back")
        #expect(r.shortcuts == ["omw", "brb"])
    }

    @Test func aTappedShortcutGoesInAsItsPhrase() {
        var composer = Self.composer([("omw", "On my way!")])
        let lifted = Synth.taps(&composer, "omw")
        #expect(composer.state.openWord == "omw")
        #expect(composer.state.replacement == "On my way!")
        let effects = composer.press(.space, time: lifted + 0.1) + composer.keyboardWillHide()
        #expect(effects.contains(.commit("On my way!")))
        #expect(effects.contains(.insert(" ")))
        // Never learned as a word of the person's, nor its touches.
        #expect(!effects.contains { if case .learn = $0 { true } else { false } })
        #expect(!effects.contains { if case .settled = $0 { true } else { false } })
    }

    @Test func theBarOffersTheShortcutBackAndBackspaceReopensIt() {
        var composer = Self.composer([("omw", "On my way!")])
        let lifted = Synth.taps(&composer, "omw")
        _ = composer.press(.space, time: lifted + 0.1)
        composer.setContext(before: "On my way! ")
        guard case .fix(let words, 0) = composer.state.bar else {
            Issue.record("expected the fix bar, got \(composer.state.bar)"); return
        }
        #expect(Array(words.prefix(2)) == ["On my way!", "omw"])
        // Tapping the shortcut writes it as typed.
        let back = composer.choose(guess: 1)
        #expect(back.contains(.deleteBackward("On my way! ".count)))
        #expect(back.contains(.insert("omw ")))

        // Backspace right after the phrase takes it back to the shortcut, still open.
        var other = Self.composer([("omw", "On my way!")])
        let t = Synth.taps(&other, "omw")
        _ = other.press(.space, time: t + 0.1)
        other.setContext(before: "On my way! ")
        let undo = other.press(.backspace, time: t + 0.3)
        #expect(undo.contains(.deleteBackward("On my way! ".count)))
        #expect(undo.contains(.mark("omw")))
        #expect(other.state.replacement == "On my way!")
    }

    @Test func aSwipedShortcutGoesInToo() {
        var composer = Self.composer([("brb", "be right back")])
        Synth.swipe(&composer, "brb")
        #expect(composer.state.openWord == "brb")
        let effects = composer.press(.space, time: 0.5)
        #expect(effects.contains(.commit("be right back")))
    }

    @Test func aCapitalOnTheShortcutCapitalisesThePhrase() {
        var composer = Self.composer([("brb", "be right back")], autoCapitalize: true)
        composer.setContext(before: "")
        let lifted = Synth.taps(&composer, "brb")
        #expect(composer.state.openWord == "Brb")
        let effects = composer.press(.space, time: lifted + 0.1)
        #expect(effects.contains(.commit("Be right back")))
    }

    @Test func variablesFillInAsThePhraseGoesIn() {
        var composer = Self.composer([("tdy", "{day}, {date}")])
        let lifted = Synth.taps(&composer, "tdy")
        let effects = composer.press(.space, time: lifted + 0.1)
        #expect(effects.contains(.commit("Sunday, Nov 8, 2026")))
    }

    @Test func noReplacementWhereTheFieldSaysNo() {
        var composer = Self.composer([("omw", "On my way!")])
        composer.settings = Field(content: .password).composerSettings(composer.settings)
        let lifted = Synth.taps(&composer, "omw")
        #expect(composer.state.replacement == nil)
        let effects = composer.press(.space, time: lifted + 0.1)
        #expect(effects.contains(.commit("omw")))

        // An email field still replaces: a shortcut for an address.
        #expect(Field(keyboard: .email).replacesText)
        #expect(!Field(keyboard: .numbers).replacesText)
        #expect(!Field(corrects: false).replacesText)
    }

    @Test func savingKeepsOneReplacementPerShortcut() {
        var settings = KeyboardSettings()
        let saved = settings.save(TextReplacement(shortcut: "OMW", phrase: "On my way"))
        let spaced = settings.save(TextReplacement(shortcut: "o m w", phrase: "x"))
        let empty = settings.save(TextReplacement(shortcut: "sig", phrase: ""))
        #expect(saved && !spaced && !empty)
        var edited = settings.textReplacements[0]
        edited.phrase = "On my way!"
        settings.save(edited)
        settings.save(TextReplacement(shortcut: "brb", phrase: "Be right back"))
        #expect(settings.textReplacements.map(\.shortcut) == ["brb", "omw"])
        #expect(settings.textReplacements[1].phrase == "On my way!")
        // A new one on a shortcut already used takes its place.
        settings.save(TextReplacement(shortcut: "omw", phrase: "Coming"))
        #expect(settings.textReplacements.map(\.phrase) == ["Coming", "Be right back"])

        // They survive a round trip, and older settings read with none.
        let data = try! JSONEncoder().encode(settings)
        let back = try! JSONDecoder().decode(KeyboardSettings.self, from: data)
        #expect(back.textReplacements == settings.textReplacements)
        let old = try! JSONDecoder().decode(KeyboardSettings.self, from: Data("{\"autospace\":true}".utf8))
        #expect(old.textReplacements.isEmpty && old.usesPhoneReplacements)
        #expect(settings.composerSettings().replacements.phrase(for: "brb") == "Be right back")
    }
}
