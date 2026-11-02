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
    @Environment(ProModel.self) private var pro
    @Environment(AlarmsModel.self) private var model
    @AppStorage(Wardrobe.key) private var outfitID = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    PenguinView(mood: mood, accessory: newOutfit?.accessory ?? wearing)
                        .frame(maxWidth: 200)
                        .padding(.top, 24)
                    Text(title)
                        .titleFont(34)
                        .multilineTextAlignment(.center)
                    Text(line)
                        .font(Theme.body)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    if !upActions.isEmpty {
                        UpChips(actions: upActions)
                    }
                    if let newOutfit {
                        NewOutfitCard(outfit: newOutfit, wearing: outfitID == newOutfit.rawValue) {
                            outfitID = newOutfit.rawValue
                            Telemetry.count("outfit.changed", ["outfit": newOutfit.rawValue])
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
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

    /// What "When you're up" just did, shown as chips.
    private var upActions: [HomeAction] {
        guard let record else { return [] }
        return model.alarms.first { $0.id == record.alarmID }?.upActions ?? []
    }

    /// What Squawk wears today (see Settings).
    private var wearing: PenguinAccessory? {
        Wardrobe.accessory(outfitID: outfitID, access: pro.access, bestStreak: log.bestStreak)
    }

    /// The outfit this morning's streak just earned, for someone without Pro.
    private var newOutfit: Outfit? {
        guard record?.outcome == .firstRing, !pro.access.allows(.outfits) else { return nil }
        return Outfit.newlyEarned(streak: log.streak, bestStreak: log.bestStreak)
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

/// "New outfit!" after a streak earns one, with a button to put it on.
private struct NewOutfitCard: View {
    var outfit: Outfit
    var wearing: Bool
    var onWear: () -> Void

    var body: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: "gift.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.bounce, value: wearing)
                VStack(alignment: .leading, spacing: 4) {
                    Text("New outfit: \(outfit.name.lowercased())!").font(Theme.label)
                    Text(outfit.howToGet.capitalizedFirst + ". Squawk earned it.")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    Button(wearing ? "Wearing it" : "Wear it", action: onWear)
                        .buttonStyle(LinkButtonStyle())
                        .disabled(wearing)
                }
                Spacer(minLength: 0)
            }
        }
        .background(Theme.sun.opacity(0.2), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#Preview("First ring") {
    GoodMorningView(
        record: MorningRecord(alarmID: UUID(), date: LocalDate(Date()), outcome: .firstRing, upAt: Date(), ringNumber: 1, ringCount: 3),
        log: MorningsLog(),
        onClose: {}
    )
    .environment(ProModel.preview())
    .environment(AlarmsModel.preview())
}

#Preview("Last ring, large text") {
    GoodMorningView(
        record: MorningRecord(alarmID: UUID(), date: LocalDate(Date()), outcome: .lastRing, upAt: Date(), ringNumber: 3, ringCount: 3),
        log: MorningsLog(),
        onClose: {}
    )
    .environment(ProModel.preview())
    .environment(AlarmsModel.preview())
    .dynamicTypeSize(.accessibility3)
}

/// "Blinds opening", "Coffee maker on": what "When you're up" just did.
private struct UpChips: View {
    var actions: [HomeAction]
    @State private var shown = false

    var body: some View {
        FlowChips {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                HStack(spacing: 6) {
                    ThingIcon(kind: .home(action.kind), size: 20)
                    Text(action.summary)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.ice, in: Capsule())
                .scaleEffect(shown ? 1 : 0.4)
                .opacity(shown ? 1 : 0)
                .animation(.spring(duration: 0.5, bounce: 0.45).delay(0.3 + Double(index) * 0.08), value: shown)
            }
        }
        .onAppear { shown = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("When you're up: " + actions.map(\.summary).joined(separator: ", "))
    }
}

/// Lays chips out in rows, wrapping when they don't fit.
private struct FlowChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
