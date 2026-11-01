import PenguinKit
import SquawkKit
import SwiftUI

/// First launch shows the setup screens; after that, Home.
struct RootView: View {
    @State private var model = AlarmsModel.shared
    @AppStorage("onboarding.done") private var onboardingDone = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if onboardingDone {
                HomeView()
                    .transition(.opacity)
            } else {
                OnboardingFlow { withAnimation(.spring) { onboardingDone = true } }
                    .transition(.opacity)
            }
        }
        .environment(model)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}

#Preview { RootView() }
