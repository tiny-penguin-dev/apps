import Foundation
import Testing
@testable import AstrotypeCore

/// features/fix-earlier-word: the cursor put in a word written earlier (or the word
/// selected) shows it on the bar with its other readings; one tapped swaps it in place
/// and the cursor goes back to where typing was.
@Suite struct EarlierWordTests {
    /// A field with a cursor: the text before it and after it.
    struct Field {
        var before = ""
        var after = ""

        mutating func apply(_ effects: [Composer.Effect]) {
            for effect in effects {
                switch effect {
                case .insert(let s), .commit(let s): before += s
                case .deleteBackward(let n): before = String(before.dropLast(n))
                case .moveCursor(let n) where n > 0:
                    let moved = after.prefix(n)
                    before += moved
                    after = String(after.dropFirst(moved.count))
                case .moveCursor(let n) where n < 0:
                    let moved = before.suffix(-n)
                    after = moved + after
                    before = String(before.dropLast(moved.count))
                default: break
                }
            }
        }

        /// The person taps the cursor to `offset` characters into the text.
        mutating func put(at offset: Int) {
            let all = before + after
            before = String(all.prefix(offset))
            after = String(all.dropFirst(offset))
        }

        var text: String { before + after }
    }

    // MARK: Finding the word

    @Test func findsTheWordAroundTheCursor() throws {
        let spot = try #require(EarlierSpot.find(before: "at the ca", after: "ge tomorrow ", selected: nil, typedAfter: ""))
        #expect(spot.word == "cage")
        #expect(spot.offset == 2)
        #expect(!spot.selected)
        // " tomorrow " lies between the word and where typing was.
        #expect(spot.rest == 10)
    }

    @Test func rightAfterAWordCounts() throws {
        let spot = try #require(EarlierSpot.find(before: "at the cage", after: " tomorrow", selected: nil, typedAfter: ""))
        #expect(spot.word == "cage")
        #expect(spot.offset == 4)
        #expect(spot.rest == 9)
    }

    @Test func notInAWord() {
        // Right after a space, before a word: not in it.
        #expect(EarlierSpot.find(before: "at the ", after: "cage", selected: nil, typedAfter: "") == nil)
        #expect(EarlierSpot.find(before: "", after: "", selected: nil, typedAfter: "") == nil)
        #expect(EarlierSpot.find(before: "call 555", after: "", selected: nil, typedAfter: "") == nil)
        // Several words selected: not one word.
        #expect(EarlierSpot.find(before: "at ", after: " now", selected: "the cage", typedAfter: "") == nil)
    }

    @Test func aSelectedWord() throws {
        let spot = try #require(EarlierSpot.find(before: "at the ", after: " tomorrow", selected: "cage", typedAfter: ""))
        #expect(spot.word == "cage")
        #expect(spot.selected)
        #expect(spot.offset == 0)
        #expect(spot.rest == 9)
    }

    @Test func goesBackOnlyWhereTypingWas() throws {
        // Typing was before " later": the cursor goes back to there, not to the end.
        let spot = try #require(EarlierSpot.find(before: "the ca", after: "ge now later", selected: nil, typedAfter: " later"))
        #expect(spot.rest == 4)
        // The text after changed: stay after the word.
        let lost = try #require(EarlierSpot.find(before: "the ca", after: "ge now", selected: nil, typedAfter: "xyz"))
        #expect(lost.rest == 0)
    }

    @Test func apostrophesStayInside() throws {
        #expect(EarlierSpot.find(before: "it's don", after: "'t", selected: nil, typedAfter: "")?.word == "don't")
        // A closing quote is not part of the word.
        #expect(EarlierSpot.find(before: "say 'cage'", after: "", selected: nil, typedAfter: "") == nil)
    }

    // MARK: The bar

    @Test func aRecentWordShowsItsSwipeReadings() throws {
        var composer = Synth.composer()
        var field = Field()
        field.apply(Synth.swipe(&composer, "there"))
        composer.setContext(before: field.before)
        field.apply(composer.press(.space, time: 1))
        composer.setContext(before: field.before)
        guard case .fix(let readings, let chosen) = composer.state.bar, readings.count > 1 else {
            Issue.record("the swipe has one reading only")
            return
        }
        // Another word, so the first settles.
        field.apply(Synth.swipe(&composer, "now", at: 2))
        field.apply(composer.press(.space, time: 3))
        composer.setContext(before: field.before)

        let written = readings[chosen]
        field.put(at: 2)
        composer.setContext(before: field.before)
        let spot = try #require(EarlierSpot.find(before: field.before, after: field.after, selected: nil, typedAfter: ""))
        _ = composer.cursorLanded(at: spot)
        guard case .earlier(let words, let pill) = composer.state.bar else {
            Issue.record("no earlier bar: \(composer.state.bar)")
            return
        }
        #expect(words[pill] == written)
        #expect(Set(words) == Set(readings))
        #expect(composer.state.canCorrect)

        // Tap another reading: it replaces the word, and the cursor goes back to the end.
        let other = try #require(words.indices.first { $0 != pill })
        let out = composer.choose(guess: other, time: 4)
        field.apply(out)
        #expect(field.text == words[other] + " now ")
        #expect(field.after.isEmpty)
        let settled = try #require(out.compactMap { if case .settled(let w) = $0 { w } else { nil } }.first)
        #expect(settled.word == words[other].lowercased())
        #expect(settled.fixedFrom == written.lowercased())
        #expect(composer.state.bar != .earlier(words, chosen: pill))

        // Undo puts it back, the cursor still at the end.
        field.apply(composer.undoEarlierFix())
        #expect(field.text == written + " now ")
        #expect(field.after.isEmpty)
        #expect(composer.undoEarlierFix().isEmpty)
    }

    @Test func anOlderWordShowsNearWords() throws {
        var composer = Synth.composer()
        var field = Field(before: "lets meet at the cage tomorrow ", after: "")
        composer.setContext(before: field.before)
        field.put(at: 19)
        composer.setContext(before: field.before)
        let spot = try #require(EarlierSpot.find(before: field.before, after: field.after, selected: nil, typedAfter: ""))
        #expect(spot.word == "cage")
        _ = composer.cursorLanded(at: spot)
        guard case .earlier(let words, let pill) = composer.state.bar else {
            Issue.record("no earlier bar: \(composer.state.bar)")
            return
        }
        #expect(words[pill] == "cage")
        #expect(words.count > 1)
        let other = try #require(words.indices.first { $0 != pill })
        field.apply(composer.choose(guess: other, time: 1))
        #expect(field.text == "lets meet at the \(words[other]) tomorrow ")
        #expect(field.after.isEmpty)
    }

    @Test func casingFollowsTheWord() throws {
        var composer = Synth.composer()
        let field = Field(before: "Cage", after: " is shut")
        composer.setContext(before: field.before)
        let spot = try #require(EarlierSpot.find(before: field.before, after: field.after, selected: nil, typedAfter: ""))
        _ = composer.cursorLanded(at: spot)
        guard case .earlier(let words, _) = composer.state.bar else {
            Issue.record("no earlier bar")
            return
        }
        #expect(words.allSatisfy { $0.first?.isUppercase == true })
    }

    @Test func aSelectedWordIsTypedOver() throws {
        var composer = Synth.composer()
        composer.setContext(before: "at the ")
        let spot = EarlierSpot(word: "cage", offset: 0, selected: true, rest: 9)
        _ = composer.cursorLanded(at: spot)
        guard case .earlier(let words, let pill) = composer.state.bar, let other = words.indices.first(where: { $0 != pill }) else {
            Issue.record("no earlier bar")
            return
        }
        let out = composer.choose(guess: other, time: 1)
        #expect(out.first == .insert(words[other]))
        #expect(out.contains(.moveCursor(9)))
        #expect(!out.contains { if case .deleteBackward = $0 { true } else { false } })
    }

    @Test func notItTypesTheWordMeant() throws {
        var composer = Synth.composer()
        var field = Field(before: "at the ca", after: "ge now ")
        composer.setContext(before: field.before)
        let spot = try #require(EarlierSpot.find(before: field.before, after: field.after, selected: nil, typedAfter: ""))
        _ = composer.cursorLanded(at: spot)
        composer.beginCorrection()
        #expect(composer.state.bar == .correcting(""))
        _ = MissedWordTests.taps(&composer, "cafe", at: 1)
        field.apply(composer.saveCorrection(time: 2))
        #expect(field.text == "at the cafe now ")
        #expect(field.after.isEmpty)
    }

    @Test func typingLeavesIt() throws {
        var composer = Synth.composer()
        composer.setContext(before: "at the ca")
        _ = composer.cursorLanded(at: EarlierSpot(word: "cage", offset: 2))
        guard case .earlier = composer.state.bar else {
            Issue.record("no earlier bar")
            return
        }
        // A key types at the cursor as always, and the bar lets go of the word.
        let out = composer.press(character: "x", time: 1)
        #expect(out.contains(.insert("x")))
        if case .earlier = composer.state.bar { Issue.record("still showing the earlier word") }
        // Moving off the word closes it too.
        _ = composer.cursorLanded(at: EarlierSpot(word: "cage", offset: 2))
        _ = composer.cursorLanded(at: nil)
        if case .earlier = composer.state.bar { Issue.record("still showing the earlier word") }
        #expect(composer.undoEarlierFix().isEmpty)
    }

    @Test func notWhileAWordIsOpen() {
        var composer = Synth.composer()
        _ = Synth.swipe(&composer, "there")
        #expect(composer.cursorLanded(at: EarlierSpot(word: "cage", offset: 2)).isEmpty)
        if case .earlier = composer.state.bar { Issue.record("an open word was dropped for an earlier one") }
    }

    @Test func onlyACursorMoveCounts() {
        // Another app's dictation adds text before the cursor: not a move.
        #expect(!EarlierSpot.cursorMoved(lastAfter: "", after: "", selected: nil))
        #expect(!EarlierSpot.cursorMoved(lastAfter: " later", after: " later", selected: nil))
        // A tap into an earlier word changes what's after the cursor.
        #expect(EarlierSpot.cursorMoved(lastAfter: "", after: "ge tomorrow ", selected: nil))
        // A selection always counts, even when what's after it is the same.
        #expect(EarlierSpot.cursorMoved(lastAfter: "", after: "", selected: "more"))
        // Before the keyboard has looked once, it can't tell.
        #expect(!EarlierSpot.cursorMoved(lastAfter: nil, after: "ge", selected: nil))
    }
}
