import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// One page of Settings (features/settings/FEATURE.md): its title, then section labels,
/// groups and footnotes. Shown pushed on a phone, or beside the main page on a wide
/// screen.
struct SettingsPageView: View {
    var page: SettingsPage
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(title).font(.sw(.title)).padding(.vertical, Theme.Space.s)
                    .accessibilityAddTraits(.isHeader)
                switch page {
                case .typing: TypingSettings(model: model, path: $path)
                case .languages: LanguagesSettings(model: model, path: $path)
                case .appearance: AppearanceSettings(model: model, path: $path)
                case .words: WordsSettings(model: model, path: $path)
                case .privacy: PrivacySettings(model: model, path: $path)
                case .about: AboutSettings()
                case .debug: DebugSettings(model: model)
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

    private var title: String {
        switch page {
        case .typing: "Typing"
        case .languages: "Languages"
        case .appearance: "Appearance"
        case .words: "Your words"
        case .privacy: "Privacy and sharing"
        case .about: "About"
        case .debug: "Debug"
        }
    }
}

/// What a touch does: two thumbs, autospace, how sure it must be of words, gestures.
private struct TypingSettings: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]

    var body: some View {
        SectionLabel("Words")
        SettingsGroup {
            SettingsRow("Two-thumb typing", subtitle: model.entitlement.allows(.twoThumbs)
                        ? "Taps and swipes from both thumbs, in one word"
                        : "In Astrotype Pro. One finger at a time until then.",
                        symbol: "hand.tap", tint: Theme.right) {
                if model.entitlement.allows(.twoThumbs) {
                    ProBadge()
                } else {
                    Button("See Pro") { path.append(.pro) }.buttonStyle(.small)
                }
            }
            SettingsToggle("Autospace", subtitle: "Puts a swiped word in after a pause", symbol: "space",
                           tint: Theme.left, isOn: $model.keyboardSettings.autospace)
            SettingsSlider(nil, value: $model.keyboardSettings.autospaceDelay, in: KeyboardSettings.delayRange, step: 0.1,
                           low: "Quick", high: "Relaxed",
                           valueText: "\(model.keyboardSettings.autospaceDelay.formatted(.number.precision(.fractionLength(1)))) s",
                           spokenValue: "\(model.keyboardSettings.autospaceDelay.formatted(.number.precision(.fractionLength(1)))) seconds",
                           accessibilityLabel: "Autospace wait")
                .opacity(model.keyboardSettings.autospace ? 1 : 0.45)
                .disabled(!model.keyboardSettings.autospace)
            SettingsToggle("Guess the next word", subtitle: "Likely next words in the bar after each word. A tap writes one.",
                           symbol: "text.append", tint: Theme.mint, isOn: $model.keyboardSettings.nextWords)
            SettingsSlider("Real words", value: $model.keyboardSettings.wordStrictness, in: 0...1, step: 0.01,
                           low: "As tapped", high: "Words only", valueText: percent(model.keyboardSettings.wordStrictness))
            SettingsSlider("Split words", value: $model.keyboardSettings.splitStrictness, in: 0...1, step: 0.01,
                           low: "Never", high: "Whenever it's sure", valueText: percent(model.keyboardSettings.splitStrictness))
        }
        GroupFootnote("Real words: how sure the keyboard must be before it swaps letters you tapped for a word. Split words: how sure before it puts a space into letters that read as two words, like textseparately, or takes out a space autospace put inside a word, like some thing.")

        SectionLabel("Gestures").padding(.top, Theme.Space.m)
        SettingsGroup {
            SettingsToggle("Slide on space", subtitle: "Move the cursor", symbol: "arrow.left.and.right",
                           tint: Theme.left, isOn: $model.keyboardSettings.spaceSlide)
            SettingsToggle("Swipe left on ⌫", subtitle: "Delete the last word", symbol: "delete.left",
                           tint: Theme.right, isOn: $model.keyboardSettings.backspaceSwipe)
        }
    }
}

/// The languages the keyboard types in (features/languages): a switch each, any one
/// free, two at once Pro, and a line when the trial ended with two on.
private struct LanguagesSettings: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]

    var body: some View {
        let allowsTwo = model.entitlement.allows(.twoLanguages)
        let active = model.activeLanguages
        if let off = model.languageOffWithoutPro {
            SettingsGroup {
                SettingsRow("\(Language.names[off] ?? off) is off", subtitle: "Pro types in both at once.",
                            symbol: "star.fill", tint: Theme.sun) {
                    Button("See Pro") { path.append(.pro) }.buttonStyle(.small)
                }
            }
        }
        SettingsGroup {
            ForEach(Language.bundledCodes, id: \.self) { code in
                SettingsToggle(Language.names[code] ?? code, subtitle: Language.englishNames[code],
                               symbol: "character.bubble", tint: code == "en" ? Theme.left : Theme.right,
                               isOn: Binding(get: { active.contains(code) }, set: { model.setLanguage(code, on: $0) }))
                    .disabled(active == [code])
            }
        }
        GroupFootnote(allowsTwo
                      ? "With two on, the first word can be either. Once a word shows which language you're writing, the rest of the sentence keeps to it. No switching."
                      : "One language at a time: turning one on turns the other off. Pro types in two at once.")
        if allowsTwo, active.count > 1 {
            SettingsGroup {
                SettingsToggle("Mix in one sentence", subtitle: "Guess from both languages for every word",
                               symbol: "shuffle", tint: Theme.sun, isOn: $model.keyboardSettings.mixesLanguages)
            }
            .padding(.top, Theme.Space.m)
            GroupFootnote("For when you switch languages mid-sentence. Off keeps each sentence to one language, so words from the other one don't sneak in.")
        }
        if !allowsTwo, model.languageOffWithoutPro == nil {
            Button("See Pro") { path.append(.pro) }.buttonStyle(.small)
        }
        GroupFootnote("Hold a, e, i, o, u or n for its accents, and ? or ! for ¿ and ¡. You can also just swipe the plain letters: the accents go in by themselves.")
            .padding(.top, Theme.Space.s)
    }
}

/// How the keyboard looks and feels: its height, the guesses bar, trails, haptics, the
/// underline, and the layout on wide screens.
private struct AppearanceSettings: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]

    var body: some View {
        SectionLabel("Size")
        SettingsGroup {
            KeyboardPreview(heightScale: model.keyboardSettings.heightScale, showsBar: model.keyboardSettings.showsBar)
            SettingsSlider("Height", value: $model.keyboardSettings.keyboardHeight, in: KeyboardSettings.heightRange, step: 0.05,
                           low: "Shorter", high: "Taller", valueText: percent(model.keyboardSettings.heightScale))
            SettingsToggle("Guesses bar", subtitle: "Above the keys on a phone. Wide screens show them beside the keys.",
                           symbol: "rectangle.topthird.inset.filled", tint: Theme.left, isOn: $model.keyboardSettings.showsBar)
        }
        GroupFootnote("At 100% every key sits where Apple's does. The guesses bar adds to the height.")

        SectionLabel("Look and feel").padding(.top, Theme.Space.m)
        SettingsGroup {
            SettingsToggle("Trails and flashes", subtitle: "Show which thumb did what. Off saves battery.", symbol: "scribble",
                           tint: Theme.right, isOn: $model.keyboardSettings.trails)
            SettingsToggle("Haptics", subtitle: "A soft tap on each key. In other apps this needs Full Access.",
                           symbol: "iphone.radiowaves.left.and.right", tint: Theme.slate, isOn: $model.keyboardSettings.haptics)
            SettingsToggle("Underline the open word", subtitle: "In other apps. Off keeps spaces right in every app.",
                           symbol: "underline", tint: Theme.slate, isOn: $model.keyboardSettings.underlinesWord)
        }

        SectionLabel("Wide screens", pro: true).padding(.top, Theme.Space.m)
        SettingsGroup {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SettingsRow("Layout", subtitle: "On the iPhone Duo's inner screen: one keyboard across, or a half under each thumb.",
                            symbol: "rectangle.split.2x1", tint: Theme.sun)
                Picker("Layout on wide screens", selection: $model.keyboardSettings.splitOnWide) {
                    Text("Full").tag(false)
                    Text("Split").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(!model.entitlement.allows(.splitLayout))
                .padding(.horizontal, 14).padding(.bottom, Theme.Space.m)
            }
            if model.keyboardSettings.splitOnWide && model.entitlement.allows(.splitLayout) {
                SettingsToggle("Extra letters on split", subtitle: "Y H B on the left, T F C on the right, for swiping across. Off is Apple's split.",
                               isOn: $model.keyboardSettings.splitExtraLetters)
            }
            if !model.entitlement.allows(.splitLayout) {
                SettingsRow("Split is in Astrotype Pro") {
                    Button("See Pro") { path.append(.pro) }.buttonStyle(.small)
                }
            }
        }
    }
}

/// What the keyboard remembers: learned words, and what it learns from the person.
private struct WordsSettings: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]
    @State private var confirmingForget = false

    var body: some View {
        SettingsGroup {
            SettingsLink("Learned words", subtitle: learnedSubtitle, symbol: "book.closed", tint: Theme.mint,
                         value: "\(model.learnedWords.recent.count)") { path.append(.learnedWords) }
            SettingsLink("Words it missed", subtitle: missedSubtitle, symbol: "pencil", tint: Theme.mint,
                         value: "\(model.missedWords.count)") { path.append(.missedWords) }
            SettingsToggle("Learns from you", subtitle: personalSubtitle, symbol: "brain", tint: Theme.mint,
                           isOn: $model.learnsFromYou)
        }
        .onAppear { model.reloadMissed() }
        GroupFootnote("Your word pairs and where your thumbs land, kept on this phone. With Full Access they follow you to your other devices.")

        SettingsGroup {
            Button { confirmingForget = true } label: {
                SettingsRow("Forget what it learned", subtitle: "Word pairs, thumb spots and fixed swipes, on every device. Learned words stay.",
                            titleColor: Theme.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Theme.Space.m)
        .confirmationDialog("Forget what the keyboard learned from you?", isPresented: $confirmingForget, titleVisibility: .visible) {
            Button("Forget everything", role: .destructive) { model.forgetPersonal() }
        } message: {
            Text("Your word pairs, thumb positions and the swipes you fixed go, on this phone and your other devices. Your learned words stay.")
        }
    }

    private var missedSubtitle: String {
        model.missedWords.isEmpty ? "Swipes you fixed with Not it? in the bar" : "Swipes you fixed, and what it wrote"
    }

    private var learnedSubtitle: String {
        model.learnedWords.recent.isEmpty ? "Words you peck out that it doesn't know end up here" : "Words it learned from you"
    }

    private var personalSubtitle: String {
        guard model.learnsFromYou else { return "Off. It learns nothing and uses nothing it learned." }
        let summary = model.personalSummary
        guard summary.words > 0 || summary.mappedKeys > 0 else {
            return model.isFullAccessOn ? "Nothing yet. It learns as you type in other apps." : "It learns as you type in other apps."
        }
        let pairs = "\(summary.pairs.formatted()) word pair\(summary.pairs == 1 ? "" : "s")"
        return pairs + (summary.thumbsMapped ? ", thumbs mapped" : ", learning your thumbs")
    }
}

/// The few things the person can choose to share, and what they look like before they go.
private struct PrivacySettings: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]
    @State private var shareUsage = Telemetry.isEnabled

    var body: some View {
        Text("Nothing you type in other apps is ever sent. These are the few things you can choose to share.")
            .font(.sw(.body)).foregroundStyle(Theme.muted)
            .padding(.horizontal, Theme.Space.xs)

        SectionLabel("Crash reports").padding(.top, Theme.Space.m)
        SettingsGroup {
            SettingsToggle("Share anonymous usage data", subtitle: "Crashes from the app and the keyboard, and counts like how many people turn the keyboard on. Never anything you type.",
                           symbol: "chart.bar", tint: Theme.slate, isOn: $shareUsage)
        }
        .onChange(of: shareUsage) { Telemetry.isEnabled = shareUsage }

        SectionLabel("Help tune the keyboard").padding(.top, Theme.Space.m)
        SettingsGroup {
            SettingsToggle("Send practice sessions", subtitle: "Words from speed tests and drills here, with the paths of your thumbs",
                           symbol: "paperplane", tint: Theme.left, isOn: $model.sharePractice)
            SettingsToggle("Include corrections", subtitle: correctionsSubtitle, symbol: "pencil", tint: Theme.right,
                           isOn: $model.shareCorrections)
                .disabled(!model.sharePractice || !model.isFullAccessOn)
                .opacity(model.sharePractice && model.isFullAccessOn ? 1 : 0.5)
            SettingsLink("What gets shared", subtitle: sharedSubtitle, symbol: "eye", tint: Theme.mint) { path.append(.sharing) }
            SettingsLink("Practice words", subtitle: "Common words and short phrases, one at a time, no timer",
                         symbol: "text.alignleft", tint: Theme.mint) { path.append(.practiceWords) }
        }
        GroupFootnote("Sent one word at a time with no name attached, so nobody can read a sentence back.")
    }

    private var correctionsSubtitle: String {
        if !model.isFullAccessOn { return "The word you wrote and the one you meant. Needs Full Access." }
        if !model.sharePractice { return "The word you wrote and the one you meant. Turn on practice sessions first." }
        return "The word you wrote and the one you meant, never the text around them"
    }

    private var sharedSubtitle: String {
        switch model.pendingShared.count {
        case 0: return "Every field of what we'd send, before it goes"
        case 1: return "1 word waiting. See it before it goes."
        case let count: return "\(count) words waiting. See them before they go."
        }
    }
}

/// The version and credits.
private struct AboutSettings: View {
    var body: some View {
        SettingsGroup {
            SettingsRow("Version", subtitle: DeviceInfo.appVersion, symbol: "info.circle", tint: Theme.ice)
            SettingsRow("Word pairs", subtitle: "Built from Tatoeba's English and Spanish sentences (tatoeba.org, CC BY 2.0 FR)",
                        symbol: "text.quote", tint: Theme.ice)
            SettingsRow("Word lists", subtitle: "From wordfreq by Robyn Speer (CC BY-SA 4.0)",
                        symbol: "text.book.closed", tint: Theme.ice)
        }
    }
}

private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
private func percent(_ value: CGFloat) -> String { percent(Double(value)) }
