import PenguinKit
import SquawkKit
import SwiftUI

/// Screens 9–11: the wake-up checks for the alarm that's ringing, one after another,
/// with the math way out always one tap away. Ends on Good morning.
struct CheckFlowView: View {
    var alarm: Alarm
    @Environment(AlarmsModel.self) private var model
    @State private var step = 0
    @State private var stage: Stage = .checks

    private enum Stage { case checks, math, done }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch stage {
            case .done:
                GoodMorningView(record: model.goodMorning, log: model.log) {
                    model.closeGoodMorning()
                    model.closeCheck()
                }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            case .math:
                MathWayOut(onSolved: { finish(how: "math") }, onBack: { withAnimation(.spring) { stage = .checks } })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .checks:
                if let check = currentCheck {
                    checkScreen(check)
                        .id(check.id)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .interactiveDismissDisabled()
    }

    private var currentCheck: WakeUpCheck? {
        alarm.checks.indices.contains(step) ? alarm.checks[step] : nil
    }

    private func checkScreen(_ check: WakeUpCheck) -> some View {
        VStack(spacing: 16) {
            HStack {
                TimeLeft(deadline: alarm.checkDeadline(at: Date()))
                Spacer()
                if alarm.checks.count > 1 {
                    Text("\(step + 1) of \(alarm.checks.count)")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
            }
            switch check.kind {
            case .tag: TagCheckView(check: check, onDone: next)
            case .code: CodeCheckView(check: check, onDone: next)
            case .game: GameCheckView(onDone: next)
            }
            Button("Stuck? Answer a math question instead") {
                withAnimation(.spring) { stage = .math }
            }
            .buttonStyle(LinkButtonStyle())
            .padding(.bottom, 8)
        }
        .padding(20)
        .readableWidth()
    }

    private func next() {
        if step + 1 < alarm.checks.count {
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { step += 1 }
        } else {
            finish(how: "checks")
        }
    }

    private func finish(how: String) {
        Task { await model.finishChecks(how: how) }
        withAnimation(.spring(duration: 0.6, bounce: 0.4)) { stage = .done }
    }
}

/// "8:42 left" until the last ring stops coming back.
private struct TimeLeft: View {
    var deadline: Date?

    var body: some View {
        if let deadline {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(deadline.timeIntervalSince(context.date)))
                Label("\(seconds / 60):\(String(format: "%02d", seconds % 60)) left", systemImage: "timer")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

// MARK: Tag

/// Screen 9: "Go scan your tag", where it is, and a pulsing scan target.
private struct TagCheckView: View {
    var check: WakeUpCheck
    var onDone: () -> Void
    @State private var reader = TagReader()
    @State private var pulse = false
    @State private var wrong = 0
    @State private var message: String?

    var body: some View {
        VStack(spacing: 18) {
            PenguinView(mood: .grumpy).frame(width: 120, height: 120)
            Text("Go scan your tag").titleFont(30)
            if !check.place.isEmpty {
                Text("It's on the \(check.place.lowercased()).")
                    .font(Theme.body).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Button(action: scan) {
                ZStack {
                    ForEach(0..<3) { ring in
                        Circle()
                            .stroke(Theme.accent.opacity(0.35), lineWidth: 3)
                            .scaleEffect(pulse ? 1.6 : 0.8)
                            .opacity(pulse ? 0 : 1)
                            .animation(.easeOut(duration: 2).repeatForever(autoreverses: false).delay(Double(ring) * 0.6), value: pulse)
                    }
                    Circle().fill(Theme.accent).frame(width: 130, height: 130)
                    VStack(spacing: 4) {
                        Image(systemName: "wave.3.right").font(.system(size: 34, weight: .bold))
                        Text("Scan").font(Theme.label)
                    }
                    .foregroundStyle(Theme.accentInk)
                }
                .frame(width: 200, height: 200)
            }
            .buttonStyle(SquishStyle())
            .modifier(Shake(count: wrong))
            if let message {
                Text(message).font(Theme.label).foregroundStyle(Theme.coral)
            }
            Spacer(minLength: 0)
        }
        .onAppear { pulse = true }
        .sensoryFeedback(.error, trigger: wrong)
    }

    private func scan() {
        Task {
            guard let id = await reader.scan(prompt: "Hold the top of your iPhone near your tag.") else { return }
            if check.matches(id) {
                onDone()
            } else {
                message = "That's a different tag."
                withAnimation(.default) { wrong += 1 }
            }
        }
    }
}

// MARK: Code

/// "Scan your code": the camera, with a friendly frame.
private struct CodeCheckView: View {
    var check: WakeUpCheck
    var onDone: () -> Void
    @State private var message: String?
    @State private var finished = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Go scan your code").titleFont(30)
            if !check.place.isEmpty {
                Text("It's the \(check.place.lowercased()).")
                    .font(Theme.body).foregroundStyle(Theme.muted)
            }
            CodeScanner { code in
                guard !finished else { return }
                if check.matches(code) {
                    finished = true
                    onDone()
                } else {
                    message = "That's not your code. Keep looking!"
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.accent, lineWidth: 4))
            .overlay(alignment: .bottomTrailing) {
                PenguinView(mood: .grumpy, animated: false).frame(width: 80, height: 80).padding(8)
            }
            if let message {
                Text(message).font(Theme.label).foregroundStyle(Theme.coral)
            }
        }
        .sensoryFeedback(.error, trigger: message)
    }
}

// MARK: Game

/// Screen 10: "How many penguins?" Three rounds. Wrong answers shake, no penalty.
private struct GameCheckView: View {
    var onDone: () -> Void
    @State private var round = 0
    @State private var count = Int.random(in: 3...9)
    @State private var choices: [Int] = []
    @State private var wrong = 0
    private let rounds = 3

    var body: some View {
        VStack(spacing: 16) {
            Text("How many penguins?").titleFont(30)
            Text("Round \(round + 1) of \(rounds)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(0..<count, id: \.self) { index in
                    PenguinView(mood: index % 3 == 0 ? .grumpy : .awake, animated: false)
                        .frame(height: 64)
                }
            }
            .padding(14)
            .background(Theme.ice, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            // VoiceOver reads the count as a question with choices (DESIGN.md "Accessibility").
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(count) penguins. How many penguins? Pick the number below.")
            .id(round)
            .transition(.scale.combined(with: .opacity))
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                ForEach(choices, id: \.self) { choice in
                    Button("\(choice)") { pick(choice) }
                        .titleFont(28)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .buttonStyle(SquishStyle())
                }
            }
            .modifier(Shake(count: wrong))
        }
        .sensoryFeedback(.error, trigger: wrong)
        .onAppear(perform: makeChoices)
    }

    private func pick(_ choice: Int) {
        guard choice == count else {
            withAnimation(.default) { wrong += 1 }
            return
        }
        if round + 1 >= rounds {
            onDone()
            return
        }
        withAnimation(.spring(duration: 0.4, bounce: 0.4)) {
            round += 1
            count = Int.random(in: 3...9)
            makeChoices()
        }
    }

    private func makeChoices() {
        var set: Set<Int> = [count]
        while set.count < 4 { set.insert(Int.random(in: 2...10)) }
        choices = set.sorted()
    }
}

// MARK: Math way out

/// Screen 11: one multiplication and a big keypad. Always works, so nobody is stuck.
struct MathWayOut: View {
    var onSolved: () -> Void
    var onBack: () -> Void
    @State private var a = Int.random(in: 12...99)
    @State private var b = Int.random(in: 3...9)
    @State private var answer = ""
    @State private var wrong = 0

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button("Back", action: onBack).buttonStyle(LinkButtonStyle())
                Spacer()
            }
            Text("The way out").titleFont(30)
            Text("\(a) × \(b)")
                .bigNumberFont(56)
            Text(answer.isEmpty ? " " : answer)
                .bigNumberFont(44, weight: .heavy)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .modifier(Shake(count: wrong))
            Spacer(minLength: 0)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "✓"], id: \.self) { key in
                    Button { tap(key) } label: {
                        Text(key)
                            .titleFont(28)
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .background(key == "✓" ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .foregroundStyle(key == "✓" ? Theme.accentInk : Theme.ink)
                    }
                    .buttonStyle(SquishStyle())
                    .accessibilityLabel(key == "⌫" ? "Delete" : key == "✓" ? "Check answer" : key)
                }
            }
        }
        .padding(20)
        .readableWidth()
        .sensoryFeedback(.error, trigger: wrong)
    }

    private func tap(_ key: String) {
        switch key {
        case "⌫":
            if !answer.isEmpty { answer.removeLast() }
        case "✓":
            if Int(answer) == a * b {
                onSolved()
            } else {
                answer = ""
                withAnimation(.default) { wrong += 1 }
            }
        default:
            if answer.count < 4 { answer += key }
        }
    }
}
