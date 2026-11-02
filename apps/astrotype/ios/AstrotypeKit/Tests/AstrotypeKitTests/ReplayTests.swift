import Foundation
import Testing
@testable import AstrotypeCore

/// features/smart-matching Phase A: a recording replays to the same guesses the
/// keyboard made, so the harness measures the engine and not the playback.
@Suite struct ReplayTests {
    static let english = ContextMatcherTests.english
    static let device = PracticeRecording.Device(model: "test", system: "test", app: "test", writer: "w")

    /// Types `words` into a composer and a recorder at once, the way the keyboard
    /// session does, one swipe per word and space 0.3 s after each; returns the
    /// recording and what the live composer wrote.
    static func record(_ words: [String], expected: String? = nil, strokes: ((String, TimeInterval) -> [Synth.Stroke])? = nil)
        -> (recording: PracticeRecording, typed: [String], guesses: [[String]]) {
        var composer = Composer(language: english, layout: Synth.layout, settings: Replay.settings)
        var recorder = TouchRecorder(kind: "test", layoutWidth: Synth.layout.width, layoutHeight: Synth.layout.height, split: false)
        var typed: [String] = []
        var guesses: [[String]] = []
        var text = ""
        var time: TimeInterval = 10
        composer.setContext(before: text)
        for word in words {
            let script = strokes?(word, time) ?? [Synth.Stroke.swipe(word, id: 1, from: time, to: time + 0.3)]
            play(script, into: &composer, recorder: &recorder)
            time = (script.map(\.end).max() ?? time) + 0.3
            if case .guesses(let offered, _) = composer.state.bar { guesses.append(offered) } else { guesses.append([]) }
            let effects = composer.press(.space, time: time)
            let written = effects.compactMap { if case .commit(let w) = $0 { return w } else { return nil } }.first ?? ""
            typed.append(written)
            recorder.committed(written, time: time)
            text += written + " "
            composer.setContext(before: text)
            time += 0.4
        }
        let recording = recorder.recording(expected: expected ?? words.joined(separator: " "), device: device, now: Date())
        return (recording, typed, guesses)
    }

    static func play(_ strokes: [Synth.Stroke], into composer: inout Composer, recorder: inout TouchRecorder) {
        enum Kind: Int { case down, move, up }
        var events: [(time: TimeInterval, kind: Kind, id: Int, point: CGPoint)] = []
        for stroke in strokes {
            let points = stroke.letters.count == 1 ? [Synth.center(stroke.letters.first!)] : Synth.path(stroke.letters)
            events.append((stroke.start, .down, stroke.id, points[0]))
            for (i, point) in points.enumerated().dropFirst().dropLast() {
                events.append((stroke.start + (stroke.end - stroke.start) * Double(i) / Double(points.count - 1), .move, stroke.id, point))
            }
            events.append((stroke.end, .up, stroke.id, points[points.count - 1]))
        }
        events.sort { $0.time == $1.time ? $0.kind.rawValue < $1.kind.rawValue : $0.time < $1.time }
        for event in events {
            switch event.kind {
            case .down:
                recorder.touch(.began, id: event.id, x: event.point.x, y: event.point.y, time: event.time)
                _ = composer.touchDown(id: event.id, at: event.point, time: event.time)
            case .move:
                recorder.touch(.moved, id: event.id, x: event.point.x, y: event.point.y, time: event.time)
                _ = composer.touchMoved(id: event.id, to: event.point, time: event.time)
            case .up:
                recorder.touch(.ended, id: event.id, x: event.point.x, y: event.point.y, time: event.time)
                _ = composer.touchUp(id: event.id, at: event.point, time: event.time)
            }
        }
    }

    @Test func replaysTheFixtureWordsToTheLiveResult() throws {
        let words = Synth.fixtures.map(\.word)
        let live = Self.record(Synth.fixtures.map(\.swipe), expected: words.joined(separator: " "))
        let outcome = try Replay.run(live.recording, language: Self.english)
        #expect(outcome.words.count == words.count)
        #expect(outcome.words.map(\.guesses.first) == live.typed.map { $0.isEmpty ? nil : $0 })
        let liveHits = zip(live.typed, words).filter { $0 == $1 }.count
        #expect(outcome.firstGuesses == liveHits)
        #expect(outcome.firstGuessRate >= 0.9, "\(outcome.misses)")
        #expect(outcome.topThrees >= outcome.firstGuesses)
    }

    @Test func replaysTwoThumbWordsAndSentenceContext() throws {
        // "i" is a tap, "put" a swipe on the right, "it" and "on" and "the" swipes;
        // the second "the" is a left-right tap and swipe at once (Phase 3's merge).
        let words = ["i", "put", "it", "on", "the", "table"]
        let live = Self.record(words) { word, t in
            switch word {
            case "i": return [.tap("i", id: 2, at: t)]
            case "the": return [.tap("t", id: 1, at: t), .swipe("he", id: 2, from: t + 0.05, to: t + 0.25)]
            default: return [.swipe(word, id: 1, from: t, to: t + 0.3)]
            }
        }
        #expect(live.typed == words, "the live keyboard writes the sentence")
        let outcome = try Replay.run(live.recording, language: Self.english)
        #expect(outcome.words.map(\.expected) == words)
        #expect(outcome.firstGuesses == words.count, "\(outcome.misses)")
        #expect(outcome.misses.isEmpty)
        #expect(outcome.firstGuessRate == 1)
    }

    @Test func aWrongWordKeepsTheExpectedOneUntilItIsTyped() throws {
        // The person swiped "pot" at the start of a sentence (the keyboard wrote
        // "put"), then swiped it again after a correction. Both score against "pot".
        let live = Self.record(["pot", "pot"], expected: "pot")
        #expect(live.typed.first == "put")
        let outcome = try Replay.run(live.recording, language: Self.english)
        #expect(outcome.words.map(\.expected) == ["pot", "pot"])
        #expect(outcome.words.map(\.isFirstGuess) == [false, live.typed[1] == "pot"])
        #expect(outcome.words[0].isInTopThree)
    }

    @Test func skipsRecordingsWithoutCommitsOrTouches() {
        var recorder = TouchRecorder(kind: "speedtest", layoutWidth: 390, layoutHeight: 216, split: false)
        recorder.touch(.began, id: 1, x: 10, y: 10, time: 0)
        recorder.touch(.ended, id: 1, x: 10, y: 10, time: 0.1)
        let noCommits = recorder.recording(expected: "a", device: Self.device, now: Date())
        #expect(throws: Replay.Skip.noCommits) { try Replay.run(noCommits, language: Self.english) }
        var empty = TouchRecorder(kind: "speedtest", layoutWidth: 390, layoutHeight: 216, split: false)
        empty.committed("a", time: 1)
        let noTouches = empty.recording(expected: "a", device: Self.device, now: Date())
        #expect(throws: Replay.Skip.noTouches) { try Replay.run(noTouches, language: Self.english) }
    }

    @Test func reportAddsUpAndListsMisses() {
        let a = Replay.Outcome(id: UUID(), kind: "speedtest", words: [
            Replay.Word(expected: "store", guesses: ["stare", "store"]),
            Replay.Word(expected: "the", guesses: ["the"]),
            Replay.Word(expected: "store", guesses: ["stare"]),
        ])
        let b = Replay.Outcome(id: UUID(), kind: "drill.pairs", words: [
            Replay.Word(expected: "put", guesses: ["pot", "pit", "put", "pat"]),
            Replay.Word(expected: "it", guesses: []),
        ])
        let report = Replay.Report([a, b], skipped: 2)
        #expect(report.wordCount == 5)
        #expect(report.firstGuesses == 1)
        #expect(report.topThrees == 3)
        #expect(report.missLines == ["store → stare ×2", "it → ∅", "put → pot"])
        #expect(report.summary == "2 sessions · 5 words · first guess 20.0% · top three 60.0% · 4 misses · 2 skipped (no commit times)")
    }
}
