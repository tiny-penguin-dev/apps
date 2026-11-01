import Foundation

/// What the app remembers between launches that is not a keyboard setting: when it
/// was first opened (the trial starts then), how far setup got, and the days the
/// person practised. A small versioned value in the app's own `UserDefaults`.
public struct AppState: Codable, Sendable, Equatable {
    public static let version = 1

    public var version = AppState.version
    /// The first launch, set the first time the app runs. The Pro trial counts from it.
    public var firstLaunch: Date?
    /// The person reached Home: the setup screens do not show again.
    public var onboardingDone = false
    /// The keyboard was seen turned on at least once (`setup.keyboard_on` counted).
    public var keyboardOnSeen = false
    /// The Full Access screen was answered (opened Settings or skipped).
    public var fullAccessAsked = false
    /// Days with a word typed in the app, as `dayKey` strings, newest last.
    public var practiceDays: [String] = []
    /// The app version that last ran; a new one backs the data up first (`Backup`).
    public var lastRunVersion: String?
    /// The Trial over sheet was shown (once, on the first launch after the trial ended).
    public var trialOverShown = false
    /// The best speed test on the Astrotype keyboard, and the last few tests.
    public var bestWordsPerMinute: Int?
    public var speedTests: [SpeedResult] = []
    /// The speed test typed on Apple's keyboard, for the comparison on Home.
    public var appleWordsPerMinute: Int?
    /// When each drill was last finished, by `Drill.ID` raw value.
    public var drillsDone: [String: Date] = [:]
    /// Milestones whose sheet was shown, by raw value.
    public var milestonesSeen: [String] = []
    /// Send the touches of speed tests and drills to tune the keyboard. Off by default.
    public var sharePractice = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.version
        firstLaunch = try c.decodeIfPresent(Date.self, forKey: .firstLaunch)
        onboardingDone = try c.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? false
        keyboardOnSeen = try c.decodeIfPresent(Bool.self, forKey: .keyboardOnSeen) ?? false
        fullAccessAsked = try c.decodeIfPresent(Bool.self, forKey: .fullAccessAsked) ?? false
        practiceDays = try c.decodeIfPresent([String].self, forKey: .practiceDays) ?? []
        lastRunVersion = try c.decodeIfPresent(String.self, forKey: .lastRunVersion)
        trialOverShown = try c.decodeIfPresent(Bool.self, forKey: .trialOverShown) ?? false
        bestWordsPerMinute = try c.decodeIfPresent(Int.self, forKey: .bestWordsPerMinute)
        speedTests = try c.decodeIfPresent([SpeedResult].self, forKey: .speedTests) ?? []
        appleWordsPerMinute = try c.decodeIfPresent(Int.self, forKey: .appleWordsPerMinute)
        drillsDone = try c.decodeIfPresent([String: Date].self, forKey: .drillsDone) ?? [:]
        milestonesSeen = try c.decodeIfPresent([String].self, forKey: .milestonesSeen) ?? []
        sharePractice = try c.decodeIfPresent(Bool.self, forKey: .sharePractice) ?? false
    }

    /// Keeps the last 30 speed tests and the best on the Astrotype keyboard. Returns
    /// whether this one is a new best.
    @discardableResult
    public mutating func record(_ result: SpeedResult) -> Bool {
        speedTests.append(result)
        if speedTests.count > 30 { speedTests.removeFirst(speedTests.count - 30) }
        switch result.keyboard {
        case .apple:
            appleWordsPerMinute = result.wordsPerMinute
            return false
        case .astrotype:
            let best = bestWordsPerMinute ?? 0
            guard result.wordsPerMinute > best else { return false }
            bestWordsPerMinute = result.wordsPerMinute
            return true
        }
    }

    /// A day as "2026-11-01" in `calendar`'s time zone, the key `practiceDays` uses.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Notes a practice word typed at `date`; keeps the last 60 days.
    public mutating func recordPractice(at date: Date, calendar: Calendar = .current) {
        let key = Self.dayKey(date, calendar: calendar)
        guard practiceDays.last != key else { return }
        practiceDays.removeAll { $0 == key }
        practiceDays.append(key)
        if practiceDays.count > 60 { practiceDays.removeFirst(practiceDays.count - 60) }
    }
}

/// Where the app's state is kept.
public protocol AppStateStore: Sendable {
    func load() -> AppState?
    func save(_ state: AppState)
}

public final class UserDefaultsAppStateStore: AppStateStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "appState") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AppState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppState.self, from: data)
    }

    public func save(_ state: AppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

public final class MemoryAppStateStore: AppStateStore, @unchecked Sendable {
    private var state: AppState?
    private let lock = NSLock()

    public init(_ state: AppState? = nil) { self.state = state }

    public func load() -> AppState? {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    public func save(_ state: AppState) {
        lock.lock(); defer { lock.unlock() }
        self.state = state
    }
}
