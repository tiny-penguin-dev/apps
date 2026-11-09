import Foundation
import Testing
@testable import AstrotypeCore

/// Dictation (features/dictation): how the keyboard writes what the app hears, and the
/// small rules both sides share.
@Suite struct DictationTests {
    /// Applies `edit` to `field` the way the keyboard does: backspaces, then typing.
    static func apply(_ edit: DictationEdit, to field: inout String) {
        field.removeLast(edit.delete)
        field += edit.insert
    }

    @Test func editKeepsWhatTheyShare() {
        #expect(DictationEdit.between("Hello wor", "Hello world") == DictationEdit(delete: 0, insert: "ld"))
        #expect(DictationEdit.between("Hello word", "Hello world") == DictationEdit(delete: 1, insert: "ld"))
        #expect(DictationEdit.between("", "Hi") == DictationEdit(delete: 0, insert: "Hi"))
        #expect(DictationEdit.between("Hi", "") == DictationEdit(delete: 2, insert: ""))
        #expect(DictationEdit.between("same", "same").isEmpty)
    }

    @Test func wordsStreamIntoTheField() {
        var field = "Yes! "
        var text = DictationText()
        for transcript in ["Running", "Running ten", "Running tin minutes", "Running ten minutes late."] {
            Self.apply(text.update(transcript: transcript, before: field), to: &field)
        }
        #expect(field == "Yes! Running ten minutes late.")
        Self.apply(text.finish(transcript: "Running ten minutes late.", before: field), to: &field)
        #expect(field == "Yes! Running ten minutes late. ")
    }

    @Test func spaceAndCapitalAtTheJoin() {
        #expect(DictationText.joined("hello", after: "") == "Hello")
        #expect(DictationText.joined("hello", after: "Yes! ") == "Hello")
        #expect(DictationText.joined("hello", after: "Yes!") == " Hello")
        #expect(DictationText.joined("you", after: "how r ") == "you")
        #expect(DictationText.joined("you", after: "how r") == " you")
        #expect(DictationText.joined("next", after: "Line one\n") == "Next")
        #expect(DictationText.joined("", after: "x") == "")
    }

    /// Gabriel's example (9 Nov 2026): say "hello how", type "r", say "you".
    @Test func talkAndTypeTogether() {
        var field = ""
        var text = DictationText()
        Self.apply(text.update(transcript: "Hello how", before: field), to: &field)
        #expect(field == "Hello how")
        // A key: what was said stays, the person types " r ".
        text.freeze(transcript: "Hello how")
        field += " r "
        // The transcript keeps growing from the start of the listen.
        Self.apply(text.update(transcript: "Hello how", before: field), to: &field)
        #expect(field == "Hello how r ")
        Self.apply(text.update(transcript: "Hello how you", before: field), to: &field)
        #expect(field == "Hello how r you")
        // A late fix to the kept words changes nothing already in the field.
        Self.apply(text.update(transcript: "Hello, how you doing", before: field), to: &field)
        #expect(field == "Hello how r you doing")
    }

    @Test func movingTheCursorKeepsWhatsThere() {
        var text = DictationText()
        var field = "Hi "
        Self.apply(text.update(transcript: "there", before: field), to: &field)
        #expect(field == "Hi there")
        // The person moved the cursor to the start: nothing is deleted.
        #expect(text.update(transcript: "there friend", before: "").isEmpty)
        #expect(text.written.isEmpty)
    }

    @Test func discardTakesBackTheLivePart() {
        var text = DictationText()
        var field = "Note: "
        Self.apply(text.update(transcript: "buy milk", before: field), to: &field)
        Self.apply(text.discard(transcript: "buy milk"), to: &field)
        #expect(field == "Note: ")
    }

    @Test func backspaceAfterAFreezeIsThePersons() {
        var text = DictationText()
        var field = ""
        Self.apply(text.update(transcript: "Hello there", before: field), to: &field)
        text.freeze(transcript: "Hello there")
        field.removeLast() // backspace
        Self.apply(text.update(transcript: "Hello there", before: field), to: &field)
        #expect(field == "Hello ther")
        Self.apply(text.update(transcript: "Hello there friend", before: field), to: &field)
        #expect(field == "Hello ther friend")
    }

    @Test func pressAndWindow() {
        #expect(DictationPress.how(heldFor: 0.1) == .tap)
        #expect(DictationPress.how(heldFor: 0.5) == .hold)
        let start = Date(timeIntervalSince1970: 0)
        #expect(DictationWindow.endsAt(lastUsed: start, minutes: 1) == start.addingTimeInterval(60))
        #expect(DictationWindow.endsAt(lastUsed: start, minutes: 7) == start.addingTimeInterval(300))
    }

    @Test func oldStateIsOff() {
        let now = Date(timeIntervalSince1970: 1000)
        let state = DictationState(phase: .ready, alive: now.addingTimeInterval(-2))
        #expect(state.phase(at: now) == .ready)
        #expect(state.phase(at: now.addingTimeInterval(10)) == .off)
        let decoded = try? JSONDecoder().decode(DictationState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }

    @Test func micPressSteps() {
        #expect(DictationPress.down(in: .off) == .none)
        #expect(DictationPress.up(heldFor: 0.1, phaseAtDown: .off) == .openApp)
        #expect(DictationPress.down(in: .ready) == .listen)
        #expect(DictationPress.up(heldFor: 0.1, phaseAtDown: .ready) == .none)
        #expect(DictationPress.up(heldFor: 1, phaseAtDown: .ready) == .stop)
        #expect(DictationPress.down(in: .listening) == .none)
        #expect(DictationPress.up(heldFor: 0.1, phaseAtDown: .listening) == .stop)
    }

    @Test func sessionRunsAListenAndTurnsOff() {
        let start = Date(timeIntervalSince1970: 0)
        var session = DictationSession(minutes: 1)
        let early = session.listen(at: start)
        #expect(!early)
        session.micOn(at: start)
        #expect(session.state.phase == .ready)
        #expect(session.state.readyUntil == start.addingTimeInterval(60))
        let first = session.listen(at: start)
        let again = session.listen(at: start)
        #expect(first && !again)
        #expect(session.state.listen == 1)
        session.heard("Hello", level: 3, at: start)
        #expect(session.state.transcript == "Hello" && session.state.level == 1)
        // Listening never times out.
        #expect(!session.shouldTurnOff(at: start.addingTimeInterval(600)))
        let done = start.addingTimeInterval(30)
        session.finished("Hello there", at: done)
        #expect(session.state.phase == .ready && session.state.finished)
        #expect(session.state.readyUntil == done.addingTimeInterval(60))
        #expect(!session.shouldTurnOff(at: done.addingTimeInterval(59)))
        #expect(session.shouldTurnOff(at: done.addingTimeInterval(60)))
        // The next listen starts clean.
        session.listen(at: done)
        #expect(session.state.listen == 2 && session.state.transcript.isEmpty && !session.state.finished)
        session.off(problem: .failed, at: done)
        #expect(session.state.phase == .off && session.state.finished && session.state.readyUntil == nil)
    }

    /// A field that tells only the end of its text still gets the rest of the words.
    @Test func aFieldThatTellsLittle() {
        var text = DictationText()
        var field = "Ok."
        Self.apply(text.update(transcript: "this is a long one", before: field), to: &field)
        #expect(field == "Ok. This is a long one")
        // The field now says only "long one".
        let edit = text.update(transcript: "this is a long one indeed", before: "long one")
        Self.apply(edit, to: &field)
        #expect(field == "Ok. This is a long one indeed")
    }
}
