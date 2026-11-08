import Foundation

// Everyday typing speed (features/typing-speed): the keyboard times stretches of typing
// in every app (`SpeedMeter` → `SpeedRun`), the app folds them into days
// (`SpeedHistory`) and draws them next to practice. Only counts and times, never text.

/// The rules that keep the number honest (FEATURE.md "What counts").
public enum SpeedRules {
    /// A pause longer than this ends a run.
    public static let pause: TimeInterval = 5
    /// A run counts only with this many words: quick replies don't.
    public static let minWords = 10
    /// Faster than this is a paste or a glitch, not typing.
    public static let maxWordsPerMinute: Double = 200
    /// A day has a speed only with this many runs.
    public static let minRunsPerDay = 3
    /// The everyday speed is the median of this many recent days with a speed...
    public static let everydayDays = 7
    /// ...and shows once there are this many.
    public static let minEverydayDays = 3
    /// Days looked back over for the everyday speed.
    public static let everydayWindow = 30
    /// The fastest run is picked among runs at least this long.
    public static let fastestMinWords = 20
    /// Runs the keyboard keeps for the app to pick up.
    public static let keptRunDays = 14
    /// Days the app keeps.
    public static let keptDays = 400
}

/// One stretch of typing with no pause over `SpeedRules.pause`, in one field.
public struct SpeedRun: Codable, Sendable, Equatable {
    /// When its first touch was.
    public var started: Date
    /// From the first touch to the last change to the text.
    public var seconds: Double
    /// Characters that stayed in the text (backspaced ones taken off).
    public var characters: Int
    /// Words that went in.
    public var words: Int

    public init(started: Date, seconds: Double, characters: Int, words: Int) {
        self.started = started
        self.seconds = seconds
        self.characters = characters
        self.words = words
    }

    /// The usual typing-test measure, as the speed test: characters / 5 per minute.
    public var wordsPerMinute: Double {
        seconds > 0 ? Double(characters) / 5 / (seconds / 60) : 0
    }

    /// Long enough to count, and not so fast it can't be typing.
    public var counts: Bool {
        words >= SpeedRules.minWords && seconds > 0 && characters > 0
            && wordsPerMinute <= SpeedRules.maxWordsPerMinute
    }
}

/// Times runs as the keyboard types. Pure: the host passes the times in (the same
/// clock for all calls) and the wall-clock date when a touch comes.
///
///     meter.touched(at: now, date: Date())   // a run that just ended, or nil
///     meter.edited(characters: 3, at: now)
///     meter.wordWentIn()
///     meter.end()                             // keyboard hides, field changes
public struct SpeedMeter: Sendable, Equatable {
    private struct Open: Sendable, Equatable {
        var start: TimeInterval
        var date: Date
        var lastActivity: TimeInterval
        var lastEdit: TimeInterval?
        var characters = 0
        var words = 0
    }

    private var open: Open?

    public init() {}

    /// Whether a run is going.
    public var isRunning: Bool { open != nil }

    /// A touch or key. After a long pause it ends the run before it (returned when it
    /// counts) and starts a new one.
    @discardableResult
    public mutating func touched(at time: TimeInterval, date: Date) -> SpeedRun? {
        var finished: SpeedRun?
        if let run = open, time - run.lastActivity > SpeedRules.pause {
            finished = end()
        }
        if open == nil {
            open = Open(start: time, date: date, lastActivity: time)
        } else {
            open?.lastActivity = time
        }
        return finished
    }

    /// The text changed by `characters` (negative for deletes) at `time`. Changes with
    /// no run going (nothing touched) are not typing and are left out.
    public mutating func edited(characters: Int, at time: TimeInterval) {
        guard var run = open, characters != 0 else { return }
        if time - run.lastActivity > SpeedRules.pause { return }
        run.characters += characters
        run.lastEdit = time
        run.lastActivity = max(run.lastActivity, time)
        open = run
    }

    /// A word went in (it settled).
    public mutating func wordWentIn() {
        open?.words += 1
    }

    /// Ends the run going, returning it when it counts.
    @discardableResult
    public mutating func end() -> SpeedRun? {
        defer { open = nil }
        guard let run = open, let last = run.lastEdit else { return nil }
        let speed = SpeedRun(started: run.date, seconds: last - run.start, characters: run.characters, words: run.words)
        return speed.counts ? speed : nil
    }
}

/// The runs the keyboard leaves in the App Group for the app, the last
/// `SpeedRules.keptRunDays` days of them.
public struct SpeedRuns: Codable, Sendable, Equatable {
    public var runs: [SpeedRun]

    public init(runs: [SpeedRun] = []) {
        self.runs = runs
    }

    public mutating func add(_ run: SpeedRun, now: Date) {
        runs.append(run)
        let cutoff = now.addingTimeInterval(-Double(SpeedRules.keptRunDays) * 86_400)
        runs.removeAll { $0.started < cutoff }
    }
}

/// The App Group file of `SpeedRuns`: the keyboard adds, the app reads.
public struct SpeedRunStore: Sendable {
    private let file: JSONFile<SpeedRuns>

    public init(url: URL) {
        file = JSONFile(url)
    }

    public func load() -> SpeedRuns { file.read() ?? SpeedRuns() }

    public func add(_ run: SpeedRun, now: Date = Date()) {
        var runs = load()
        runs.add(run, now: now)
        file.write(runs)
    }

    public func clear() { file.write(SpeedRuns()) }
}

/// One day of typing: the speed of each run that counted.
public struct SpeedDay: Codable, Sendable, Equatable {
    /// "2026-11-08", in the phone's calendar when the runs were typed.
    public var day: String
    /// Each counted run's words per minute.
    public var speeds: [Double]
    /// Words in the counted runs.
    public var words: Int
    /// The fastest run of at least `SpeedRules.fastestMinWords` words.
    public var fastest: Double?

    public init(day: String, speeds: [Double] = [], words: Int = 0, fastest: Double? = nil) {
        self.day = day
        self.speeds = speeds
        self.words = words
        self.fastest = fastest
    }

    /// The median run, once the day has enough of them.
    public var speed: Double? {
        speeds.count >= SpeedRules.minRunsPerDay ? SpeedHistory.median(speeds) : nil
    }
}

/// The ranges Your speed shows.
public enum SpeedRange: String, CaseIterable, Sendable, Identifiable {
    case week, month, year
    public var id: String { rawValue }
}

/// One point on the graph: a day (week and month) or a week (year).
public struct SpeedPoint: Sendable, Equatable, Identifiable {
    /// The day, or the week's first day.
    public var date: Date
    /// Everyday speed, nil for a gap.
    public var everyday: Double?
    /// The best practice that day or week, if any.
    public var practice: Int?
    /// Counted runs and words in it.
    public var runs: Int
    public var words: Int

    public var id: Date { date }
}

/// What a range adds up to, for the tiles.
public struct SpeedSummary: Sendable, Equatable {
    /// The median of the range's day speeds.
    public var speed: Int?
    public var fastest: Int?
    public var words: Int
    public var bestPractice: Int?
}

/// The days the app keeps (in its own container): runs folded in as they arrive.
public struct SpeedHistory: Codable, Sendable, Equatable {
    public var days: [SpeedDay]
    /// The newest run folded in, so a run is only counted once.
    public var foldedThrough: Date?
    /// The last day whose speed went out as `speed.everyday`.
    public var reportedThrough: String?

    public init(days: [SpeedDay] = [], foldedThrough: Date? = nil) {
        self.days = days
        self.foldedThrough = foldedThrough
    }

    /// Finished days (before today) with a speed that have not been reported yet.
    public func toReport(now: Date, calendar: Calendar = .current) -> [SpeedDay] {
        let today = Self.key(now, calendar: calendar)
        return days.filter { $0.day < today && $0.speed != nil && $0.day > (reportedThrough ?? "") }
    }

    /// Marks every day before today as reported.
    public mutating func reported(now: Date, calendar: Calendar = .current) {
        guard let last = toReport(now: now, calendar: calendar).last else { return }
        reportedThrough = last.day
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    public static func key(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Folds in the runs newer than the last fold. Returns whether anything changed.
    @discardableResult
    public mutating func add(_ runs: [SpeedRun], calendar: Calendar = .current) -> Bool {
        let fresh = runs.filter { run in run.counts && foldedThrough.map { run.started > $0 } ?? true }
            .sorted { $0.started < $1.started }
        guard !fresh.isEmpty else { return false }
        for run in fresh {
            let key = Self.key(run.started, calendar: calendar)
            var day = days.last(where: { $0.day == key }) ?? SpeedDay(day: key)
            day.speeds.append(run.wordsPerMinute)
            day.words += run.words
            if run.words >= SpeedRules.fastestMinWords {
                day.fastest = max(day.fastest ?? 0, run.wordsPerMinute)
            }
            if let i = days.firstIndex(where: { $0.day == key }) { days[i] = day } else { days.append(day) }
        }
        days.sort { $0.day < $1.day }
        if days.count > SpeedRules.keptDays { days.removeFirst(days.count - SpeedRules.keptDays) }
        foldedThrough = fresh.last?.started
        return true
    }

    private func day(_ date: Date, calendar: Calendar) -> SpeedDay? {
        let key = Self.key(date, calendar: calendar)
        return days.last { $0.day == key }
    }

    /// The everyday speed at `now`: the median of the last `SpeedRules.everydayDays`
    /// days with a speed in the last `SpeedRules.everydayWindow` days, once there are
    /// `SpeedRules.minEverydayDays` of them.
    public func everyday(now: Date, calendar: Calendar = .current) -> Int? {
        var speeds: [Double] = []
        for back in 0..<SpeedRules.everydayWindow {
            guard let date = calendar.date(byAdding: .day, value: -back, to: now) else { continue }
            if let speed = day(date, calendar: calendar)?.speed { speeds.append(speed) }
            if speeds.count == SpeedRules.everydayDays { break }
        }
        guard speeds.count >= SpeedRules.minEverydayDays, let m = Self.median(speeds) else { return nil }
        return Int(m.rounded())
    }

    /// How the everyday speed moved over the last week (now against a week ago).
    public func weekChange(now: Date, calendar: Calendar = .current) -> Int? {
        guard let today = everyday(now: now, calendar: calendar),
              let before = calendar.date(byAdding: .day, value: -7, to: now),
              let then = everyday(now: before, calendar: calendar) else { return nil }
        return today - then
    }

    /// Days with a speed so far (for "Day 1 of 3").
    public var daysWithSpeed: Int { days.filter { $0.speed != nil }.count }

    /// The graph's points for `range`, oldest first. Practice is the speed test results.
    public func points(_ range: SpeedRange, now: Date, practice: [SpeedResult] = [],
                       calendar: Calendar = .current) -> [SpeedPoint] {
        let today = calendar.startOfDay(for: now)
        func practiceBest(from start: Date, days count: Int) -> Int? {
            guard let end = calendar.date(byAdding: .day, value: count, to: start) else { return nil }
            return practice.filter { $0.keyboard == .astrotype && $0.date >= start && $0.date < end }
                .map(\.wordsPerMinute).max()
        }
        switch range {
        case .week, .month:
            let count = range == .week ? 7 : 30
            return (0..<count).reversed().compactMap { back in
                guard let date = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
                let d = day(date, calendar: calendar)
                return SpeedPoint(date: date, everyday: d?.speed, practice: practiceBest(from: date, days: 1),
                                  runs: d?.speeds.count ?? 0, words: d?.words ?? 0)
            }
        case .year:
            return (0..<52).reversed().compactMap { back in
                guard let start = calendar.date(byAdding: .day, value: -(back * 7 + 6), to: today) else { return nil }
                let week = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
                    .compactMap { day($0, calendar: calendar) }
                return SpeedPoint(date: start, everyday: Self.median(week.compactMap(\.speed)),
                                  practice: practiceBest(from: start, days: 7),
                                  runs: week.reduce(0) { $0 + $1.speeds.count }, words: week.reduce(0) { $0 + $1.words })
            }
        }
    }

    /// The tiles for `range`.
    public func summary(_ range: SpeedRange, now: Date, practice: [SpeedResult] = [],
                        calendar: Calendar = .current) -> SpeedSummary {
        let count: Int
        switch range {
        case .week: count = 7
        case .month: count = 30
        case .year: count = 365
        }
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
        let startKey = Self.key(start, calendar: calendar)
        let inRange = days.filter { $0.day >= startKey }
        let best = practice.filter { $0.keyboard == .astrotype && $0.date >= start }.map(\.wordsPerMinute).max()
        return SpeedSummary(speed: Self.median(inRange.compactMap(\.speed)).map { Int($0.rounded()) },
                            fastest: inRange.compactMap(\.fastest).max().map { Int($0.rounded()) },
                            words: inRange.reduce(0) { $0 + $1.words },
                            bestPractice: best)
    }
}

/// The app's copy of the history, in its own container.
public struct SpeedHistoryStore: Sendable {
    private let file: JSONFile<SpeedHistory>

    public init(url: URL) {
        file = JSONFile(url)
    }

    public func load() -> SpeedHistory { file.read() ?? SpeedHistory() }
    public func save(_ history: SpeedHistory) { file.write(history) }
}
