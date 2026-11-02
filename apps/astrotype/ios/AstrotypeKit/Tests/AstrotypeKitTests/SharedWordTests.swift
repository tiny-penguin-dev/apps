import Foundation
import Testing
@testable import AstrotypeCore

/// features/smart-matching Phase C: what is shared is one word at a time, exactly what
/// "What gets shared" shows, and it replays to what the keyboard did.
@Suite struct SharedWordTests {
    static let english = ContextMatcherTests.english

    @Test func aSessionGoesAsItsWords() {
        let session = ReplayTests.record(["thank", "you", "so", "much"])
        let words = SharedWord.words(of: session.recording)
        #expect(words.count == 4)
        #expect(Set(words.map(\.word)) == ["thank", "you", "so", "much"])
        for word in words {
            #expect(word.kind == "word.test")
            #expect(!word.touches.isEmpty)
            // Times start at the word's own first touch: nothing ties it to the others.
            #expect(word.touches.compactMap { $0.points.first?[2] }.min() == 0)
            #expect(word.day.count == 10)
            #expect(word.writer.isEmpty)
        }
        // The word before is the one we asked for, never the person's text.
        #expect(words.first { $0.word == "thank" }?.previous == NgramModel.sentenceStart)
        #expect(words.first { $0.word == "much" }?.previous == "so")
    }

    @Test func aMissKeepsWhatWentIn() {
        // "pot" asked for, the swipe gives "put" with no context: a labelled miss.
        let session = ReplayTests.record(["pot"], expected: "pot")
        let words = SharedWord.words(of: session.recording)
        #expect(words.count == 1)
        #expect(words.first?.word == "pot")
        #expect(words.first?.typed == session.typed.first.map { SpeedTest.normalize($0) })
    }

    @Test func eachWordReplaysToWhatTheKeyboardDid() throws {
        let session = ReplayTests.record(["going", "to", "the", "store"])
        for word in SharedWord.words(of: session.recording) {
            let outcome = try Replay.run(word, language: Self.english)
            #expect(outcome.words.count == 1)
            let index = ["going", "to", "the", "store"].firstIndex(of: word.word)!
            #expect(outcome.words.first?.guesses.first == session.guesses[index].first.map { SpeedTest.normalize($0) })
        }
    }

    @Test func aFixInAnotherAppIsACorrection() throws {
        var composer = ContextMatcherTests.composer()
        composer.setContext(before: "Dinner was in the ")
        Synth.swipe(&composer, "pot")
        _ = composer.press(.space, time: 1)
        guard case .fix(let words, let chosen) = composer.state.bar, let other = words.indices.first(where: { $0 != chosen }) else {
            Issue.record("no fix bar"); return
        }
        _ = composer.choose(guess: other, time: 1.2)
        let settled = composer.press(.space, time: 1.5).compactMap { effect -> SettledWord? in
            if case .settled(let word) = effect { word } else { nil }
        }.first
        let word = try #require(settled)
        let correction = try #require(SharedWord.correction(word, layout: Synth.layout, now: Date()))
        #expect(correction.isCorrection)
        #expect(correction.word == words[other])
        #expect(correction.typed == words[chosen])
        // Nothing around it: not the word before, not the sentence.
        #expect(correction.previous == nil)
        #expect(correction.touches.count == 1)
        let points = try #require(correction.touches.first?.points)
        #expect(points.allSatisfy { $0[0] >= 0 && $0[0] <= 1 && $0[1] >= 0 && $0[1] <= 1 })
        #expect(points.first?[2] == 0)
        // It replays (with no context, which a correction never carries) to a word to compare.
        let replayed = try Replay.run(correction, language: Self.english)
        #expect(replayed.words.count == 1)
        #expect(replayed.words.first?.expected == words[other])
        #expect(replayed.words.first?.guesses.isEmpty == false)
    }

    @Test func aWordThatWasNotFixedIsNoCorrection() {
        let word = SettledWord(word: "hello", previous: "<s>", source: .swiped,
                               strokes: [.init(side: .left, points: [.zero], times: [0])])
        #expect(SharedWord.correction(word, layout: Synth.layout, now: Date()) == nil)
    }

    @Test func theAppStampsTheDevice() {
        let word = SharedWord(kind: SharedWord.correctionKind, word: "hello", layoutWidth: 390, layoutHeight: 216,
                              split: false, touches: [], day: "2026-11-02")
        let stamped = word.stamped(with: ReplayTests.device)
        #expect(stamped.writer == "w" && stamped.device == "test")
        #expect(SharedWord.day(of: Date(timeIntervalSince1970: 1_793_491_200)) == "2026-11-01")
    }

    @Test func theStoreKeepsSendsAndForgets() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("astrotype-sharing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SharedWordStore(folder: folder, limit: 3)
        let words = (0..<5).map { i in
            SharedWord(kind: "word.test", word: "w\(i)", layoutWidth: 390, layoutHeight: 216, split: false, touches: [], day: "2026-11-02")
        }
        for word in words { store.save([word]) }
        // At most `limit` wait.
        #expect(store.pendingCount == 3)
        let pending = store.pending()
        store.remove([pending[0].id])
        #expect(store.pendingCount == 2)
        store.markUploaded([pending[1].id])
        #expect(store.pending().map(\.id) == [pending[2].id])
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Uploaded/\(pending[1].id.uuidString).json").path))
    }

    @Test func aSharedWordRoundTrips() throws {
        let session = ReplayTests.record(["hello"])
        let word = try #require(SharedWord.words(of: session.recording).first)
        let data = try JSONEncoder().encode(word)
        #expect(try JSONDecoder().decode(SharedWord.self, from: data) == word)
        // The tools tell a shared word from a whole recording.
        #expect((try? JSONDecoder().decode(PracticeRecording.self, from: data)) == nil)
        #expect(word.version == 3)
    }
}
