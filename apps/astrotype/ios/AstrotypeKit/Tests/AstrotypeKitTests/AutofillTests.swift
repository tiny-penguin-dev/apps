import Foundation
import Testing
@testable import AstrotypeCore

/// Autofill (features/autofill): the person's details on the bar when a field asks for
/// them, when it likely wants them, after "my email is ", or while one is being typed.
@Suite struct AutofillTests {
    static let details = PersonalDetails(firstName: "Ada", lastName: "Byron", email: "ada@example.com",
                                         phone: "555 0100", username: "adab", street: "1 Main St",
                                         city: "Springfield", state: "IL", postalCode: "62701", country: "USA")

    static func composer(_ field: Field) -> Composer {
        var composer = Synth.composer()
        composer.settings = field.composerSettings(composer.settings)
        composer.settings.details = details
        composer.setContext(before: "")
        return composer
    }

    @Test func aFieldSaysWhatItWants() {
        #expect(Field(asks: .name).autofillSlots == [.name])
        #expect(Field(content: .username).autofillSlots == [.username, .email])
        #expect(Field(asks: .username).autofillSlots == [.username, .email])
        #expect(Field(keyboard: .email).autofillSlots == [.email])
        // Capitals on every word and nothing else: a name or an address.
        #expect(Field(capitals: .words).autofillSlots == [.name, .address])
        #expect(Field().autofillSlots.isEmpty)
        #expect(Field(content: .password).autofillSlots.isEmpty)
        #expect(Field(secure: true, asks: .email).autofillSlots.isEmpty)
        // A phone or postal code field is a code (typed exactly), but still filled.
        #expect(Field(content: .code, asks: .phone).autofillSlots == [.phone])
    }

    @Test func detailsJoinAndSplit() {
        #expect(Self.details.name == "Ada Byron")
        #expect(Self.details.address == "1 Main St, Springfield, IL 62701, USA")
        #expect(Self.details.cityAndState == "Springfield, IL")
        #expect(PersonalDetails(street: "1 Main St\nApt 2", city: "Springfield").address == "1 Main St, Apt 2, Springfield")
        let old = PersonalDetails(name: "Ada King Byron", address: "1 Main St, Springfield")
        #expect(old.firstName == "Ada" && old.lastName == "King Byron")
        #expect(old.address == "1 Main St, Springfield")
    }

    @Test func olderSavedDetailsStillRead() throws {
        let json = #"{"name":"Ada Byron","email":"ada@example.com","address":"1 Main St, Springfield"}"#
        let read = try JSONDecoder().decode(PersonalDetails.self, from: Data(json.utf8))
        #expect(read.firstName == "Ada" && read.lastName == "Byron")
        #expect(read.street == "1 Main St, Springfield")
        #expect(read.name == "Ada Byron")
        // Written back with the joined ones too, for older keyboards on other devices.
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.details)) as? [String: Any]
        #expect(written?["name"] as? String == "Ada Byron")
        #expect(written?["address"] as? String == Self.details.address)
        #expect(try JSONDecoder().decode(PersonalDetails.self, from: JSONEncoder().encode(Self.details)) == Self.details)
    }

    @Test func anEmptyFieldOffersWhatItAsksFor() {
        let offers = Autofill.offers(for: [.username, .email], details: Self.details, before: "")
        #expect(offers.map(\.text) == ["adab", "ada@example.com"])
        // Not once something is in it.
        #expect(Autofill.offers(for: [.email], details: Self.details, before: "ada").isEmpty)
        // Nothing set, nothing offered; an empty detail is skipped.
        #expect(Autofill.offers(for: [.email], details: PersonalDetails(), before: "").isEmpty)
        #expect(Autofill.offers(for: [.company, .email], details: Self.details, before: "").map(\.slot) == [.email])
    }

    @Test func aChatAskingOffersTheDetail() {
        #expect(Autofill.offers(for: [], details: Self.details, before: "Sure! My email is ").map(\.text) == ["ada@example.com"])
        #expect(Autofill.offers(for: [], details: Self.details, before: "call me at ").map(\.text) == ["555 0100"])
        #expect(Autofill.offers(for: [], details: Self.details, before: "Mi dirección es ").map(\.slot) == [.address])
        // Only right after it, with the space.
        #expect(Autofill.offers(for: [], details: Self.details, before: "My email is").isEmpty)
        #expect(Autofill.offers(for: [], details: Self.details, before: "my email is down ").isEmpty)
        // A whole phrase, not the end of a longer word.
        #expect(Autofill.offers(for: [], details: Self.details, before: "enemy name is ").isEmpty)
    }

    @Test func aLongTextBeforeTheQuestionStillOffers() {
        // Only the end is read (it runs on every keystroke); the answer is the same.
        let paragraph = String(repeating: "We talked about the plan for a while and it went well. ", count: 60)
        #expect(Autofill.offers(for: [], details: Self.details, before: paragraph + "My email is ").map(\.slot) == [.email])
        #expect(Autofill.offers(for: [], details: Self.details, before: paragraph + "my email is    ").map(\.slot) == [.email])
        #expect(Autofill.offers(for: [], details: Self.details, before: paragraph + "My email is \n ").isEmpty)
        #expect(Autofill.offers(for: [], details: Self.details, before: paragraph + "enemy name is ").isEmpty)
        #expect(Autofill.offers(for: [.phone], details: Self.details, before: "  \n ").map(\.slot) == [.phone])
        // Against the plain reading of the whole text.
        func plain(_ before: String) -> [Autofill.Slot]? {
            guard before.last == " " else { return nil }
            let text = before.lowercased().trimmingCharacters(in: .whitespaces)
            for (slots, phrases) in Autofill.phrases {
                for phrase in phrases where text.hasSuffix(phrase) {
                    if let previous = text.dropLast(phrase.count).last, previous.isLetter { continue }
                    return slots
                }
            }
            return nil
        }
        let ends = ["", " ", "  ", "\n", "\n ", "x ", "My email is ", " my email is ", "MY EMAIL IS  ", "\tmy email is ",
                    "enemy name is ", "Mi correo electrónico es ", "mi correo electrónico es", "call me at ", "call me at\n",
                    "i live at ", "my username is ", "me llamo ", "name is ", "İ my name is "]
        for start in ["", "Hi. ", paragraph, "¿"] {
            for end in ends {
                let before = start + end
                #expect(Autofill.asked(before: before) == plain(before), "\(before.suffix(30))")
            }
        }
    }

    @Test func theStartOfADetailOffersAllOfIt() {
        let email = Autofill.completion(of: ["ada@"], slots: [], details: Self.details)
        #expect(email == Autofill.Offer(slot: .email, text: "ada@example.com", replacing: "ada@"))
        // The full name before the first name it starts with.
        #expect(Autofill.completion(of: ["ad"], slots: [], details: Self.details)?.slot == .email)
        #expect(Autofill.completion(of: ["ad"], slots: [.name], details: Self.details)?.text == "Ada Byron")
        #expect(Autofill.completion(of: ["Ada By", "By"], slots: [], details: Self.details)?.replacing == "Ada By")
        // Two letters at least, and never one already whole.
        #expect(Autofill.completion(of: ["a"], slots: [], details: Self.details) == nil)
        #expect(Autofill.completion(of: ["adab"], slots: [.username], details: Self.details) == nil)
    }

    @Test func tappingTheOfferFillsAnEmptyField() {
        var composer = Self.composer(Field(capitals: .words, asks: .name))
        #expect(composer.state.autofill == [Autofill.Offer(slot: .name, text: "Ada Byron")])
        var field = TypingReplay.Field()
        field.apply(composer.fill(autofill: 0, time: 0))
        #expect(field.text == "Ada Byron")
        composer.setContext(before: field.text)
        #expect(composer.state.autofill.isEmpty)
    }

    @Test func typingTheStartOffersTheRest() {
        var composer = Self.composer(Field(keyboard: .email))
        let lifted = Synth.taps(&composer, "ad")
        #expect(composer.state.openWord == "ad")
        #expect(composer.state.autofill.first?.text == "ada@example.com")
        var field = TypingReplay.Field()
        field.marked = "ad"
        let effects = composer.fill(autofill: 0, time: lifted + 0.1)
        field.apply(effects)
        #expect(field.text == "ada@example.com")
        // Nothing learned, and no space after it.
        #expect(!effects.contains { if case .learn = $0 { true } else { false } })
        #expect(!effects.contains(.insert(" ")))
        // What was typed waits on the bar, to take it back.
        guard case .fix(let words, 0) = composer.state.bar else { Issue.record("\(composer.state.bar)"); return }
        #expect(words == ["ada@example.com", "ad"])
    }

    @Test func aChatGetsTheDetailAfterTheQuestion() {
        var composer = Self.composer(.text)
        var field = TypingReplay.Field(text: "My email is ")
        composer.setContext(before: field.text)
        #expect(composer.state.autofill.map(\.text) == ["ada@example.com"])
        field.apply(composer.fill(autofill: 0, time: 0))
        #expect(field.text == "My email is ada@example.com")
    }

    @Test func nothingWhenSwitchedOffOrInAPassword() {
        var off = Self.composer(Field(asks: .name))
        off.settings.autofills = false
        #expect(off.state.autofill.isEmpty)
        let password = Self.composer(Field(content: .password))
        #expect(password.state.autofill.isEmpty)
        var settings = KeyboardSettings()
        #expect(settings.autofill)
        settings.autofill = false
        #expect(!settings.composerSettings().autofills)
    }
}
