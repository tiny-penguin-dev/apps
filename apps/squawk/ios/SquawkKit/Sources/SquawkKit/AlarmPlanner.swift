import Foundation

/// One AlarmKit alarm to schedule. The app maps these straight onto AlarmKit.
public struct PlannedRing: Hashable, Sendable {
    public enum Schedule: Hashable, Sendable {
        /// Repeats every week on these days at this time.
        case weekly(TimeOfDay, [Weekday])
        /// Rings once.
        case once(Date)
    }

    /// Stable for the same alarm, ring and day group, so re-planning gives the same ids.
    public let id: UUID
    public let alarmID: UUID
    public let ringID: UUID
    public let schedule: Schedule
    public let title: String
    public let sound: AlarmSound
    public let color: RingColor
    /// True for the alarm's last ring (and its repeats, with a wake-up check).
    public let isLastRing: Bool
    /// The alarm has a wake-up check: "Stop" only snoozes, and the way to turn it off
    /// is in the app.
    public var needsCheck: Bool = false
}

extension PlannedRing {
    /// When this ring next goes off after `now`. Nil for a one-off ring that has passed.
    public func nextFire(after now: Date, calendar: Calendar = .current) -> Date? {
        switch schedule {
        case .once(let date):
            return date > now ? date : nil
        case .weekly(let time, let days):
            return days.compactMap { day in
                calendar.nextDate(
                    after: now,
                    matching: DateComponents(hour: time.hour, minute: time.minute, weekday: day.calendarWeekday),
                    matchingPolicy: .nextTime
                )
            }.min()
        }
    }
}

/// Turns saved alarms into the AlarmKit alarms to schedule. This is the one place that
/// decides what rings when (PRODUCT.md 8b), so every feature uses the same path.
public enum AlarmPlanner {
    public static func plan(_ alarms: [Alarm], now: Date, calendar: Calendar = .current) -> [PlannedRing] {
        alarms.filter(\.isOn).flatMap { plan($0, now: now, calendar: calendar) }
    }

    /// How many weeks of one-off rings to plan for a weekday whose next morning has a
    /// change. AlarmKit can't skip one week of a repeating alarm, so that weekday rings
    /// as one-off alarms until the next re-plan (any time the app opens) puts it back
    /// on a weekly repeat.
    static let weeksAhead = 4

    /// Mornings planned ahead for an alarm with a wake-up check. Re-planned whenever the
    /// app opens, a ring is snoozed or a morning ends, so this only runs down when nobody
    /// touches the phone for that many alarm mornings in a row.
    static let checkMorningsAhead = 5

    /// The last ring's repeats are scheduled for this long ahead of now (or of when it
    /// first goes off). Each Snooze re-plans, which schedules the next ones.
    static let checkDenseSeconds: TimeInterval = 120

    /// Past that, only every this-many-seconds repeat is scheduled, as a backup in case
    /// a Snooze doesn't get to re-plan. Keeps an alarm with a check to a few AlarmKit
    /// alarms a morning instead of one every 30 s.
    static let checkBackupSeconds: TimeInterval = 120

    public static func plan(_ alarm: Alarm, now: Date, calendar: Calendar = .current) -> [PlannedRing] {
        if alarm.hasChecks {
            return planWithChecks(alarm, now: now, calendar: calendar)
        }
        let lastID = alarm.sortedRings.last?.id

        func once(_ day: LocalDate) -> [PlannedRing] {
            alarm.ringTimes(on: day, calendar: calendar)
                .filter { $0.fire > now }
                .map { item in
                    PlannedRing(
                        id: StableID.make("\(alarm.id)|\(item.ring.id)|\(day)"),
                        alarmID: alarm.id, ringID: item.ring.id, schedule: .once(item.fire),
                        title: alarm.title, sound: item.ring.sound, color: item.ring.color,
                        isLastRing: item.ring.id == lastID
                    )
                }
        }

        if let date = alarm.date {
            return once(date)
        }

        // Weekdays whose next morning has a change ring as one-off alarms for a while.
        let changed = changedWeekdays(alarm, now: now, calendar: calendar)

        var result: [PlannedRing] = []
        for (_, day) in changed.sorted(by: { $0.value < $1.value }) {
            for week in 0...weeksAhead {
                result += once(day.adding(days: 7 * week, calendar: calendar))
            }
        }

        // Every other group of days with the same time becomes one weekly alarm per ring.
        let weeklyDays = alarm.days.subtracting(changed.keys)
        for group in alarm.timeGroups(for: weeklyDays) {
            for ring in alarm.sortedRings {
                let shifted = group.time.minutesAfterMidnight + ring.offsetMinutes
                let dayShift = Int((Double(shifted) / 1440).rounded(.down))
                let time = group.time.adding(minutes: ring.offsetMinutes)
                let days = group.days.map { shift($0, by: dayShift) }.sorted()
                result.append(PlannedRing(
                    id: StableID.make("\(alarm.id)|\(ring.id)|\(group.days.map(\.rawValue))"),
                    alarmID: alarm.id, ringID: ring.id, schedule: .weekly(time, days),
                    title: alarm.title, sound: ring.sound, color: ring.color, isLastRing: ring.id == lastID
                ))
            }
        }
        return result
    }

    /// With a wake-up check, every ring is a one-off alarm, and the last one comes back
    /// every 30 seconds for 10 minutes. Only the next couple of minutes of repeats are
    /// scheduled, plus a backup every 2 minutes after that: each Snooze re-plans from
    /// its own time, which tops the repeats back up. Doing the check marks the morning
    /// done, and the re-plan cancels the rest.
    static func planWithChecks(_ alarm: Alarm, now: Date, calendar: Calendar) -> [PlannedRing] {
        let days = alarm.date.map { [$0] } ?? checkMornings(alarm, now: now, calendar: calendar)
        let repeats = Int(Alarm.checkWindowSeconds / Alarm.checkRepeatSeconds)
        var result: [PlannedRing] = []
        for day in days {
            let rings = alarm.ringTimes(on: day, calendar: calendar)
            guard let last = rings.last else { continue }
            for item in rings.dropLast() where item.fire > now {
                result.append(PlannedRing(
                    id: StableID.make("\(alarm.id)|\(item.ring.id)|\(day)"),
                    alarmID: alarm.id, ringID: item.ring.id, schedule: .once(item.fire),
                    title: alarm.title, sound: item.ring.sound, color: item.ring.color,
                    isLastRing: false, needsCheck: true
                ))
            }
            let denseUntil = max(now, last.fire).addingTimeInterval(checkDenseSeconds)
            let backupEvery = max(1, Int(checkBackupSeconds / Alarm.checkRepeatSeconds))
            for k in 0..<repeats {
                let fire = last.fire.addingTimeInterval(Double(k) * Alarm.checkRepeatSeconds)
                guard fire > now, fire <= denseUntil || k % backupEvery == 0 else { continue }
                result.append(PlannedRing(
                    id: StableID.make("\(alarm.id)|\(last.ring.id)|\(day)|\(k)"),
                    alarmID: alarm.id, ringID: last.ring.id, schedule: .once(fire),
                    title: alarm.title, sound: last.ring.sound, color: last.ring.color,
                    isLastRing: true, needsCheck: true
                ))
            }
        }
        return result
    }

    /// The mornings a repeating alarm with a wake-up check is planned for: the next
    /// `checkMorningsAhead` that haven't ended, looking at most two weeks ahead.
    static func checkMornings(_ alarm: Alarm, now: Date, calendar: Calendar) -> [LocalDate] {
        var days: [LocalDate] = []
        let today = LocalDate(now, calendar: calendar)
        for offset in -1...14 where days.count < checkMorningsAhead {
            let day = today.adding(days: offset, calendar: calendar)
            if alarm.isPending(day, now: now, calendar: calendar) { days.append(day) }
        }
        return days
    }

    // MARK: Before the plan runs out

    /// The reminder goes off at this time on the evening before the last planned morning.
    static let reminderTime = TimeOfDay(hour: 20, minute: 0)

    /// When to remind the person to open Squawk, because a repeating alarm is only
    /// planned for a few mornings and nothing re-planned it since. Nil when every
    /// plan is open-ended (plain weekly alarms) or the reminder time has passed.
    ///
    /// Every re-plan (opening the app, a Snooze, a morning ending) moves this further
    /// out, so it only goes off when nobody has touched Squawk for days: the phone was
    /// off, or the alarms rang out without anyone stopping them. It's set for the
    /// evening before the last planned morning, so that morning still rings and
    /// opening the app plans the next few.
    public static func runOutReminder(_ alarms: [Alarm], now: Date, calendar: Calendar = .current) -> Date? {
        alarms.filter(\.isOn)
            .compactMap { lastPlannedRing($0, now: now, calendar: calendar) }
            .compactMap { reminder(before: $0, calendar: calendar) }
            .filter { $0 > now }
            .min()
    }

    /// The first ring of the last morning the plan covers, for a repeating alarm whose
    /// plan stops after a while: with a wake-up check (`checkMorningsAhead` mornings),
    /// or with a one-morning change (that weekday rings as one-off alarms for
    /// `weeksAhead` weeks). Nil for a one-time alarm or one that repeats weekly.
    static func lastPlannedRing(_ alarm: Alarm, now: Date, calendar: Calendar) -> Date? {
        guard alarm.date == nil else { return nil }
        let days: [LocalDate]
        if alarm.hasChecks {
            days = checkMornings(alarm, now: now, calendar: calendar)
        } else {
            // Each changed weekday stops after its last one-off week; the earliest
            // of those is when the plan first runs out.
            days = changedWeekdays(alarm, now: now, calendar: calendar).values
                .map { $0.adding(days: 7 * weeksAhead, calendar: calendar) }
                .sorted()
                .prefix(1)
                .map { $0 }
        }
        // A skipped morning at the end doesn't ring, so look for the last one that does.
        return days.reversed().lazy
            .compactMap { alarm.ringTimes(on: $0, calendar: calendar).first?.fire }
            .first
    }

    /// `reminderTime` on the day before `firstRing`.
    static func reminder(before firstRing: Date, calendar: Calendar) -> Date? {
        LocalDate(firstRing, calendar: calendar)
            .adding(days: -1, calendar: calendar)
            .date(at: reminderTime, calendar: calendar)
    }

    /// Weekdays whose next morning has a one-morning change, with that morning. These
    /// can't use a weekly repeat until the change has passed.
    static func changedWeekdays(_ alarm: Alarm, now: Date, calendar: Calendar) -> [Weekday: LocalDate] {
        let today = LocalDate(now, calendar: calendar)
        var seen: Set<Weekday> = []
        var changed: [Weekday: LocalDate] = [:]
        for offset in -1...7 {
            let day = today.adding(days: offset, calendar: calendar)
            let weekday = day.weekday(calendar: calendar)
            guard !seen.contains(weekday), alarm.isPending(day, now: now, calendar: calendar) else { continue }
            seen.insert(weekday)
            if alarm.change(on: day) != nil { changed[weekday] = day }
        }
        return changed
    }

    static func shift(_ day: Weekday, by delta: Int) -> Weekday {
        let index = ((day.rawValue - 1 + delta) % 7 + 7) % 7
        return Weekday(rawValue: index + 1)!
    }
}

/// Deterministic UUIDs from strings (two FNV-1a hashes), so the same input always
/// gives the same id without needing CryptoKit.
enum StableID {
    static func make(_ string: String) -> UUID {
        let a = fnv(string, seed: 0xcbf29ce484222325)
        let b = fnv(string, seed: 0x84222325cbf29ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((a >> (8 * UInt64(i))) & 0xFF)
            bytes[i + 8] = UInt8((b >> (8 * UInt64(i))) & 0xFF)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 style
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func fnv(_ string: String, seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
