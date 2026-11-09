import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// Learn and practice (features/home-and-welcome): what used to sit on Home under Your
/// speed, on its own screen (Gabriel, 9 Nov 2026). Practice: Speed practice, the three
/// drills, Practice words, free typing and the week. Learn: the two-thumb lesson again,
/// and tips. Home's two tiles open it at their half.
struct LearnPracticeView: View {
    enum Part: Hashable { case practice, learn }

    var model: AppModel
    var part: Part
    @Binding var path: [HomeView.Route]

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Learn and practice").font(.sw(.title)).padding(.top, Theme.Space.s)
                        .accessibilityAddTraits(.isHeader)
                    Text("A few minutes a day makes two thumbs feel natural.")
                        .font(.sw(.body)).foregroundStyle(Theme.muted)

                    SectionLabel("Practice").padding(.top, Theme.Space.s).id(Part.practice)
                    SettingsGroup {
                        SettingsLink("Speed practice", subtitle: speedSubtitle, symbol: "stopwatch", tint: Theme.accent) {
                            path.append(.speedTest(.astrotype, nil))
                        }
                        ForEach(Drill.all) { drill in drillRow(drill) }
                        SettingsLink("Practice words", subtitle: "Words it missed, one more time", symbol: "textformat.abc", tint: Theme.right) {
                            path.append(.practiceWords)
                        }
                        SettingsLink("Just type", subtitle: "A field and the keyboard, nothing measured", symbol: "keyboard", tint: Theme.slate) {
                            path.append(.practice)
                        }
                    }
                    if !model.entitlement.allows(.drills) {
                        GroupFootnote("Drills are in Astrotype Pro.")
                    }

                    SectionLabel("This week").padding(.top, Theme.Space.s)
                    WeekDots(days: model.week.days.map { WeekDots.Day(id: $0.key, letter: $0.letter, done: $0.practised, isToday: $0.isToday) })

                    SectionLabel("Learn").padding(.top, Theme.Space.s).id(Part.learn)
                    SettingsGroup {
                        SettingsLink("The two-thumb lesson", subtitle: "Five words with thumb hints, from the start",
                                     symbol: "hand.raised.fingers.spread", tint: Theme.left) {
                            model.lessonOpened()
                            path.append(.lesson)
                        }
                        SettingsLink("Tips", subtitle: "Gestures, fixing a word, the 123 panel", symbol: "lightbulb", tint: Theme.sun) {
                            path.append(.tips)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                if part == .learn { reader.scrollTo(Part.learn, anchor: .top) }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var speedSubtitle: String {
        if let speed = model.everydaySpeed { return "Three sentences, against your everyday \(speed)" }
        return "Three sentences, timed"
    }

    /// A drill: ticked when done today; opens it, or Pro when drills are not allowed.
    private func drillRow(_ drill: Drill) -> some View {
        let allowed = model.entitlement.allows(.drills)
        let done = model.isDrillDone(drill.id)
        return Button {
            path.append(allowed ? .drill(drill.id) : .pro)
        } label: {
            HStack(spacing: Theme.Space.m) {
                NumberBadge(done ? .done : .number(drill.number))
                VStack(alignment: .leading, spacing: 2) {
                    Text(drill.title).font(.system(.body, design: .rounded, weight: .bold))
                    Text(drill.subtitle).font(.sw(.small)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if allowed {
                    Image(systemName: "chevron.right").font(.footnote.weight(.heavy)).foregroundStyle(Theme.muted)
                } else {
                    ProBadge()
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(drill.title), \(drill.subtitle)\(done ? ", done today" : "")\(allowed ? "" : ", in Astrotype Pro")")
    }
}

/// Short tips for the gestures people miss (Learn → Tips).
struct TipsView: View {
    private let tips: [(symbol: String, title: String, text: String)] = [
        ("arrow.left.and.right", "Slide on space", "Hold space a moment, then slide to move the cursor."),
        ("delete.left", "Swipe left on ⌫", "Deletes the whole last word."),
        ("hand.tap", "Hold a guess", "Hold a word in the bar to never suggest it, or to learn it."),
        ("pencil", "Fix an earlier word", "Tap a word you already wrote, and the bar offers its other guesses."),
        ("123.rectangle", "Hold 123", "Opens the keyboard's own settings: autospace, height, languages and more."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Tips").font(.sw(.title)).padding(.top, Theme.Space.s).accessibilityAddTraits(.isHeader)
                ForEach(tips, id: \.title) { tip in
                    Card {
                        HStack(alignment: .top, spacing: Theme.Space.m) {
                            IconTile(tip.symbol, tint: Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.title).font(.system(.body, design: .rounded, weight: .bold))
                                Text(tip.text).font(.sw(.small)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
