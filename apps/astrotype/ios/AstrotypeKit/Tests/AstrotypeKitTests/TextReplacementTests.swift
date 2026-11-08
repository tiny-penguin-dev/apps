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
        #expect(expand("{nope} {date") == "{nope} {date")
        #expect(expand("{ {date}") == "{ Nov 8, 2026")
        #expect(expand("plain") == "plain")
    }

    @Test func shortcutsAreOneWordWithNoSpaces() {
        #expect(TextReplacements.shortcut(" OMW ") == "omw")
        #expect(TextReplacements.shortcut("añoq") == "añoq")
        #expect(TextReplacements.shortcut("a") == nil)
        #expect(TextReplacements.shortcut("on my") == nil)
        #expect(TextReplacements.shortcut("@@") == "@@")
        #expect(TextReplacements.shortcut(";Addr") == ";addr")
        #expect(TextReplacements.shortcut("addr1") == "addr1")
        #expect(TextReplacements.shortcut("12") == nil)
        #expect(TextReplacements.isWord("omw") && !TextReplacements.isWord(";addr"))
    }

    @Test func ownReplacementsWinOverThePhones() {
        let r = TextReplacements(own: [TextReplacement(shortcut: "omw", phrase: "Mine")],
                                 phone: [TextReplacement(shortcut: "OMW", phrase: "Phone's"),
                                         TextReplacement(shortcut: "brb", phrase: "Be right back"),
                                         TextReplacement(shortcut: ";;", phrase: "Semis")])
        #expect(r.phrase(for: "Omw") == "Mine")
        #expect(r.phrase(for: "brb") == "Be right back")
        #expect(r.phrase(for: ";;") == "Semis")
        // Only the shortcuts of letters are offered as words.
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
    // MARK: Phase 2: more variables, the cursor, blanks, symbols, suggesting, the snippet page

    @Test func moreVariablesFillIn() {
        let details = PersonalDetails(name: "Gabriel", email: "g@example.com", phone: "555 0100", address: "1 Main St")
        let context = TextReplacements.Context(date: Self.day, locale: Self.locale, timeZone: Self.utc,
                                               clipboard: { "copied" }, details: details, random: { $0 - 1 },
                                               filled: ["who": "Ana"])
        let expand = { (phrase: String) in TextReplacements.expand(phrase, in: context) }
        #expect(expand("{name} <{email}> {phone}, {address}").text == "Gabriel <g@example.com> 555 0100, 1 Main St")
        #expect(expand("{date+7} {date-1} {date+0}").text == "Nov 15, 2026 Nov 7, 2026 Nov 8, 2026")
        // Sunday the 8th: next Friday is the 13th, next Sunday a week on.
        #expect(expand("{next friday} {Next Sunday}").text == "Nov 13, 2026 Nov 15, 2026")
        #expect(expand("{pick: thanks | cheers | ty}").text == "ty")
        #expect(expand("{clipboard}!").text == "copied!")
        #expect(expand("Hi {?who}, {?what}").text == "Hi Ana, [what]")
        #expect(expand("Dear {cursor},").text == "Dear ,")
        #expect(expand("Dear {cursor},").cursorFromEnd == 1)
        #expect(expand("{next blursday} {date+x}").text == "{next blursday} {date+x}")
        #expect(TextReplacements.blanks(in: "{?who} {?when} {?who} {?}") == ["who", "when"])
    }

    @Test func theCursorGoesWhereThePhraseSays() {
        var composer = Self.composer([("ds", "Dear {cursor},")])
        var field = TypingReplay.Field()
        let lifted = Synth.taps(&composer, "ds")
        #expect(composer.state.replacement == "Dear ,")
        let effects = composer.press(.space, time: lifted + 0.1)
        field.apply(effects)
        // No space after it: the person types at the cursor.
        #expect(effects.contains(.moveCursor(-1)))
        #expect(field.text == "Dear " && field.after == ",")
        #expect(composer.state.bar == .idle)
    }

    @Test func theClipboardIsReadOnlyWhenThePhraseGoesIn() {
        var composer = Self.composer([("cb", "Copied: {clipboard}")])
        let reads = Counter()
        composer.clipboard = { reads.bump(); return "hello" }
        let lifted = Synth.taps(&composer, "cb")
        // The bar shows a stand-in, never the pasteboard.
        #expect(composer.state.replacement == "Copied: [clipboard]")
        #expect(reads.count == 0)
        let effects = composer.press(.space, time: lifted + 0.1)
        #expect(effects.contains(.commit("Copied: hello")))
        #expect(reads.count == 1)
    }

    @Test func aRandomPickIsTheOneTheBarShowed() {
        var composer = Self.composer([("ty", "{pick:thanks|cheers|ty!}")])
        composer.random = { $0 > 3 ? 7 : 0 }   // the roll: 7 % 3 = 1
        let lifted = Synth.taps(&composer, "ty")
        #expect(composer.state.replacement == "cheers")
        let effects = composer.press(.space, time: lifted + 0.1)
        #expect(effects.contains(.commit("cheers")))
    }

    @Test func yourDetailsComeFromSettings() {
        var settings = KeyboardSettings()
        settings.personalDetails = PersonalDetails(name: "Gabriel", email: "g@example.com")
        settings.save(TextReplacement(shortcut: "sig", phrase: "{name} ({email})"))
        var composer = Self.composer([])
        composer.settings = settings.composerSettings(from: composer.settings)
        let lifted = Synth.taps(&composer, "sig")
        let effects = composer.press(.space, time: lifted + 0.1)
        #expect(effects.contains(.commit("Gabriel (g@example.com)")))

        let back = try! JSONDecoder().decode(KeyboardSettings.self, from: JSONEncoder().encode(settings))
        #expect(back.personalDetails == settings.personalDetails)
        let old = try! JSONDecoder().decode(KeyboardSettings.self, from: Data("{\"autospace\":true}".utf8))
        #expect(old.personalDetails.isEmpty)
    }

    @Test func blanksAreAskedForBeforeThePhraseGoesIn() {
        var composer = Self.composer([("mtg", "Meeting with {?who} at {?when}.")])
        var field = TypingReplay.Field()
        let lifted = Synth.taps(&composer, "mtg")
        field.apply(composer.press(.space, time: lifted + 0.1))
        // The shortcut stays as typed while the bar asks.
        #expect(field.text == "mtg")
        #expect(composer.state.fillPrompt == "who")
        #expect(composer.state.bar == .correcting(""))
        composer.setContext(before: field.text)
        // Shift gives a capital; space types a space; any text goes in as it is.
        _ = composer.press(.shift, time: 1)
        field.apply(composer.press(.letter("a"), time: 1.1))
        field.apply(composer.press(.text("na Lu"), time: 1.2))
        #expect(composer.state.bar == .correcting("Ana Lu"))
        _ = composer.press(.backspace, time: 1.3)
        _ = composer.press(.text("z"), time: 1.4)
        field.apply(composer.press(.returnKey, time: 1.5))
        #expect(composer.state.fillPrompt == "when")
        #expect(field.text == "mtg")
        field.apply(composer.press(.text("3pm"), time: 1.6))
        field.apply(composer.press(.space, time: 1.7))
        field.apply(composer.press(.text("today"), time: 1.8))
        field.apply(composer.saveCorrection(time: 1.9))
        #expect(field.text == "Meeting with Ana Lz at 3pm today. ")
        #expect(composer.state.fillPrompt == nil)
        guard case .fix(let words, 0) = composer.state.bar else { Issue.record("\(composer.state.bar)"); return }
        #expect(words == ["Meeting with Ana Lz at 3pm today.", "mtg"])
    }

    @Test func cancellingABlankLeavesTheShortcut() {
        var composer = Self.composer([("mtg", "Meeting with {?who}")])
        var field = TypingReplay.Field()
        let lifted = Synth.taps(&composer, "mtg")
        field.apply(composer.press(.space, time: lifted + 0.1))
        _ = composer.press(.text("Ana"), time: 1)
        composer.cancelCorrection(time: 1.1)
        #expect(field.text == "mtg")
        #expect(composer.state.fillPrompt == nil)
        #expect(composer.state.bar != .correcting(""))
    }

    @Test func aShortcutWithASymbolBeforeItsLetters() {
        var composer = Self.composer([(";addr", "1 Main St")])
        var field = TypingReplay.Field()
        field.apply(composer.press(.symbol(";"), time: 0))
        composer.setContext(before: field.text)
        let lifted = Synth.taps(&composer, "addr", at: 0.5)
        #expect(composer.state.openWord == "addr")
        #expect(composer.state.replacement == "1 Main St")
        field.apply(composer.press(.space, time: lifted + 0.1))
        #expect(field.text == "1 Main St ")
        composer.setContext(before: field.text)
        guard case .fix(let words, 0) = composer.state.bar else { Issue.record("\(composer.state.bar)"); return }
        #expect(words.prefix(2) == ["1 Main St", ";addr"])
        // Taking it back writes the shortcut as it was.
        field.apply(composer.choose(guess: 1))
        #expect(field.text == ";addr ")
    }

    @Test func aShortcutOfSymbolsGoesInAtSpace() {
        var composer = Self.composer([("@@", "g@example.com"), ("addr1", "1 Main St")])
        var field = TypingReplay.Field(text: "mail ")
        composer.setContext(before: field.text)
        field.apply(composer.press(.text("@@"), time: 0))
        composer.setContext(before: field.text)
        field.apply(composer.press(.space, time: 0.2))
        #expect(field.text == "mail g@example.com ")
        composer.setContext(before: field.text)
        // Letters, then a digit: the word goes in, then the whole of it is replaced.
        let lifted = Synth.taps(&composer, "addr", at: 1)
        field.apply(composer.press(.symbol("1"), time: lifted + 0.1))
        composer.setContext(before: field.text)
        field.apply(composer.press(.returnKey, time: lifted + 0.2))
        #expect(field.text == "mail g@example.com 1 Main St\n")
    }

    @Test func aShortcutBeingTypedShowsOnTheBar() {
        var composer = Self.composer([("omw", "On my way!"), ("omwl", "On my way, a bit late")])
        let lifted = Synth.taps(&composer, "om")
        guard case .guesses(let words, let chosen) = composer.state.bar else { Issue.record("\(composer.state.bar)"); return }
        #expect(words.contains("omw"))
        #expect(words[chosen] != "omw")
        #expect(composer.state.previews["omw"] == "On my way!")
        let effects = composer.choose(guess: words.firstIndex(of: "omw")!, time: lifted + 0.1)
        #expect(effects.contains(.commit("On my way!")))
        // One letter is not enough to offer it.
        var other = Self.composer([("omw", "On my way!")])
        _ = Synth.taps(&other, "o")
        #expect(other.state.previews.isEmpty)
    }

    @Test func theSnippetPageWritesAPhrase() {
        var composer = Self.composer([("omw", "on my way!"), ("mtg", "Meeting with {?who}")], autoCapitalize: true)
        var field = TypingReplay.Field(text: "Hello")
        composer.setContext(before: field.text)
        field.apply(composer.write(replacement: "omw", time: 0))
        #expect(field.text == "Hello on my way! ")
        composer.setContext(before: field.text)

        // At a sentence start it gets its capital.
        var fresh = Self.composer([("omw", "on my way!")], autoCapitalize: true)
        var start = TypingReplay.Field(text: "Hi. ")
        fresh.setContext(before: start.text)
        start.apply(fresh.write(replacement: "omw", time: 0))
        #expect(start.text == "Hi. On my way! ")

        // An open word goes in first.
        var typing = Self.composer([("omw", "on my way!")])
        var open = TypingReplay.Field(text: "I'm ")
        typing.setContext(before: open.text)
        let lifted = Synth.taps(&typing, "ok")
        open.apply(typing.write(replacement: "omw", time: lifted + 0.1))
        #expect(open.text == "I'm ok on my way! ")

        // A phrase with blanks asks first, then goes in at the cursor.
        field.apply(composer.write(replacement: "mtg", time: 1))
        #expect(composer.state.fillPrompt == "who")
        field.apply(composer.press(.text("Ana"), time: 1.1))
        field.apply(composer.saveCorrection(time: 1.2))
        #expect(field.text == "Hello on my way! Meeting with Ana ")
    }

    @Test func thePhonesListCopiesInOncePerShortcut() {
        let phone = [TextReplacement(shortcut: "omw", phrase: "On my way!"), TextReplacement(shortcut: "BRB", phrase: "Be right back"),
                     TextReplacement(shortcut: "brb", phrase: "Again"), TextReplacement(shortcut: "x", phrase: "too short")]
        let own = [TextReplacement(shortcut: "omw", phrase: "Mine")]
        let copied = PhoneReplacementsFile.toCopy(phone, into: own)
        #expect(copied.map(\.shortcut) == ["brb"])
        #expect(copied[0].phrase == "Be right back")
        #expect(copied[0].id != phone[1].id)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("phone-\(UUID()).json")
        PhoneReplacementsFile.save(phone, to: url)
        #expect(PhoneReplacementsFile.load(from: url) == phone)
        #expect(PhoneReplacementsFile.load(from: nil).isEmpty)
        try? FileManager.default.removeItem(at: url)
    }
}

/// Counts calls from a `@Sendable` closure.
final class Counter: @unchecked Sendable {
    private(set) var count = 0
    func bump() { count += 1 }
}
