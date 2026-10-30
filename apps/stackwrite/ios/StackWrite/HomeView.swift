import SwiftUI

struct HomeView: View {
    @Environment(RecognitionService.self) private var recognition
    @Environment(SampleStore.self) private var samples
    @Environment(SampleUploader.self) private var uploader
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        TryView()
                    } label: {
                        Label("Try the keyboard", systemImage: "keyboard")
                    }
                    NavigationLink {
                        TrainView()
                    } label: {
                        Label("Write training words", systemImage: "pencil.and.scribble")
                    }
                } footer: {
                    Text("Write a whole word as one stroke, each letter on top of the last. Lift your finger to finish the word.")
                }

                Section {
                    LabeledContent("Words recorded", value: samples.count.formatted())
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
                         + "Uploads go to StackWrite's iCloud database: the strokes you write and the word they spell, with no name or account attached. Nothing you type on the keyboard is sent.")
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
