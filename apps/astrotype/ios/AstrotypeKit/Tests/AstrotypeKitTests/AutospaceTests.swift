import Foundation
import Testing
@testable import AstrotypeCore

/// Autospace and tap typing together (Gabriel, 14 Nov 2026): pecked words get no
/// autospace until a swiped word wakes it, it stays awake until the keyboard closes or
/// the person spaces pecked words by hand again, and the wait can be 0 (a space as the
/// swipe lifts).
@Suite struct AutospaceTests {
    static func composer(delay: TimeInterval = 0.9) -> Composer {
        var settings = Composer.Settings()
        settings.autoCapitalize = false
        settings.autospaceDelay = delay
        settings.pecksWaitForSwipe = true
        return Composer(dictionary: Synth.lexicon, layout: Synth.layout, settings: settings)
    }

    /// Swipes `letters` at `time` and lets autospace write it; returns when it did.
    @discardableResult
    static func swipeAndAutospace(_ composer: inout Composer, _ letters: String, at time: TimeInterval) -> TimeInterval {
        Synth.swipe(&composer, letters, at: time)
        let due = composer.autospaceDue ?? .infinity
        #expect(composer.tick(time: due).contains(.insert(" ")))
        return due
    }

    @Test func peckedWordsGetNoAutospaceBeforeASwipe() {
        var composer = Self.composer()
        let lifted = Synth.taps(&composer, "hello")
        #expect(composer.autospaceDue == nil)
        #expect(composer.tick(time: lifted + 5).isEmpty)
        #expect(!composer.autospacesPecks)
    }

    @Test func aSwipedWordWakesItForPeckedWords() {
        var composer = Self.composer()
        Self.swipeAndAutospace(&composer, "there", at: 0)
        #expect(composer.autospacesPecks)
        let lifted = Synth.taps(&composer, "a", at: 3)
        #expect(abs((composer.autospaceDue ?? 0) - (lifted + 0.9)) < 1e-9)
        #expect(composer.tick(time: lifted + 1).contains(.insert(" ")))
    }

    @Test func aZeroWaitSpacesASwipeAsItLifts() {
        var composer = Self.composer(delay: 0)
        Synth.swipe(&composer, "there", at: 0)
        #expect(abs((composer.autospaceDue ?? -1) - 0.3) < 1e-9)
        let effects = composer.tick(time: 0.3)
        #expect(effects.contains(.commit("there")))
        #expect(effects.contains(.insert(" ")))
    }

    @Test func peckedWordsWaitLongerThanAZeroWait() {
        var composer = Self.composer(delay: 0)
        Self.swipeAndAutospace(&composer, "there", at: 0)
        let lifted = Synth.taps(&composer, "hello", at: 3)
        #expect(abs((composer.autospaceDue ?? 0) - (lifted + Composer.peckWait)) < 1e-9)
        #expect(composer.tick(time: lifted + 0.2).isEmpty)
    }

    @Test func twoPeckedWordsSpacedByHandPutItBackToSleep() {
        var composer = Self.composer()
        Self.swipeAndAutospace(&composer, "there", at: 0)
        var lifted = Synth.taps(&composer, "hi", at: 3)
        _ = composer.press(.space, time: lifted + 0.1)
        #expect(composer.autospacesPecks)
        lifted = Synth.taps(&composer, "you", at: 6)
        _ = composer.press(.space, time: lifted + 0.1)
        #expect(!composer.autospacesPecks)
        Synth.taps(&composer, "ok", at: 9)
        #expect(composer.autospaceDue == nil)
        // A swipe wakes it again, and swiped words autospace either way.
        Synth.swipe(&composer, "there", at: 12)
        #expect(composer.autospacesPecks)
    }

    @Test func aSwipeStartsTheHandSpaceCountOver() {
        var composer = Self.composer()
        Self.swipeAndAutospace(&composer, "there", at: 0)
        var lifted = Synth.taps(&composer, "hi", at: 3)
        _ = composer.press(.space, time: lifted + 0.1)
        Self.swipeAndAutospace(&composer, "there", at: 6)
        lifted = Synth.taps(&composer, "ok", at: 9)
        _ = composer.press(.space, time: lifted + 0.1)
        #expect(composer.autospacesPecks)
    }

    @Test func theKeyboardClosingPutsItBackToSleep() {
        var composer = Self.composer()
        Self.swipeAndAutospace(&composer, "there", at: 0)
        _ = composer.keyboardWillHide()
        #expect(!composer.autospacesPecks)
        Synth.taps(&composer, "ok", at: 3)
        #expect(composer.autospaceDue == nil)
    }

    @Test func theOlderRuleStillAutospacesEveryWord() {
        var composer = Synth.composer()
        Synth.taps(&composer, "hello")
        #expect(composer.autospaceDue != nil)
    }
}
