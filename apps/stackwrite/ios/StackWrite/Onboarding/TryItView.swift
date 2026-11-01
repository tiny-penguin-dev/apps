import StackWriteCore
import StackWriteUI
import SwiftUI

/// DESIGN.md screen 4: five words with a thumb by thumb hint, typed in a field with the
/// keyboard up. "Show me" replays the word on the keys. Each word that lands moves on;
/// after the fifth, confetti and Home.
struct TryItView: View {
    var model: AppModel
    @State private var session: KeyboardSession?
    @State private var index = 0
    @State private var done = false
    @State private var showing = false

    private var words: [TryWord] { TryWord.all }
    private var word: TryWord { words[min(index, words.count - 1)] }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack {
                    Chip("Try it · word \(min(index + 1, words.count)) of \(words.count)")
                    Spacer()
                    Button("Skip") { model.finishOnboarding() }
                        .buttonStyle(.ghost)
                }
                .padding(.top, Theme.Space.s)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Type this word").font(.sw(.small)).foregroundStyle(Theme.muted)
                    Text(word.word).font(.sw(.title))
                        .contentTransition(.numericText())
                }
                if let session {
                    KeyboardField(session: session)
                        .frame(minHeight: 96, maxHeight: 150)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
                hint
                    .font(.sw(.small))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Space.m) {
                    Button("Show me") { showMe() }
                        .buttonStyle(.small)
                        .disabled(showing)
                    Text("or just try it").font(.sw(.small)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(Theme.Motion.spring, value: index)
            if done {
                Confetti().ignoresSafeArea()
            }
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            guard session == nil else { return }
            let session = KeyboardSession(settingsStore: MemorySettingsStore(model.keyboardSettings), learned: model.learnedWords)
            session.onWordsChange = { words in model.learnedWordsChanged(words) }
            session.onCommit = { word in committed(word) }
            self.session = session
        }
        .accessibilityAction(named: "Show me") { showMe() }
    }

    /// The hint with the thumbs in their colours and the letters bold.
    private var hint: Text {
        word.hint.reduce(Text("")) { text, part in
            switch part.role {
            case .plain: text + Text(part.text)
            case .strong: text + Text(part.text).bold().foregroundStyle(Theme.ink)
            case .left: text + Text(part.text).fontWeight(.black).foregroundStyle(Theme.left)
            case .right: text + Text(part.text).fontWeight(.black).foregroundStyle(Theme.right)
            }
        }
    }

    private func showMe() {
        guard let session, !showing else { return }
        showing = true
        session.replay(word) { showing = false }
    }

    private func committed(_ typed: String) {
        guard !done, let session else { return }
        model.recordPractice()
        guard typed.lowercased() == word.word else { return }
        if index + 1 < words.count {
            index += 1
            session.clear()
        } else {
            done = true
            session.clear()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.4))
                model.finishOnboarding()
            }
        }
    }
}
