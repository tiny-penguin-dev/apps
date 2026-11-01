import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// DESIGN.md screen 5: "Both flippers, go." The speed test and the Pro row on the
/// left, drills, the week and Settings on the right; one column on a phone, two on the
/// wide size. A sun-yellow banner leads back to setup while the keyboard is off. The
/// Trial over sheet comes up here once, on the first launch after the trial ends.
struct HomeView: View {
    var model: AppModel
    @State private var path: [Route] = []

    enum Route: Hashable {
        case practice, settings, learnedWords, turnOn, sync, pro
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { proxy in
                let wide = proxy.size.width >= 700
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        header(wide: wide)
                        if !model.isKeyboardOn {
                            Banner("Astrotype isn't on yet.", action: "Turn on") { path.append(.turnOn) }
                        }
                        if wide {
                            HStack(alignment: .top, spacing: Theme.Space.gutter) {
                                leftColumn.frame(maxWidth: .infinity)
                                rightColumn.frame(maxWidth: .infinity)
                            }
                        } else {
                            leftColumn
                            rightColumn
                        }
                    }
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.bottom, Theme.Space.xl)
                    .frame(maxWidth: wide ? 1100 : 560)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .foregroundStyle(Theme.ink)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .practice: PracticeView(model: model)
                case .settings: SettingsView(model: model, path: $path)
                case .learnedWords: LearnedWordsView(model: model)
                case .turnOn: TurnOnView(model: model, inSetup: false)
                case .sync: SyncView(model: model, inSetup: false)
                case .pro: ProView(model: model)
                }
            }
            .sheet(isPresented: trialOverShowing) {
                TrialOverView(model: model) { path.append(.pro) }
            }
        }
        .tint(Theme.accent)
    }

    /// The Trial over sheet is up while it is due; closing it marks it seen.
    private var trialOverShowing: Binding<Bool> {
        Binding(get: { model.trialOverDue }, set: { if !$0 { model.trialOverSeen() } })
    }

    private func header(wide: Bool) -> some View {
        HStack(alignment: .top) {
            Text(wide ? "Both flippers, go." : "Both\nflippers, go.")
                .font(wide ? .system(size: 36, weight: .black, design: .rounded) : .sw(.title))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            ThumbsArt(animated: false).frame(width: 72, height: 72)
        }
        .padding(.top, Theme.Space.l)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack {
                        Text("Speed test").font(.sw(.heading))
                        Spacer()
                        Chip("Soon")
                    }
                    Text("Measure yourself against Apple's keyboard. Until it arrives, practise with the keyboard here.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                    Button("Practice") { path.append(.practice) }
                        .buttonStyle(.small)
                }
            }
            proRow
        }
    }

    /// Where the person stands with Pro; opens the Pro screen.
    private var proRow: some View {
        Button { path.append(.pro) } label: {
            switch model.proStatus {
            case .trial:
                let days = model.trial.daysLeft(now: model.now)
                Row("Pro trial", subtitle: "\(days) day\(days == 1 ? "" : "s") left. Two-thumb typing, gestures, layouts.") {
                    ProBadge()
                }
            case .free:
                Row("Astrotype Pro", subtitle: "Two-thumb typing is resting. Keep it from $2.99 a month.") {
                    Text("See Pro ›").font(.system(.subheadline, design: .rounded, weight: .heavy)).foregroundStyle(Theme.muted)
                }
            case .pro:
                Row("Astrotype Pro", subtitle: "You're Pro. Both thumbs, every layout, every drill.") {
                    Chip("On", tint: Theme.mint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel("Drills")
            VStack(spacing: Theme.Space.s) {
                drill(1, "Two-letter swipes", "th, in, er, on")
                drill(2, "Switching thumbs", "Start left, finish right")
                drill(3, "Doubled letters", "A tap inside a swipe")
            }
            Text("Drills open with the speed test.")
                .font(.sw(.small)).foregroundStyle(Theme.muted).padding(.leading, Theme.Space.xs)
            SectionLabel("This week").padding(.top, Theme.Space.s)
            WeekDots(days: model.week.days.map { WeekDots.Day(id: $0.key, letter: $0.letter, done: $0.practised, isToday: $0.isToday) })
            Button { path.append(.settings) } label: {
                Row("Settings", subtitle: "Autospace, gestures, trails, sync") {
                    Text("Open ›").font(.system(.subheadline, design: .rounded, weight: .heavy)).foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Space.s)
        }
    }

    private func drill(_ number: Int, _ title: String, _ subtitle: String) -> some View {
        Card {
            HStack(spacing: Theme.Space.m) {
                NumberBadge(.number(number))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.body, design: .rounded, weight: .bold))
                    Text(subtitle).font(.sw(.small)).foregroundStyle(Theme.muted)
                }
            }
        }
        .opacity(0.6)
    }
}
