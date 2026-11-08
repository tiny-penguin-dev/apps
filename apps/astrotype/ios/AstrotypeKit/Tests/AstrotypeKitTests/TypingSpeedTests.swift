import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct TypingSpeedTests {
    private let t0 = Date(timeIntervalSince1970: 1_793_491_200) // 2026-11-01 00:00 UTC
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Types `words` words of 4 letters and a space, one character every `gap` seconds.
    private func type(_ meter: inout SpeedMeter, words: Int, from start: TimeInterval, gap: TimeInterval = 0.2,
                      date: Date) -> TimeInterval {
        var time = start
        for _ in 0..<words {
            for _ in 0..<5 {
                meter.touched(at: time, date: date)
                meter.edited(characters: 1, at: time)
                time += gap
            }
            meter.wordWentIn()
        }
        return time
    }

    @Test func runIsCharactersOverFivePerMinute() {
        var meter = SpeedMeter()
        _ = type(&meter, words: 12, from: 100, date: t0)
        let run = meter.end()
        #expect(run != nil)
        #expect(run?.characters == 60)
        #expect(run?.words == 12)
        // 60 characters in 11.8 s: 12 words in 0.1967 min, about 61 wpm.
        #expect(abs((run?.wordsPerMinute ?? 0) - 61.0) < 0.2)
        #expect(meter.isRunning == false)
    }

    @Test func shortRunsDoNotCount() {
        var meter = SpeedMeter()
        _ = type(&meter, words: 3, from: 0, date: t0)
        let ended = meter.end()
        #expect(ended == nil)
    }

    @Test func pauseEndsTheRunAndStartsAnother() {
        var meter = SpeedMeter()
        let end = type(&meter, words: 10, from: 0, date: t0)
        let finished = meter.touched(at: end + 6, date: t0.addingTimeInterval(end + 6))
        #expect(finished?.words == 10)
        #expect(meter.isRunning)
        // A short pause keeps the run going.
        var other = SpeedMeter()
        let mid = type(&other, words: 5, from: 0, date: t0)
        let kept = other.touched(at: mid + 4, date: t0)
        #expect(kept == nil)
        _ = type(&other, words: 5, from: mid + 4, date: t0)
        let joined = other.end()
        #expect(joined?.words == 10)
    }

    @Test func deletesComeOffAndEditsWithoutATouchAreIgnored() {
        var meter = SpeedMeter()
        meter.edited(characters: 50, at: 0) // nothing touched: a paste or the app
        #expect(meter.isRunning == false)
        let end = type(&meter, words: 12, from: 1, date: t0)
        meter.edited(characters: -10, at: end)
        let net = meter.end()
        #expect(net?.characters == 50)
    }

    @Test func tooFastIsThrownAway() {
        let run = SpeedRun(started: t0, seconds: 10, characters: 500, words: 100) // 600 wpm
        #expect(run.counts == false)
        #expect(SpeedRun(started: t0, seconds: 60, characters: 300, words: 60).counts)
    }

    @Test func runsFileKeepsTwoWeeks() {
        var runs = SpeedRuns()
        runs.add(SpeedRun(started: t0, seconds: 60, characters: 250, words: 50), now: t0)
        runs.add(SpeedRun(started: t0.addingTimeInterval(20 * 86_400), seconds: 60, characters: 250, words: 50),
                 now: t0.addingTimeInterval(20 * 86_400))
        #expect(runs.runs.count == 1)
    }

    private func run(day: Int, hour: Int = 9, wpm: Double, words: Int = 20) -> SpeedRun {
        // characters / 5 / minutes = wpm with one minute.
        SpeedRun(started: t0.addingTimeInterval(Double(day) * 86_400 + Double(hour) * 3600), seconds: 60,
                 characters: Int((wpm * 5).rounded()), words: words)
    }

    @Test func dayIsTheMedianOfItsRunsWithThreeRuns() {
        var history = SpeedHistory()
        history.add([run(day: 0, wpm: 40), run(day: 0, hour: 10, wpm: 44)], calendar: utc)
        #expect(history.days.first?.speed == nil) // two runs: not enough
        history.add([run(day: 0, hour: 11, wpm: 150)], calendar: utc)
        #expect(history.days.first?.speed == 44) // the odd fast run doesn't swing it
        #expect(history.days.count == 1)
    }

    @Test func runsAreFoldedOnce() {
        var history = SpeedHistory()
        let runs = [run(day: 0, wpm: 40), run(day: 0, hour: 10, wpm: 42), run(day: 0, hour: 11, wpm: 44)]
        let first = history.add(runs, calendar: utc)
        let again = history.add(runs, calendar: utc)
        #expect(first)
        #expect(again == false)
        #expect(history.days[0].speeds.count == 3)
    }

    private func history(days speeds: [Int: Double]) -> SpeedHistory {
        var h = SpeedHistory()
        h.add(speeds.flatMap { day, wpm in [run(day: day, hour: 8, wpm: wpm), run(day: day, hour: 9, wpm: wpm),
                                             run(day: day, hour: 10, wpm: wpm)] }, calendar: utc)
        return h
    }

    @Test func everydayNeedsThreeDaysAndTakesTheMedian() {
        let now = t0.addingTimeInterval(9 * 86_400 + 12 * 3600)
        #expect(history(days: [8: 40, 9: 50]).everyday(now: now, calendar: utc) == nil)
        #expect(history(days: [7: 40, 8: 50, 9: 46]).everyday(now: now, calendar: utc) == 46)
        // The last seven days with a speed, not older ones.
        let long = history(days: [0: 10, 1: 10, 2: 10, 3: 50, 4: 50, 5: 50, 6: 50, 7: 50, 8: 50, 9: 50])
        #expect(long.everyday(now: now, calendar: utc) == 50)
    }

    @Test func pointsLeaveGapsAndShowPractice() {
        let now = t0.addingTimeInterval(6 * 86_400 + 12 * 3600)
        let h = history(days: [0: 40, 2: 42, 6: 45])
        let practice = [SpeedResult(wordsPerMinute: 55, fixes: 0, misses: 0, words: 20, seconds: 30,
                                    date: t0.addingTimeInterval(2 * 86_400 + 3600), keyboard: .astrotype),
                        SpeedResult(wordsPerMinute: 70, fixes: 0, misses: 0, words: 20, seconds: 30,
                                    date: t0.addingTimeInterval(2 * 86_400 + 7200), keyboard: .apple)]
        let points = h.points(.week, now: now, practice: practice, calendar: utc)
        #expect(points.count == 7)
        #expect(points.map(\.everyday) == [40, nil, 42, nil, nil, nil, 45])
        #expect(points[2].practice == 55) // Apple's keyboard is not practice on Astrotype
        #expect(h.points(.year, now: now, calendar: utc).count == 52)
        let summary = h.summary(.week, now: now, practice: practice, calendar: utc)
        #expect(summary.speed == 42)
        #expect(summary.bestPractice == 55)
        #expect(summary.words == 9 * 20)
        #expect(summary.fastest == 45)
    }

    @Test func finishedDaysAreReportedOnce() {
        let now = t0.addingTimeInterval(2 * 86_400 + 12 * 3600)
        var h = history(days: [0: 40, 1: 42, 2: 45])
        #expect(h.toReport(now: now, calendar: utc).map(\.day) == ["2026-11-01", "2026-11-02"]) // not today
        h.reported(now: now, calendar: utc)
        #expect(h.toReport(now: now, calendar: utc).isEmpty)
    }

    @Test func settingDefaultsOnAndOldFilesReadOn() throws {
        #expect(KeyboardSettings().measuresSpeed)
        let old = try JSONDecoder().decode(KeyboardSettings.self, from: Data("{}".utf8))
        #expect(old.measuresSpeed)
    }
}
