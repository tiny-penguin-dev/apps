import Foundation

/// A wall-clock time, like 7:30. Stored as minutes after midnight.
public struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        let total = ((hour * 60 + minute) % 1440 + 1440) % 1440
        self.hour = total / 60
        self.minute = total % 60
    }

    public var minutesAfterMidnight: Int { hour * 60 + minute }

    /// This time moved by some minutes, wrapping around midnight.
    public func adding(minutes: Int) -> TimeOfDay {
        TimeOfDay(hour: 0, minute: minutesAfterMidnight + minutes)
    }

    /// "7:30" (12-hour, no AM/PM).
    public var short: String {
        let h = (hour + 11) % 12 + 1
        return "\(h):" + (minute < 10 ? "0\(minute)" : "\(minute)")
    }

    /// "AM" or "PM".
    public var period: String { hour < 12 ? "AM" : "PM" }

    /// "7:30 AM".
    public var full: String { "\(short) \(period)" }

    public static func < (a: TimeOfDay, b: TimeOfDay) -> Bool { a.minutesAfterMidnight < b.minutesAfterMidnight }

    public static let sevenAM = TimeOfDay(hour: 7, minute: 0)
}
