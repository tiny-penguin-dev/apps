import Foundation
import Testing
@testable import AstrotypeCore

/// features/look-back: when the next word, typed fast, shows the word before was a
/// wrong reading of its swipe or taps, the keyboard swaps it.
@Suite struct LookBackTests {
    // MARK: Choosing

    @Test func anotherReadingWinsOnlyByTheMargin() {
        let readings = [Candidate(word: "thai", score: -1.0), Candidate(word: "this", score: -1.2)]
        // "is" follows "this" far better: swap.
        #expect(LookBack.choose(readings: readings, current: 0, margin: 0.3) { $0 == "this" ? 0.6 : 0 } == 1)
        // Only a little better: keep what was written.
        #expect(LookBack.choose(readings: readings, current: 0, margin: 0.3) { $0 == "this" ? 0.4 : 0 } == nil)
        // The one written fits best already.
        #expect(LookBack.choose(readings: readings, current: 1, margin: 0.3) { $0 == "this" ? 0.6 : 0 } == nil)
    }

    @Test func nothingChangesWhenTheNextWordCantTell() {
        let readings = [Candidate(word: "thai", score: -1.0), Candidate(word: "this", score: -1.2)]
        // Nothing known about the word written: no comparison, no swap.
        #expect(LookBack.choose(readings: readings, current: 0, margin: 0.3) { $0 == "this" ? 0.6 : nil } == nil)
        // Nothing known about the other: it is never swapped to.
        #expect(LookBack.choose(readings: readings, current: 0, margin: 0.3) { $0 == "thai" ? 0 : nil } == nil)
        #expect(LookBack.choose(readings: [readings[0]], current: 0, margin: 0.3) { _ in 1 } == nil)
    }

    // MARK: Typing

    /// A field the composer types into: the text before the cursor, with the open word
    /// shown in it as the keyboard shows it.
    struct Field {
        var text = ""
        var mark = 0

        mutating func apply(_ effects: [Composer.Effect]) {
            for effect in effects {
                switch effect {
                case .insert(let s): text += s
                case .deleteBackward(let n): text = String(text.dropLast(n))
                case .mark(let s):
                    text = String(text.dropLast(mark)) + s
                    mark = s.count
                case .commit(let s):
                    text = String(text.dropLast(mark)) + s
                    mark = 0
                case .clearMark:
                    text = String(text.dropLast(mark))
                    mark = 0
                default: break
                }
            }
        }

        var words: [String] { text.lowercased().split(whereSeparator: { $0 == " " }).map(String.init) }
    }

    static let english = ContextMatcherTests.english

    /// The recording typed into a fresh composer, space after each word as recorded;
    /// `margin` nil types with looking back off. `pause` is added before each word after
    /// the first. Returns the words in the field and how many swaps were made.
    static func type(_ recording: PracticeRecording, margin: Double?, pause: TimeInterval = 0,
                     undo: Bool = false) -> (words: [String], swaps: Int) {
        let layout = Layout.qwerty(width: recording.layoutWidth, split: recording.split, height: recording.layoutHeight)
        var settings = Replay.settings
        settings.autospaceDelay = nil
        settings.fixesAsYouGo = margin != nil
        var composer = Composer(language: english, layout: layout, settings: settings)
        if let margin { composer.lookBackMargin = margin }
        var field = Field()
        var events = Replay.events(of: recording, layout: layout)
        events.sort { $0.time == $1.time ? $0.order < $1.order : $0.time < $1.time }
        var shift = 0.0
        var spaced = false
        func apply(_ effects: [Composer.Effect]) {
            field.apply(effects)
            composer.setContext(before: field.text)
        }
        composer.setContext(before: "")
        for event in events {
            switch event.kind {
            case .down(let point):
                if spaced { shift += pause; spaced = false }
                apply(composer.touchDown(id: event.id, at: point, time: event.time + shift))
            case .move(let point): apply(composer.touchMoved(id: event.id, to: point, time: event.time + shift))
            case .up(let point): apply(composer.touchUp(id: event.id, at: point, time: event.time + shift))
            case .commit:
                let swaps = composer.lookBackCount
                apply(composer.press(.space, time: event.time + shift))
                if undo, composer.lookBackCount > swaps {
                    #expect(composer.undoesLookBack)
                    apply(composer.undoEarlierFix())
                    #expect(!composer.canUndoEarlierFix)
                }
                spaced = true
            }
        }
        apply(composer.reset())
        return (field.words, composer.lookBackCount)
    }

    static let sentences: [[String]] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/look-back-sentences.txt")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map { $0.split(separator: " ").map(String.init) }.filter { !$0.isEmpty }
    }()

    struct Count: CustomStringConvertible {
        var words = 0
        var wrong = 0
        var fixed = 0
        var broken = 0
        var swaps = 0
        var examples: [String] = []
        var description: String {
            String(format: "%d words, %d wrong without (%.1f%%): fixed %d, broke %d, swaps %d → wrong %.1f%%",
                   words, wrong, 100 * Double(wrong) / Double(max(1, words)), fixed, broken, swaps,
                   100 * Double(wrong - fixed + broken) / Double(max(1, words)))
        }
    }

    /// Every sentence typed with made-up touches, with looking back off and at each
    /// margin: words it fixed and words it broke.
    static func measure(_ thumbs: SyntheticTyping.Thumbs, noise: Double, margins: [Double], pause: TimeInterval = 0,
                        undo: Bool = false, sentences: [[String]] = sentences, seed: UInt64 = 11) -> [Double: Count] {
        var out: [Double: Count] = [:]
        var typing = SyntheticTyping(layout: Synth.layout, noise: noise, thumbs: thumbs, seed: seed)
        for words in sentences {
            let recording = typing.record(words)
            let off = type(recording, margin: nil).words
            guard off.count == words.count else { continue }
            for margin in margins {
                let on = type(recording, margin: margin, pause: pause, undo: undo)
                var count = out[margin] ?? Count()
                guard on.words.count == words.count else { continue }
                count.words += words.count
                count.swaps += on.swaps
                for i in words.indices {
                    let was = off[i] == words[i], now = on.words[i] == words[i]
                    if !was { count.wrong += 1 }
                    if !was && now { count.fixed += 1; count.examples.append("+ \(off[i])→\(on.words[i]) in “\(words.joined(separator: " "))”") }
                    if was && !now { count.broken += 1; count.examples.append("− \(off[i])→\(on.words[i]) in “\(words.joined(separator: " "))”") }
                }
                out[margin] = count
            }
        }
        return out
    }

    /// Fast two-thumb typing with sloppy touches: the next word fixes some words, and
    /// breaks none (measured 12 Nov 2026 over all the sentences: 45 fixed, none broken).
    @Test func theNextWordFixesWordsTypedFast() throws {
        let count = try #require(Self.measure(.two(wobble: 0.04), noise: 0.35, margins: [LookBack.margin],
                                              sentences: Array(Self.sentences.prefix(30)))[LookBack.margin])
        print("look back, 30 sentences: \(count)")
        #expect(count.fixed >= 3, "\(count.examples)")
        #expect(count.broken == 0, "\(count.examples)")
    }

    /// A pause before the next word: the person had time to read the word and kept it.
    @Test func aPauseKeepsTheWord() throws {
        let count = try #require(Self.measure(.two(wobble: 0.04), noise: 0.35, margins: [LookBack.margin], pause: 1.2,
                                              sentences: Array(Self.sentences.prefix(30)))[LookBack.margin])
        #expect(count.swaps == 0, "\(count.examples)")
        #expect(count.fixed == 0)
    }

    /// Undo right after a swap puts the word back as it was typed.
    @Test func undoPutsTheWordBack() throws {
        let count = try #require(Self.measure(.two(wobble: 0.04), noise: 0.35, margins: [LookBack.margin], undo: true,
                                              sentences: Array(Self.sentences.prefix(30)))[LookBack.margin])
        #expect(count.swaps >= 3)
        #expect(count.fixed == 0 && count.broken == 0, "\(count.examples)")
    }

    /// A word typed fast waits to settle (and be learned) until the next word is in and
    /// has been checked against it; after a pause it settles as the next word starts.
    @Test func aWordTypedFastSettlesOnceTheNextIsIn() {
        func settled(_ effects: [Composer.Effect]) -> [String] {
            effects.compactMap { if case .settled(let word) = $0 { word.word } else { nil } }
        }
        var composer = ContextMatcherTests.composer()
        composer.setContext(before: "I ")
        var t = Synth.taps(&composer, "hope")
        _ = composer.press(.space, time: t)
        composer.setContext(before: "I hope ")
        // "so" starts right away: "hope" waits.
        #expect(settled(Synth.tap(&composer, "s", at: t + 0.3)).isEmpty)
        t = Synth.taps(&composer, "o", at: t + 0.45)
        _ = composer.press(.space, time: t)
        composer.setContext(before: "I hope so ")
        // After a pause, the next word settles both.
        #expect(settled(Synth.tap(&composer, "w", at: t + 2)) == ["hope", "so"])
    }

    /// The numbers behind `LookBack.margin` (features/look-back, phase 1). Slow: run
    /// with LOOKBACK_MEASURE=1 and `-c release`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LOOKBACK_MEASURE"] != nil))
    func measureMargins() {
        let margins = [0.1, 0.2, 0.3, 0.4, 0.5]
        for (name, thumbs, noise) in [("one swipe", SyntheticTyping.Thumbs.one, 0.2), ("one swipe", .one, 0.35),
                                      ("two thumbs", .two(wobble: 0.04), 0.2), ("two thumbs", .two(wobble: 0.04), 0.35)] {
            let counts = Self.measure(thumbs, noise: noise, margins: margins)
            for margin in margins {
                print(String(format: "%@ noise %.2f margin %.2f: ", name, noise, margin) + "\(counts[margin] ?? Count())")
            }
            if let at = counts[LookBack.margin] { print(at.examples.prefix(40).joined(separator: "\n")) }
        }
    }
}
