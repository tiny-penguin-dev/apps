import Foundation

/// Days in a row with a practice word typed, counting back from today (or from
/// yesterday, so a streak is not lost until the day is over).
public enum Streak {
    public static func days(practiceDays: [String], now: Date, calendar: Calendar = .current) -> Int {
        let practised = Set(practiceDays)
        var day = calendar.startOfDay(for: now)
        if !practised.contains(AppState.dayKey(day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  practised.contains(AppState.dayKey(yesterday, calendar: calendar)) else { return 0 }
            day = yesterday
        }
        var count = 0
        while practised.contains(AppState.dayKey(day, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

/// The small rewards (PRODUCT.md §7): shown once each, in a sheet with confetti.
public enum Milestone: String, CaseIterable, Codable, Sendable, Identifiable {
    case fortyWordsPerMinute
    case firstWeek
    case hundredWords

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fortyWordsPerMinute: "40 words a minute"
        case .firstWeek: "A whole week"
        case .hundredWords: "A hundred words"
        }
    }

    public var line: String {
        switch self {
        case .fortyWordsPerMinute: "Faster than most people type on a phone. Both flippers, clearly."
        case .firstWeek: "Seven days of practice. The keyboard knows your thumbs by now."
        case .hundredWords: "A hundred words of yours the keyboard learned. It types like you."
        }
    }

    /// Everything reached so far, from what the app knows.
    public static func reached(bestWordsPerMinute: Int?, practiceDays: [String], learnedWords: Int) -> Set<Milestone> {
        var set: Set<Milestone> = []
        if let best = bestWordsPerMinute, best >= 40 { set.insert(.fortyWordsPerMinute) }
        if Set(practiceDays).count >= 7 { set.insert(.firstWeek) }
        if learnedWords >= 100 { set.insert(.hundredWords) }
        return set
    }

    /// The next one to show: reached but not seen, in the order above.
    public static func pending(reached: Set<Milestone>, seen: [String]) -> Milestone? {
        allCases.first { reached.contains($0) && !seen.contains($0.rawValue) }
    }
}
