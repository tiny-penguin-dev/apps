import Foundation

/// The two weekly leaderboards (features/leaderboards), on Game Center.
public enum Leaderboard: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Your everyday speed, as on Home. The main board.
    case everyday
    /// Your best Speed practice this week.
    case practice

    public var id: String { rawValue }

    /// The leaderboard's ID in App Store Connect (`store/game-center.json`).
    public var gameCenterID: String { "com.tinypenguin.astrotype.board.\(rawValue)" }
}

/// Who a leaderboard shows: everyone on Astrotype (first), or Game Center friends.
public enum LeaderboardScope: String, CaseIterable, Sendable, Identifiable {
    case everyone, friends
    public var id: String { rawValue }
}

/// What gets posted to the leaderboards, so a score on them means something.
///
///     LeaderboardRules.everydayScore(history, now: now)   // nil until 3 days in the last 7
///     LeaderboardRules.practiceScore(result)              // nil on Apple's keyboard or 3+ wrong words
public enum LeaderboardRules {
    /// Days with a speed, in the last `window` days, before the everyday speed is posted.
    public static let minDays = 3
    public static let window = 7
    /// Wrong words a practice test may have and still be posted.
    public static let maxMisses = 2
    /// Scores the boards take (Game Center's score range, set in App Store Connect).
    public static let scores = 1...200

    /// For each of the last `window` days, oldest first (today last), whether it has a speed.
    public static func daysCounted(_ history: SpeedHistory, now: Date, calendar: Calendar = .current) -> [Bool] {
        let have = Set(history.days.filter { $0.speed != nil }.map(\.day))
        return (0..<window).reversed().map { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: now) else { return false }
            return have.contains(SpeedHistory.key(date, calendar: calendar))
        }
    }

    /// How many more days with a speed it takes to be posted (0 once it's on).
    public static func daysToGo(_ history: SpeedHistory, now: Date, calendar: Calendar = .current) -> Int {
        max(0, minDays - daysCounted(history, now: now, calendar: calendar).filter { $0 }.count)
    }

    /// The everyday speed to post, once the last week has `minDays` days with a speed.
    public static func everydayScore(_ history: SpeedHistory, now: Date, calendar: Calendar = .current) -> Int? {
        guard daysToGo(history, now: now, calendar: calendar) == 0,
              let speed = history.everyday(now: now, calendar: calendar), scores.contains(speed) else { return nil }
        return speed
    }

    /// A practice result to post: on the Astrotype keyboard, with at most `maxMisses` wrong words.
    public static func practiceScore(_ result: SpeedResult) -> Int? {
        guard result.keyboard == .astrotype, result.misses <= maxMisses,
              scores.contains(result.wordsPerMinute) else { return nil }
        return result.wordsPerMinute
    }
}

/// One row on a leaderboard.
public struct LeaderboardEntry: Sendable, Equatable, Identifiable {
    public var rank: Int
    /// The Game Center nickname.
    public var name: String
    public var score: Int
    public var isMe: Bool

    public var id: String { "\(rank)-\(name)" }

    public init(rank: Int, name: String, score: Int, isMe: Bool = false) {
        self.rank = rank
        self.name = name
        self.score = score
        self.isMe = isMe
    }
}

/// What the Leaderboard screen shows for one board and scope.
public struct LeaderboardPage: Sendable, Equatable {
    public var board: Leaderboard
    public var scope: LeaderboardScope
    /// Your row, nil when you have no score on this board this week.
    public var me: LeaderboardEntry?
    /// Everyone with a score on the board this week (or every friend with one).
    public var total: Int
    /// The top 10 (friends: all of them).
    public var top: [LeaderboardEntry]
    /// Up to 5 above and 5 below you, empty when you're in the top 10 or not on it.
    public var around: [LeaderboardEntry]
    /// When the board starts over, if Game Center said.
    public var resets: Date?

    public init(board: Leaderboard, scope: LeaderboardScope, me: LeaderboardEntry? = nil, total: Int = 0,
                top: [LeaderboardEntry] = [], around: [LeaderboardEntry] = [], resets: Date? = nil) {
        self.board = board
        self.scope = scope
        self.me = me
        self.total = total
        self.top = top
        self.around = around
        self.resets = resets
    }

    /// The share of people you're faster than, 0 to 99, nil without a rank.
    /// Rank 1,204 of 18,400: faster than 93%.
    public var fasterThan: Int? {
        guard let me, total > 1 else { return nil }
        return min(99, max(0, (total - me.rank) * 100 / total))
    }

    /// Rows "around you" that the top 10 doesn't already show.
    public static func around(_ entries: [LeaderboardEntry], top: [LeaderboardEntry]) -> [LeaderboardEntry] {
        let shown = Set(top.map(\.rank))
        guard let me = entries.first(where: \.isMe), !shown.contains(me.rank) else { return [] }
        return entries.filter { !shown.contains($0.rank) && abs($0.rank - me.rank) <= 5 }
    }
}

/// How joining went.
public enum LeaderboardSignIn: Sendable, Equatable {
    case signedIn
    /// Closed Apple's sign-in, or Game Center is off for this app.
    case cancelled
    /// Screen Time or a profile doesn't allow Game Center.
    case restricted
}

/// Game Center, behind a protocol so the model can be tested (docs/building.md §4).
@MainActor
public protocol LeaderboardService: AnyObject {
    /// Whether this iPhone is signed in to Game Center for the app right now.
    var isSignedIn: Bool { get }
    /// Signs in, showing Apple's sheet when `interactive` and it's needed.
    func signIn(interactive: Bool) async -> LeaderboardSignIn
    func submit(_ score: Int, to board: Leaderboard) async throws
    func page(_ board: Leaderboard, scope: LeaderboardScope) async throws -> LeaderboardPage
}

/// Leaderboards by hand, for previews and tests: keeps what was posted.
@MainActor
public final class MemoryLeaderboardService: LeaderboardService {
    public var isSignedIn: Bool
    public var signInResult: LeaderboardSignIn
    public private(set) var submitted: [(score: Int, board: Leaderboard)] = []
    public var pages: [Leaderboard: LeaderboardPage] = [:]

    public init(isSignedIn: Bool = false, signInResult: LeaderboardSignIn = .signedIn) {
        self.isSignedIn = isSignedIn
        self.signInResult = signInResult
    }

    public func signIn(interactive: Bool) async -> LeaderboardSignIn {
        if isSignedIn { return .signedIn }
        guard interactive else { return .cancelled }
        isSignedIn = signInResult == .signedIn
        return signInResult
    }

    public func submit(_ score: Int, to board: Leaderboard) async throws {
        submitted.append((score, board))
    }

    public func page(_ board: Leaderboard, scope: LeaderboardScope) async throws -> LeaderboardPage {
        pages[board] ?? LeaderboardPage(board: board, scope: scope)
    }
}
