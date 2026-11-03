import Foundation

/// A change to one morning only, without editing the alarm (PRODUCT.md: "Skip / change
/// once"). Also records "already up", which cancels the rest of that morning's rings.
public struct MorningChange: Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        /// Don't ring this morning.
        case skip
        /// Ring at a different time this morning only.
        case time(TimeOfDay)
        /// Already up: the rest of this morning's rings are cancelled.
        case done
    }

    /// The morning's date: the day of the wake-up time, even if a ring before it falls
    /// on the day before.
    public var date: LocalDate
    public var kind: Kind

    public init(date: LocalDate, kind: Kind) {
        self.date = date
        self.kind = kind
    }
}

/// One ring on one morning.
public struct MorningRing: Hashable, Sendable {
    public let ring: Ring
    public let fire: Date
}

extension Alarm {
    /// Rings at most this many minutes before or after the wake-up time.
    public static let ringRange = -120...120

    /// With a wake-up check, the last ring comes back this often...
    public static let checkRepeatSeconds: TimeInterval = 30
    /// ...for this long after it first goes off (PRODUCT.md 5.3).
    public static let checkWindowSeconds: TimeInterval = 600

    public var hasChecks: Bool { !checks.isEmpty }

    /// How long a morning keeps ringing after its last ring.
    var tailSeconds: TimeInterval { hasChecks ? Self.checkWindowSeconds : 0 }

    // MARK: One-morning changes

    public func change(on date: LocalDate) -> MorningChange.Kind? {
        changes.first { $0.date == date }?.kind
    }

    /// Sets or clears (nil) the change for one morning.
    public mutating func setChange(_ kind: MorningChange.Kind?, on date: LocalDate) {
        changes.removeAll { $0.date == date }
        if let kind { changes.append(MorningChange(date: date, kind: kind)) }
        changes.sort { $0.date < $1.date }
    }

    /// Drops changes for mornings that are over (keeps yesterday, for rings after midnight).
    public mutating func dropOldChanges(now: Date, calendar: Calendar = .current) {
        let yesterday = LocalDate(now, calendar: calendar).adding(days: -1, calendar: calendar)
        changes.removeAll { $0.date < yesterday }
    }

    // MARK: Mornings

    /// The normal wake-up time on a day, ignoring changes, or nil if it doesn't ring then.
    public func scheduledTime(on date: LocalDate, calendar: Calendar = .current) -> TimeOfDay? {
        if let oneDate = self.date {
            return oneDate == date ? time : nil
        }
        let weekday = date.weekday(calendar: calendar)
        return days.contains(weekday) ? time(on: weekday) : nil
    }

    /// The wake-up time on a day after changes, or nil when it doesn't ring (not a
    /// ringing day, skipped, or already up).
    public func wakeTime(on date: LocalDate, calendar: Calendar = .current) -> TimeOfDay? {
        guard let normal = scheduledTime(on: date, calendar: calendar) else { return nil }
        switch change(on: date) {
        case .skip, .done: return nil
        case .time(let time): return time
        case nil: return normal
        }
    }

    /// Every ring on a morning, earliest first, after changes.
    public func ringTimes(on date: LocalDate, calendar: Calendar = .current) -> [MorningRing] {
        guard let wake = wakeTime(on: date, calendar: calendar) else { return [] }
        return rings(on: date, at: wake, calendar: calendar)
    }

    /// Rings sorted by time, first to last.
    public var sortedRings: [Ring] {
        rings.sorted { $0.offsetMinutes < $1.offsetMinutes }
    }

    func rings(on date: LocalDate, at wake: TimeOfDay, calendar: Calendar) -> [MorningRing] {
        guard let base = date.date(at: wake, calendar: calendar) else { return [] }
        return sortedRings.map { MorningRing(ring: $0, fire: base.addingTimeInterval(Double($0.offsetMinutes) * 60)) }
    }

    /// True while a morning still has rings to come, using its changed time if it has
    /// one, otherwise its normal time (so a skipped morning stays "upcoming" until it's
    /// over, and can be un-skipped).
    func isPending(_ date: LocalDate, now: Date, calendar: Calendar) -> Bool {
        guard let normal = scheduledTime(on: date, calendar: calendar) else { return false }
        var wake = normal
        if case .time(let changed) = change(on: date) { wake = changed }
        guard let last = rings(on: date, at: wake, calendar: calendar).last else { return false }
        return last.fire.addingTimeInterval(tailSeconds) > now
    }

    /// The next morning that hasn't started yet: what "Skip tomorrow" and "Change next
    /// morning" act on. Nil for one-time alarms and alarms with no days.
    public func upcomingMorning(after now: Date, calendar: Calendar = .current) -> LocalDate? {
        guard date == nil else { return nil }
        let today = LocalDate(now, calendar: calendar)
        for offset in -1...8 {
            let day = today.adding(days: offset, calendar: calendar)
            guard let normal = scheduledTime(on: day, calendar: calendar) else { continue }
            var wake = normal
            if case .time(let changed) = change(on: day) { wake = changed }
            if case .done = change(on: day) { continue }
            if let first = rings(on: day, at: wake, calendar: calendar).first, first.fire > now {
                return day
            }
        }
        return nil
    }

    /// The morning whose first ring has gone off and whose last ring is still to come
    /// (or, with a wake-up check, is still coming back).
    public func morningInProgress(at now: Date, calendar: Calendar = .current) -> LocalDate? {
        guard isOn else { return nil }
        let today = LocalDate(now, calendar: calendar)
        for offset in -1...1 {
            let day = today.adding(days: offset, calendar: calendar)
            let rings = ringTimes(on: day, calendar: calendar)
            if let first = rings.first, let last = rings.last, first.fire <= now,
               last.fire.addingTimeInterval(tailSeconds) > now {
                return day
            }
        }
        return nil
    }

    /// When the last ring stops coming back on the morning in progress: the time left
    /// on the check screen.
    public func checkDeadline(at now: Date, calendar: Calendar = .current) -> Date? {
        guard let day = morningInProgress(at: now, calendar: calendar),
              let last = ringTimes(on: day, calendar: calendar).last else { return nil }
        return last.fire.addingTimeInterval(tailSeconds)
    }

    /// "I'm up": cancels the rest of the morning that's ringing. Returns false if no
    /// morning is in progress (so opening the app the night before changes nothing).
    /// With wake-up checks, call it only once they're done.
    @discardableResult
    public mutating func markUp(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let day = morningInProgress(at: now, calendar: calendar) else { return false }
        setChange(.done, on: day)
        return true
    }

    // MARK: "Turn off Squawk" Shortcut

    /// What the "Turn off Squawk" action does to this alarm right now. It can't skip a
    /// wake-up check: it only turns the morning off when the alarm has no checks, or
    /// when its checks are all "Run a Shortcut". With other checks too, it counts as the
    /// Shortcut check, and the rest are done in the app.
    public func shortcutTurnOff(at now: Date, calendar: Calendar = .current) -> ShortcutTurnOff {
        guard let day = morningInProgress(at: now, calendar: calendar) else {
            return lastRingMayBeRinging(at: now, calendar: calendar) ? .lastRing : .notRinging
        }
        guard hasChecks else { return .up(day) }
        guard checks.contains(where: { $0.kind == .shortcut }) else { return .needsOtherCheck }
        return checks.allSatisfy { $0.kind == .shortcut } ? .up(day) : .shortcutDone(day)
    }

    /// Without a check, a morning is over once its last ring goes off, but that ring
    /// keeps going until it's stopped. The action can still silence it for a while.
    public static let shortcutGraceSeconds: TimeInterval = 600

    private func lastRingMayBeRinging(at now: Date, calendar: Calendar) -> Bool {
        guard isOn, !hasChecks else { return false }
        let today = LocalDate(now, calendar: calendar)
        return [today.adding(days: -1, calendar: calendar), today].contains { day in
            guard let last = ringTimes(on: day, calendar: calendar).last else { return false }
            return last.fire <= now && now < last.fire.addingTimeInterval(Self.shortcutGraceSeconds)
        }
    }

    // MARK: Adding rings

    /// Adds a soft ring 10 minutes before the first one.
    public mutating func addSoftRing() {
        let first = rings.map(\.offsetMinutes).min() ?? 0
        rings.append(Ring(
            offsetMinutes: max(first - 10, Self.ringRange.lowerBound),
            soundID: AlarmSound.soft.id, color: .sun
        ))
    }

    /// Adds a loud ring 5 minutes after the last one.
    public mutating func addLoudRing() {
        let last = rings.map(\.offsetMinutes).max() ?? 0
        rings.append(Ring(
            offsetMinutes: min(last + 5, Self.ringRange.upperBound),
            soundID: AlarmSound.loud.id, color: .coral
        ))
    }
}

extension Ring {
    /// "10 min before", "At wake-up", "5 min after", "1 h 5 min after".
    public var offsetText: String {
        if offsetMinutes == 0 { return "At wake-up" }
        let minutes = abs(offsetMinutes)
        let amount = minutes >= 60
            ? (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min")
            : "\(minutes) min"
        return offsetMinutes < 0 ? "\(amount) before" : "\(amount) after"
    }

    /// What the timeline shows: its name, or "6:50 · Nudge".
    public func summary(wake: TimeOfDay) -> String {
        let time = wake.adding(minutes: offsetMinutes).short
        if let name, !name.isEmpty { return "\(time) · \(name)" }
        return "\(time) · \(sound.name)"
    }
}

/// What running the "Turn off Squawk" action means for one alarm.
public enum ShortcutTurnOff: Equatable, Sendable {
    /// No morning of this alarm is going on.
    case notRinging
    /// This morning is over: cancel the rest of it.
    case up(LocalDate)
    /// An alarm without a check whose last ring went off a moment ago: nothing is left
    /// to cancel, but that ring may still be going off.
    case lastRing
    /// The Shortcut check of this morning is done, but other checks are left.
    case shortcutDone(LocalDate)
    /// The alarm has checks and none of them is a Shortcut, so it keeps ringing.
    case needsOtherCheck
}
