import SwiftUI

struct HomeView: View {
    @Environment(RecognitionService.self) private var recognition
    @Environment(SampleStore.self) private var samples
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

                Section("Training data") {
                    LabeledContent("Words recorded", value: samples.count.formatted())
                    Button("Export samples…", systemImage: "square.and.arrow.up") {
                        do {
                            exportURL = try samples.exportArchive()
                        } catch {
                            exportError = error.localizedDescription
                        }
                    }
                    .disabled(samples.count == 0)
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
