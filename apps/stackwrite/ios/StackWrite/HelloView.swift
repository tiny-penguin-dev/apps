import StackWriteUI
import SwiftUI

/// The first screen (DESIGN.md screen 1): a keyboard with two thumb trails drawing
/// themselves, one line, one button. Phase 4 adds the setup screens after it.
struct HelloView: View {
    var next: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Spacer()
            ThumbsArt()
                .frame(width: 220, height: 220)
            Text("Type with both thumbs.")
                .font(.sw(.title))
                .multilineTextAlignment(.center)
            Text("Tap with one, swipe with the other, mix them any way you like. Press space when the word looks right. We'll show you.")
                .font(.sw(.body))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Let's go", action: next)
                .buttonStyle(.primary)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.bottom, Theme.Space.xl)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Theme.ink)
        .background(Theme.bg.ignoresSafeArea())
    }
}

#Preview {
    HelloView {}
}
