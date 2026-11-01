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
