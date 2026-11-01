import PenguinKit
import SquawkKit
import SwiftUI

/// First launch: Hello → Allow alarms → Wake-up time. Three taps to a 7:00 weekday alarm.
struct OnboardingFlow: View {
    var onFinish: () -> Void

    private enum Step { case hello, permission, time }
    @State private var step = Step.hello
    @State private var startedAt = Date()
    @Environment(AlarmsModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch step {
            case .hello:
                WelcomeView { go(to: model.access == .allowed ? .time : .permission) }
                    .transition(slide)
            case .permission:
                PermissionView(
                    onAllow: {
                        Task {
                            await model.requestAccess()
                            go(to: .time)
                        }
                    },
                    onSkip: { go(to: .time) }
                )
                .transition(slide)
            case .time:
                WakeUpTimeView { alarm in
                    model.save(alarm)
                    Telemetry.duration("onboarding.finished", seconds: Date().timeIntervalSince(startedAt))
                    onFinish()
                }
                .transition(slide)
            }
        }
    }

    private var slide: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity)
    }

    private func go(to next: Step) {
        withAnimation(.spring(duration: 0.5, bounce: 0.3)) { step = next }
    }
}

/// Screen 1: Squawk waddles in and waves.
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

/// Screen 2: why we ask to ring like a real alarm.
struct PermissionView: View {
    var onAllow: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            PenguinView(mood: .squawk)
                .frame(width: 180, height: 180)
            Text("Can I ring like a real alarm?")
                .font(Theme.title(28))
                .multilineTextAlignment(.center)
            Text("Squawk rings on your lock screen, even on silent or in Focus. Your iPhone will ask you to allow alarms.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
            Button("Allow alarms", action: onAllow)
                .buttonStyle(PillButtonStyle())
            Button("Not now", action: onSkip)
                .buttonStyle(LinkButtonStyle())
                .padding(.vertical, 6)
        }
        .padding(22)
    }
}

/// Screen 3: pick the wake-up time and days.
struct WakeUpTimeView: View {
    var onDone: (Alarm) -> Void

    @State private var time = TimeOfDay.sevenAM
    @State private var days = Weekday.weekdays

    var body: some View {
        VStack(spacing: 18) {
            Text("When do you want to wake up?")
                .font(Theme.title(28))
                .multilineTextAlignment(.center)
                .padding(.top, 40)
            DatePicker("Wake-up time", selection: $time.asDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
            DayButtons(selection: $days)
            Spacer()
            Button("Set my alarm") { onDone(Alarm(time: time, days: days)) }
                .buttonStyle(PillButtonStyle())
                .disabled(days.isEmpty)
                .opacity(days.isEmpty ? 0.5 : 1)
        }
        .padding(22)
    }
}

#Preview {
    OnboardingFlow {}
        .environment(AlarmsModel.preview([]))
}
