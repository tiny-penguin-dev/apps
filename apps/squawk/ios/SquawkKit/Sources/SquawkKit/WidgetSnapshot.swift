import Foundation

/// What the next-alarm widget shows: the next few wake-ups and the streak. The app saves
/// one whenever alarms or mornings change; the widget reads it and shows each wake-up
/// until it has passed, so it stays right for days without the app opening.
///
/// ```swift
/// // App
/// WidgetSnapshotStore.shared.save(WidgetSnapshot(alarms: alarms, streak: log.streak, now: .now))
/// // Widget
/// let snapshot = WidgetSnapshotStore.shared.load()
/// snapshot.next(after: .now)   // WakeUp(at: Tue 7:00, title: "Wake up", ringCount: 2)
/// ```
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    /// One morning's wake-up time for one alarm.
    public struct WakeUp: Codable, Hashable, Sendable {
        /// The wake-up time that morning, after one-morning changes.
        public var at: Date
        /// The alarm's label, or "Wake up".
        public var title: String
        public var ringCount: Int

        public init(at: Date, title: String, ringCount: Int) {
            self.at = at
            self.title = title
            self.ringCount = ringCount
        }
    }

    /// Soonest first.
    public var wakeUps: [WakeUp]
    public var streak: Int

    /// How many wake-ups are kept, enough for about a week.
    public static let limit = 10

    public init(wakeUps: [WakeUp] = [], streak: Int = 0) {
        self.wakeUps = wakeUps.sorted { $0.at < $1.at }
        self.streak = streak
    }

    /// The coming wake-ups of every alarm that's on, counting skipped and changed
    /// mornings, over the next week.
    public init(alarms: [Alarm], streak: Int, now: Date, calendar: Calendar = .current) {
        let today = LocalDate(now, calendar: calendar)
        var wakeUps: [WakeUp] = []
        for alarm in alarms where alarm.isOn {
            for offset in 0...8 {
                let day = today.adding(days: offset, calendar: calendar)
                guard let wake = alarm.wakeTime(on: day, calendar: calendar),
                      let at = day.date(at: wake, calendar: calendar), at > now else { continue }
                wakeUps.append(WakeUp(at: at, title: alarm.title, ringCount: alarm.rings.count))
            }
        }
        self.init(wakeUps: Array(wakeUps.sorted { $0.at < $1.at }.prefix(Self.limit)), streak: streak)
    }

    /// The wake-up to show at `date`: the first one that hasn't happened yet.
    public func next(after date: Date) -> WakeUp? {
        wakeUps.first { $0.at > date }
    }
}

/// Where the app leaves the snapshot for the widget: the shared App Group's defaults.
public struct WidgetSnapshotStore: Sendable {
    /// The App Group both the app and the widget belong to.
    public static let appGroup = "group.com.tinypenguin.squawk"
    public static let shared = WidgetSnapshotStore(suiteName: appGroup)

    private let suiteName: String?
    private static let key = "widget.snapshot"

    /// `suiteName` nil uses the standard defaults, for tests.
    public init(suiteName: String?) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults? {
        guard let suiteName else { return .standard }
        return UserDefaults(suiteName: suiteName)
    }

    /// An empty snapshot when nothing was saved yet.
    public func load() -> WidgetSnapshot {
        guard let data = defaults?.data(forKey: Self.key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snapshot
    }

    /// Saves it, and returns true when it changed (so the widget only reloads then).
    @discardableResult
    public func save(_ snapshot: WidgetSnapshot) -> Bool {
        // Sorted keys, so the same snapshot always encodes to the same bytes.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let defaults, let data = try? encoder.encode(snapshot) else { return false }
        if defaults.data(forKey: Self.key) == data { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }
}
