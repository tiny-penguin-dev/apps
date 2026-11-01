import SquawkKit
import SwiftUI

/// A white (or night navy) rounded card.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Round day buttons, Monday first. Shrink a bit on tap, with a light haptic.
struct DayButtons: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(day.letter)
                        .font(.system(.body, design: .rounded, weight: .heavy))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Circle().fill(on ? Theme.accent : Theme.ice))
                        .foregroundStyle(on ? Theme.accentInk : Theme.ink)
                }
                .buttonStyle(SquishStyle())
                .accessibilityLabel(day.full)
                .accessibilityAddTraits(on ? .isSelected : [])
                .sensoryFeedback(.selection, trigger: on)
            }
        }
    }
}

/// Shrinks a little while pressed.
struct SquishStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.5), value: configuration.isPressed)
    }
}

/// A small text button in the main color, like "+ Different time on a day".
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(Theme.accent)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// A banner at the top of Home for things that need attention.
struct Banner: View {
    var text: String
    var button: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(text)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let button {
                Button(button, action: action)
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.accent))
                    .foregroundStyle(Theme.accentInk)
            }
        }
        .padding(14)
        .background(Theme.coral.opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension TimeOfDay {
    /// Today at this time, for the time pickers.
    var pickerDate: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    init(pickerDate date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 7, minute: c.minute ?? 0)
    }
}

extension Binding where Value == TimeOfDay {
    /// The same time as a `Date`, for `DatePicker`.
    var asDate: Binding<Date> {
        Binding<Date>(get: { wrappedValue.pickerDate }, set: { wrappedValue = TimeOfDay(pickerDate: $0) })
    }
}

/// The fish streak chip on Home: mornings in a row up on the first ring.
struct StreakChip: View {
    var streak: Int

    var body: some View {
        Label("\(streak)", systemImage: "fish.fill")
            .font(.system(.subheadline, design: .rounded, weight: .heavy))
            .monospacedDigit()
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.sun.opacity(0.25), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(streak == 1 ? "1 morning up on the first ring" : "\(streak) mornings in a row up on the first ring")
    }
}

/// This week's mornings, Monday to Sunday: a dot per day, colored by how it went.
struct WeekDots: View {
    var week: [Weekday: MorningRecord.Outcome]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Weekday.allCases) { day in
                VStack(spacing: 6) {
                    Circle()
                        .fill(week[day].map(\.color) ?? Theme.ice)
                        .frame(width: 22, height: 22)
                        .overlay {
                            if week[day] == .firstRing {
                                Image(systemName: "star.fill").font(.system(size: 10, weight: .black)).foregroundStyle(.white)
                            }
                        }
                    Text(day.letter)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.full): \(week[day]?.spoken ?? "no alarm")")
            }
        }
    }
}

extension MorningRecord.Outcome {
    /// Mint for the first ring, sun in between, coral for the last ring, muted for a faint.
    var color: Color {
        switch self {
        case .firstRing: Theme.mint
        case .fine: Theme.sun
        case .lastRing: Theme.coral
        case .fainted: Theme.muted
        }
    }

    var spoken: String {
        switch self {
        case .firstRing: "up on the first ring"
        case .fine: "up before the last ring"
        case .lastRing: "up on the last ring"
        case .fainted: "the alarm ran out"
        }
    }
}

/// The little "PRO" tag next to anything that needs Squawk Pro. Tapping the thing it
/// marks opens the Pro screen.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(.caption2, design: .rounded, weight: .black))
            .tracking(0.8)
            .foregroundStyle(Theme.sunInk)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.sun, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel("Needs Pro")
    }
}

/// A link-style button that opens the Pro screen when `locked`, with a PRO badge.
/// Use it for "+ Add a check" and the like: the label stays the same either way.
struct ProLinkButton: View {
    var title: String
    var locked: Bool
    var action: () -> Void
    var onLocked: () -> Void

    var body: some View {
        Button {
            if locked { onLocked() } else { action() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if locked { ProBadge() }
            }
        }
        .buttonStyle(LinkButtonStyle())
    }
}

#Preview("Pro badge") {
    VStack(alignment: .leading, spacing: 16) {
        ProBadge()
        ProLinkButton(title: "+ Add a check", locked: true, action: {}, onLocked: {})
        ProLinkButton(title: "+ Add a check", locked: false, action: {}, onLocked: {})
    }
    .padding()
    .background(Theme.background)
}

extension View {
    /// Keeps a screen's content at a comfortable width and centered on wide screens, like
    /// the iPhone Duo's inner screen, instead of stretching it edge to edge.
    func readableWidth(_ maxWidth: CGFloat = 640) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}

extension View {
    /// Shows the content as is when it fits, and scrolls it when it doesn't, like a
    /// setup screen at the largest text size or on the iPhone Duo's short outer screen.
    func scrollsWhenTight() -> some View {
        ViewThatFits(in: .vertical) {
            self
            ScrollView { self }
        }
    }
}
