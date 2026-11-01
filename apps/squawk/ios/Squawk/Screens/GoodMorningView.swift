import PenguinKit
import SquawkKit
import SwiftUI

/// Screen 12: Squawk's reaction to how the morning went, this week's dots and the
/// streak, with fish confetti for a first-ring morning.
struct GoodMorningView: View {
    /// The morning to react to. Nil shows a plain "Rise and waddle!".
    var record: MorningRecord?
    var log: MorningsLog
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    PenguinView(mood: mood)
                        .frame(maxWidth: 200)
                        .padding(.top, 24)
                    Text(title)
                        .font(Theme.title(34))
                        .multilineTextAlignment(.center)
                    Text(line)
                        .font(Theme.body)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("This week").font(Theme.label)
                            WeekDots(week: log.week(of: Date()))
                            if log.streak > 0 {
                                Label(streakText, systemImage: "fish.fill")
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            if record?.outcome == .firstRing {
                FishConfetti().ignoresSafeArea()
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Start my day", action: onClose)
                .buttonStyle(PillButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .frame(maxWidth: 560)
        }
        .sensoryFeedback(.success, trigger: record?.id)
    }

    private var mood: PenguinMood {
        switch record?.outcome {
        case .firstRing, nil: .proud
        case .fine: .awake
        case .lastRing: .grumpy
        case .fainted: .faint
        }
    }

    private var title: String {
        switch record?.outcome {
        case .firstRing: "Up on the first ring!"
        case .fainted: "Squawk fainted"
        default: "Rise and waddle!"
        }
    }

    private var line: String {
        guard let record else { return "You're up. The rest of this morning's rings are off." }
        let time = record.upAt.map { TimeOfDay(pickerDate: $0).full } ?? ""
        switch record.outcome {
        case .firstRing:
            return "Up at \(time). Squawk is very proud."
        case .fine:
            return "Up at \(time), on ring \(record.ringNumber) of \(record.ringCount)."
        case .lastRing:
            return "Up at \(time), on the last ring. Tomorrow, let's try the first one."
        case .fainted:
            return "The alarm rang for 10 minutes and nobody came. Let's try again tomorrow."
        }
    }

    private var streakText: String {
        log.streak == 1 ? "1 morning up on the first ring" : "\(log.streak) mornings in a row up on the first ring"
    }
}

#Preview("First ring") {
    GoodMorningView(
        record: MorningRecord(alarmID: UUID(), date: LocalDate(Date()), outcome: .firstRing, upAt: Date(), ringNumber: 1, ringCount: 3),
        log: MorningsLog(),
        onClose: {}
    )
}

#Preview("Last ring, large text") {
    GoodMorningView(
        record: MorningRecord(alarmID: UUID(), date: LocalDate(Date()), outcome: .lastRing, upAt: Date(), ringNumber: 3, ringCount: 3),
        log: MorningsLog(),
        onClose: {}
    )
    .dynamicTypeSize(.accessibility3)
}
