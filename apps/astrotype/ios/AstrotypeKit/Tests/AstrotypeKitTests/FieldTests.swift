import Foundation
import Testing
@testable import AstrotypeCore

/// features/field-types: the keyboard follows the field it types in.
@Suite struct FieldTests {
    // MARK: Reading the field

    @Test func theKeyboardTypeAndContentPickTheKind() {
        #expect(Field().kind == .text)
        #expect(Field(keyboard: .email).kind == .email)
        #expect(Field(content: .username).kind == .email)
        #expect(Field(content: .email).kind == .email)
        #expect(Field(keyboard: .url).kind == .url)
        #expect(Field(content: .url).kind == .url)
        #expect(Field(keyboard: .webSearch).kind == .webSearch)
        #expect(Field(keyboard: .twitter).kind == .social)
        #expect(Field(keyboard: .numbers).kind == .numbers)
        #expect(Field(keyboard: .phone).kind == .numbers)
    }

    /// Return acts (search, go, send, next...) everywhere but the plain return key, and
    /// the composer is told, so nothing changes the text after the "\n" has gone.
    @Test func returnActsUnlessItIsAPlainReturn() {
        for key in Field.ReturnKey.allCases {
            let settings = Field(returnKey: key).composerSettings(Composer.Settings())
            #expect(settings.returnActs == (key != .return))
        }
    }

    @Test func addressesAndNumbersAreTypedExactlyWithNoSpacesOrCapitals() {
        for field in [Field(keyboard: .email), Field(keyboard: .url), Field(keyboard: .numbers)] {
            #expect(field.exactTaps)
            #expect(!field.spacesWords)
            #expect(!field.autospaces)
            #expect(!field.learns)
            #expect(field.capitals == .none)
        }
    }

    @Test func plainSearchAndSocialFieldsKeepTheirTyping() {
        let text = Field()
        #expect(!text.exactTaps && text.spacesWords && text.autospaces && text.learns)
        let search = Field(keyboard: .webSearch, returnKey: .search)
        #expect(!search.exactTaps && search.spacesWords && !search.autospaces && search.learns)
        let social = Field(keyboard: .twitter)
        #expect(!social.exactTaps && social.autospaces && social.learns)
    }

    @Test func noCorrectionsMeansExactTapsButSpacesStay() {
        let field = Field(corrects: false)
        #expect(field.exactTaps)
        #expect(field.spacesWords && field.autospaces)
        #expect(!field.learns)
    }

    @Test func codesAndPasswordsAreTypedExactlyAndNeverLearned() {
        for field in [Field(content: .code), Field(content: .password), Field(secure: true)] {
            #expect(field.exactTaps)
            #expect(!field.spacesWords)
            #expect(!field.learns)
            #expect(field.capitals == .none)
        }
    }

    @Test func theFieldsCapitalsCount() {
        #expect(Field(capitals: .words).capitals == .words)
        #expect(Field(capitals: .all).capitals == .all)
        #expect(Field(capitals: .none).capitals == .none)
        // An address never gets a capital, whatever the app says.
        #expect(Field(keyboard: .email, capitals: .sentences).capitals == .none)
    }

    @Test func theReturnKeySaysTheAppsWord() {
        #expect(Field.ReturnKey.return.label == nil)
        #expect(Field.ReturnKey.go.label == "go")
        #expect(Field.ReturnKey.search.label == "search")
        #expect(Field.ReturnKey.emergencyCall.label == "emergency call")
        #expect(Field.ReturnKey.go.isAction)
        #expect(Field.ReturnKey.send.isAction)
        #expect(!Field.ReturnKey.next.isAction)
        #expect(!Field.ReturnKey.return.isAction)
        #expect(Field.ReturnKey.search.spokenName == "Search")
        #expect(Field.ReturnKey.return.spokenName == "Return")
    }

    @Test func theFieldOnlyTakesAwayFromThePersonsSettings() {
        var base = Composer.Settings()
        base.autospaceDelay = nil // the person turned autospace off
        let text = Field().composerSettings(base)
        #expect(text.autospaceDelay == nil)
        base.autospaceDelay = 0.9
        #expect(Field().composerSettings(base).autospaceDelay == 0.9)
        #expect(Field(keyboard: .webSearch).composerSettings(base).autospaceDelay == nil)
        let email = Field(keyboard: .email).composerSettings(base)
        #expect(email.autospaceDelay == nil && email.exactTaps && !email.spacesWords && email.capitals == .none)
    }

    @Test func theFieldPicksTheRowAndPage() {
        #expect(Field().bottomRow == .standard)
        #expect(Field(keyboard: .email).bottomRow == .email)
        #expect(Field(keyboard: .url).bottomRow == .url)
        #expect(Field(keyboard: .webSearch).bottomRow == .webSearch)
        #expect(Field(keyboard: .twitter).bottomRow == .social)
        #expect(Field(keyboard: .numbers).startPage == .numbers)
        #expect(Field().startPage == .letters)
    }

    // MARK: Typing

    static func composer(_ field: Field) -> Composer {
        var settings = Composer.Settings()
        settings.autoCapitalize = true
        return Composer(dictionary: Synth.lexicon, layout: Synth.layout, settings: field.composerSettings(settings))
    }

    @Test func tapsInAnEmailFieldGoInAsTapped() {
        var composer = Self.composer(Field(keyboard: .email))
        var normal = Self.composer(Field())
        Synth.taps(&normal, "gmial")
        let lifted = Synth.taps(&composer, "gmial")
        #expect(composer.state.openWord == "gmial")
        // No autospace, no capital at the start.
        #expect(composer.autospaceDue == nil)
        #expect(composer.tick(time: lifted + 5).isEmpty)
        let effects = composer.press(text: ".com", time: lifted + 0.2)
        #expect(effects.contains(.commit("gmial")))
        #expect(effects.contains(.insert(".com")))
        #expect(!effects.contains { if case .learn = $0 { true } else { false } })
    }

    @Test func aSwipeInAnEmailFieldIsStillGuessed() {
        var composer = Self.composer(Field(keyboard: .email))
        Synth.swipe(&composer, "gmail")
        #expect(composer.state.openWord != nil)
        #expect(composer.autospaceDue == nil)
    }

    @Test func aGuessFromTheBarInAnAddressHasNoSpaceAfterIt() {
        var composer = Self.composer(Field(keyboard: .email))
        let lifted = Synth.taps(&composer, "hello")
        let effects = composer.choose(guess: 0, time: lifted + 0.1)
        #expect(effects.contains(.commit("hello")))
        #expect(!effects.contains(.insert(" ")))
        // And a space pressed now is a plain space, not skipped.
        #expect(composer.press(.space, time: lifted + 0.2).contains(.insert(" ")))
    }

    @Test func aDoubleSpaceInAnAddressIsNoPeriod() {
        var composer = Self.composer(Field(keyboard: .email))
        let lifted = Synth.taps(&composer, "hi")
        _ = composer.press(.space, time: lifted + 0.1)
        let second = composer.press(.space, time: lifted + 0.2)
        #expect(!second.contains(.insert(". ")))
        #expect(second.contains(.insert(" ")))
    }

    @Test func tapsInAFieldWithoutCorrectionsGoInAsTappedWithAutospace() {
        var composer = Self.composer(Field(corrects: false))
        let lifted = Synth.taps(&composer, "teh")
        #expect(composer.state.openWord == "Teh")
        #expect(composer.autospaceDue != nil)
        let effects = composer.tick(time: lifted + 5)
        #expect(effects.contains(.commit("Teh")))
        #expect(effects.contains(.insert(" ")))
    }

    @Test func capitalsFollowTheField() {
        var none = Self.composer(Field(capitals: .none))
        #expect(!none.state.isShifted)
        Synth.taps(&none, "the")
        #expect(none.state.openWord == "the")

        var words = Self.composer(Field(capitals: .words))
        words.setContext(before: "Ada ")
        #expect(words.state.isShifted)
        words.setContext(before: "Ada")
        #expect(!words.state.isShifted)

        var all = Self.composer(Field(capitals: .all))
        all.setContext(before: "ABC ")
        Synth.taps(&all, "the")
        #expect(all.state.openWord == "THE")
    }

    @Test func dotComTypesItselfWithNoWordOpen() {
        var composer = Self.composer(Field(keyboard: .url))
        let effects = composer.press(.text(".com"), time: 0)
        #expect(effects.contains(.insert(".com")))
    }

    // MARK: The bottom row

    @Test func theEmailRowSwapsEmojiForAtAndShortensReturn() {
        let standard = Layout.qwerty(width: 390)
        let email = Layout.qwerty(width: 390, bottom: .email)
        let space = email.frame(of: .space)!, at = email.frame(of: .symbol("@"))!, dot = email.frame(of: .symbol("."))!
        let ret = email.frame(of: .returnKey)!
        // "@" takes the emoji key's place; space keeps its size and place.
        #expect(email.frame(of: .emoji) == nil)
        #expect(at == standard.frame(of: .emoji))
        #expect(space == standard.frame(of: .space))
        // "." comes out of return, which still ends at P's edge (Gabriel, 9 Nov 2026).
        let q = email.frame(of: .letter("q"))!
        #expect(dot.width == q.width)
        #expect(ret.maxX == standard.frame(of: .returnKey)!.maxX)
        #expect(abs(ret.width - (standard.frame(of: .returnKey)!.width - q.width - Layout.keyGap)) < 0.01)
        #expect(space.maxX < dot.minX && dot.maxX < ret.minX)
        #expect(abs((ret.minX - dot.maxX) - Layout.keyGap) < 0.01)
        // Each key is found where it is drawn.
        #expect(email.key(at: CGPoint(x: at.midX, y: at.midY)) == .symbol("@"))
    }

    @Test func aWebSearchShortensReturnForItsDot() {
        let standard = Layout.qwerty(width: 390)
        let search = Layout.qwerty(width: 390, bottom: .webSearch)
        #expect(search.frame(of: .space) == standard.frame(of: .space))
        #expect(search.frame(of: .emoji) == standard.frame(of: .emoji))
        #expect(search.frame(of: .returnKey)!.width < standard.frame(of: .returnKey)!.width)
    }

    @Test func withAGlobeTheFieldsRowKeepsIt() {
        let email = Layout.qwerty(width: 390, globe: true, bottom: .email)
        #expect(email.frame(of: .globe) == Layout.qwerty(width: 390, globe: true).frame(of: .globe))
        #expect(email.frame(of: .emoji) == nil)
        // Both keys go after space then, and return is never narrower than 123.
        let at = email.frame(of: .symbol("@"))!, space = email.frame(of: .space)!
        #expect(space.maxX < at.minX)
        #expect(email.frame(of: .returnKey)!.width >= email.frame(of: .numbers)!.width)
        let q = email.frame(of: .letter("q"))!
        #expect(space.width > 2.5 * q.width)
        // A plain field keeps both.
        #expect(Layout.qwerty(width: 390, globe: true).frame(of: .emoji) != nil)
    }

    @Test func theWebAddressRowHasNoSpace() {
        let url = Layout.qwerty(width: 390, bottom: .url)
        #expect(url.frame(of: .space) == nil)
        let dot = url.frame(of: .symbol("."))!, slash = url.frame(of: .symbol("/"))!, com = url.frame(of: .text(".com"))!
        #expect(abs(com.width - 2 * dot.width) <= 2 + Layout.keyGap)
        #expect(abs(dot.width - slash.width) <= 1)
        #expect(abs((url.frame(of: .returnKey)!.minX - com.maxX) - Layout.keyGap) < 0.01)
        #expect(url.frame(of: .returnKey) == Layout.qwerty(width: 390).frame(of: .returnKey))
    }

    @Test func otherPagesKeepApplesRow() {
        let numbers = Layout.qwerty(width: 390, page: .numbers, bottom: .url)
        #expect(numbers.bottomRow == .standard)
        #expect(numbers.frame(of: .space) == Layout.qwerty(width: 390, page: .numbers).frame(of: .space))
    }

    @Test func theSplitKeyboardSharesTheKeysOut() {
        let split = Layout.qwerty(width: 1000, split: true, bottom: .email)
        let spaces = split.placements.filter { $0.key == .space }
        #expect(spaces.count == 2)
        let at = split.frame(of: .symbol("@"))!, dot = split.frame(of: .symbol("."))!
        #expect(split.side(at: CGPoint(x: at.midX, y: 0)) == .left)
        #expect(split.side(at: CGPoint(x: dot.midX, y: 0)) == .right)
        let q = split.frame(of: .letter("q"))!
        for space in spaces { #expect(space.frame.width >= q.width) }

        let url = Layout.qwerty(width: 1000, split: true, bottom: .url)
        #expect(url.frame(of: .space) == nil)
        #expect(url.frame(of: .text(".com")) != nil)
        // Nothing overlaps on the bottom row.
        let row = url.placements.filter { $0.row == 3 }.map(\.frame).sorted { $0.minX < $1.minX }
        for (a, b) in zip(row, row.dropFirst()) { #expect(a.maxX <= b.minX) }
    }
}
