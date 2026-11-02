import Foundation

/// One Home automation to set up: a step's Home things and when they run. The app turns
/// each one into a HomeKit action set plus a trigger, which the Home hub runs.
public struct PlannedHomeStep: Hashable, Sendable {
    /// Stable for the same alarm, step and day group, so re-planning gives the same ids.
    public let id: UUID
    public let alarmID: UUID
    public let offsetMinutes: Int
    public let schedule: PlannedRing.Schedule
    public let actions: [HomeAction]
    /// What the Home app shows: "Squawk · Wake up · 6:30".
    public let name: String

    /// Changes whenever what the automation does or when it runs changes, so syncing
    /// knows to rebuild it.
    public var fingerprint: String {
        let when: String
        switch schedule {
        case .weekly(let time, let days): when = "w\(time.hour):\(time.minute)|\(days.map(\.rawValue))"
        case .once(let date): when = "o\(Int(date.timeIntervalSince1970))"
        }
        let what = actions.map { a in
            "\(a.kind.rawValue)|\(a.targets.map(\.id.uuidString).sorted())|\(a.setting.isOn)|\(a.setting.brightness ?? -1)|\(a.setting.warmth ?? -1)|\(a.setting.position ?? -1)"
        }
        return StableID.make("\(name)|\(when)|\(what)").uuidString
    }
}

/// Turns alarms into the Home automations to set up, with the same rules as rings
/// (`AlarmPlanner`): days that share a time get one weekly automation per step, and a
/// day whose next morning has a change (skip, a new time, already up) gets one-off
/// automations for a few weeks, until a re-plan puts it back on weekly.
public enum HomePlanner {
    public static func plan(_ alarms: [Alarm], now: Date, calendar: Calendar = .current) -> [PlannedHomeStep] {
        alarms.filter(\.isOn).flatMap { plan($0, now: now, calendar: calendar) }
    }

    public static func plan(_ alarm: Alarm, now: Date, calendar: Calendar = .current) -> [PlannedHomeStep] {
        let steps = alarm.steps.filter { !$0.actions.isEmpty }
        guard !steps.isEmpty else { return [] }

        func once(_ day: LocalDate) -> [PlannedHomeStep] {
            guard let wake = alarm.wakeTime(on: day, calendar: calendar),
                  let base = day.date(at: wake, calendar: calendar) else { return [] }
            return steps.compactMap { step in
                let fire = base.addingTimeInterval(Double(step.offsetMinutes) * 60)
                guard fire > now else { return nil }
                return PlannedHomeStep(
                    id: StableID.make("home|\(alarm.id)|\(step.offsetMinutes)|\(day)"),
                    alarmID: alarm.id, offsetMinutes: step.offsetMinutes, schedule: .once(fire),
                    actions: step.actions, name: name(alarm, wake.adding(minutes: step.offsetMinutes))
                )
            }
        }

        if let date = alarm.date {
            return once(date)
        }

        let changed = AlarmPlanner.changedWeekdays(alarm, now: now, calendar: calendar)
        var result: [PlannedHomeStep] = []
        for (_, day) in changed.sorted(by: { $0.value < $1.value }) {
            for week in 0...AlarmPlanner.weeksAhead {
                result += once(day.adding(days: 7 * week, calendar: calendar))
            }
        }

        let weeklyDays = alarm.days.subtracting(changed.keys)
        for group in alarm.timeGroups(for: weeklyDays) {
            for step in steps {
                let shifted = group.time.minutesAfterMidnight + step.offsetMinutes
                let dayShift = Int((Double(shifted) / 1440).rounded(.down))
                let time = group.time.adding(minutes: step.offsetMinutes)
                let days = group.days.map { AlarmPlanner.shift($0, by: dayShift) }.sorted()
                result.append(PlannedHomeStep(
                    id: StableID.make("home|\(alarm.id)|\(step.offsetMinutes)|\(group.days.map(\.rawValue))"),
                    alarmID: alarm.id, offsetMinutes: step.offsetMinutes, schedule: .weekly(time, days),
                    actions: step.actions, name: name(alarm, time)
                ))
            }
        }
        return result
    }

    /// "Squawk · Wake up · 6:30", or the alarm's label instead of "Wake up".
    static func name(_ alarm: Alarm, _ time: TimeOfDay) -> String {
        "Squawk · \(alarm.title) · \(time.short)"
    }

    /// Every automation Squawk makes starts with this, so it can tell its own apart.
    public static let namePrefix = "Squawk · "
}
