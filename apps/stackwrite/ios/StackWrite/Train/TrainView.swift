import StackWriteKit
import SwiftUI

/// Shows words to write and saves each stroke as a labeled training sample.
struct TrainView: View {
    @Environment(RecognitionService.self) private var recognition
    @Environment(SampleStore.self) private var samples
    @Environment(SampleUploader.self) private var uploader

    @State private var phrase: [String] = []
    @State private var index = 0
    /// Samples saved for the current phrase, so Back can remove them.
    @State private var saved: [Int: UUID] = [:]
    @State private var feedback: Feedback?
    @State private var sessionCount = 0
    @State private var session = UUID().uuidString
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    struct Feedback: Equatable {
        var word: String
        var read: [String]
        var right: Bool { read.first == word }
    }

    private var current: String? { phrase.indices.contains(index) ? phrase[index] : nil }

    var body: some View {
        VStack(spacing: 16) {
            phraseView
            Text(current ?? " ")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .contentTransition(.opacity)
                .animation(.default, value: current)
            feedbackView
            Spacer(minLength: 0)
            Text("\(sessionCount) words this time · \(samples.count) saved")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack {
                Button("Back", systemImage: "arrow.uturn.backward", action: back)
                    .disabled(index == 0)
                Spacer()
                Button("Skip", systemImage: "forward", action: advance)
                Spacer()
                Button("New words", systemImage: "arrow.clockwise", action: newPhrase)
            }
            .labelStyle(.titleAndIcon)
            .font(.callout)
            WritingPad { points, size in record(points, size: size) }
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

    private var phraseView: some View {
        HStack(spacing: 8) {
            ForEach(Array(phrase.enumerated()), id: \.offset) { i, word in
                Text(word)
                    .foregroundStyle(i == index ? Color.accentColor : i < index ? .secondary : .primary)
                    .fontWeight(i == index ? .semibold : .regular)
            }
        }
        .font(.title3)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var feedbackView: some View {
        if let feedback {
            Label {
                Text(feedback.read.isEmpty ? "Couldn't read “\(feedback.word)”"
                     : "“\(feedback.word)” read as \(feedback.read.prefix(3).joined(separator: ", "))")
            } icon: {
                Image(systemName: feedback.right ? "checkmark.circle.fill" : "questionmark.circle")
                    .foregroundStyle(feedback.right ? .green : .orange)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
            Text("Write the highlighted word as one stroke.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func record(_ points: [StrokePoint], size: CGSize) {
        guard let word = current, Features.length(points) > 0.05 else { return }
        let read = recognition.recognize(points)?.words ?? []
        let sample = StrokeSample(
            label: word,
            labelSource: .prompt,
            points: points,
            padSize: size,
            writer: DeviceInfo.writerID,
            session: session,
            device: DeviceInfo.model,
            system: DeviceInfo.system,
            app: DeviceInfo.appVersion,
            prompt: phrase.joined(separator: " "),
            recognized: read
        )
        do {
            try samples.save(sample)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        saved[index] = sample.id
        sessionCount += 1
        // Upload in batches; the last few words wait so Back can still take them out.
        if samples.pendingCount >= 25 { uploader.upload() }
        feedback = Feedback(word: word, read: read)
        advance()
    }

    private func advance() {
        if index + 1 < phrase.count {
            index += 1
        } else {
            newPhrase()
        }
    }

    /// Goes back one word and removes what was saved for it.
    private func back() {
        guard index > 0 else { return }
        index -= 1
        if let id = saved.removeValue(forKey: index) {
            if samples.delete(id) { uploader.remove(id) }
            sessionCount -= 1
        }
        feedback = nil
    }

    private func newPhrase() {
        phrase = PromptGenerator(entries: recognition.entries).phrase()
        index = 0
        saved = [:]
    }
}
