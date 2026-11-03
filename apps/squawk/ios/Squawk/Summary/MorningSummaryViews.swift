import SquawkKit
import SwiftUI

/// The Today card on Good morning: the weather and the first event of the day. Either
/// half can be missing (off, not allowed, or the weather didn't load in time).
struct TodayCard: View {
    var weather: SummaryWeather?
    var agenda: Agenda?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Today").font(Theme.label)
                if let weather {
                    WeatherRow(weather: weather)
                }
                if weather != nil, agenda != nil {
                    Divider()
                }
                if let agenda {
                    AgendaRow(agenda: agenda)
                }
                if let credit = weather?.credit {
                    WeatherCreditView(credit: credit)
                }
            }
        }
    }
}

/// "☁️ 12°  H 16° · L 9°  Rain from 3 PM".
private struct WeatherRow: View {
    var weather: SummaryWeather
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            Image(systemName: weather.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(.largeTitle, design: .rounded))
                .frame(minWidth: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Self.degrees(weather.now)).titleFont(30)
                    Text("H \(Self.degrees(weather.high)) · L \(Self.degrees(weather.low))")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                if let note = weather.note {
                    Text(Self.text(for: note))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [
            "\(weather.condition), \(Self.degrees(weather.now))",
            "high \(Self.degrees(weather.high)), low \(Self.degrees(weather.low))",
        ]
        if let note = weather.note { parts.append(Self.text(for: note)) }
        return parts.joined(separator: ". ")
    }

    /// "12°", in the phone's units.
    static func degrees(_ temperature: Measurement<UnitTemperature>) -> String {
        temperature.formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static func text(for note: WeatherNote) -> String {
        switch note {
        case .rain(let from): from <= Date() ? "Rain now" : "Rain from \(from.formatted(.dateTime.hour()))"
        case .snow(let from): from <= Date() ? "Snow now" : "Snow from \(from.formatted(.dateTime.hour()))"
        case .windy: "Windy today"
        }
    }
}

/// "9:30 · Standup", "and 2 more", or "Nothing on the calendar today."
private struct AgendaRow: View {
    var agenda: Agenda

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "calendar")
                .font(.body.weight(.heavy))
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                switch agenda {
                case .empty:
                    Text("Nothing on the calendar today.")
                        .font(.system(.body, design: .rounded, weight: .bold))
                case .next(let event, let started, let more):
                    Text("\(started ? "Now" : event.start.formatted(date: .omitted, time: .shortened)) · \(event.title)")
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .lineLimit(2)
                    if more > 0 {
                        Text("and \(more) more")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Apple's Weather mark and its "Data sources" link, which WeatherKit requires next to
/// the weather.
private struct WeatherCreditView: View {
    var credit: WeatherCredit
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: colorScheme == .dark ? credit.darkMark : credit.lightMark) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text("Apple Weather").font(.caption2.weight(.semibold))
            }
            .frame(height: 12)
            .accessibilityLabel("Apple Weather")
            Link("Data sources", destination: credit.legalPage)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 44)
        }
    }
}

/// "Add the weather and your day", shown on Good morning until the summary is on or
/// "Not now" is tapped. Without Pro, it carries the Pro tag and opens the Pro screen.
struct SummaryOfferCard: View {
    var locked: Bool
    var working: Bool
    var onTurnOn: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sun.max.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.sun)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Add the weather and your day").font(Theme.label)
                        if locked { ProBadge() }
                    }
                    Text("See today's weather and your first event right here. Squawk asks for your rough location and your calendar. Both stay between your phone and Apple.")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 18) {
                        Button(working ? "Asking…" : "Turn it on", action: onTurnOn)
                            .buttonStyle(LinkButtonStyle())
                            .disabled(working)
                        Button("Not now", action: onNotNow)
                            .buttonStyle(LinkButtonStyle())
                            .foregroundStyle(Theme.muted)
                            .disabled(working)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Settings → Morning summary: a switch for the weather and one for the calendar, with a
/// way back when iOS Settings turned one off.
struct SummarySettingsCard: View {
    var onLocked: () -> Void
    @Environment(MorningSummaryModel.self) private var summary
    @Environment(ProModel.self) private var pro

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("Morning summary").font(Theme.label)
                    if locked { ProBadge() }
                }
                Text("Today's weather and your first event on Good morning.")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Toggle(isOn: binding(summary.settings.weather) { _ = await summary.setWeather($0) }) {
                    Label("Weather", systemImage: "cloud.sun.fill").font(Theme.label)
                }
                .tint(Theme.mint)
                if summary.weatherAccess == .denied {
                    DeniedNote(text: "Location is off for Squawk in iOS Settings.")
                }
                Toggle(isOn: binding(summary.settings.calendar) { _ = await summary.setCalendar($0) }) {
                    Label("First event", systemImage: "calendar").font(Theme.label)
                }
                .tint(Theme.mint)
                if summary.calendarAccess == .denied {
                    DeniedNote(text: "Calendar access is off for Squawk in iOS Settings.")
                }
            }
        }
        .onAppear { summary.refreshAccess() }
    }

    private var locked: Bool { !pro.access.allows(.summary) }

    private func binding(_ value: Bool, set: @escaping @MainActor (Bool) async -> Void) -> Binding<Bool> {
        Binding(
            get: { value && !locked },
            set: { on in
                if locked {
                    onLocked()
                } else {
                    Task { await set(on) }
                }
            }
        )
    }
}

/// "Turned off in iOS Settings" with a button there.
private struct DeniedNote: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(LinkButtonStyle())
        }
    }
}

#Preview("Today") {
    VStack(spacing: 16) {
        TodayCard(weather: .preview, agenda: Agenda(events: MorningSummaryModel.previewEvents, now: Date()))
        TodayCard(weather: nil, agenda: .empty)
        SummaryOfferCard(locked: true, working: false, onTurnOn: {}, onNotNow: {})
    }
    .padding()
    .background(Theme.background)
}

#Preview("Today, large text") {
    TodayCard(weather: .preview, agenda: Agenda(events: MorningSummaryModel.previewEvents, now: Date()))
        .padding()
        .background(Theme.background)
        .dynamicTypeSize(.accessibility3)
}
