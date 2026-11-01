import AstrotypeCore
import AstrotypeUI
import SwiftUI
import UIKit

/// DESIGN.md screen 8: one habit, five words. The keys of the next word are outlined in
/// each thumb's colour; a right word moves on, a wrong one shakes. After the fifth,
/// confetti and back to Home with the drill ticked.
struct DrillView: View {
    var model: AppModel
    var drill: Drill
    @Binding var path: [HomeView.Route]
    @State private var session: KeyboardSession?
    @State private var index = 0
    @State private var done = false
    @State private var shaking = false

    private var current: Drill.Word? { drill.words.indices.contains(index) ? drill.words[index] : nil }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack {
                    Text(drill.title).font(.sw(.title))
                    Spacer()
                    Chip("\(min(index + 1, drill.words.count)) of \(drill.words.count)")
                }
                .padding(.top, Theme.Space.s)
                hint
                    .font(.sw(.small))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                WordCards(words: drill.words.map(\.text), current: index)
                if let session {
                    KeyboardField(session: session)
                        .frame(minHeight: 96, maxHeight: 150)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .offset(x: shaking ? -8 : 0)
                        .animation(shaking ? .linear(duration: 0.06).repeatCount(5, autoreverses: true) : .default, value: shaking)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if done {
                Confetti().ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            guard session == nil else { return }
            let session = KeyboardSession(settingsStore: MemorySettingsStore(model.keyboardSettings), learned: model.learnedWords)
            session.apply(entitlement: model.entitlement)
            session.onWordsChange = { words in model.learnedWordsChanged(words) }
            session.onCommit = { word in committed(word) }
            if model.sharePractice { session.startRecording(kind: "drill.\(drill.id.rawValue)") }
            session.hint(current)
            self.session = session
        }
        .onChange(of: index) { session?.hint(current) }
    }

    /// The drill's hint with the thumbs in their colours and the paths bold.
    private var hint: Text {
        drill.hint.reduce(Text("")) { text, part in
            switch part.role {
            case .plain: text + Text(part.text)
            case .strong: text + Text(part.text).bold().foregroundStyle(Theme.ink)
            case .left: text + Text(part.text).fontWeight(.black).foregroundStyle(Theme.left)
            case .right: text + Text(part.text).fontWeight(.black).foregroundStyle(Theme.right)
            }
        }
    }

    private func committed(_ typed: String) {
        guard !done, let session, let word = current else { return }
        model.recordPractice()
        guard SpeedTest.normalize(typed) == word.text else {
            shaking = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            session.clear()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                shaking = false
            }
            return
        }
        session.clear()
        if index + 1 < drill.words.count {
            index += 1
            return
        }
        done = true
        index = drill.words.count
        session.hint(nil)
        model.drillFinished(drill.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let recording = session.stopRecording(expected: drill.words.map(\.text).joined(separator: " "),
                                                 device: model.device, now: model.now) {
            model.savePractice(recording)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            path.removeAll()
        }
    }
}
