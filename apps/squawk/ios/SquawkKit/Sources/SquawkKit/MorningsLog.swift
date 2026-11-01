import Foundation

/// How one morning went, for Squawk's reaction and the streak.
///
/// ```swift
/// if let record = alarm.record(upAt: now) { log.add(record) }
/// log.streak          // 5 mornings up on the first ring
/// log.week(of: now)   // [.monday: .firstRing, .tuesday: .lastRing, ...]
/// ```
public struct MorningRecord: Codable, Identifiable, Hashable, Sendable {
    public enum Outcome: String, Codable, CaseIterable, Sendable {
        /// Up on the first ring: proud Squawk.
        case firstRing
        /// Up on a ring in between.
        case fine
        /// Needed the last ring: grumpy Squawk.
        case lastRing
        /// The wake-up check ran out after 10 minutes: Squawk faints.
        case fainted
    }

    public var id: UUID
    public var alarmID: UUID
    /// The morning's date (see `MorningChange.date`).
    public var date: LocalDate
    public var outcome: Outcome
    /// When you got up. Nil when Squawk fainted.
    public var upAt: Date?
    /// Which ring you got up on, from 1. Repeats of the last ring count as the last ring.
    public var ringNumber: Int
    public var ringCount: Int
    /// False until the Good morning screen has shown it.
    public var seen: Bool

    public init(
        id: UUID = UUID(), alarmID: UUID, date: LocalDate, outcome: Outcome,
        upAt: Date?, ringNumber: Int, ringCount: Int, seen: Bool = false
    ) {
        self.id = id
        self.alarmID = alarmID
        self.date = date
        self.outcome = outcome
        self.upAt = upAt
        self.ringNumber = ringNumber
        self.ringCount = ringCount
        self.seen = seen
    }
}

/// Every morning Squawk remembers (the last 120 days), newest last.
public struct MorningsLog: Codable, Hashable, Sendable {
    public private(set) var records: [MorningRecord]
    /// The longest streak so far. Kept even after old mornings are dropped, since it
    /// earns outfits (`Outfit.streakToEarn`).
    public private(set) var bestStreak: Int

    /// How many days are kept.
    public static let daysKept = 120

    public init(records: [MorningRecord] = [], bestStreak: Int = 0) {
        self.records = records.sorted { $0.date < $1.date }
        self.bestStreak = bestStreak
        self.bestStreak = max(bestStreak, streak)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            records: try c.decode([MorningRecord].self, forKey: .records),
            bestStreak: try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
        )
    }

    /// Adds a morning. A second record for the same alarm and morning replaces the first.
    public mutating func add(_ record: MorningRecord, calendar: Calendar = .current) {
        records.removeAll { $0.alarmID == record.alarmID && $0.date == record.date }
        records.append(record)
        records.sort { $0.date < $1.date }
        if let newest = records.last?.date {
            let oldest = newest.adding(days: -Self.daysKept, calendar: calendar)
            records.removeAll { $0.date < oldest }
        }
        bestStreak = max(bestStreak, streak)
    }

    public func contains(alarmID: UUID, date: LocalDate) -> Bool {
        records.contains { $0.alarmID == alarmID && $0.date == date }
    }

    /// Marks a record as shown on the Good morning screen.
    public mutating func markSeen(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].seen = true
    }

    /// The newest morning not shown yet, if it's from today or yesterday.
    public func unseen(now: Date, calendar: Calendar = .current) -> MorningRecord? {
        let yesterday = LocalDate(now, calendar: calendar).adding(days: -1, calendar: calendar)
        return records.last(where: { !$0.seen && $0.date >= yesterday })
    }

    /// Mornings in a row up on the first ring, counting back from the newest. Days
    /// without an alarm don't break it. With two alarms on one morning, the worse counts.
    public var streak: Int {
        var count = 0
        for day in daysNewestFirst {
            guard day.outcome == .firstRing else { break }
            count += 1
        }
        return count
    }

    /// This week (Monday to Sunday) around `date`: each day's outcome, if it had one.
    public func week(of date: Date, calendar: Calendar = .current) -> [Weekday: MorningRecord.Outcome] {
        let today = LocalDate(date, calendar: calendar)
        let monday = today.adding(days: 1 - today.weekday(calendar: calendar).rawValue, calendar: calendar)
        let sunday = monday.adding(days: 6, calendar: calendar)
        var result: [Weekday: MorningRecord.Outcome] = [:]
        for day in daysNewestFirst where day.date >= monday && day.date <= sunday {
            result[day.date.weekday(calendar: calendar)] = day.outcome
        }
        return result
    }

    /// One entry per morning (the worst outcome that day), newest first.
    private var daysNewestFirst: [(date: LocalDate, outcome: MorningRecord.Outcome)] {
        var worst: [LocalDate: MorningRecord.Outcome] = [:]
        for record in records {
            let current = worst[record.date]
            if current == nil || record.outcome.rank > current!.rank {
                worst[record.date] = record.outcome
            }
        }
        return worst.map { (date: $0.key, outcome: $0.value) }.sorted { $0.date > $1.date }
    }
}

extension MorningRecord.Outcome {
    /// Higher is a harder morning.
    var rank: Int {
        switch self {
        case .firstRing: 0
        case .fine: 1
        case .lastRing: 2
        case .fainted: 3
        }
    }
}

extension Alarm {
    /// How the morning in progress went if you're up now. Nil when no morning is ringing.
    /// Call it before `markUp(at:)`, which ends the morning.
    public func record(upAt now: Date, calendar: Calendar = .current) -> MorningRecord? {
        guard let day = morningInProgress(at: now, calendar: calendar) else { return nil }
        let rings = ringTimes(on: day, calendar: calendar)
        let count = rings.count
        let rang = max(1, min(count, rings.filter { $0.fire <= now }.count))
        let outcome: MorningRecord.Outcome = rang <= 1 ? .firstRing : rang >= count ? .lastRing : .fine
        return MorningRecord(alarmID: id, date: day, outcome: outcome, upAt: now, ringNumber: rang, ringCount: count)
    }

    /// Mornings with a wake-up check that rang out without the check being done (today
    /// or yesterday, already over). Squawk faints on those.
    public func faintedMornings(before now: Date, calendar: Calendar = .current) -> [MorningRecord] {
        guard hasChecks, isOn else { return [] }
        let today = LocalDate(now, calendar: calendar)
        return [today.adding(days: -1, calendar: calendar), today].compactMap { day -> MorningRecord? in
            let rings = ringTimes(on: day, calendar: calendar)
            guard let last = rings.last, last.fire.addingTimeInterval(tailSeconds) <= now else { return nil }
            return MorningRecord(
                alarmID: id, date: day, outcome: .fainted, upAt: nil,
                ringNumber: rings.count, ringCount: rings.count
            )
        }
    }
}

/// Where the mornings log is saved.
public protocol MorningsStore: Sendable {
    func load() throws -> MorningsLog
    func save(_ log: MorningsLog) throws
}

/// Saves the mornings log as a JSON file next to the alarms.
public struct FileMorningsStore: MorningsStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Application Support/mornings.json`.
    public static func standard() throws -> FileMorningsStore {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return FileMorningsStore(url: folder.appendingPathComponent("mornings.json"))
    }

    public func load() throws -> MorningsLog {
        guard FileManager.default.fileExists(atPath: url.path) else { return MorningsLog() }
        return try JSONDecoder().decode(SavedMornings.self, from: Data(contentsOf: url)).log
    }

    public func save(_ log: MorningsLog) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(SavedMornings(version: 1, log: log)).write(to: url, options: [.atomic])
    }
}

struct SavedMornings: Codable {
    var version: Int
    var log: MorningsLog
}

/// Keeps the mornings log in memory, for previews and tests.
public final class MemoryMorningsStore: MorningsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var log: MorningsLog

    public init(_ log: MorningsLog = MorningsLog()) {
        self.log = log
    }

    public func load() throws -> MorningsLog {
        lock.withLock { log }
    }

    public func save(_ log: MorningsLog) throws {
        lock.withLock { self.log = log }
    }
}
