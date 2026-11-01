import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// DESIGN.md screen 9, the rows that exist so far: typing and the learned words,
/// gestures, layout, look, the keyboard's status, sync, privacy and the version.
/// Two-thumb typing and Pro come with their phases.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]
    @State private var shareUsage = Telemetry.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Settings").font(.sw(.title)).padding(.top, Theme.Space.s)

                SectionLabel("Typing")
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
                Row("Learned words", subtitle: learnedWordsSubtitle) {
                    Button("Open") { path.append(.learnedWords) }.buttonStyle(.small)
                }

                SectionLabel("Gestures").padding(.top, Theme.Space.s)
                Row("Slide on space", subtitle: "Move the cursor") {
                    Toggle("Slide on space", isOn: $model.keyboardSettings.spaceSlide).labelsHidden().tint(Theme.mint)
                }
                Row("Swipe left on ⌫", subtitle: "Delete the last word") {
                    Toggle("Swipe left on backspace", isOn: $model.keyboardSettings.backspaceSwipe).labelsHidden().tint(Theme.mint)
                }

                SectionLabel("Layout").padding(.top, Theme.Space.s)
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Picker("Layout on wide screens", selection: $model.keyboardSettings.splitOnWide) {
                            Text("Full").tag(false)
                            Text("Split").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Text("On the iPhone Duo's inner screen: one keyboard across, or a half under each thumb.")
                            .font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                }

                SectionLabel("Look").padding(.top, Theme.Space.s)
                Row("Trails and flashes", subtitle: "Show which thumb did what") {
                    Toggle("Trails and flashes", isOn: $model.keyboardSettings.trails).labelsHidden().tint(Theme.mint)
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

                SectionLabel("Privacy").padding(.top, Theme.Space.s)
                Row("Share anonymous usage data", subtitle: "Crash reports and counts like how many people turn the keyboard on. Never anything you type.") {
                    Toggle("Share anonymous usage data", isOn: $shareUsage).labelsHidden().tint(Theme.mint)
                        .onChange(of: shareUsage) { Telemetry.isEnabled = shareUsage }
                }

                if Flags.handwritingPad {
                    HandwritingSettings()
                }

                SectionLabel("About").padding(.top, Theme.Space.s)
                Row("Version", subtitle: DeviceInfo.appVersion)
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
        .onAppear {
            model.refreshKeyboardStatus()
            model.reloadWords()
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
