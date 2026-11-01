import StackWriteCore
import SwiftUI

struct HomeView: View {
    @Environment(RecognitionService.self) private var recognition
    @Environment(SampleStore.self) private var samples
    @Environment(SampleUploader.self) private var uploader
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var shareUsage = Telemetry.isEnabled

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PracticeView()
                    } label: {
                        Label("Try the keyboard", systemImage: "keyboard")
                    }
                } header: {
                    Text("Phase 2")
                } footer: {
                    Text("Tap or swipe with one finger. Space, a pause or punctuation writes the word; the bar offers fixes after. In other apps, turn StackWrite on in Settings › General › Keyboard › Keyboards.")
                }

                Section {
                    Toggle("Share anonymous usage data", isOn: $shareUsage)
                        .onChange(of: shareUsage) { Telemetry.isEnabled = shareUsage }
                } header: {
                    Text("Settings")
                } footer: {
                    Text("Crash reports and counts like how many people turn the keyboard on. Never anything you type.")
                }

                // The v1 handwriting pad, kept behind a flag (PRODUCT.md "Later").
                if Flags.handwritingPad {
                    Section {
                        NavigationLink {
                            TryView()
                        } label: {
                            Label("Try the keyboard", systemImage: "keyboard")
                        }
                        NavigationLink {
                            TrainView()
                        } label: {
                            Label("Write training phrases", systemImage: "pencil.and.scribble")
                        }
                    } footer: {
                        Text("Write each letter on top of the last, lifting your finger whenever you like. Between words, pause for a moment or tap.")
                    }

                    Section {
                        LabeledContent("Recordings", value: samples.count.formatted())
                        Toggle("Upload to help train StackWrite", isOn: Bindable(uploader).isEnabled)
                        if uploader.isEnabled {
                            Button {
                                uploader.upload()
                            } label: {
                                LabeledContent("Upload now") {
                                    if uploader.isUploading {
                                        ProgressView()
                                    } else {
                                        Text("\(samples.pendingCount) waiting")
                                    }
                                }
                            }
                            .disabled(samples.pendingCount == 0 || uploader.isUploading)
                        }
                        Button("Export samples…", systemImage: "square.and.arrow.up") {
                            do {
                                exportURL = try samples.exportArchive()
                            } catch {
                                exportError = error.localizedDescription
                            }
                        }
                        .disabled(samples.count == 0)
                    } header: {
                        Text("Training data")
                    } footer: {
                        Text((uploader.status.map { $0 + "\n" } ?? "")
                             + "Uploads go to StackWrite's iCloud database: the strokes you write and the words they spell, with no name or account attached. Nothing you type on the keyboard is sent.")
                    }

                }

                Section {
                    LabeledContent("Version", value: DeviceInfo.appVersion)
                    LabeledContent("Model", value: recognition.statusText)
                }
            }
            .navigationTitle("StackWrite")
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
            .alert("Couldn't export", isPresented: .constant(exportError != nil)) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
