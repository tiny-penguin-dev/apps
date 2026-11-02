import AstrotypeCore
import AstrotypeUI
import SwiftUI
import UIKit

/// "Practice words" (features/smart-matching Phase D): one common word or short phrase
/// at a time from the language itself, no timer. A right word moves on, a wrong one
/// shakes and waits to be typed again, like a drill. With "Send practice sessions" on,
/// each prompt's touches are kept to share word by word, so what the keyboard learns
/// from covers far more than the speed test's sentences.
struct PracticeWordsView: View {
    var model: AppModel
    @State private var session: KeyboardSession?
    @State private var prompts: PracticeWords?
    @State private var prompt: [String] = []
    @State private var index = 0
    @State private var typed = 0
    @State private var shaking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text("Practice words").font(.sw(.title))
                Spacer()
                Chip("\(typed) typed")
            }
            .padding(.top, Theme.Space.s)
            Text(model.sharePractice
                 ? "Type what you see. Each word goes to tuning the keyboard on its own, with no sentence around it."
                 : "Type what you see. Turn on Send practice sessions in Settings to help tune the keyboard with them.")
                .font(.sw(.small)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            WordCards(words: prompt, current: index)
            if let session {
                KeyboardField(session: session)
                    .frame(minHeight: 96, maxHeight: 150)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .offset(x: shaking ? -8 : 0)
                    .animation(shaking ? .linear(duration: 0.06).repeatCount(5, autoreverses: true) : .default, value: shaking)
            }
            HStack {
                Spacer()
                Button("Skip") { nextPrompt(save: false) }.buttonStyle(.ghost)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            guard session == nil else { return }
            let session = KeyboardSession(settingsStore: MemorySettingsStore(model.keyboardSettings), learned: model.learnedWords, personal: model.personal)
            session.apply(entitlement: model.entitlement)
            session.onWordsChange = { words in model.learnedWordsChanged(words) }
            session.onCommit = { word in committed(word) }
            self.session = session
            prompts = model.practiceWords()
            nextPrompt(save: false)
        }
        .onDisappear { nextPrompt(save: true, andShowAnother: false) }
    }

    private func committed(_ word: String) {
        guard let session, prompt.indices.contains(index) else { return }
        model.recordPractice()
        guard SpeedTest.normalize(word) == prompt[index] else {
            shaking = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            // Take the wrong word back out once the keyboard has finished writing it; the
            // words before it stay as the context.
            Task { @MainActor in session.model.deleteWord() }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                shaking = false
            }
            return
        }
        typed += 1
        index += 1
        // The next prompt once the keyboard has finished writing this word.
        if index == prompt.count { Task { @MainActor in nextPrompt(save: true) } }
    }

    /// Keeps the prompt just typed (to share, when sharing is on) and shows the next.
    private func nextPrompt(save: Bool, andShowAnother: Bool = true) {
        if let session {
            if save, let recording = session.stopRecording(expected: prompt.joined(separator: " "), device: model.device, now: model.now) {
                model.savePractice(recording)
            } else {
                _ = session.stopRecording(expected: "", device: model.device, now: model.now)
            }
            session.clear()
        }
        guard andShowAnother, var prompts else { return }
        prompt = prompts.next().split(separator: " ").map(String.init)
        self.prompts = prompts
        index = 0
        if model.sharePractice { session?.startRecording(kind: "practice.words") }
    }
}
