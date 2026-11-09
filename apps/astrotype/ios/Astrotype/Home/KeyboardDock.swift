import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// The keyboard at the bottom of Home, like the real one (Gabriel, 9 Nov 2026: "show it
/// on the bottom like a real keyboard… let you show or minimize it"). It is a one-line
/// field whose input view is the practice keyboard (`KeyboardSession`), so iOS slides
/// the keys up and down as it does for any keyboard and Home scrolls above them. Hide
/// puts it away and leaves a Keyboard button in the corner; Home remembers which.
struct KeyboardDock: View {
    var model: AppModel
    /// Whether the person left it open, kept across launches.
    @Binding var shown: Bool
    /// Home is on top (nothing pushed over it): the keys only come up then.
    var active: Bool
    /// Handed back so Home can play an effect on the keys.
    var onSession: (KeyboardSession) -> Void = { _ in }
    @State private var session: KeyboardSession?
    @State private var focused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let session {
                HStack(spacing: Theme.Space.s) {
                    KeyboardField(session: session, font: .preferredFont(forTextStyle: .body), focusesOnAppear: false)
                        .frame(height: 44)
                    Button {
                        shown = false
                        session.unfocus()
                    } label: {
                        Label("Hide", systemImage: "chevron.down")
                            .font(.system(.subheadline, design: .rounded, weight: .heavy))
                            .padding(.horizontal, Theme.Space.m)
                            .padding(.vertical, 7)
                            .background(Theme.ink.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide keyboard")
                }
                .padding(.leading, Theme.Space.xs)
                .padding(.trailing, Theme.Space.m)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .padding(.horizontal, Theme.Space.s)
                .padding(.bottom, Theme.Space.xs)
                // Off screen while hidden: the field stays in the view so it can take the keys again.
                .opacity(focused ? 1 : 0)
                .allowsHitTesting(focused)
                .accessibilityHidden(!focused)
            }
            if !focused {
                Button {
                    shown = true
                    session?.focus()
                } label: {
                    Label("Keyboard", systemImage: "keyboard")
                        .font(.system(.body, design: .rounded, weight: .heavy))
                        .foregroundStyle(Theme.bg)
                        .padding(.horizontal, Theme.Space.l)
                        .padding(.vertical, Theme.Space.m)
                        .background(Theme.ink, in: Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, Theme.Space.gutter)
                .padding(.bottom, Theme.Space.s)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
                .accessibilityLabel("Show keyboard")
            }
        }
        .animation(Theme.Motion.spring(reduceMotion: reduceMotion), value: focused)
        .onAppear {
            guard session == nil else { return }
            let session = KeyboardSession(settingsStore: MemorySettingsStore(model.keyboardSettings), learned: model.learnedWords, personal: model.personal)
            session.apply(entitlement: model.entitlement)
            session.onWordsChange = { words in model.learnedWordsChanged(words) }
            session.onFocusChange = { isFocused in focused = isFocused }
            self.session = session
            onSession(session)
            if shown, active { Task { @MainActor in session.focus() } }
        }
        .onChange(of: active) {
            // Away while another screen is on top (it brings its own keys), back after.
            if active, shown { session?.focus() } else if !active { session?.unfocus() }
        }
        .onChange(of: model.keyboardSettings) { session?.apply(model.keyboardSettings) }
        .onChange(of: model.proStatus) { session?.apply(entitlement: model.entitlement) }
    }
}
