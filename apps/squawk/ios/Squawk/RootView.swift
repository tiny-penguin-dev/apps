import PenguinKit
import SquawkKit
import SwiftUI

/// First launch shows the setup screens; after that, Home.
struct RootView: View {
    @State private var model = AlarmsModel.shared
    @State private var pro = ProModel.shared
    @State private var home = HomeAccess.shared
    @AppStorage("onboarding.done") private var onboardingDone = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var confetti = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if onboardingDone {
                HomeView()
                    .transition(.opacity)
            } else {
                OnboardingFlow {
                    withAnimation(.spring) { onboardingDone = true }
                    celebrate()
                }
                    .transition(.opacity)
            }
        }
        .overlay {
            if confetti { FishConfetti().ignoresSafeArea() }
        }
        .environment(model)
        .environment(pro)
        .environment(home)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .task {
            pro.start()
            await model.refresh()
        }
        .fullScreenCover(isPresented: coverShowing) {
            Group {
                if let alarm = model.activeCheckAlarm {
                    CheckFlowView(alarm: alarm)
                } else {
                    GoodMorningView(record: model.goodMorning, log: model.log) { model.closeGoodMorning() }
                }
            }
            .environment(model)
            .environment(pro)
            .environment(home)
        }
    }

    /// Fish confetti when setup is done (DESIGN.md "Success").
    private func celebrate() {
        confetti = true
        Task {
            try? await Task.sleep(for: .seconds(4))
            confetti = false
        }
    }

    /// The wake-up check, then Good morning, over everything else.
    private var coverShowing: Binding<Bool> {
        Binding(
            get: { model.activeCheckID != nil || model.goodMorning != nil },
            set: { showing in
                if !showing {
                    model.closeGoodMorning()
                    model.closeCheck()
                }
            }
        )
    }
}

#Preview { RootView() }
