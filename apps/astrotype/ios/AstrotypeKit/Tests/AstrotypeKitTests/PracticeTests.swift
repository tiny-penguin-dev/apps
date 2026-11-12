import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct SpeedTestTests {
    @Test func picksThreeDifferentSentencesRepeatablyFromASeed() {
        let a = SpeedTest.pick(seed: 7)
        let b = SpeedTest.pick(seed: 7)
        #expect(a == b)
        #expect(a.count == 3)
        #expect(Set(a).count == 3)
        #expect(SpeedTest.pick(seed: 8) != a)
        for sentence in SpeedTest.sentences {
            #expect(sentence.allSatisfy { ($0.isLetter && $0.isLowercase) || $0 == " " }, "\(sentence)")
        }
    }

    @Test func walksTheSentencesAndMeasuresWordsPerMinute() {
        var test = SpeedTest(sentences: ["the cat sat", "on a mat", "and slept"])
        #expect(test.expectedWord == "the")
        #expect(test.totalWords == 8)
        #expect(!test.isStarted)
        test.start(at: 10)
        // The word being typed doesn't count until a space follows it.
        #expect(test.follow(field: "The", at: 10.5) == .next)
        #expect(test.typed.isEmpty)
        #expect(test.follow(field: "The ", at: 11) == .next)
        #expect(test.typed == ["the"])
        #expect(test.remaining == ["cat", "sat"])
        // A wrong word moves on, marked, and counts as a miss (Gabriel, 8 Nov 2026).
        #expect(test.follow(field: "The cot ", at: 12) == .next)
        #expect(test.lastMissed)
        #expect(test.misses == 1)
        #expect(test.isMissed(word: 1))
        #expect(!test.isMissed(word: 0))
        #expect(test.expectedWord == "sat")
        #expect(test.follow(field: "The cot sat ", at: 14) == .sentence)
        #expect(!test.lastMissed)
        #expect(test.sentence == 1)
        #expect(test.typed.isEmpty)
        test.fixed()
        #expect(test.follow(field: "", at: 14) == .next)
        #expect(test.follow(field: "on ", at: 15) == .next)
        #expect(test.follow(field: "on a ", at: 16) == .next)
        #expect(test.follow(field: "on a mat ", at: 17) == .sentence)
        #expect(test.follow(field: "and ", at: 18) == .next)
        #expect(test.follow(field: "and slept ", at: 40) == .finished)
        #expect(test.isFinished)
        #expect(test.follow(field: "and slept more ", at: 41) == .finished)
        // "the cat sat" (11, less the missed "cat": 8) + "on a mat" (8) + "and slept" (9)
        // = 25 characters over 30 s.
        #expect(test.charactersTyped == 25)
        #expect(test.elapsed(at: 100) == 30)
        #expect(test.wordsPerMinute(at: 100) == 10)
        let result = test.result(date: Date(timeIntervalSince1970: 0), keyboard: .astrotype)
        #expect(result?.wordsPerMinute == 10)
        #expect(result?.fixes == 1)
        #expect(result?.misses == 1)
        #expect(result?.words == 8)
        #expect(result?.seconds == 30)
    }

    @Test func theClockStartsOnTheFirstTouchOrWord() {
        var test = SpeedTest(sentences: ["hi there"])
        #expect(test.elapsed(at: 5) == 0)
        #expect(test.wordsPerMinute(at: 5) == 0)
        #expect(test.follow(field: "hi ", at: 20) == .next)
        #expect(test.started == 20)
        #expect(test.result(date: Date(), keyboard: .apple) == nil)
    }

    /// Gabriel, 12 Nov 2026: after a wrong word the test lost its place, a fixed word
    /// stayed wrong and later right words turned red. It reads the field now.
    @Test func aWrongWordFixedWithBackspaceTurnsRight() {
        var test = SpeedTest(sentences: ["we should go out for coffee"])
        test.follow(field: "we shoild ", at: 1)
        #expect(test.word == 2)
        #expect(test.isMissed(word: 1))
        // Backspace back into it: the test steps back with the field.
        test.follow(field: "we shoil", at: 2)
        #expect(test.word == 1)
        #expect(!test.isMissed(word: 1))
        test.follow(field: "we should ", at: 3)
        #expect(test.word == 2)
        #expect(test.misses == 0)
        #expect(!test.lastMissed)
        test.follow(field: "we should go ", at: 4)
        #expect(test.word == 3)
        #expect(test.misses == 0)
    }

    @Test func aWordSwappedLaterTurnsRight() {
        // Look-back or the bar changes a word already written; nothing new goes in.
        var test = SpeedTest(sentences: ["this is a small park"])
        test.follow(field: "thai is ", at: 1)
        #expect(test.isMissed(word: 0))
        test.follow(field: "this is ", at: 1.1)
        #expect(!test.isMissed(word: 0))
        #expect(test.word == 2)
    }

    @Test func keepsItsPlaceAfterSlips() {
        let target = SpeedTest.sentences[0].split(separator: " ").map(String.init)
        // the cat went to the store for some bread ...
        func line(_ field: String) -> (count: Int, wrong: Set<Int>) {
            SpeedTest.align(SpeedTest.doneWords(in: field), to: target)
        }
        // A wrong word stands in for the one asked for, and the next right one is right.
        #expect(line("the dog went to ") == (4, [1]))
        #expect(line("the cst went ") == (3, [1]))
        // A word typed twice is an extra, not a wrong word after it.
        #expect(line("the the cat went ") == (3, []))
        // A skipped word is wrong; the words after still line up.
        #expect(line("the went to ") == (4, [1]))
        // Two words run together, or one in two pieces.
        #expect(line("the catwent to ") == (4, [1, 2]))
        #expect(line("the ca t went ") == (3, [1]))
        // A wrong last word still moves the test on.
        #expect(line("the cat xyzq ") == (3, [2]))
        #expect(line("") == (0, []))
    }

    @Test func oneSlipNeverMarksTheWordsAfterIt() {
        // Every sentence, every place, every kind of slip: the words after it stay right.
        for sentence in SpeedTest.sentences {
            let words = sentence.split(separator: " ").map(String.init)
            for at in words.indices.dropLast() {
                let slips: [[String]] = [
                    [String(words[at].reversed()) + "x"],          // wrong word
                    [words[at], words[at]],                        // typed twice
                    [],                                            // skipped
                    [words[at] + words[at + 1]],                   // run together
                ]
                for slip in slips {
                    let after = slip.count == 1 && slip[0] == words[at] + words[at + 1] ? at + 2 : at + 1
                    let typed = Array(words[..<at]) + slip + Array(words[after...])
                    let line = SpeedTest.align(typed, to: words)
                    #expect(line.count == words.count, "\(typed)")
                    #expect(line.wrong.allSatisfy { $0 < after }, "\(typed) \(line.wrong)")
                    #expect(line.wrong.allSatisfy { $0 >= at }, "\(typed) \(line.wrong)")
                }
            }
        }
    }

    @Test func countsOnlyFinishedWords() {
        #expect(SpeedTest.doneWords(in: "the cat") == ["the"])
        #expect(SpeedTest.doneWords(in: "the cat ") == ["the", "cat"])
        #expect(SpeedTest.doneWords(in: "The cat.") == ["the", "cat"])
        #expect(SpeedTest.doneWords(in: "the  , cat ") == ["the", "cat"])
        #expect(SpeedTest.doneWords(in: "") == [])
    }

    @Test func normalizesWhatTheFieldGot() {
        #expect(SpeedTest.normalize("Hello,") == "hello")
        #expect(SpeedTest.normalize(" The ") == "the")
    }
}

@Suite struct StreakAndMilestoneTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func countsDaysInARowEndingTodayOrYesterday() {
        let today = Date(timeIntervalSince1970: 1_793_491_200 + 3600) // 2026-11-01 01:00 UTC
        #expect(Streak.days(practiceDays: [], now: today, calendar: calendar) == 0)
        #expect(Streak.days(practiceDays: ["2026-11-01"], now: today, calendar: calendar) == 1)
        #expect(Streak.days(practiceDays: ["2026-10-30", "2026-10-31", "2026-11-01"], now: today, calendar: calendar) == 3)
        // Not practised yet today: yesterday's streak still stands.
        #expect(Streak.days(practiceDays: ["2026-10-30", "2026-10-31"], now: today, calendar: calendar) == 2)
        // A gap breaks it.
        #expect(Streak.days(practiceDays: ["2026-10-28", "2026-10-29", "2026-10-31"], now: today, calendar: calendar) == 1)
        #expect(Streak.days(practiceDays: ["2026-10-29"], now: today, calendar: calendar) == 0)
    }

    @Test func milestonesAreReachedOnceAndShownInOrder() {
        #expect(Milestone.reached(bestWordsPerMinute: nil, practiceDays: [], learnedWords: 0).isEmpty)
        #expect(Milestone.reached(bestWordsPerMinute: 39, practiceDays: [], learnedWords: 0).isEmpty)
        let days = (1...7).map { "2026-11-0\($0)" }
        let reached = Milestone.reached(bestWordsPerMinute: 40, practiceDays: days + days, learnedWords: 100)
        #expect(reached == Set(Milestone.allCases))
        #expect(Milestone.pending(reached: reached, seen: []) == .fortyWordsPerMinute)
        #expect(Milestone.pending(reached: reached, seen: ["fortyWordsPerMinute"]) == .firstWeek)
        #expect(Milestone.pending(reached: reached, seen: Milestone.allCases.map(\.rawValue)) == nil)
        #expect(Milestone.pending(reached: [.hundredWords], seen: []) == .hundredWords)
    }
}

@Suite struct DrillTests {
    @Test func threeDrillsOfFiveWordsWithHints() {
        #expect(Drill.all.count == 3)
        #expect(Drill.all.map(\.id) == Drill.ID.allCases)
        for drill in Drill.all {
            #expect(drill.words.count == 5)
            #expect(!drill.hintText.isEmpty)
            for word in drill.words {
                // The strokes spell the word (a doubled letter is crossed once by the swipe).
                let letters = word.strokes.map(\.letters).joined()
                #expect(Set(letters) == Set(word.text), "\(word.text)")
            }
        }
        #expect(Drill.named(.switching).hintText == "Left swipes w→e, right swipes n→t. Keys light up to show which thumb.")
        let keys = Drill.keys(for: Drill.named(.switching).words[0])
        #expect(keys.map(\.letter) == ["w", "e", "n", "t"])
        #expect(keys.map(\.side) == [.left, .left, .right, .right])
    }

    @Test func theWordsTypeOnTheEngine() {
        for drill in Drill.all {
            for word in drill.words {
                var composer = Synth.composer()
                if word.tapInsideSwipe {
                    // The swipe over 0.6 s, the tap when it passes the doubled letter.
                    let swipe = word.strokes.first { !$0.isTap }!
                    let tap = word.strokes.first { $0.isTap }!
                    let letters = Array(swipe.letters)
                    let position = letters.firstIndex(of: tap.letters.first!) ?? 0
                    let at = 0.6 * Double(position) / Double(max(1, letters.count - 1))
                    Synth.play(&composer, [.swipe(swipe.letters, id: 1, from: 0, to: 0.6), .tap(tap.letters.first!, id: 2, at: at)])
                } else {
                    var time: TimeInterval = 0
                    var id = 1
                    for stroke in word.strokes {
                        if stroke.isTap {
                            Synth.tap(&composer, stroke.letters.first!, id: id, at: time)
                            time += 0.2
                        } else {
                            Synth.swipe(&composer, stroke.letters, id: id, at: time)
                            time += 0.5
                        }
                        id += 1
                    }
                }
                #expect(composer.state.openWord == word.text, "\(drill.id): \(word.text) came out as \(String(describing: composer.state.openWord))")
            }
        }
    }
}

@Suite struct PracticeRecordingTests {
    let device = PracticeRecording.Device(model: "iPhone17,1", system: "iOS 26.1", app: "0.2.0 (1)", writer: "w")

    @Test func recordsTouchesInLayoutUnitsFromTheFirstTouch() {
        var recorder = TouchRecorder(kind: "speedtest", layoutWidth: 400, layoutHeight: 200, split: false)
        recorder.touch(.began, id: 1, x: 40, y: 20, time: 100)
        recorder.touch(.moved, id: 1, x: 80, y: 20, time: 100.1)
        recorder.touch(.began, id: 2, x: 300, y: 100, time: 100.15)
        recorder.touch(.ended, id: 1, x: 120, y: 20, time: 100.2)
        recorder.touch(.ended, id: 2, x: 300, y: 100, time: 100.3)
        recorder.touch(.moved, id: 9, x: 0, y: 0, time: 101) // never began: ignored
        recorder.committed("Hello", time: 100.4)
        recorder.committed("", time: 100.5)
        let recording = recorder.recording(expected: "hello", device: device, now: Date(timeIntervalSince1970: 0), wordsPerMinute: 40, fixes: 1)
        #expect(recording.touches.count == 2)
        #expect(recording.touches[0].points == [[0.1, 0.1, 0], [0.2, 0.1, 0.1], [0.3, 0.1, 0.2]])
        #expect(recording.touches[1].id == 2)
        #expect(recording.touches[1].points.first == [0.75, 0.5, 0.15])
        #expect(recording.label == "hello")
        #expect(recording.expected == "hello")
        #expect(recording.wordsPerMinute == 40)
        #expect(recording.writer == "w")
        #expect(recording.kind == "speedtest")
        #expect(recording.commits == [PracticeRecording.Commit(word: "hello", t: 0.4)])
        #expect(recording.version == 2)
    }

    /// Sessions recorded before commits were kept still decode, with none.
    @Test func decodesAVersionOneRecording() throws {
        let json = """
        {"version":1,"id":"6B9A2C1E-0000-4000-8000-000000000001","kind":"speedtest","label":"hi","expected":"hi",
         "layoutWidth":390,"layoutHeight":216,"split":false,"touches":[{"id":1,"points":[[0.1,0.2,0]]}],
         "writer":"w","device":"iPhone","system":"iOS 26","app":"0.2.0","createdAt":0}
        """
        let recording = try JSONDecoder().decode(PracticeRecording.self, from: Data(json.utf8))
        #expect(recording.version == 1)
        #expect(recording.commits.isEmpty)
        #expect(recording.touches.count == 1)
    }

    @Test func storeKeepsPendingUntilUploaded() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AstrotypeKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PracticeStore(folder: dir.appendingPathComponent("Practice"))
        #expect(store.pending().isEmpty)
        var recorder = TouchRecorder(kind: "drill.pairs", layoutWidth: 390, layoutHeight: 216, split: false)
        recorder.touch(.began, id: 1, x: 10, y: 10, time: 0)
        recorder.touch(.ended, id: 1, x: 10, y: 10, time: 0.1)
        let first = recorder.recording(expected: "then", device: device, now: Date(timeIntervalSince1970: 100))
        let second = recorder.recording(expected: "into", device: device, now: Date(timeIntervalSince1970: 200))
        try store.save(second)
        try store.save(first)
        let pending = store.pending()
        #expect(pending.map(\.id) == [first.id, second.id])
        #expect(pending[0] == first)
        let uploader = FakePracticeUploader()
        let sent = try await uploader.upload(pending)
        store.markUploaded(sent)
        #expect(store.pending().isEmpty)
        #expect(uploader.uploaded.count == 2)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Practice/Uploaded/\(first.id.uuidString).json").path))
    }
}

@Suite struct PracticeStateTests {
    @Test func recordsTestsKeepsTheBestAndApplesNumber() {
        var state = AppState()
        let date = Date(timeIntervalSince1970: 0)
        func result(_ wpm: Int, _ keyboard: PracticeKeyboard = .astrotype) -> SpeedResult {
            SpeedResult(wordsPerMinute: wpm, fixes: 0, misses: 0, words: 30, seconds: 60, date: date, keyboard: keyboard)
        }
        let first = state.record(result(30))
        #expect(first)
        let slower = state.record(result(25))
        #expect(!slower)
        let faster = state.record(result(31))
        #expect(faster)
        #expect(state.bestWordsPerMinute == 31)
        let apple = state.record(result(50, .apple))
        #expect(!apple)
        #expect(state.appleWordsPerMinute == 50)
        #expect(state.bestWordsPerMinute == 31)
        for i in 0..<240 { _ = state.record(result(i)) }
        #expect(state.speedTests.count == 200)
        #expect(state.bestWordsPerMinute == 239)
    }

    @Test func newFieldsRoundTripAndDefault() throws {
        var state = AppState()
        state.bestWordsPerMinute = 42
        state.appleWordsPerMinute = 30
        state.drillsDone["pairs"] = Date(timeIntervalSince1970: 1000)
        state.milestonesSeen = ["firstWeek"]
        state.sharePractice = true
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
        let older = try JSONDecoder().decode(AppState.self, from: Data(#"{"version":1}"#.utf8))
        #expect(older.bestWordsPerMinute == nil)
        #expect(older.drillsDone.isEmpty)
        #expect(!older.sharePractice)
    }

    @Test func metricsRecordGauges() {
        let metrics = RecordingMetrics()
        metrics.gauge("speedtest.finished", value: 52, ["keyboard": "astrotype"])
        #expect(metrics.sent.last?.value == 52)
        #expect(metrics.sent.last?.attributes == ["keyboard": "astrotype"])
    }
}
