import StackWriteCore
import SwiftUI

/// Shows a short phrase to write and saves the strokes as a labeled training
/// sample when the writer taps Done.
struct TrainView: View {
    @Environment(RecognitionService.self) private var recognition
    @Environment(SampleStore.self) private var samples
    @Environment(SampleUploader.self) private var uploader

    @State private var phrase: [String] = []
    @State private var recording = Recording()
    @State private var padSize = CGSize.zero
    /// What the model reads so far, live.
    @State private var reading: String?
    /// The last saved sample, so Undo can take it back out.
    @State private var lastSaved: (id: UUID, feedback: Feedback)?
    @State private var sessionCount = 0
    @State private var session = UUID().uuidString
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    struct Feedback {
        var text: String
        var read: [String]
        var right: Bool { read.first == text }
    }

    private var text: String { phrase.joined(separator: " ") }

    var body: some View {
        VStack(spacing: 16) {
            Text(text.isEmpty ? " " : text)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .contentTransition(.opacity)
                .animation(.default, value: text)
            statusView
            Spacer(minLength: 0)
            Text("\(sessionCount) phrases this time · \(samples.count) saved")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack {
                Button("Redo", systemImage: "arrow.uturn.backward") { clear() }
                    .disabled(recording.isEmpty)
                Spacer()
                Button("Skip", systemImage: "forward", action: newPhrase)
                Spacer()
                Button("Done", systemImage: "checkmark", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(recording.isEmpty)
            }
            .labelStyle(.titleAndIcon)
            .font(.callout)
            WritingPad { points, size in
                padSize = size
                recording.add(points)
                reading = recognition.recognize(recording.strokes, partial: true)?.texts.first
            }
        }
        .padding()
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Delete all samples", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .confirmationDialog("Delete all \(samples.count) samples?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { samples.deleteAll() }
        }
        .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: sessionCount)
        .onDisappear { uploader.upload() }
        .onChange(of: recognition.entries.count, initial: true) {
            if phrase.isEmpty { newPhrase() }
        }
    }

    @ViewBuilder private var statusView: some View {
        if !recording.isEmpty {
            Text("Reading “\(reading ?? "…")”")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let feedback = lastSaved?.feedback {
            HStack {
                Label {
                    Text(feedback.read.isEmpty ? "Saved. Couldn't read it"
                         : "Saved. Read as “\(feedback.read[0])”")
                } icon: {
                    Image(systemName: feedback.right ? "checkmark.circle.fill" : "questionmark.circle")
                        .foregroundStyle(feedback.right ? .green : .orange)
                }
                Button("Undo", action: undo)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
            Text("Write each letter on top of the last, lifting your finger whenever you like. Between words, pause or tap. Then tap Done.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func save() {
        guard !text.isEmpty, !recording.isEmpty else { return }
        let read = recognition.recognize(recording.strokes)?.texts ?? []
        let sample = StrokeSample(
            label: text,
            labelSource: .prompt,
            strokes: recording.strokes,
            padSize: padSize,
            writer: DeviceInfo.writerID,
            session: session,
            device: DeviceInfo.model,
            system: DeviceInfo.system,
            app: DeviceInfo.appVersion,
            prompt: text,
            recognized: read
        )
        do {
            try samples.save(sample)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        recognition.learnLifts(recording.lifts)
        lastSaved = (sample.id, Feedback(text: text, read: read))
        sessionCount += 1
        // Upload in batches; the last few wait so Undo can still take them out.
        if samples.pendingCount >= 25 { uploader.upload() }
        newPhrase()
    }

    /// Removes the last saved phrase and asks for it again.
    private func undo() {
        guard let saved = lastSaved else { return }
        if samples.delete(saved.id) { uploader.remove(saved.id) }
        sessionCount -= 1
        lastSaved = nil
        phrase = saved.feedback.text.split(separator: " ").map(String.init)
        clear()
    }

    private func clear() {
        recording.removeAll()
        reading = nil
    }

    private func newPhrase() {
        phrase = PromptGenerator(entries: recognition.entries).phrase()
        clear()
    }
}
