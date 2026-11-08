import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// DESIGN.md screen 5: "Both flippers, go." Your speed (features/typing-speed) and the Pro row on the
/// left, drills, the week and Settings on the right; one column on a phone, two on the
/// wide size. A sun-yellow banner leads back to setup while the keyboard is off. The
/// Trial over sheet comes up here once, on the first launch after the trial ends.
struct HomeView: View {
    var model: AppModel
    @State private var path: [Route] = []

    enum Route: Hashable {
        case practice, practiceWords, settings, learnedWords, neverSuggest, textReplacements, wordPairs, missedWords, sharing, turnOn, sync, pro
        /// A page under Settings → Appearance (features/customization).
        case appearance(AppearancePage)
        case speedTest(PracticeKeyboard, UInt64?)
        /// Your speed (features/typing-speed).
        case speed
        /// A page of Settings opened from elsewhere (Your speed → Privacy and sharing).
        case settingsPage(SettingsPage)
        case drill(Drill.ID)
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
                case .neverSuggest: NeverSuggestView(model: model)
                case .textReplacements: TextReplacementsView(model: model)
                case .wordPairs: WordPairsView(model: model)
                case .missedWords: MissedWordsView(model: model)
                case .sharing: SharingView(model: model)
                case .practiceWords: PracticeWordsView(model: model)
                case .turnOn: TurnOnView(model: model, inSetup: false)
                case .sync: SyncView(model: model, inSetup: false)
                case .pro: ProView(model: model)
                case .appearance(let page): AppearancePageView(page: page, model: model, path: $path)
                case .speedTest(let keyboard, let seed): SpeedTestView(model: model, keyboard: keyboard, seed: seed, path: $path)
                case .drill(let id): DrillView(model: model, drill: Drill.named(id), path: $path)
                case .speed: SpeedHistoryView(model: model, path: $path)
                case .settingsPage(let page): SettingsPageView(page: page, model: model, path: $path)
                }
            }
            // The keyboard's "Open Astrotype" (astrotype://settings) lands on Settings.
            .onOpenURL { url in
                if url.scheme == "astrotype", url.host == "settings" { path = [.settings] }
            }
            .sheet(isPresented: trialOverShowing) {
                TrialOverView(model: model) { path.append(.pro) }
            }
            .sheet(item: milestoneShowing) { milestone in
                MilestoneView(milestone: milestone)
            }
        }
        .tint(Theme.accent)
    }

    /// The next milestone's sheet, while one is due and Home is on top; closing it
    /// marks it seen.
    private var milestoneShowing: Binding<Milestone?> {
        Binding(get: { path.isEmpty && !model.trialOverDue ? model.pendingMilestone : nil },
                set: { if $0 == nil, let shown = model.pendingMilestone { model.milestoneSeen(shown) } })
    }

    /// The Trial over sheet is up while it is due; closing it marks it seen.
    private var trialOverShowing: Binding<Bool> {
        Binding(get: { model.trialOverDue }, set: { if !$0 { model.trialOverSeen() } })
    }

    private func header(wide: Bool) -> some View {
        HStack(alignment: .top) {
            if wide {
                Text("Both flippers, go.").displayTitleFont().fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Both\nflippers, go.").font(.sw(.title)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            ThumbsArt(animated: false).frame(width: 72, height: 72)
        }
        .padding(.top, Theme.Space.l)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            // Your speed leads Home (features/typing-speed): the everyday speed, and
            // practice that measures you against it.
            SpeedCard(model: model, open: { path.append(.speed) },
                      practice: { path.append(.speedTest(.astrotype, nil)) },
                      drills: { path.append(.practice) },
                      turnOn: { path.append(.turnOn) })
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
                ForEach(Drill.all) { drill in
                    drillRow(drill)
                }
            }
            if !model.entitlement.allows(.drills) {
                Text("Drills are in Astrotype Pro.")
                    .font(.sw(.small)).foregroundStyle(Theme.muted).padding(.leading, Theme.Space.xs)
            }
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

    /// A drill: ticked when finished today; opens the drill, or the Pro screen when
    /// drills are not allowed.
    private func drillRow(_ drill: Drill) -> some View {
        let allowed = model.entitlement.allows(.drills)
        return Button {
            path.append(allowed ? .drill(drill.id) : .pro)
        } label: {
            Card {
                HStack(spacing: Theme.Space.m) {
                    NumberBadge(model.isDrillDone(drill.id) ? .done : .number(drill.number))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(drill.title).font(.system(.body, design: .rounded, weight: .bold))
                        Text(drill.subtitle).font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if allowed {
                        Text("›").font(.system(.body, design: .rounded, weight: .black)).foregroundStyle(Theme.accent)
                    } else {
                        ProBadge()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(drill.title), \(drill.subtitle)\(model.isDrillDone(drill.id) ? ", done today" : "")\(allowed ? "" : ", in Astrotype Pro")")
    }
}
