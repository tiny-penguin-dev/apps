import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// Home (features/home-and-welcome): "Astrotype", the Your speed card with Practice and
/// learn in it, the Your keyboard card (themes, effects, height), the everyday settings
/// (Typing, Languages, Your words), then Pro and Settings,
/// with the practice keyboard docked at the bottom to try the look on. One column on a
/// phone; on the wide size Your speed, Pro and Settings on the left and Your keyboard on
/// the right. A sun-yellow banner leads back to setup while the keyboard is off. The
/// Trial over sheet comes up here once, on the first launch after the trial ends.
struct HomeView: View {
    var model: AppModel
    @State private var path: [Route] = []
    /// The dock was left open (Gabriel, 9 Nov 2026: show it or tuck it away).
    @AppStorage("home.keyboardShown") private var dockShown = true
    @State private var dock: KeyboardSession?

    enum Route: Hashable {
        case practice, practiceWords, settings, learnedWords, neverSuggest, textReplacements, wordPairs, missedWords, sharing, turnOn, sync, pro
        /// A page under Settings → Appearance (features/customization).
        case appearance(AppearancePage)
        case speedTest(PracticeKeyboard, UInt64?)
        /// Your speed (features/typing-speed).
        case speed
        /// The weekly leaderboards (features/leaderboards).
        case leaderboard
        /// A page of Settings opened from elsewhere (Your speed → Privacy and sharing).
        case settingsPage(SettingsPage)
        case drill(Drill.ID)
        /// Learn and practice, at one of its halves (features/home-and-welcome).
        case learnPractice(LearnPracticeView.Part)
        /// The two-thumb lesson again, from Learn.
        case lesson
        case tips
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
                                VStack(spacing: Theme.Space.l) {
                                    leftColumn
                                    everydaySettings
                                    accountRows
                                }
                                .frame(maxWidth: .infinity)
                                keyboardColumn.frame(maxWidth: .infinity)
                            }
                        } else {
                            leftColumn
                            keyboardColumn
                            everydaySettings
                            accountRows
                        }
                    }
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.bottom, Theme.Space.xl)
                    .frame(maxWidth: wide ? 1100 : 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.never)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                KeyboardDock(model: model, shown: $dockShown, active: path.isEmpty && !sheetUp) { dock = $0 }
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
                case .leaderboard: LeaderboardView(model: model, path: $path)
                case .settingsPage(let page): SettingsPageView(page: page, model: model, path: $path)
                case .learnPractice(let part): LearnPracticeView(model: model, part: part, path: $path)
                case .lesson: TryItView(model: model, inSetup: false).toolbar(.hidden, for: .navigationBar)
                case .tips: TipsView()
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
        .overlay {
            // Setup just finished: a little party, once.
            if model.arrivedFromSetup {
                Confetti()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .task {
                        try? await Task.sleep(for: .seconds(2.5))
                        model.arrivalCelebrated()
                    }
            }
        }
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

    /// Just the name (Gabriel, 9 Nov 2026: "it's fine if it just says Astrotype").
    private func header(wide: Bool) -> some View {
        HStack(alignment: .center) {
            Text("Astrotype")
                .font(.sw(.title))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            ThumbsArt(animated: false).frame(width: 56, height: 56)
        }
        .padding(.top, Theme.Space.l)
    }

    /// A sheet is over Home: the dock's keys stay down.
    private var sheetUp: Bool { model.trialOverDue || (path.isEmpty && model.pendingMilestone != nil) }

    private var leftColumn: some View {
        // Your speed leads Home (features/typing-speed): one card with the everyday speed,
        // Practice for speed, and the way into Practice and learn.
        SpeedCard(model: model, open: { path.append(.speed) },
                  practice: { path.append(.speedTest(.astrotype, nil)) },
                  learnAndPractice: { path.append(.learnPractice(.practice)) },
                  turnOn: { path.append(.turnOn) })
    }

    private var keyboardColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel("Your keyboard")
            YourKeyboardCard(model: model, moreStyling: { path.append(.settingsPage(.appearance)) },
                             openPro: { path.append(.pro) },
                             played: playOnDock)
        }
    }

    /// Plays the picked effect on the docked keys, once the dock has the new settings.
    private func playOnDock() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { dock?.keyboard.surface.playBurst() }
    }

    /// The everyday settings, on Home (Gabriel, 9 Nov 2026: Settings is for the more
    /// serious things). Dictation lives inside Typing.
    private var everydaySettings: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel("Typing")
            SettingsGroup {
                SettingsLink("Typing", subtitle: "Autospace, real words, gestures, dictation", symbol: "keyboard", tint: Theme.right) {
                    path.append(.settingsPage(.typing))
                }
                SettingsLink("Languages", subtitle: languagesSubtitle, symbol: "character.bubble", tint: Theme.sun) {
                    path.append(.settingsPage(.languages))
                }
                SettingsLink("Your words", subtitle: wordsSubtitle, symbol: "text.book.closed", tint: Theme.mint) {
                    path.append(.settingsPage(.words))
                }
            }
        }
    }

    private var languagesSubtitle: String {
        model.activeLanguages.map { Language.names[$0] ?? $0 }.joined(separator: ", ")
    }

    private var wordsSubtitle: String {
        let count = model.learnedWords.recent.count
        return "\(count) learned · learning \(model.learnsFromYou ? "on" : "off")"
    }

    private var accountRows: some View {
        VStack(spacing: Theme.Space.s) {
            proRow
            Button { path.append(.settings) } label: {
                Row("Settings", subtitle: "iCloud sync, privacy, about") {
                    Text("Open ›").font(.system(.subheadline, design: .rounded, weight: .heavy)).foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)
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
}
