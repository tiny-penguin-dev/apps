import Foundation

/// One alarm: a wake-up time, the days it repeats (or one date), and its steps: rings
/// and Home things at times around the wake-up time.
///
/// Built to grow (PRODUCT.md 8b): wake-up checks are an open list, and new kinds are
/// new enum cases. Actions and conditions join the same way in later versions.
public struct Alarm: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// The normal wake-up time.
    public var time: TimeOfDay
    /// Repeat days. Ignored when `date` is set.
    public var days: Set<Weekday>
    /// Set for a one-time alarm.
    public var date: LocalDate?
    /// Days that wake up at a different time ("Fri 7:30"). Everything else is shared.
    public var dayTimes: [Weekday: TimeOfDay]
    /// Every alarm has at least one ring, at the wake-up time.
    public var rings: [Ring]
    public var label: String
    public var isOn: Bool
    public var checks: [WakeUpCheck]
    /// One-morning changes: skip, a different time, or "already up".
    public var changes: [MorningChange]
    /// Timed Home things (lights, scenes, plugs, blinds). With the rings, they make up the
    /// alarm's steps (`steps`).
    public var homeActions: [HomeAction]
    /// "When you're up": Home things that run when the morning ends.
    public var upActions: [HomeAction]

    public init(
        id: UUID = UUID(),
        time: TimeOfDay = .sevenAM,
        days: Set<Weekday> = Weekday.weekdays,
        date: LocalDate? = nil,
        dayTimes: [Weekday: TimeOfDay] = [:],
        rings: [Ring] = [Ring()],
        label: String = "",
        isOn: Bool = true,
        checks: [WakeUpCheck] = [],
        changes: [MorningChange] = [],
        homeActions: [HomeAction] = [],
        upActions: [HomeAction] = []
    ) {
        self.id = id
        self.time = time
        self.days = days
        self.date = date
        self.dayTimes = dayTimes
        self.rings = rings.isEmpty ? [Ring()] : rings
        self.label = label
        self.isOn = isOn
        self.checks = checks
        self.changes = changes
        self.homeActions = homeActions
        self.upActions = upActions
    }

    public var isOneTime: Bool { date != nil }

    /// The time this alarm wakes you on a given day.
    public func time(on day: Weekday) -> TimeOfDay { dayTimes[day] ?? time }

    /// Repeat days grouped by their wake-up time, earliest day first.
    public var timeGroups: [(time: TimeOfDay, days: [Weekday])] { timeGroups(for: days) }

    /// Some of the repeat days grouped by their wake-up time, earliest day first.
    func timeGroups(for days: Set<Weekday>) -> [(time: TimeOfDay, days: [Weekday])] {
        var groups: [TimeOfDay: [Weekday]] = [:]
        for day in days.sorted() {
            groups[time(on: day), default: []].append(day)
        }
        return groups
            .map { (time: $0.key, days: $0.value.sorted()) }
            .sorted { ($0.days.first?.rawValue ?? 0) < ($1.days.first?.rawValue ?? 0) }
    }

    /// The schedule in words: "Weekdays", "Mon–Thu 7:00 · Fri 7:30", "Sat, Nov 7".
    public func scheduleLine(calendar: Calendar = .current) -> String {
        if let date {
            return date.formatted(calendar: calendar)
        }
        let groups = timeGroups
        if groups.isEmpty { return "Never" }
        if groups.count == 1 { return groups[0].days.summary }
        return groups.map { "\($0.days.summary) \($0.time.short)" }.joined(separator: " · ")
    }

    /// The title iOS shows on the ringing screen.
    public var title: String { label.isEmpty ? "Wake up" : label }

    /// When the next ring goes off, counting one-morning changes, or nil if never.
    public func nextRing(after now: Date, calendar: Calendar = .current) -> Date? {
        guard isOn else { return nil }
        let today = LocalDate(now, calendar: calendar)
        for offset in -1...8 {
            let day = today.adding(days: offset, calendar: calendar)
            if let fire = ringTimes(on: day, calendar: calendar).map(\.fire).first(where: { $0 > now }) {
                return fire
            }
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, time, days, date, dayTimes, rings, label, isOn, checks, changes, homeActions, upActions
    }

    /// Decodes leniently so alarms saved by older versions still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            time: try c.decode(TimeOfDay.self, forKey: .time),
            days: try c.decodeIfPresent(Set<Weekday>.self, forKey: .days) ?? [],
            date: try c.decodeIfPresent(LocalDate.self, forKey: .date),
            dayTimes: try c.decodeIfPresent([Weekday: TimeOfDay].self, forKey: .dayTimes) ?? [:],
            rings: try c.decodeIfPresent([Ring].self, forKey: .rings) ?? [Ring()],
            label: try c.decodeIfPresent(String.self, forKey: .label) ?? "",
            isOn: try c.decodeIfPresent(Bool.self, forKey: .isOn) ?? true,
            checks: (try? c.decodeIfPresent([WakeUpCheck].self, forKey: .checks)) ?? [],
            changes: (try? c.decodeIfPresent([MorningChange].self, forKey: .changes)) ?? [],
            homeActions: (try? c.decodeIfPresent([HomeAction].self, forKey: .homeActions)) ?? [],
            upActions: (try? c.decodeIfPresent([HomeAction].self, forKey: .upActions)) ?? []
        )
    }
}

/// One ring of an alarm. Extra rings sit before or after the wake-up time.
public struct Ring: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Minutes from the wake-up time: -10 is "10 min before".
    public var offsetMinutes: Int
    public var soundID: String
    public var color: RingColor
    /// Rings have no name unless someone adds one.
    public var name: String?

    public init(
        id: UUID = UUID(), offsetMinutes: Int = 0, soundID: String = AlarmSound.standard.id,
        color: RingColor = .sunrise, name: String? = nil
    ) {
        self.id = id
        self.offsetMinutes = offsetMinutes
        self.soundID = soundID
        self.color = color
        self.name = name
    }

    public var sound: AlarmSound { AlarmSound.with(id: soundID) }
}

/// The tint for a ring on the ringing screen and the timeline.
public enum RingColor: String, Codable, CaseIterable, Sendable {
    case sunrise, sun, coral, mint

    public var hex: UInt32 {
        switch self {
        case .sunrise: 0xFF8A4C
        case .sun: 0xFFC24D
        case .coral: 0xFF5C63
        case .mint: 0x2FBF96
        }
    }
}

/// Something you must do to fully turn off the alarm (PRODUCT.md 5.5). New kinds are
/// new `Kind` cases.
public struct WakeUpCheck: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Tap the phone on an NFC sticker.
        case tag
        /// Scan a QR code or barcode.
        case code
        /// Count the penguins.
        case game

        public var id: String { rawValue }
    }

    public var id: UUID
    public var kind: Kind
    /// What must match: the tag's id or the code's text. Empty for the game.
    public var secret: String
    /// Where it is, like "Bathroom mirror". Shown on the check screen.
    public var place: String

    public init(id: UUID = UUID(), kind: Kind, secret: String = "", place: String = "") {
        self.id = id
        self.kind = kind
        self.secret = secret
        self.place = place
    }

    /// True when a scanned tag or code is the right one.
    public func matches(_ scanned: String) -> Bool {
        !secret.isEmpty && scanned.trimmingCharacters(in: .whitespacesAndNewlines) == secret
    }
}

/// A calendar day with no time or time zone, for one-time alarms.
public struct LocalDate: Codable, Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// This day at a wall-clock time, in the calendar's time zone.
    public func date(at time: TimeOfDay, calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: time.hour, minute: time.minute))
    }

    /// "Sat, Nov 7".
    public func formatted(calendar: Calendar = .current) -> String {
        guard let d = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return "" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d"
        return f.string(from: d)
    }

    /// The day this many days later (or earlier, when negative).
    public func adding(days: Int, calendar: Calendar = .current) -> LocalDate {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              let moved = calendar.date(byAdding: .day, value: days, to: start) else { return self }
        return LocalDate(moved, calendar: calendar)
    }

    public func weekday(calendar: Calendar = .current) -> Weekday {
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
        return Weekday(of: noon, calendar: calendar)
    }
}

extension LocalDate: Comparable {
    public static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

extension LocalDate: CustomStringConvertible {
    /// "2026-11-02".
    public var description: String {
        let m = month < 10 ? "0\(month)" : "\(month)"
        let d = day < 10 ? "0\(day)" : "\(day)"
        return "\(year)-\(m)-\(d)"
    }
}
