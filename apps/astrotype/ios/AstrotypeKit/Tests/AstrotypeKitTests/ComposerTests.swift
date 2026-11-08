import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct ComposerTests {
    typealias Effect = Composer.Effect

    @Test func aSentenceStartIsReadFromTheEnd() {
        // The same answer as trimming the whole text, for every kind of ending.
        func trimmed(_ before: String) -> Bool {
            if let last = before.last, Accents.openers.contains(last) { return trimmed(String(before.dropLast())) }
            let text = before.trimmingCharacters(in: .whitespaces)
            guard let last = before.last else { return true }
            guard last.isWhitespace || last.isNewline else { return false }
            return text.isEmpty || text.hasSuffix(".") || text.hasSuffix("?") || text.hasSuffix("!") || last.isNewline
        }
        let paragraph = String(repeating: "We talked about the plan for a while and it went well. ", count: 40)
        let ends = ["", " ", "   ", "\t", "\n", "\n ", " \n", "\u{00A0}", "word", "word ", "word.", "word. ", "word.  \t",
                    "word? ", "word! ", "word, ", "word; ", "word.\n", "word.\n ", "word \n ", "...", "... ", "¿", "¡ ", "Hola. ¿",
                    "Dime, ¿", "😀 ", "e\u{301} ", ". ", "? ", "!", "!\n"]
        for start in ["", "Hi.", "Hi. ", "Hi\n", paragraph] {
            for end in ends {
                let before = start + end
                #expect(Composer.startsSentence(before) == trimmed(before), "\(before.suffix(20).debugDescription)")
            }
        }
    }

    @Test func tapsOpenAWordAndSpaceCommitsIt() {
        var composer = Synth.composer()
        let lifted = Synth.taps(&composer, "the")
        #expect(composer.state.openWord == "the")
        let effects = composer.press(.space, time: lifted + 0.1)
        #expect(effects.contains(.commit("the")))
        #expect(effects.contains(.insert(" ")))
        #expect(effects.contains(.haptic(.commit)))
        #expect(composer.state.openWord == nil)
        #expect(composer.pieces.isEmpty)
        if case .fix(let words, let chosen) = composer.state.bar {
            #expect(words[chosen] == "the")
        } else {
            Issue.record("expected the fix bar, got \(composer.state.bar)")
        }
    }

    @Test func freeModeTakesOneThumbAtATime() {
        var composer = Synth.composer()
        composer.settings.twoThumbs = false
        // The left thumb starts a word; the right thumb comes down while it is still on
        // the keys: not a piece, just the notice. Nothing in the field changes.
        let t = Synth.center("t")
        let h = Synth.center("h")
        _ = composer.touchDown(id: 1, at: t, time: 0)
        let second = composer.touchDown(id: 2, at: h, time: 0.05)
        #expect(second == [.notice(.twoThumbsIsPro)])
        #expect(composer.touchUp(id: 2, at: h, time: 0.1).isEmpty)
        _ = composer.touchUp(id: 1, at: t, time: 0.12)
        #expect(composer.pieces.count == 1)
        // With the first thumb up, the next touch types as usual, whichever thumb it is.
        _ = composer.touchDown(id: 2, at: h, time: 0.3)
        _ = composer.touchUp(id: 2, at: h, time: 0.38)
        Synth.tap(&composer, "e", id: 1, at: 0.5)
        #expect(composer.state.openWord == "the")

        // Pro turns the second thumb back on.
        var pro = Synth.composer()
        pro.settings.twoThumbs = true
        _ = pro.touchDown(id: 1, at: t, time: 0)
        #expect(pro.touchDown(id: 2, at: h, time: 0.05) != [.notice(.twoThumbsIsPro)])
    }

    @Test func anUnknownTappedWordIsLearnedWhenItSettles() {
        var composer = Synth.composer()
        let lifted = Synth.taps(&composer, "zorblat")
        #expect(composer.state.openWord == "zorblat")
        let effects = composer.press(.space, time: lifted + 0.1) + composer.keyboardWillHide()
        #expect(effects.contains(.learn("zorblat")))

        // The host adds it; the next time it goes in it counts one more use.
        composer.learned.learn("zorblat")
        let again = Synth.taps(&composer, "zorblat", at: lifted + 1)
        let effects2 = composer.press(.space, time: again + 0.1) + composer.keyboardWillHide()
        #expect(effects2.contains(.learn("zorblat")))

        // Dictionary words are never learned.
        let the = Synth.taps(&composer, "the", at: again + 2)
        let effects3 = composer.press(.space, time: the + 0.1)
        #expect(!effects3.contains(where: isLearn))
    }

    @Test func aSwipedWordIsNeverLearned() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there")
        let effects = composer.press(.space, time: 0.5)
        #expect(!effects.contains(where: isLearn))
    }

    private func isLearn(_ effect: Effect) -> Bool {
        if case .learn = effect { return true }
        return false
    }

    @Test func learnedWordsAreOfferedToSwipes() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "zorblat")
        #expect(composer.state.openWord != "zorblat")
        composer.reset()
        composer.learned.learn("zorblat")
        Synth.swipe(&composer, "zorblat", at: 1)
        #expect(composer.state.openWord == "zorblat")
    }

    @Test func forgettingAReadingDropsItFromTheFixBar() {
        var composer = Synth.composer()
        let lifted = Synth.taps(&composer, "the")
        _ = composer.press(.space, time: lifted + 0.1)
        guard case .fix(let words, let chosen) = composer.state.bar, words.count > 1 else {
            Issue.record("expected the fix bar with readings, got \(composer.state.bar)")
            return
        }
        let other = words.first { $0 != words[chosen] }!
        composer.learned.forget(other)
        _ = composer.learnedDidChange(time: lifted + 0.2)
        if case .fix(let kept, let keptChosen) = composer.state.bar {
            #expect(!kept.contains(other))
            #expect(kept[keptChosen] == words[chosen])
        } else {
            #expect(composer.state.bar == .idle)
        }
    }

    @Test func theOpenWordIsMarkedInTheField() {
        var composer = Synth.composer()
        let effects = Synth.swipe(&composer, "there")
        #expect(effects.last == .mark("there"))
    }

    @Test func autospaceCommitsAfterTheDelay() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there", at: 0)
        #expect(abs((composer.autospaceDue ?? 0) - 1.2) < 1e-9)
        #expect(composer.tick(time: 1.1).isEmpty)
        let effects = composer.tick(time: 1.25)
        #expect(effects.contains(.commit("there")))
        #expect(effects.contains(.insert(" ")))
        #expect(composer.tick(time: 2).isEmpty)
    }

    @Test func autospaceAlsoFollowsPeckedWords() {
        var composer = Synth.composer()
        let lifted = Synth.taps(&composer, "a")
        #expect(composer.autospaceDue != nil)
        let effects = composer.tick(time: lifted + 5)
        #expect(effects.contains(.insert(" ")))
    }

    /// One space between words: a space pressed after autospace (or a guess from the
    /// bar) wrote one is not a second (Gabriel, 2 Nov 2026).
    @Test func aSpaceAfterAutospaceIsNotASecondSpace() {
        var composer = Synth.composer()
        let lifted = Synth.taps(&composer, "a")
        let auto = composer.tick(time: lifted + 5)
        #expect(auto.contains(.insert(" ")))
        let pressed = composer.press(.space, time: lifted + 5.2)
        #expect(!pressed.contains(.insert(" ")))
        // A second press later is the person's own: it types.
        #expect(composer.press(.space, time: lifted + 6).contains(.insert(" ")))
    }

    /// Double tap on space: a period, after autospace or not (Gabriel, 2 Nov 2026).
    @Test func aDoubleTapOnSpaceTypesAPeriod() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there", at: 0)
        #expect(composer.press(.space, time: 0.5).contains(.insert(" ")))
        let second = composer.press(.space, time: 0.7)
        #expect(second.contains(.deleteBackward(1)))
        #expect(second.contains(.insert(". ")))
        // After autospace: the first tap adds nothing, the second makes the period.
        composer = Synth.composer()
        Synth.swipe(&composer, "there", at: 0)
        _ = composer.tick(time: 2)
        let first = composer.press(.space, time: 2.1)
        #expect(!first.contains(.insert(" ")) && !first.contains(.insert(". ")))
        let again = composer.press(.space, time: 2.3)
        #expect(again.contains(.deleteBackward(1)))
        #expect(again.contains(.insert(". ")))
    }

    @Test func slowSpacesAreNotADoubleTap() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there", at: 0)
        _ = composer.press(.space, time: 0.5)
        let later = composer.press(.space, time: 1.5)
        #expect(later.contains(.insert(" ")))
        #expect(!later.contains(.insert(". ")))
    }

    @Test func aSpaceAfterAChosenGuessIsNotASecondSpace() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there", at: 0)
        #expect(composer.choose(guess: 0, time: 0.4).contains(.insert(" ")))
        #expect(!composer.press(.space, time: 0.5).contains(.insert(" ")))
    }

    @Test func punctuationGoesBeforeTheAutospace() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there", at: 0)
        _ = composer.tick(time: 2)
        let effects = composer.press(character: ".", time: 2.1)
        #expect(effects.contains(.deleteBackward(1)))
        #expect(effects.contains(.insert(". ")))
        // And a space after it is still not a second one.
        #expect(!composer.press(.space, time: 2.2).contains(.insert(" ")))
    }

    @Test func aSpaceAfterOtherTypingStillTypes() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there", at: 0)
        _ = composer.tick(time: 2)
        // The cursor moved somewhere without a space before it.
        composer.setContext(before: "hello")
        #expect(composer.press(.space, time: 2.1).contains(.insert(" ")))
        // A word committed by its own space, then space again: the person's two spaces.
        Synth.swipe(&composer, "there", at: 3)
        #expect(composer.press(.space, time: 3.5).contains(.insert(" ")))
        #expect(composer.press(.space, time: 4.5).contains(.insert(" ")))
    }

    @Test func returnAfterAutospaceLeavesNoTrailingSpace() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there", at: 0)
        _ = composer.tick(time: 2)
        let effects = composer.press(.returnKey, time: 2.1)
        #expect(effects.contains(.deleteBackward(1)))
        #expect(effects.contains(.insert("\n")))
    }

    @Test func autospaceWaitsWhileAFingerIsDown() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there", at: 0)
        _ = composer.touchDown(id: 2, at: Synth.center("s"), time: 0.5)
        #expect(composer.autospaceDue == nil)
        #expect(composer.tick(time: 5).isEmpty)
        _ = composer.touchUp(id: 2, at: Synth.center("s"), time: 5.1)
        #expect(abs((composer.autospaceDue ?? 0) - 6.0) < 1e-9)
    }

    @Test func autospaceCanBeOff() {
        var composer = Synth.composer()
        composer.settings.autospaceDelay = nil
        Synth.swipe(&composer, "there", at: 0)
        #expect(composer.autospaceDue == nil)
        #expect(composer.tick(time: 10).isEmpty)
    }

    @Test func backspaceRemovesTheLastPieceThenReopensTheLastWord() {
        var composer = Synth.composer()
        composer.settings.strictness = 0
        var t = Synth.taps(&composer, "thex")
        #expect(composer.state.openWord == "thex")
        #expect(composer.press(.backspace, time: t) == [.haptic(.key), .mark("the")])
        #expect(composer.state.openWord == "the")

        t += 0.2
        _ = composer.press(.space, time: t)
        composer.setContext(before: "the ")
        let reopened = composer.press(.backspace, time: t + 0.3)
        #expect(reopened == [.haptic(.key), .deleteBackward(4), .mark("the")])
        #expect(composer.state.openWord == "the")
        #expect(composer.pieces.count == 3)

        // Backspacing through the whole word leaves nothing open, then deletes characters.
        for i in 0..<3 { _ = composer.press(.backspace, time: t + 0.4 + Double(i) * 0.1) }
        #expect(composer.state.openWord == nil)
        #expect(composer.state.bar == .idle)
        composer.setContext(before: "")
        #expect(composer.press(.backspace, time: t + 1) == [.haptic(.key), .deleteBackward(1)])
    }

    @Test func backspaceDoesNotReopenWhenTheFieldChanged() {
        var composer = Synth.composer()
        let t = Synth.taps(&composer, "the")
        _ = composer.press(.space, time: t)
        composer.setContext(before: "something else")
        #expect(composer.press(.backspace, time: t + 1) == [.haptic(.key), .deleteBackward(1)])
    }

    @Test func theFixBarReplacesTheLastWord() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there", at: 0)
        _ = composer.press(.space, time: 0.5)
        guard case .fix(let words, let chosen) = composer.state.bar, words.count > 1 else {
            Issue.record("expected fixes, got \(composer.state.bar)"); return
        }
        #expect(words[chosen] == "there")
        let other = chosen == 0 ? 1 : 0
        let effects = composer.choose(guess: other, time: 0.6)
        #expect(effects.first == .deleteBackward("there ".count))
        #expect(effects.contains(.insert(words[other] + " ")))
        #expect(composer.state.bar == .fix(words, chosen: other))
        // A new word clears the fix bar.
        _ = composer.touchDown(id: 3, at: Synth.center("a"), time: 1)
        #expect(composer.state.bar == .idle)
    }

    @Test func tappingAGuessWritesIt() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there", at: 0)
        guard case .guesses(let words, _) = composer.state.bar, words.count > 1 else {
            Issue.record("expected guesses, got \(composer.state.bar)"); return
        }
        let effects = composer.choose(guess: 1, time: 0.5)
        #expect(effects.contains(.commit(words[1])))
        #expect(effects.contains(.insert(" ")))
    }

    @Test func punctuationCommitsWithoutASpace() {
        var composer = Synth.composer()
        let t = Synth.taps(&composer, "the")
        let effects = composer.press(character: ",", time: t)
        #expect(effects.contains(.commit("the")))
        #expect(effects.contains(.insert(",")))
        // The comma left "the" alone, so it settles as the "!" goes in.
        let next = composer.press(character: "!", time: t + 1)
        #expect(Array(next.prefix(2)) == [.haptic(.key), .insert("!")])
        #expect(next.dropFirst(2).allSatisfy { if case .settled = $0 { true } else { false } })
    }

    @Test func returnCommitsWithANewline() {
        var composer = Synth.composer()
        let t = Synth.taps(&composer, "the")
        let effects = composer.press(.returnKey, time: t)
        #expect(effects.contains(.commit("the")))
        #expect(effects.contains(.insert("\n")))
    }

    @Test func shiftCapitalisesTheNextWordAndDoubleTapLocksCaps() {
        var composer = Synth.composer()
        _ = composer.press(.shift, time: 0)
        #expect(composer.state.isShifted)
        Synth.taps(&composer, "the", at: 0.5)
        #expect(composer.state.openWord == "The")
        #expect(!composer.state.isShifted)
        _ = composer.press(.space, time: 1.5)

        _ = composer.press(.shift, time: 2)
        _ = composer.press(.shift, time: 2.2)
        #expect(composer.state.shift == .locked)
        Synth.taps(&composer, "the", at: 3)
        #expect(composer.state.openWord == "THE")
        #expect(composer.state.isShifted)
        _ = composer.press(.shift, time: 5)
        #expect(composer.state.shift == .off)
    }

    @Test func sentencesStartWithACapital() {
        var composer = Synth.composer(autoCapitalize: true)
        #expect(composer.state.isShifted)
        Synth.taps(&composer, "the", at: 0)
        #expect(composer.state.openWord == "The")
        _ = composer.press(.space, time: 1)
        composer.setContext(before: "The ")
        #expect(!composer.state.isShifted)
        composer.setContext(before: "The end. ")
        #expect(composer.state.isShifted)
        composer.setContext(before: "The end.")
        #expect(!composer.state.isShifted)
        composer.setContext(before: "The end\n")
        #expect(composer.state.isShifted)
    }

    @Test func shiftTurnsOffASentenceStartsCapital() {
        // Like Apple's keyboard: at a sentence start one tap on shift gives lowercase.
        var composer = Synth.composer(autoCapitalize: true)
        #expect(composer.state.isShifted)
        _ = composer.press(.shift, time: 0)
        #expect(!composer.state.isShifted)
        #expect(composer.state.shift == .off)
        Synth.taps(&composer, "the", at: 1)
        #expect(composer.state.openWord == "the")
        _ = composer.press(.space, time: 2)
        composer.setContext(before: "the end. ")
        // Spent: the next sentence capitalises again.
        #expect(composer.state.isShifted)

        // A second tap brings the capital back as one-shot shift.
        _ = composer.press(.shift, time: 3)
        _ = composer.press(.shift, time: 4)
        #expect(composer.state.shift == .on)
        #expect(composer.state.isShifted)
        // And a third turns it off again.
        _ = composer.press(.shift, time: 5)
        #expect(!composer.state.isShifted)
    }

    @Test func aSwipeKeepsTheLowercaseShiftAskedFor() {
        var composer = Synth.composer(autoCapitalize: true)
        _ = composer.press(.shift, time: 0)
        _ = Synth.swipe(&composer, "the", at: 1)
        #expect(composer.state.openWord?.first?.isLowercase == true)
    }

    @Test func doubleTapAtASentenceStartStillLocksCaps() {
        var composer = Synth.composer(autoCapitalize: true)
        _ = composer.press(.shift, time: 0)
        _ = composer.press(.shift, time: 0.2)
        #expect(composer.state.shift == .locked)
        Synth.taps(&composer, "the", at: 1)
        #expect(composer.state.openWord == "THE")
    }

    @Test func aLetterPressIsATap() {
        var composer = Synth.composer()
        _ = composer.press(.letter("t"), time: 0)
        _ = composer.press(.letter("o"), time: 0.2)
        #expect(composer.state.openWord == "to")
        #expect(composer.pieces.allSatisfy { $0.isTap })
    }

    @Test func aCancelledTouchTypesNothing() {
        var composer = Synth.composer()
        _ = composer.touchDown(id: 1, at: Synth.center("t"), time: 0)
        _ = composer.touchMoved(id: 1, to: Synth.center("h"), time: 0.1)
        #expect(composer.touchCancelled(id: 1, time: 0.2).isEmpty)
        #expect(composer.state.openWord == nil)
        #expect(composer.pieces.isEmpty)
    }

    @Test func aTapThatDriftsALittleIsStillATap() {
        var composer = Synth.composer()
        let t = Synth.center("t")
        _ = composer.touchDown(id: 1, at: t, time: 0)
        _ = composer.touchMoved(id: 1, to: CGPoint(x: t.x + 10, y: t.y + 8), time: 0.05)
        _ = composer.touchUp(id: 1, at: CGPoint(x: t.x + 12, y: t.y + 8), time: 0.1)
        #expect(composer.pieces.count == 1)
        #expect(composer.pieces[0].isTap)
        #expect(composer.pieces[0].keys == ["t"])
    }

    @Test func resetDropsTheOpenWordSilently() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there")
        composer.reset()
        #expect(composer.state.openWord == nil)
        #expect(composer.state.bar == .idle)
        #expect(composer.autospaceDue == nil)
    }

    // MARK: Gestures (Phase 3)

    @Test func deleteWordDropsTheOpenWord() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there")
        let effects = composer.deleteWord(time: 0.5)
        #expect(effects == [.haptic(.key), .clearMark])
        #expect(composer.state.openWord == nil)
        #expect(composer.state.bar == .idle)
        #expect(composer.autospaceDue == nil)
    }

    @Test func deleteWordRemovesThePreviousWordAndItsSpace() {
        var composer = Synth.composer()
        composer.setContext(before: "hello world ")
        #expect(composer.deleteWord(time: 0) == [.haptic(.key), .deleteBackward(6)])
        composer.setContext(before: "hello")
        #expect(composer.deleteWord(time: 0) == [.haptic(.key), .deleteBackward(5)])
        composer.setContext(before: "")
        #expect(composer.deleteWord(time: 0) == [.haptic(.key), .deleteBackward(1)])
    }

    @Test func cursorWillMoveWritesTheOpenWordWithoutASpace() {
        var composer = Synth.composer()
        Synth.swipe(&composer, "there")
        let effects = composer.cursorWillMove()
        #expect(effects.contains(.commit("there")))
        #expect(!effects.contains(.insert(" ")))
        #expect(!effects.contains(.insert("")))
        #expect(composer.state.openWord == nil)
        #expect(composer.state.bar == .idle)
        #expect(composer.cursorWillMove().isEmpty)
    }
}
