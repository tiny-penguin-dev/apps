import AstrotypeCore
import AstrotypeUI
import SwiftUI
import UIKit

/// DESIGN.md screen 6: three sentences to type, the typed words turning mint, a timer
/// that starts on the first touch, a wrong word shaking the field. On the Astrotype
/// keyboard, or on Apple's for the comparison on Home (the same three sentences,
/// through the system keyboard). Ends in the result screen.
struct SpeedTestView: View {
    var model: AppModel
    var keyboard: PracticeKeyboard
    @Binding var path: [HomeView.Route]
    @State private var test: SpeedTest
    @State private var session: KeyboardSession?
    @State private var shaking = false
    @State private var result: SpeedResult?
    @State private var newBest = false
    @State private var appleText = ""
    @FocusState private var appleFocused: Bool

    init(model: AppModel, keyboard: PracticeKeyboard, seed: UInt64?, path: Binding<[HomeView.Route]>) {
        self.model = model
        self.keyboard = keyboard
        _path = path
        _test = State(initialValue: seed.map { SpeedTest(sentences: SpeedTest.pick(seed: $0), seed: $0) } ?? SpeedTest.fresh())
    }

    var body: some View {
        ZStack {
            if let result {
                SpeedResultView(model: model, result: result, seed: test.seed, newBest: newBest, path: $path) {
                    again()
                }
                .transition(.opacity)
            } else {
                typing.transition(.opacity)
            }
        }
        .animation(Theme.Motion.spring, value: result != nil)
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear(perform: startSession)
    }

    private var typing: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text("Type this").font(.sw(.title))
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Chip(Self.clock(test.elapsed(at: Self.uptime)))
                }
            }
            .padding(.top, Theme.Space.s)
            sentence
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .animation(Theme.Motion.quickSpring, value: test.typedWords)
            Text(keyboard == .apple
                 ? "Sentence \(test.sentence + 1) of \(test.sentences.count), on Apple's keyboard. Space after each word."
                 : "Sentence \(test.sentence + 1) of \(test.sentences.count). Space after each word; a wrong word clears to try again.")
                .font(.sw(.small)).foregroundStyle(Theme.muted)
            field
                .frame(minHeight: 96, maxHeight: 150)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .offset(x: shaking ? -8 : 0)
                .animation(shaking ? .linear(duration: 0.06).repeatCount(5, autoreverses: true) : .default, value: shaking)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The current sentence, the typed words in mint.
    private var sentence: Text {
        let typed = test.typed.joined(separator: " ")
        let remaining = test.remaining.joined(separator: " ")
        return Text(typed.isEmpty ? "" : typed + " ").foregroundStyle(Theme.mint).bold() + Text(remaining)
    }

    @ViewBuilder
    private var field: some View {
        switch keyboard {
        case .astrotype:
            if let session {
                KeyboardField(session: session)
            }
        case .apple:
            TextField("", text: $appleText, axis: .vertical)
                .font(.system(.title2, design: .rounded))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($appleFocused)
                .padding(14)
                .frame(maxHeight: .infinity, alignment: .top)
                .onChange(of: appleText) { _, text in appleTyped(text) }
                .onAppear { appleFocused = true }
        }
    }

    // MARK: Running the test

    private func startSession() {
        guard keyboard == .astrotype, session == nil else { return }
        let session = KeyboardSession(settingsStore: MemorySettingsStore(model.keyboardSettings), learned: model.learnedWords)
        session.apply(entitlement: model.entitlement)
        session.onWordsChange = { words in model.learnedWordsChanged(words) }
        session.onFirstTouch = { test.start(at: Self.uptime) }
        session.onFix = { test.fixed() }
        session.onCommit = { word in committed(word) }
        if model.sharePractice { session.startRecording(kind: "speedtest") }
        self.session = session
    }

    /// Apple's keyboard: each space (or return) hands over the word before it.
    private func appleTyped(_ text: String) {
        guard !text.isEmpty else { return }
        test.start(at: Self.uptime)
        guard let last = text.last, last == " " || last == "\n" else { return }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        appleText = ""
        if !word.isEmpty { committed(word) }
    }

    private func committed(_ word: String) {
        guard result == nil else { return }
        model.recordPractice()
        let outcome = test.commit(word, at: Self.uptime)
        switch outcome {
        case .miss:
            shake()
            session?.clear()
            appleText = ""
        case .next:
            break
        case .sentence:
            session?.clear()
            appleText = ""
        case .finished:
            finish()
        }
    }

    private func shake() {
        shaking = true
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            shaking = false
        }
    }

    private func finish() {
        guard let done = test.result(date: model.now, keyboard: keyboard) else { return }
        newBest = model.speedTestFinished(done)
        if newBest { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        if let session, let recording = session.stopRecording(
            expected: test.sentences.map { $0.joined(separator: " ") }.joined(separator: " "),
            device: model.device, now: model.now, wordsPerMinute: done.wordsPerMinute, fixes: done.fixes) {
            model.savePractice(recording)
        }
        session?.clear()
        result = done
    }

    /// "Again": fresh sentences, the same keyboard.
    private func again() {
        test = SpeedTest.fresh()
        result = nil
        newBest = false
        appleText = ""
        session?.clear()
        if model.sharePractice { session?.startRecording(kind: "speedtest") }
        if keyboard == .astrotype { session?.focus() } else { appleFocused = true }
    }

    /// The keyboard's clock: the same one its touches are stamped with.
    static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
