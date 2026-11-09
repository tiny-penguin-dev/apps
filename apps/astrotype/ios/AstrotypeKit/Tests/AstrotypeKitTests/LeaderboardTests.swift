import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct LeaderboardTests {
    private let t0 = Date(timeIntervalSince1970: 1_793_491_200) // 2026-11-01 00:00 UTC
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Three one-minute runs at `wpm` on each day, so each day has a speed.
    private func history(days speeds: [Int: Double]) -> SpeedHistory {
        var h = SpeedHistory()
        let runs = speeds.flatMap { day, wpm in
            (8...10).map { hour in
                SpeedRun(started: t0.addingTimeInterval(Double(day) * 86_400 + Double(hour) * 3600), seconds: 60,
                         characters: Int((wpm * 5).rounded()), words: 20)
            }
        }
        h.add(runs, calendar: utc)
        return h
    }

    @Test func everydayIsPostedOnceTheWeekHasThreeDays() {
        let now = t0.addingTimeInterval(9 * 86_400 + 12 * 3600)
        let two = history(days: [8: 40, 9: 50])
        #expect(LeaderboardRules.everydayScore(two, now: now, calendar: utc) == nil)
        #expect(LeaderboardRules.daysToGo(two, now: now, calendar: utc) == 1)
        #expect(LeaderboardRules.daysCounted(two, now: now, calendar: utc) == [false, false, false, false, false, true, true])
        let three = history(days: [3: 44, 8: 40, 9: 50])
        #expect(LeaderboardRules.everydayScore(three, now: now, calendar: utc) == 44)
        #expect(LeaderboardRules.daysToGo(three, now: now, calendar: utc) == 0)
        // Days older than a week don't count toward the three.
        let old = history(days: [0: 44, 8: 40, 9: 50])
        #expect(LeaderboardRules.everydayScore(old, now: now, calendar: utc) == nil)
    }

    @Test func practiceIsPostedFromAstrotypeWithFewWrongWords() {
        func result(_ wpm: Int, misses: Int = 0, keyboard: PracticeKeyboard = .astrotype) -> SpeedResult {
            SpeedResult(wordsPerMinute: wpm, fixes: 0, misses: misses, words: 20, seconds: 30, date: t0, keyboard: keyboard)
        }
        #expect(LeaderboardRules.practiceScore(result(57)) == 57)
        #expect(LeaderboardRules.practiceScore(result(57, misses: 2)) == 57)
        #expect(LeaderboardRules.practiceScore(result(57, misses: 3)) == nil)
        #expect(LeaderboardRules.practiceScore(result(70, keyboard: .apple)) == nil)
        #expect(LeaderboardRules.practiceScore(result(0)) == nil)
        #expect(LeaderboardRules.practiceScore(result(250)) == nil)
    }

    @Test func fasterThanAndAroundYou() {
        let me = LeaderboardEntry(rank: 1_204, name: "gabe", score: 46, isMe: true)
        let page = LeaderboardPage(board: .everyday, scope: .everyone, me: me, total: 18_400)
        #expect(page.fasterThan == 93)
        #expect(LeaderboardPage(board: .everyday, scope: .everyone, me: me, total: 1).fasterThan == nil)
        let first = LeaderboardEntry(rank: 1, name: "a", score: 90, isMe: true)
        #expect(LeaderboardPage(board: .everyday, scope: .everyone, me: first, total: 10).fasterThan == 90)

        let top = (1...10).map { LeaderboardEntry(rank: $0, name: "p\($0)", score: 100 - $0) }
        let near = (1_199...1_209).map { LeaderboardEntry(rank: $0, name: "n\($0)", score: 46, isMe: $0 == 1_204) }
        #expect(LeaderboardPage.around(near, top: top).count == 11)
        // In the top 10 already: nothing around you to add.
        let topMe = (1...10).map { LeaderboardEntry(rank: $0, name: "p\($0)", score: 100 - $0, isMe: $0 == 8) }
        #expect(LeaderboardPage.around(topMe + [LeaderboardEntry(rank: 11, name: "x", score: 80)], top: topMe).isEmpty)
        // Rank 13: rows 11 to 18, without the top 10's.
        let close = (8...18).map { LeaderboardEntry(rank: $0, name: "c\($0)", score: 50, isMe: $0 == 13) }
        #expect(LeaderboardPage.around(close, top: top).map(\.rank) == Array(11...18))
    }

    @MainActor @Test func memoryServiceSignsInAndKeepsScores() async throws {
        let service = MemoryLeaderboardService()
        #expect(await service.signIn(interactive: false) == .cancelled)
        #expect(await service.signIn(interactive: true) == .signedIn)
        try await service.submit(46, to: .everyday)
        #expect(service.submitted.map(\.score) == [46])
        #expect(Leaderboard.everyday.gameCenterID == "com.tinypenguin.astrotype.board.everyday")
    }

    @Test func settingDefaultsOffAndOldStateReadsOff() throws {
        #expect(AppState().leaderboards == false)
        let old = try JSONDecoder().decode(AppState.self, from: Data("{}".utf8))
        #expect(old.leaderboards == false)
    }
}
