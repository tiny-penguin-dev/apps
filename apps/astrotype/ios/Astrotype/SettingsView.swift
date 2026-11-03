import AstrotypeCore
import AstrotypeUI
import StoreKit
import SwiftUI

/// DESIGN.md screen 9: typing (two thumbs, autospace, the learned words), gestures,
/// layout, look, the keyboard's status, sync, Pro, privacy and the version. Pro rows
/// carry the PRO badge and lead to the Pro screen when the trial is over.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]
    @State private var shareUsage = Telemetry.isEnabled
    @State private var managing = false
    @State private var restoring = false
    @State private var restoreNote: String?
    @State private var confirmingForget = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Settings").font(.sw(.title)).padding(.top, Theme.Space.s)

                SectionLabel("Typing")
                Row("Two-thumb typing", subtitle: model.entitlement.allows(.twoThumbs)
                    ? "On. Taps and swipes from both thumbs, mixed in one word."
                    : "In Astrotype Pro. One finger at a time until then.") {
                    if model.entitlement.allows(.twoThumbs) {
                        ProBadge()
                    } else {
                        Button("See Pro") { path.append(.pro) }.buttonStyle(.small)
                    }
                }
                Row("Autospace", subtitle: "Write a swiped word after a short pause") {
                    Toggle("Autospace", isOn: $model.keyboardSettings.autospace).labelsHidden().tint(Theme.mint)
                }
                Card {
                    HStack(spacing: Theme.Space.m) {
                        Text("Quick").font(.sw(.small)).foregroundStyle(Theme.muted)
                        Slider(value: $model.keyboardSettings.autospaceDelay,
                               in: KeyboardSettings.delayRange, step: 0.1)
                            .tint(Theme.accent)
                            .accessibilityLabel("Autospace delay")
                            .accessibilityValue("\(model.keyboardSettings.autospaceDelay, specifier: "%.1f") seconds")
                        Text("Relaxed").font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                }
                .opacity(model.keyboardSettings.autospace ? 1 : 0.5)
                .disabled(!model.keyboardSettings.autospace)
                Row("Real words", subtitle: "How sure the keyboard must be of a real word before it puts one in for letters you tapped. At 100% it only ever types real words.") {
                    Text("\(Int((model.keyboardSettings.wordStrictness * 100).rounded()))%")
                        .font(.sw(.heading)).monospacedDigit()
                }
                Card {
                    HStack(spacing: Theme.Space.m) {
                        Text("As tapped").font(.sw(.small)).foregroundStyle(Theme.muted)
                        Slider(value: $model.keyboardSettings.wordStrictness, in: 0...1, step: 0.01)
                            .tint(Theme.accent)
                            .accessibilityLabel("Real words")
                            .accessibilityValue("\(Int((model.keyboardSettings.wordStrictness * 100).rounded())) percent")
                        Text("Words only").font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                }
                Row("Split words", subtitle: "How sure the keyboard must be before it puts a space into letters that read as two words, like textseparately. At 0% it never splits.") {
                    Text("\(Int((model.keyboardSettings.splitStrictness * 100).rounded()))%")
                        .font(.sw(.heading)).monospacedDigit()
                }
                Card {
                    HStack(spacing: Theme.Space.m) {
                        Text("Never").font(.sw(.small)).foregroundStyle(Theme.muted)
                        Slider(value: $model.keyboardSettings.splitStrictness, in: 0...1, step: 0.01)
                            .tint(Theme.accent)
                            .accessibilityLabel("Split words")
                            .accessibilityValue("\(Int((model.keyboardSettings.splitStrictness * 100).rounded())) percent")
                        Text("Whenever it's sure").font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                }
                Row("Learned words", subtitle: learnedWordsSubtitle) {
                    Button("Open") { path.append(.learnedWords) }.buttonStyle(.small)
                }
                Row("Learns from you", subtitle: "Your word pairs and where your thumbs land, kept on this phone.") {
                    Toggle("Learns from you", isOn: $model.learnsFromYou).labelsHidden().tint(Theme.mint)
                }
                HStack(spacing: Theme.Space.m) {
                    Text(personalSubtitle).font(.sw(.small)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Forget everything") { confirmingForget = true }
                        .buttonStyle(.ghost)
                }
                .padding(.horizontal, Theme.Space.xs)
                .confirmationDialog("Forget what the keyboard learned from you?", isPresented: $confirmingForget, titleVisibility: .visible) {
                    Button("Forget everything", role: .destructive) { model.forgetPersonal() }
                } message: {
                    Text("Your word pairs and thumb positions go, on this phone and your other devices. Your learned words stay.")
                }

                SectionLabel("Gestures").padding(.top, Theme.Space.s)
                Row("Slide on space", subtitle: "Move the cursor") {
                    Toggle("Slide on space", isOn: $model.keyboardSettings.spaceSlide).labelsHidden().tint(Theme.mint)
                }
                Row("Swipe left on ⌫", subtitle: "Delete the last word") {
                    Toggle("Swipe left on backspace", isOn: $model.keyboardSettings.backspaceSwipe).labelsHidden().tint(Theme.mint)
                }

                SectionLabel("Layout").padding(.top, Theme.Space.s)
                Row("Keyboard height", subtitle: "At 100% every key sits where Apple's keyboard has it, so your thumbs already know the way. The guesses bar adds to it.") {
                    Text("\(Int((model.keyboardSettings.heightScale * 100).rounded()))%")
                        .font(.sw(.heading)).monospacedDigit()
                }
                Card {
                    HStack(spacing: Theme.Space.m) {
                        Text("Shorter").font(.sw(.small)).foregroundStyle(Theme.muted)
                        Slider(value: $model.keyboardSettings.keyboardHeight, in: KeyboardSettings.heightRange, step: 0.05)
                            .tint(Theme.accent)
                            .accessibilityLabel("Keyboard height")
                            .accessibilityValue("\(Int((model.keyboardSettings.heightScale * 100).rounded())) percent")
                        Text("Taller").font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                }
                Row("Underline the word you're typing", subtitle: "In other apps. Off types it as plain text, which keeps spaces where they belong in every app.") {
                    Toggle("Underline the word you're typing", isOn: $model.keyboardSettings.underlinesWord).labelsHidden().tint(Theme.mint)
                }
                Row("Guesses bar", subtitle: "Above the keys on a phone. Off gives the keys its room. On a wide screen the guesses sit beside the keys.") {
                    Toggle("Guesses bar", isOn: $model.keyboardSettings.showsBar).labelsHidden().tint(Theme.mint)
                }
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack {
                            Text("Layout on wide screens").font(.system(.body, design: .rounded, weight: .bold))
                            Spacer()
                            ProBadge()
                        }
                        Picker("Layout on wide screens", selection: $model.keyboardSettings.splitOnWide) {
                            Text("Full").tag(false)
                            Text("Split").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!model.entitlement.allows(.splitLayout))
                        if model.keyboardSettings.splitOnWide && model.entitlement.allows(.splitLayout) {
                            Toggle("Extra letters on split", isOn: $model.keyboardSettings.splitExtraLetters)
                                .tint(Theme.mint)
                            Text("One more letter past the middle on each half (Y H B on the left, T F C on the right), for swiping across. Off is Apple's split.")
                                .font(.sw(.small)).foregroundStyle(Theme.muted)
                        }
                        if model.entitlement.allows(.splitLayout) {
                            Text("On the iPhone Duo's inner screen: one keyboard across, or a half under each thumb.")
                                .font(.sw(.small)).foregroundStyle(Theme.muted)
                        } else {
                            HStack {
                                Text("Split is in Astrotype Pro.").font(.sw(.small)).foregroundStyle(Theme.muted)
                                Spacer()
                                Button("See Pro") { path.append(.pro) }.buttonStyle(.small)
                            }
                        }
                    }
                }

                SectionLabel("Look and feel").padding(.top, Theme.Space.s)
                Row("Trails and flashes", subtitle: "Show which thumb did what. Off saves battery.") {
                    Toggle("Trails and flashes", isOn: $model.keyboardSettings.trails).labelsHidden().tint(Theme.mint)
                }
                Row("Haptics", subtitle: "A soft tap on each key, a firmer one on each word. In other apps this needs Full Access.") {
                    Toggle("Haptics", isOn: $model.keyboardSettings.haptics).labelsHidden().tint(Theme.mint)
                }

                SectionLabel("Keyboard").padding(.top, Theme.Space.s)
                Row("Astrotype keyboard", subtitle: model.isKeyboardOn ? "On. Hold 🌐 in any app to pick it." : "Not on yet.") {
                    if model.isKeyboardOn {
                        Chip("On", tint: Theme.mint)
                    } else {
                        Button("Turn on") { path.append(.turnOn) }.buttonStyle(.small)
                    }
                }
                Row("iCloud sync", subtitle: syncSubtitle) {
                    switch model.syncState {
                    case .needsFullAccess:
                        Button("Set up") { path.append(.sync) }.buttonStyle(.small)
                    case .syncing:
                        ProgressView().tint(Theme.accent)
                    case .idle:
                        Button("Sync now") { model.sync() }.buttonStyle(.small)
                    case .failed:
                        Button("Retry") { model.sync() }.buttonStyle(.small)
                    }
                }
                Text("With Full Access, the keyboard follows these settings and your words sync over iCloud. Without it, the keyboard in other apps keeps its own settings, under a held 123.")
                    .font(.sw(.small)).foregroundStyle(Theme.muted).padding(.horizontal, Theme.Space.xs)

                SectionLabel("Astrotype Pro").padding(.top, Theme.Space.s)
                Row("Astrotype Pro", subtitle: proSubtitle) {
                    if model.isSubscribed {
                        Button("Manage") { managing = true }.buttonStyle(.small)
                    } else {
                        Button("See Pro") { path.append(.pro) }.buttonStyle(.small)
                    }
                }
                Row("Restore purchases", subtitle: restoreNote ?? "Bought Pro on another device, or before a reinstall? Bring it here.") {
                    if restoring {
                        ProgressView().tint(Theme.accent)
                    } else {
                        Button("Restore") { restore() }.buttonStyle(.small)
                    }
                }

                SectionLabel("Privacy").padding(.top, Theme.Space.s)
                Row("Share anonymous usage data", subtitle: "Crash reports from the app and the keyboard, and counts like how many people turn the keyboard on. Never anything you type.") {
                    Toggle("Share anonymous usage data", isOn: $shareUsage).labelsHidden().tint(Theme.mint)
                        .onChange(of: shareUsage) { Telemetry.isEnabled = shareUsage }
                }
                Row("Send practice sessions", subtitle: "The words from speed tests and drills here in the app, one at a time with the paths of your thumbs, to tune the keyboard. No sentences, no name attached.") {
                    Toggle("Send practice sessions", isOn: $model.sharePractice).labelsHidden().tint(Theme.mint)
                }
                Row("Include corrections from other apps", subtitle: correctionsSubtitle) {
                    Toggle("Include corrections from other apps", isOn: $model.shareCorrections).labelsHidden().tint(Theme.mint)
                        .disabled(!model.sharePractice || !model.isFullAccessOn)
                }
                Row("What gets shared", subtitle: sharedSubtitle) {
                    Button("See") { path.append(.sharing) }.buttonStyle(.small)
                }
                Row("Practice words", subtitle: "Common words and short phrases, one at a time, no timer. With sharing on, they help tune the keyboard.") {
                    Button("Start") { path.append(.practiceWords) }.buttonStyle(.small)
                }

                if Flags.handwritingPad {
                    HandwritingSettings()
                }

                SectionLabel("About").padding(.top, Theme.Space.s)
                Row("Version", subtitle: DeviceInfo.appVersion)
                Row("Word pairs", subtitle: "Built from Tatoeba's English sentences (tatoeba.org, CC BY 2.0 FR)")
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
        .manageSubscriptionsSheet(isPresented: $managing)
        .onAppear {
            model.refreshKeyboardStatus()
            model.reloadWords()
            model.reloadShared()
        }
    }

    private var proSubtitle: String {
        switch model.proStatus {
        case .pro: return "On. Both thumbs, every layout, every drill."
        case .trial:
            let days = model.trial.daysLeft(now: model.now)
            return "Trial · \(days) day\(days == 1 ? "" : "s") left. $19.99 a year or $2.99 a month after."
        case .free: return "The trial is over. Two-thumb typing, split layouts and drills are in Pro."
        }
    }

    private func restore() {
        restoring = true
        restoreNote = nil
        Task { @MainActor in
            do {
                let found = try await model.restorePurchases()
                restoreNote = found ? "Found it. You're Pro." : "No Pro subscription on this Apple Account."
            } catch {
                restoreNote = "I couldn't reach the App Store. Try again in a moment."
            }
            restoring = false
        }
    }

    private var learnedWordsSubtitle: String {
        let count = model.learnedWords.recent.count
        switch count {
        case 0: return "Words you peck out that the keyboard doesn't know end up here."
        case 1: return "1 word the keyboard learned from you."
        default: return "\(count) words the keyboard learned from you."
        }
    }

    private var correctionsSubtitle: String {
        if !model.isFullAccessOn { return "The word you wrote and the word you meant, never the text around them. Needs Full Access." }
        if !model.sharePractice { return "The word you wrote and the word you meant, never the text around them. Turn on Send practice sessions first." }
        return "The word you wrote and the word you meant. Never the text around them."
    }

    private var sharedSubtitle: String {
        let count = model.pendingShared.count
        switch count {
        case 0: return "Every field of what we'd send, before it goes."
        case 1: return "1 word waiting. See it before it goes."
        default: return "\(count) words waiting. See them before they go."
        }
    }

    private var personalSubtitle: String {
        guard model.learnsFromYou else { return "Off. The keyboard learns nothing and uses nothing it learned." }
        let summary = model.personalSummary
        guard summary.words > 0 || summary.mappedKeys > 0 else {
            return model.isFullAccessOn
                ? "Nothing yet. It learns as you type in other apps."
                : "It learns as you type in other apps. With Full Access you can see what it knows here."
        }
        var parts = ["\(summary.pairs.formatted()) word pair\(summary.pairs == 1 ? "" : "s")"]
        parts.append(summary.thumbsMapped ? "thumbs mapped" : "learning your thumbs")
        return parts.joined(separator: ", ") + "."
    }

    private var syncSubtitle: String {
        switch model.syncState {
        case .needsFullAccess:
            return "Needs Full Access in Settings. Then your words and settings follow you to your other devices."
        case .syncing:
            return "Syncing…"
        case .idle(let last):
            guard let last else { return "On. Nothing to sync yet." }
            return "On. Last synced \(last.formatted(.relative(presentation: .named)))."
        case .failed(let message):
            return message
        }
    }
}

/// The v1 handwriting pad and its training loop, kept behind `Flags.handwritingPad`.
struct HandwritingSettings: View {
    @Environment(RecognitionService.self) private var recognition
    @Environment(SampleStore.self) private var samples
    @Environment(SampleUploader.self) private var uploader
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        SectionLabel("Handwriting").padding(.top, Theme.Space.s)
        NavigationLink { TryView() } label: {
            Row("Try the handwriting pad", subtitle: "Write each letter on top of the last")
        }
        NavigationLink { TrainView() } label: {
            Row("Write training phrases", subtitle: recognition.statusText)
        }
        Row("Recordings", subtitle: "\(samples.count.formatted()) · \(samples.pendingCount) waiting to upload") {
            Toggle("Upload to help train Astrotype", isOn: Bindable(uploader).isEnabled).labelsHidden().tint(Theme.mint)
        }
        HStack(spacing: Theme.Space.m) {
            Button("Upload now") { uploader.upload() }
                .buttonStyle(.small)
                .disabled(!uploader.isEnabled || samples.pendingCount == 0 || uploader.isUploading)
            Button("Export samples…") {
                do { exportURL = try samples.exportArchive() } catch { exportError = error.localizedDescription }
            }
            .buttonStyle(.ghost)
            .disabled(samples.count == 0)
        }
        Text((uploader.status.map { $0 + "\n" } ?? "")
             + "Uploads go to Astrotype's iCloud database: the strokes you write and the words they spell, with no name or account attached. Nothing you type on the keyboard is sent.")
            .font(.sw(.small)).foregroundStyle(Theme.muted).padding(.horizontal, Theme.Space.xs)
            .sheet(item: $exportURL) { url in ShareSheet(items: [url]) }
            .alert("Couldn't export", isPresented: .constant(exportError != nil)) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
