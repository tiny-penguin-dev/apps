import PenguinKit
import SwiftUI

/// Phase 1: the hello screen, then a placeholder until alarms arrive in phase 2.
struct RootView: View {
    @State private var started = false
    @State private var showGallery = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if started {
                ComingSoonView(onBack: { withAnimation(.spring) { started = false } })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                WelcomeView(onStart: { withAnimation(.spring) { started = true } })
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .foregroundStyle(Theme.ink)
        // Hidden debug screen: long-press Squawk anywhere.
        .onLongPressGesture(minimumDuration: 1.2) { showGallery = true }
        .sheet(isPresented: $showGallery) {
            NavigationStack {
                PenguinGallery()
                    .toolbar { Button("Done") { showGallery = false } }
            }
        }
    }
}

/// Screen 1 of DESIGN.md: Squawk waddles in and waves.
struct WelcomeView: View {
    var onStart: () -> Void

    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            PenguinView(mood: .awake, waving: arrived)
                .frame(width: 220, height: 220)
                .offset(x: arrived || reduceMotion ? 0 : -260)
                .rotationEffect(.degrees(arrived || reduceMotion ? 0 : -8))
            Text("Hi, I'm Squawk!")
                .font(Theme.title(30))
            Text("I'll get you out of bed. Gently first, and louder only if I need to.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            Button("Let's go", action: onStart)
                .buttonStyle(PillButtonStyle())
        }
        .padding(22)
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.45).delay(0.2)) { arrived = true }
        }
    }
}

/// Placeholder until the alarm screens land in phase 2.
struct ComingSoonView: View {
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            PenguinView(mood: .asleep, accessory: .nightcap)
                .frame(width: 180, height: 180)
            Text("Alarms are next")
                .font(Theme.title(28))
            Text("Squawk is practicing his squawk. Setting alarms arrives in the next build.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("Tip: long-press anywhere to see every penguin mood.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.muted)
            Spacer()
            Button("Back", action: onBack)
                .buttonStyle(PillButtonStyle())
            Text(version)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.muted)
        }
        .padding(22)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }
}

#Preview { RootView() }
