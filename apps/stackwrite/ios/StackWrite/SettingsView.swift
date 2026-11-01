import StackWriteCore
import StackWriteUI
import SwiftUI

/// DESIGN.md screen 9, the rows that exist so far: typing, gestures, look, the
/// keyboard's status, sync, privacy and the version. Two-thumb typing, learned words,
/// layouts and Pro come with their phases.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]
    @State private var shareUsage = Telemetry.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Settings").font(.sw(.title)).padding(.top, Theme.Space.s)

                SectionLabel("Typing")
                Row("Autospace", subtitle: "Write the word after a short pause") {
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

                SectionLabel("Gestures").padding(.top, Theme.Space.s)
                Row("Slide on space", subtitle: "Move the cursor") {
                    Toggle("Slide on space", isOn: $model.keyboardSettings.spaceSlide).labelsHidden().tint(Theme.mint)
                }
                Row("Swipe left on ⌫", subtitle: "Delete the last word") {
                    Toggle("Swipe left on backspace", isOn: $model.keyboardSettings.backspaceSwipe).labelsHidden().tint(Theme.mint)
                }

                SectionLabel("Look").padding(.top, Theme.Space.s)
                Row("Trails and flashes", subtitle: "Show which thumb did what") {
                    Toggle("Trails and flashes", isOn: $model.keyboardSettings.trails).labelsHidden().tint(Theme.mint)
                }

                SectionLabel("Keyboard").padding(.top, Theme.Space.s)
                Row("StackWrite keyboard", subtitle: model.isKeyboardOn ? "On. Hold 🌐 in any app to pick it." : "Not on yet.") {
                    if model.isKeyboardOn {
                        Chip("On", tint: Theme.mint)
                    } else {
                        Button("Turn on") { path.append(.turnOn) }.buttonStyle(.small)
                    }
                }
                Row("iCloud sync", subtitle: "Needs Full Access in Settings. Words and settings start syncing in an update.") {
                    Button("Set up") { path.append(.sync) }.buttonStyle(.small)
                }
                Text("Until then, these settings apply to the keyboard in this app; the keyboard in other apps has its own, under a held 123.")
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
            Toggle("Upload to help train StackWrite", isOn: Bindable(uploader).isEnabled).labelsHidden().tint(Theme.mint)
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
             + "Uploads go to StackWrite's iCloud database: the strokes you write and the words they spell, with no name or account attached. Nothing you type on the keyboard is sent.")
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
