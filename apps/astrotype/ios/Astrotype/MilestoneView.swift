import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// The milestone sheet (PRODUCT.md §7): shown once per milestone, from Home, with
/// confetti. Themes and trail colours as rewards come with Phase 8's themes.
struct MilestoneView: View {
    var milestone: Milestone
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VStack(spacing: Theme.Space.l) {
                Spacer(minLength: 0)
                art.frame(width: 170, height: 170)
                Text(milestone.title).font(.sw(.title)).multilineTextAlignment(.center)
                Text(milestone.line)
                    .font(.sw(.body))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Nice") { dismiss() }.buttonStyle(.primary)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.vertical, Theme.Space.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Confetti().ignoresSafeArea().allowsHitTesting(false)
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var art: some View {
        switch milestone {
        case .fortyWordsPerMinute: BoltArt()
        case .firstWeek: ThumbsArt(animated: true)
        case .hundredWords: StarTileArt()
        }
    }
}
