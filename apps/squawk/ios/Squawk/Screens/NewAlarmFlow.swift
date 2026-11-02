import PenguinKit
import SquawkKit
import SwiftUI

/// "+" on Home: a short guide, one question per screen, so a new alarm never starts as a
/// wall of options (features/steps/FEATURE.md, "Guided new alarm"). "All options" on
/// every screen swaps to the full edit screen with what's picked so far.
struct NewAlarmFlow: View {
    @State private var guide = NewAlarmGuide()
    @State private var question = Question.time
    @State private var allOptions: Alarm?
    @State private var forward = true
    @State private var addingCheck: WakeUpCheck.Kind?
    @State private var paywall: ProFeature?
    @State private var startedAt = Date()

    @Environment(AlarmsModel.self) private var model
    @Environment(ProModel.self) private var pro
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The guide's screens, in order.
    enum Question: Int, CaseIterable {
        case time, wake, check, done
    }

    var body: some View {
        if let allOptions {
            EditAlarmView(alarm: allOptions, isNew: true)
        } else {
            NavigationStack {
                ZStack {
                    screen
                        .id(question)
                        .transition(slide)
                }
                .background(Theme.background)
                .toolbar { toolbar }
                .navigationBarTitleDisplayMode(.inline)
            }
            .foregroundStyle(Theme.ink)
            .tint(Theme.accent)
            .sheet(item: $addingCheck) { kind in
                AddCheckSheet(kind: kind) { guide.check = $0 }
            }
            .sheet(item: $paywall, onDismiss: finishAfterPaywall) { feature in
                ProView(from: feature)
            }
        }
    }

    // MARK: Screens

    @ViewBuilder private var screen: some View {
        switch question {
        case .time: timeScreen
        case .wake: wakeScreen
        case .check: checkScreen
        case .done: doneScreen
        }
    }

    private var timeScreen: some View {
        GuideScreen(title: "When do you want to wake up?", mood: .asleep, nextDisabled: guide.days.isEmpty, next: { go(.wake) }) {
            DatePicker("Wake-up time", selection: $guide.time.asDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            DayButtons(selection: $guide.days)
            Text("Different time on some days? You can add that in All options.")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var wakeScreen: some View {
        GuideScreen(title: "How should Squawk wake you?", mood: .awake, next: { go(.check) }) {
            choice(.one, "Just one ring", "Morning squawk at wake-up time. Simple.", offsets: [0])
            choice(.gentle, "Gentle start", "A soft peep 10 minutes early, then Morning squawk.", offsets: [-10, 0])
            choice(.nudge, "Extra nudge", "Morning squawk, then the Whole colony 5 minutes later if you're still in bed.", offsets: [0, 5])
            GuideHint("You can pick the sounds and add more rings later.")
        }
    }

    private var checkScreen: some View {
        GuideScreen(
            title: "Make sure you get up?", mood: .grumpy,
            subtitle: "To turn the alarm off, do something that gets you out of bed. Until then, it keeps ringing.",
            next: { go(.done) }
        ) {
            ChoiceCard(
                title: "No check", subtitle: "Turn it off from the lock screen, like a normal alarm.",
                selected: guide.check == nil
            ) { guide.check = nil }
            ForEach(WakeUpCheck.Kind.allCases) { kind in
                ChoiceCard(
                    title: kind.title, subtitle: kind.guideLine,
                    selected: guide.check?.kind == kind,
                    pro: !pro.access.allows(.checks),
                    detail: guide.check?.kind == kind ? guide.check?.place : nil
                ) {
                    if kind == .game {
                        guide.check = WakeUpCheck(kind: .game)
                    } else if guide.check?.kind != kind {
                        addingCheck = kind
                    }
                }
            }
        }
    }

    private var doneScreen: some View {
        let alarm = guide.alarm
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Here's your morning").titleFont(28)
                        Text("\(alarm.scheduleLine()) · \(alarm.time.full)")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    PenguinView(mood: .proud).frame(width: 76, height: 76)
                }
                StepTimeline(alarm: alarm) { step in
                    StepCard(step: step, wake: alarm.time, checks: alarm.checks)
                }
                if !missingPro.isEmpty {
                    GuideHint("Wake-up checks are part of Squawk Pro. You'll see the plans when you save.")
                }
            }
            .padding(20)
            .readableWidth()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button("Save alarm", action: save)
                    .buttonStyle(PillButtonStyle())
                Button("Fine-tune in All options") { showAllOptions() }
                    .buttonStyle(LinkButtonStyle())
                    .padding(.vertical, 6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .readableWidth()
            .background(Theme.background)
        }
    }

    private func choice(_ wake: NewAlarmGuide.Wake, _ title: String, _ subtitle: String, offsets: [Int]) -> some View {
        ChoiceCard(title: title, subtitle: subtitle, selected: guide.wake == wake, times: offsets.map { guide.time.adding(minutes: $0).short }) {
            guide.wake = wake
        }
    }

    // MARK: Top bar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if question == .time {
                Button("Cancel") { dismiss() }
            } else {
                Button { back() } label: { Label("Back", systemImage: "chevron.left") }
            }
        }
        ToolbarItem(placement: .principal) {
            if question != .done { ProgressDots(count: Question.allCases.count - 1, current: question.rawValue) }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("All options") { showAllOptions() }
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Moving around

    private var slide: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading),
            removal: .move(edge: forward ? .leading : .trailing)
        ).combined(with: .opacity)
    }

    private func go(_ next: Question) {
        forward = next.rawValue > question.rawValue
        withAnimation(.spring(duration: 0.45, bounce: 0.25)) { question = next }
    }

    private func back() {
        guard let previous = Question(rawValue: question.rawValue - 1) else { return dismiss() }
        go(previous)
    }

    private func showAllOptions() {
        Telemetry.count("guide.all_options", ["at": "\(question)"])
        withAnimation { allOptions = guide.alarm }
    }

    // MARK: Saving

    /// Pro features the answers use that this person doesn't have.
    private var missingPro: Set<ProFeature> {
        guide.proFeatures.filter { !pro.access.allows($0) }
    }

    private func save() {
        if let feature = missingPro.sorted(by: { $0.rawValue < $1.rawValue }).first {
            paywall = feature
            return
        }
        finish(guide.alarm)
    }

    /// After the Pro screen: the whole alarm if they got Pro, otherwise the alarm
    /// without its Pro parts.
    private func finishAfterPaywall() {
        finish(missingPro.isEmpty ? guide.alarm : guide.freeAlarm)
    }

    private func finish(_ alarm: Alarm) {
        model.save(alarm)
        Telemetry.duration("guide.finished", seconds: Date().timeIntervalSince(startedAt))
        dismiss()
    }
}

// MARK: - Pieces

/// One guide screen: the question with Squawk beside it, the answers, and Next.
private struct GuideScreen<Content: View>: View {
    var title: String
    var mood: PenguinMood
    var subtitle: String?
    var nextDisabled = false
    var next: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 12) {
                    Text(title)
                        .titleFont(28)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    PenguinView(mood: mood).frame(width: 72, height: 72)
                }
                if let subtitle {
                    Text(subtitle).font(Theme.body).foregroundStyle(Theme.muted)
                }
                content
            }
            .padding(20)
            .readableWidth()
        }
        .safeAreaInset(edge: .bottom) {
            Button("Next", action: next)
                .buttonStyle(PillButtonStyle())
                .disabled(nextDisabled)
                .opacity(nextDisabled ? 0.5 : 1)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .readableWidth()
                .background(Theme.background)
        }
    }
}

/// A big tappable answer. The picked one has an orange outline and a tick.
struct ChoiceCard: View {
    var title: String
    var subtitle: String
    var selected: Bool
    var pro: Bool = false
    var times: [String] = []
    var detail: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title).font(Theme.label)
                    if pro { ProBadge() }
                    Spacer(minLength: 4)
                    ForEach(times, id: \.self) { time in
                        Text(time)
                            .font(.system(.caption, design: .rounded, weight: .heavy))
                            .monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.ice, in: Capsule())
                    }
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(selected ? Theme.accent : Theme.muted.opacity(0.4))
                }
                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.leading)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.08) : Color.clear)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? Theme.accent : Color.clear, lineWidth: 3)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(SquishStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// The dots at the top of the guide: where you are and how many questions are left.
private struct ProgressDots: View {
    var count: Int
    var current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Theme.accent : i < current ? Theme.accent.opacity(0.45) : Theme.muted.opacity(0.25))
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.4), value: current)
        .accessibilityElement()
        .accessibilityLabel("Question \(current + 1) of \(count)")
    }
}

/// A short quiet line under the answers.
private struct GuideHint: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.ice.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension WakeUpCheck.Kind {
    /// The line under each check in the guide.
    var guideLine: String {
        switch self {
        case .tag: "Stick a tag by the bathroom mirror and tap your phone on it."
        case .code: "Any QR code or barcode, like the one on your toothpaste."
        case .game: "Count the penguins. Hard to do half asleep."
        }
    }
}

#Preview {
    NewAlarmFlow()
        .environment(AlarmsModel.preview([]))
        .environment(ProModel.preview())
}
