import AstrotypeCore
@preconcurrency import GameKit
import UIKit

/// The leaderboards on Game Center (features/leaderboards). Apple keeps the scores and
/// the names; we post two numbers and read the boards back.
///
/// GameKit's types aren't `Sendable`, so its calls run off the main actor and hand
/// back only our own values.
@MainActor
final class GameCenterLeaderboards: LeaderboardService {
    private var waiting: [CheckedContinuation<LeaderboardSignIn, Never>] = []
    private var interactive = false
    private var handlerSet = false

    var isSignedIn: Bool { GKLocalPlayer.local.isAuthenticated }

    func signIn(interactive: Bool) async -> LeaderboardSignIn {
        if GKLocalPlayer.local.isAuthenticated { return .signedIn }
        if interactive { self.interactive = true }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            guard !handlerSet else { return }
            handlerSet = true
            // Setting the handler starts sign-in. GameKit calls it again whenever the
            // state changes, so it stays set for the life of the app.
            GKLocalPlayer.local.authenticateHandler = { [weak self] controller, error in
                MainActor.assumeIsolated {
                    self?.authenticated(controller: controller, error: error)
                }
            }
        }
    }

    private func authenticated(controller: UIViewController?, error: Error?) {
        if let controller {
            // Apple's sign-in sheet: only when the person tapped Join.
            if interactive, let top = Self.topController() {
                top.present(controller, animated: true)
                return
            }
            finish(.cancelled)
            return
        }
        if GKLocalPlayer.local.isAuthenticated {
            finish(.signedIn)
        } else if GKLocalPlayer.local.isUnderage || (error as? GKError)?.code == .gameUnrecognized
                    || (error as? GKError)?.code == .notSupported || (error as? GKError)?.code == .parentalControlsBlocked {
            finish(.restricted)
        } else {
            finish(.cancelled)
        }
    }

    private func finish(_ result: LeaderboardSignIn) {
        interactive = false
        let all = waiting
        waiting = []
        for continuation in all { continuation.resume(returning: result) }
    }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    func submit(_ score: Int, to board: Leaderboard) async throws {
        try await Self.submit(score, to: board.gameCenterID)
    }

    func page(_ board: Leaderboard, scope: LeaderboardScope) async throws -> LeaderboardPage {
        try await Self.page(board, scope: scope, myID: GKLocalPlayer.local.gamePlayerID)
    }

    // GameKit's work happens off the main actor, so its objects never cross into it;
    // only our own values come back.

    private nonisolated static func submit(_ score: Int, to id: String) async throws {
        try await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [id])
    }

    private nonisolated static func page(_ board: Leaderboard, scope: LeaderboardScope,
                                         myID: String) async throws -> LeaderboardPage {
        guard let leaderboard = try await GKLeaderboard.loadLeaderboards(IDs: [board.gameCenterID]).first else {
            throw GKError(.unknown)
        }
        func row(_ entry: GKLeaderboard.Entry) -> LeaderboardEntry {
            LeaderboardEntry(rank: entry.rank, name: entry.player.displayName, score: entry.score,
                             isMe: entry.player.gamePlayerID == myID)
        }
        if scope == .friends {
            // The Friends board needs the friends list; iOS asks once (NSGKFriendListUsageDescription).
            if (try? await GKLocalPlayer.local.loadFriendsAuthorizationStatus()) == .notDetermined {
                _ = try? await GKLocalPlayer.local.loadFriends()
            }
            let (mine, entries, total) = try await leaderboard.loadEntries(
                for: .friendsOnly, timeScope: .allTime, range: NSRange(location: 1, length: 100))
            return LeaderboardPage(board: board, scope: scope, me: mine.map(row), total: total,
                                   top: entries.map(row), resets: leaderboard.nextStartDate)
        }
        // Everyone: the top 10, then the people around you.
        let (mine, entries, total) = try await leaderboard.loadEntries(
            for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 10))
        let me = mine.map(row)
        let top = entries.map(row)
        var around: [LeaderboardEntry] = []
        if let me, me.rank > 10 {
            let near = try? await leaderboard.loadEntries(
                for: .global, timeScope: .allTime, range: NSRange(location: max(1, me.rank - 5), length: 11))
            around = LeaderboardPage.around((near?.1 ?? []).map(row), top: top)
            if around.isEmpty { around = [me] }
        }
        return LeaderboardPage(board: board, scope: scope, me: me, total: total, top: top, around: around,
                               resets: leaderboard.nextStartDate)
    }
}
