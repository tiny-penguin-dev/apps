import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// The card at the top of Home that shows only while something needs fixing, each
/// problem with a line on what's wrong and a button that fixes it (Gabriel, 9 Nov 2026).
/// Nothing wrong, no card.
struct FixItCard: View {
    var model: AppModel
    var turnOn: () -> Void
    var fullAccess: () -> Void
    /// "Not now" on Full Access: it is a choice, so the card lets it go.
    @AppStorage("home.fullAccessDismissed") private var fullAccessDismissed = false

    struct Problem: Identifiable {
        var id: String
        var symbol: String
        var title: String
        var text: String
        var action: String
        var fix: () -> Void
        var dismiss: (() -> Void)?
    }

    var problems: [Problem] {
        var problems: [Problem] = []
        if !model.isKeyboardOn {
            problems.append(Problem(id: "keyboard", symbol: "keyboard",
                                    title: "Astrotype isn't on yet",
                                    text: "Add it in Settings → Keyboards, then pick it with the globe key.",
                                    action: "Turn on", fix: turnOn))
        } else if !model.isFullAccessOn, !fullAccessDismissed {
            problems.append(Problem(id: "fullAccess", symbol: "lock.open",
                                    title: "Full Access is off",
                                    text: "Without it your words don't sync, your speed isn't measured, and dictation can't start.",
                                    action: "Turn on", fix: fullAccess,
                                    dismiss: { fullAccessDismissed = true }))
        }
        if case .failed = model.syncState {
            problems.append(Problem(id: "sync", symbol: "icloud.slash",
                                    title: "iCloud sync didn't work",
                                    text: "Your words are safe on this iPhone. Check you're signed in to iCloud, then try again.",
                                    action: "Try again", fix: { model.sync() }))
        }
        return problems
    }

    var body: some View {
        let problems = problems
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                ForEach(Array(problems.enumerated()), id: \.element.id) { index, problem in
                    if index > 0 { Rectangle().fill(Theme.sunInk.opacity(0.2)).frame(height: 1) }
                    row(problem)
                }
            }
            .foregroundStyle(Theme.sunInk)
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sun, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .onAppear { model.fixItShown(problems.map(\.id)) }
        }
    }

    private func row(_ problem: Problem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: problem.symbol)
                    .font(.system(.body, weight: .bold))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(problem.title).font(.system(.body, design: .rounded, weight: .heavy))
                    Text(problem.text).font(.sw(.small))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: Theme.Space.s) {
                Button(problem.action, action: problem.fix)
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.l).padding(.vertical, 10)
                    .background(Capsule().fill(Theme.sunInk))
                if let dismiss = problem.dismiss {
                    Button("Not now", action: dismiss)
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                        .padding(.horizontal, Theme.Space.m).padding(.vertical, 10)
                }
            }
            .padding(.leading, 24 + Theme.Space.m)
        }
    }
}
