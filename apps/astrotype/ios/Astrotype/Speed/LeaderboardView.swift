import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// The card under Your speed's tiles: your rank this week, or the join card
/// (features/leaderboards).
struct LeaderboardCard: View {
    var model: AppModel
    var open: () -> Void
    @State private var joining = false

    var body: some View {
        if model.isOnLeaderboards {
            Button(action: open) {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack {
                            Text("Leaderboard").font(.sw(.heading))
                            Spacer()
                            if let faster = model.everydayRank?.fasterThan {
                                Chip("Faster than \(faster)%", tint: Theme.mint)
                            }
                            Image(systemName: "chevron.right").font(.footnote.weight(.heavy)).foregroundStyle(Theme.muted)
                        }
                        if let page = model.everydayRank, let me = page.me {
                            HStack(alignment: .lastTextBaseline, spacing: Theme.Space.s) {
                                Text("#\(me.rank.formatted())").font(.system(size: 40, weight: .black, design: .rounded)).monospacedDigit()
                                Text("of \(page.total.formatted()) this week").font(.sw(.small)).foregroundStyle(Theme.muted)
                            }
                        } else {
                            Text(waitingText).font(.sw(.small)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the leaderboards")
        } else {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("See where you rank").font(.sw(.heading))
                    Text("Weekly leaderboards for everyday speed and Speed practice, with everyone on Astrotype and your friends. Shares your Game Center name and these two numbers, nothing you type.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let problem = model.leaderboardProblem {
                        Text(LeaderboardView.problemText(problem))
                            .font(.sw(.small)).foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: Theme.Space.m) {
                        Button(joining ? "Joining…" : "Join") {
                            joining = true
                            Task {
                                await model.joinLeaderboards()
                                joining = false
                                if model.isOnLeaderboards { open() }
                            }
                        }
                        .buttonStyle(.small)
                        .disabled(joining)
                        Text("Free · Game Center").font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private var waitingText: String {
        let days = model.leaderboardDaysToGo
        return days > 0 ? "Type on \(days) more \(days == 1 ? "day" : "days") this week to get on the board."
                        : "See where you rank this week."
    }
}

/// The weekly leaderboards: Everyday or Practice, Everyone (first) or Friends. Your
/// rank on top, then the top 10, then the people around you (features/leaderboards).
struct LeaderboardView: View {
    var model: AppModel
    @Binding var path: [HomeView.Route]
    @State private var board: Leaderboard = .everyday
    @State private var scope: LeaderboardScope = .everyone
    @State private var loading = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 700
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Leaderboard").font(.sw(.title)).padding(.top, Theme.Space.s)
                    Picker("Board", selection: $board) {
                        Text("Everyday").tag(Leaderboard.everyday)
                        Text("Practice").tag(Leaderboard.practice)
                    }
                    .pickerStyle(.segmented)
                    Picker("Who", selection: $scope) {
                        Text("Everyone").tag(LeaderboardScope.everyone)
                        Text("Friends").tag(LeaderboardScope.friends)
                    }
                    .pickerStyle(.segmented)
                    content(wide: wide)
                    Text("Weekly boards on Game Center. Only your Game Center name and these speeds are shared.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Privacy and sharing ›") { path.append(.settingsPage(.privacy)) }
                        .buttonStyle(.ghost)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: wide ? 900 : 560)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let resets = page?.resets { Chip(resetText(resets)) }
            }
        }
        .task(id: "\(board.rawValue)-\(scope.rawValue)") {
            model.leaderboardOpened(board, scope)
            loading = true
            await model.loadLeaderboard(board, scope)
            loading = false
        }
    }

    private var page: LeaderboardPage? { model.leaderboardPage(board, scope) }

    @ViewBuilder private func content(wide: Bool) -> some View {
        if !model.isOnLeaderboards {
            LeaderboardCard(model: model, open: {})
        } else if let page {
            hero(page)
            if scope == .friends, page.top.count <= 1 {
                noFriends
            } else if scope == .friends {
                list(page.top)
            } else {
                let columns = wide && !page.around.isEmpty
                let layout = columns ? AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.l))
                                     : AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.m))
                layout {
                    section("Top 10", page.top)
                    if !page.around.isEmpty { section("Around you", page.around) }
                }
            }
        } else if loading {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, Theme.Space.xl)
        } else if model.leaderboardFailed {
            Text("Couldn't load the leaderboard. Check your connection and try again.")
                .font(.sw(.small)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private func hero(_ page: LeaderboardPage) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if let me = page.me {
                    HStack(alignment: .lastTextBaseline, spacing: Theme.Space.s) {
                        (Text("#").foregroundStyle(Theme.muted) + Text(me.rank.formatted()))
                            .font(.system(size: 56, weight: .black, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text(scope == .friends ? "of \(page.total) friends" : "of \(page.total.formatted()) this week")
                            .font(.system(.subheadline, design: .rounded, weight: .heavy)).foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: Theme.Space.s) {
                        if scope == .everyone, let faster = page.fasterThan {
                            Chip("Faster than \(faster)%", tint: Theme.mint)
                        }
                        Chip("\(board == .everyday ? "Everyday" : "Best practice") \(me.score) wpm")
                    }
                } else if board == .everyday, model.leaderboardDaysToGo > 0 {
                    let days = model.leaderboardDaysToGo
                    Text("Type on \(days) more \(days == 1 ? "day" : "days") this week to get on the board")
                        .font(.sw(.heading)).fixedSize(horizontal: false, vertical: true)
                    Text("Your everyday speed goes up once the last 7 days have 3 days with enough typing. Today counts.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    weekDots
                } else {
                    Text(board == .everyday ? "Not on the board yet this week" : "No practice on the board this week")
                        .font(.sw(.heading))
                    Text(board == .everyday ? "Keep typing with Astrotype; your everyday speed goes up on its own."
                                            : "Do a Speed practice on the Astrotype keyboard with at most 2 wrong words.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    if board == .practice {
                        Button("Practice for speed") { path.append(.speedTest(.astrotype, nil)) }.buttonStyle(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : .snappy, value: page.me?.rank)
    }

    private var weekDots: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(Array(model.leaderboardDaysCounted.enumerated()), id: \.offset) { index, counted in
                ZStack {
                    Circle().fill(counted ? Theme.mint : Theme.line)
                    if counted {
                        Image(systemName: "checkmark").font(.caption.weight(.black)).foregroundStyle(.white)
                    }
                }
                .frame(width: 28, height: 28)
                .overlay {
                    if index == 6 { Circle().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [3, 3])).padding(-4) }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(model.leaderboardDaysCounted.filter { $0 }.count) of the last 7 days counted")
    }

    private var noFriends: some View {
        Card {
            VStack(spacing: Theme.Space.s) {
                Image(systemName: "person.2.fill").font(.title2).foregroundStyle(Theme.accent)
                Text("None of your Game Center friends use Astrotype yet")
                    .font(.sw(.heading)).multilineTextAlignment(.center)
                Text("Send one the app and race them on next week's board.")
                    .font(.sw(.small)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                // No App Store link until the first release; the name finds it.
                ShareLink(item: "I'm racing my typing speed on Astrotype, the two-thumb keyboard. Get it on the App Store and join me on the leaderboard.") {
                    Text("Invite a friend")
                }
                .buttonStyle(.small)
                Button("See Everyone ›") { scope = .everyone }.buttonStyle(.ghost)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func section(_ title: String, _ rows: [LeaderboardEntry]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title.uppercased())
                .font(.system(.footnote, design: .rounded, weight: .black)).tracking(0.8)
                .foregroundStyle(Theme.muted).padding(.leading, 6)
            list(rows)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(_ rows: [LeaderboardEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(Theme.line) }
                RankRow(entry: row)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private func resetText(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case ...0: return "Resets today"
        case 1: return "Resets tomorrow"
        default: return "Resets \(date.formatted(.dateTime.weekday(.wide)))"
        }
    }

    static func problemText(_ problem: LeaderboardSignIn) -> String {
        switch problem {
        case .signedIn: ""
        case .cancelled: "Game Center didn't sign in. If no sign-in sheet showed up, sign in under Settings → Game Center, then tap Join again."
        case .restricted: "Game Center isn't allowed on this iPhone (Screen Time or a profile)."
        }
    }
}

/// One row on a board: rank, a circle with the initial, the Game Center name, the
/// score. Your row is tinted.
struct RankRow: View {
    var entry: LeaderboardEntry

    private static let colors: [Color] = [Theme.left, Theme.right, Theme.sun, Theme.mint, Theme.accent, Theme.slate]

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            HStack(spacing: 4) {
                if entry.rank <= 3 {
                    Circle().fill(medal).frame(width: 8, height: 8)
                }
                Text(entry.rank.formatted()).monospacedDigit()
            }
            .font(.system(.subheadline, design: .rounded, weight: .black))
            .foregroundStyle(entry.rank <= 10 ? Theme.ink : Theme.muted)
            .frame(minWidth: 52, alignment: .trailing)
            Text(String(entry.name.prefix(1)).uppercased())
                .font(.system(.subheadline, design: .rounded, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: Circle())
                .accessibilityHidden(true)
            Text(entry.isMe ? "You" : entry.name)
                .font(.system(.body, design: .rounded, weight: .heavy))
                .foregroundStyle(entry.isMe ? Theme.accent : Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            (Text("\(entry.score)").font(.system(.body, design: .rounded, weight: .black))
                + Text(" wpm").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Theme.muted))
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(minHeight: 48)
        .background(entry.isMe ? Theme.accent.opacity(0.16) : .clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(entry.rank.formatted()), \(entry.isMe ? "you" : entry.name), \(entry.score) words per minute")
    }

    /// The same colour for a name every time (`hashValue` changes between launches).
    private var color: Color {
        Self.colors[entry.name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.colors.count]
    }

    private var medal: Color {
        switch entry.rank {
        case 1: Theme.sun
        case 2: Theme.slate
        default: Theme.right
        }
    }
}
