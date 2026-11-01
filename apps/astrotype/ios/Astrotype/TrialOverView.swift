import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// DESIGN.md screen 11: shown once, on the first launch after the trial ends. The
/// keyboard resting, what is resting and what still works, and the way to keep Pro.
struct TrialOverView: View {
    var model: AppModel
    /// "Keep two-thumb typing": the sheet closes and the Pro screen opens.
    var onKeepPro: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Spacer(minLength: 0)
            RestingKeyboardArt().frame(width: 180, height: 180)
            Text("Your trial ended").font(.sw(.title))
            Text("Two-thumb typing, gestures and layouts are resting. The keyboard still works with taps and one-finger swipes, and your learned words are safe.")
                .font(.sw(.body))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Keep two-thumb typing") {
                model.trialOverSeen()
                dismiss()
                onKeepPro()
            }
            .buttonStyle(.primary)
            Button("Stay on the free keyboard") {
                model.trialOverSeen()
                dismiss()
            }
            .buttonStyle(.ghost)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.vertical, Theme.Space.xl)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .interactiveDismissDisabled(false)
        .onDisappear { model.trialOverSeen() }
    }
}
