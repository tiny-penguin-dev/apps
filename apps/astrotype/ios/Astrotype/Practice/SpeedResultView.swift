import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// DESIGN.md screen 7: the bolt, the words per minute, how many words needed a fix,
/// versus Apple's keyboard, the best and the streak; confetti on a new best.
struct SpeedResultView: View {
    var model: AppModel
    var result: SpeedResult
    /// The sentences' seed, so Apple's keyboard can be timed on the same three.
    var seed: UInt64?
    var newBest: Bool
    @Binding var path: [HomeView.Route]
    var again: () -> Void

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: Theme.Space.m) {
                    BoltArt().frame(width: 170, height: 170).padding(.top, Theme.Space.l)
                    Text("\(result.wordsPerMinute)")
                        .bigNumberFont()
                        .contentTransition(.numericText())
                    Text(result.keyboard == .apple ? "words per minute on Apple's keyboard" : "words per minute")
                        .font(.system(.body, design: .rounded, weight: .heavy))
                    Text(line)
                        .font(.sw(.body))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Card {
                        HStack(spacing: Theme.Space.s) {
                            if let best = model.bestWordsPerMinute { Chip("Best \(best)") }
                            let streak = model.streak
                            if streak > 1 { Chip("\(streak) days in a row") }
                            Spacer()
                            ShareLink(item: shareText) {
                                Text("Share").font(.system(.subheadline, design: .rounded, weight: .heavy)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            if newBest {
                Confetti().ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.s) {
                if result.keyboard == .astrotype, model.appleWordsPerMinute == nil {
                    Button("Now try Apple's keyboard") { path.append(.speedTest(.apple, seed)) }
                        .buttonStyle(.ghost)
                }
                Button("Again", action: again).buttonStyle(.primary)
                Button("Done") { path.removeAll() }.buttonStyle(.ghost)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.s)
            .frame(maxWidth: 560)
        }
    }

    /// "3 words needed a fix. That's 21 faster than Apple's keyboard and a new best."
    private var line: String {
        var parts: [String] = []
        switch result.fixes {
        case 0: parts.append("No word needed a fix.")
        case 1: parts.append("1 word needed a fix.")
        default: parts.append("\(result.fixes) words needed a fix.")
        }
        switch result.keyboard {
        case .astrotype:
            var claims: [String] = []
            if let apple = model.appleWordsPerMinute {
                let gap = result.wordsPerMinute - apple
                if gap > 0 { claims.append("\(gap) faster than Apple's keyboard") }
                else if gap < 0 { claims.append("\(-gap) behind Apple's keyboard, for now") }
                else { claims.append("level with Apple's keyboard") }
            }
            if newBest { claims.append("a new best") }
            if !claims.isEmpty { parts.append("That's " + claims.joined(separator: " and ") + ".") }
        case .apple:
            if let best = model.bestWordsPerMinute {
                parts.append("Your best on Astrotype is \(best).")
            }
        }
        return parts.joined(separator: " ")
    }

    private var shareText: String {
        result.keyboard == .apple
            ? "I typed \(result.wordsPerMinute) words per minute on Apple's keyboard."
            : "I typed \(result.wordsPerMinute) words per minute with two thumbs on Astrotype."
    }
}
