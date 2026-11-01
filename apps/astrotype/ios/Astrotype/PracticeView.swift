import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// A field to type in with the Astrotype keyboard, inside the app, so the engine can
/// be tried without turning the keyboard on in Settings. The speed test and drills
/// (Phase 7) grow from here.
struct PracticeView: View {
    var model: AppModel
    @State private var session: KeyboardSession?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text("Practice").font(.sw(.title))
                Spacer()
                Button("Clear") { session?.clear() }.buttonStyle(.ghost)
            }
            .padding(.top, Theme.Space.s)
            Text(model.entitlement.allows(.twoThumbs)
                 ? "Tap or swipe with one thumb, or both. Space, a pause or punctuation writes the word; the bar offers fixes after."
                 : "Tap or swipe with one thumb. Space, a pause or punctuation writes the word; the bar offers fixes after.")
                .font(.sw(.small)).foregroundStyle(Theme.muted)
            if let session {
                KeyboardField(session: session)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.bottom, Theme.Space.m)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            guard session == nil else { return }
            let session = KeyboardSession(settingsStore: MemorySettingsStore(model.keyboardSettings), learned: model.learnedWords)
            session.apply(entitlement: model.entitlement)
            session.onWordsChange = { words in model.learnedWordsChanged(words) }
            session.onCommit = { _ in model.recordPractice() }
            self.session = session
        }
        .onChange(of: model.keyboardSettings) { session?.apply(model.keyboardSettings) }
        .onChange(of: model.proStatus) { session?.apply(entitlement: model.entitlement) }
    }
}
