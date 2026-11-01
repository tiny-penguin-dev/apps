import PenguinKit
import SquawkKit
import SwiftUI
import UIKit
import WidgetKit

/// The next alarm, on the home screen (small and medium) and the lock screen.
struct NextAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextAlarm", provider: NextAlarmProvider()) { entry in
            NextAlarmView(entry: entry)
                .containerBackground(for: .widget) { WidgetColors.background }
        }
        .configurationDisplayName("Next alarm")
        .description("When Squawk wakes you up next.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct NextAlarmEntry: TimelineEntry {
    var date: Date
    var wakeUp: WidgetSnapshot.WakeUp?
    var streak: Int
}

/// One entry now, then one right after each wake-up, so the widget moves on to the next
/// morning by itself.
struct NextAlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextAlarmEntry {
        NextAlarmEntry(date: .now, wakeUp: .init(at: .now.addingTimeInterval(8 * 3600), title: "Wake up", ringCount: 1), streak: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries(now: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        completion(Timeline(entries: entries(now: .now), policy: .atEnd))
    }

    private func entries(now: Date) -> [NextAlarmEntry] {
        let snapshot = WidgetSnapshotStore.shared.load()
        var entries = [NextAlarmEntry(date: now, wakeUp: snapshot.next(after: now), streak: snapshot.streak)]
        for wakeUp in snapshot.wakeUps where wakeUp.at > now {
            let after = wakeUp.at.addingTimeInterval(60)
            entries.append(NextAlarmEntry(date: after, wakeUp: snapshot.next(after: after), streak: snapshot.streak))
        }
        return entries
    }
}

struct NextAlarmView: View {
    var entry: NextAlarmEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            if let wakeUp = entry.wakeUp {
                Label("\(dayName(wakeUp.at)) \(wakeUp.at.formatted(date: .omitted, time: .shortened))", systemImage: "alarm.fill")
            } else {
                Label("No alarms", systemImage: "alarm")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "alarm.fill").font(.caption2)
                    Text(entry.wakeUp.map { shortTime($0.at) } ?? "Off")
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .minimumScaleFactor(0.6)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Squawk", systemImage: "alarm.fill")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                if let wakeUp = entry.wakeUp {
                    Text(wakeUp.at, style: .time)
                        .font(.system(.title2, design: .rounded, weight: .black))
                    Text(dayName(wakeUp.at))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                } else {
                    Text("No alarms on").font(.system(.headline, design: .rounded, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            HStack(spacing: 14) {
                penguin
                details
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    penguin.frame(width: 54, height: 54)
                    Spacer(minLength: 0)
                    if entry.streak > 0 { streakChip }
                }
                Spacer(minLength: 0)
                time
                Text(entry.wakeUp.map { dayName($0.at) } ?? "No alarms on")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(WidgetColors.muted)
            }
        }
    }

    private var penguin: some View {
        PenguinView(mood: entry.wakeUp == nil ? .awake : .asleep, accessory: entry.wakeUp == nil ? nil : .nightcap, animated: false)
    }

    @ViewBuilder private var time: some View {
        if let wakeUp = entry.wakeUp {
            Text(wakeUp.at, style: .time)
                .font(.system(.title, design: .rounded, weight: .black))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(WidgetColors.ink)
        } else {
            Text("Off")
                .font(.system(.title, design: .rounded, weight: .black))
                .foregroundStyle(WidgetColors.ink)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.wakeUp.map { dayName($0.at) } ?? "Squawk is sleeping in")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(WidgetColors.muted)
            time
            if let wakeUp = entry.wakeUp {
                Text(wakeUp.ringCount > 1 ? "\(wakeUp.title) · \(wakeUp.ringCount) rings" : wakeUp.title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(WidgetColors.muted)
                    .lineLimit(1)
            }
            if entry.streak > 0 { streakChip }
        }
    }

    private var streakChip: some View {
        Label("\(entry.streak)", systemImage: "fish.fill")
            .font(.system(.caption, design: .rounded, weight: .heavy))
            .foregroundStyle(WidgetColors.ink)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(WidgetColors.sun.opacity(0.3), in: Capsule())
            .accessibilityLabel("\(entry.streak) mornings in a row up on the first ring")
    }

    /// "Today", "Tomorrow" or the weekday.
    private func dayName(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// "7:00", without AM or PM, for the small round lock screen widget.
    private func shortTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
    }
}

/// The few colors the widget needs, from DESIGN.md "Look" (the app's `Theme` lives in
/// the app target).
enum WidgetColors {
    static let background = Color(light: 0xF4F7FF, dark: 0x11182E)
    static let ink = Color(light: 0x1E2945, dark: 0xEEF2FF)
    static let muted = Color(light: 0x6B7594, dark: 0x9AA5C6)
    static let sun = Color(light: 0xFFC24D, dark: 0xFFCD66)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

#Preview(as: .systemSmall) {
    NextAlarmWidget()
} timeline: {
    NextAlarmEntry(date: .now, wakeUp: .init(at: .now.addingTimeInterval(8 * 3600), title: "Work", ringCount: 2), streak: 5)
    NextAlarmEntry(date: .now, wakeUp: nil, streak: 0)
}

#Preview(as: .systemMedium) {
    NextAlarmWidget()
} timeline: {
    NextAlarmEntry(date: .now, wakeUp: .init(at: .now.addingTimeInterval(8 * 3600), title: "Work", ringCount: 2), streak: 5)
}

#Preview(as: .accessoryRectangular) {
    NextAlarmWidget()
} timeline: {
    NextAlarmEntry(date: .now, wakeUp: .init(at: .now.addingTimeInterval(8 * 3600), title: "Work", ringCount: 2), streak: 5)
}
