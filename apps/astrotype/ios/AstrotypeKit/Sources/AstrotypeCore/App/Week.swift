import Foundation

/// Home's "This week": seven dots, Monday to Sunday, ticked on the days the person
/// typed a practice word.
public struct Week: Sendable, Equatable {
    public struct Day: Sendable, Equatable {
        /// "M", "T", "W", "T", "F", "S", "S".
        public var letter: String
        public var key: String
        public var practised: Bool
        public var isToday: Bool
    }

    public var days: [Day]

    public init(practiceDays: [String], now: Date, calendar: Calendar = .current) {
        var calendar = calendar
        calendar.firstWeekday = 2
        let practised = Set(practiceDays)
        let today = AppState.dayKey(now, calendar: calendar)
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday
        let sinceMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -sinceMonday, to: calendar.startOfDay(for: now)) ?? now
        days = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            let key = AppState.dayKey(date, calendar: calendar)
            return Day(letter: ["M", "T", "W", "T", "F", "S", "S"][offset], key: key,
                       practised: practised.contains(key), isToday: key == today)
        }
    }

    public var practisedCount: Int { days.filter(\.practised).count }
}
