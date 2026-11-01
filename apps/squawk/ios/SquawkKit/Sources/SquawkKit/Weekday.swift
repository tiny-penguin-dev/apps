import Foundation

/// A day of the week, Monday first (how most people read a week).
public enum Weekday: Int, Codable, CaseIterable, Comparable, Identifiable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public var id: Int { rawValue }

    public var short: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    /// One letter for the round day buttons.
    public var letter: String { String(short.prefix(1)) }

    public var full: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    public static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let weekend: Set<Weekday> = [.saturday, .sunday]

    /// The weekday of a date. `Calendar` numbers Sunday as 1.
    public init(of date: Date, calendar: Calendar = .current) {
        let n = calendar.component(.weekday, from: date) // 1 = Sunday
        self = Weekday(rawValue: n == 1 ? 7 : n - 1)!
    }

    /// `Calendar`'s weekday number (Sunday = 1).
    public var calendarWeekday: Int { self == .sunday ? 1 : rawValue + 1 }

    public static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }
}

extension Collection where Element == Weekday {
    /// "Mon–Thu", "Mon, Wed, Fri", "Every day", "Weekdays", "Weekends".
    public var summary: String {
        let days = Set(self)
        if days.count == 7 { return "Every day" }
        if days == Weekday.weekdays { return "Weekdays" }
        if days == Weekday.weekend { return "Weekends" }
        let sorted = days.sorted()
        // Split into runs of consecutive days.
        var runs: [[Weekday]] = []
        for day in sorted {
            if let last = runs.last?.last, last.rawValue + 1 == day.rawValue {
                runs[runs.count - 1].append(day)
            } else {
                runs.append([day])
            }
        }
        return runs.map { run in
            run.count >= 3 ? "\(run.first!.short)–\(run.last!.short)" : run.map(\.short).joined(separator: ", ")
        }.joined(separator: ", ")
    }
}
