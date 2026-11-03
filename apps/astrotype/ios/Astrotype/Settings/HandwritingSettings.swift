import AstrotypeCore
import AstrotypeUI
import SwiftUI

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
