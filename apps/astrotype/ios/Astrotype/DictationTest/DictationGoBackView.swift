import SwiftUI

// THROWAWAY SPIKE (Gabriel, 9 Nov 2026), see DictationProbeIntent.swift. Round 7: the
// keyboard's Talk opened the app to start the mic. This tells you to go back. The real
// screen (pointing at the bottom bar, animated, iPhone Duo aware) comes with the feature.

struct DictationGoBackView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill").font(.largeTitle).foregroundStyle(.red)
            Text("Listening").font(.title.bold())
            Text("Swipe right along the bottom edge to go back to where you were typing, or tap ◀ at the top left.")
                .multilineTextAlignment(.center)
            Text(DictationProbeLog.last).font(.footnote).foregroundStyle(.secondary)
            Button("Close") { dismiss() }
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}
