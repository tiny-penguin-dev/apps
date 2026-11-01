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

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.version
        firstLaunch = try c.decodeIfPresent(Date.self, forKey: .firstLaunch)
        onboardingDone = try c.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? false
        keyboardOnSeen = try c.decodeIfPresent(Bool.self, forKey: .keyboardOnSeen) ?? false
        fullAccessAsked = try c.decodeIfPresent(Bool.self, forKey: .fullAccessAsked) ?? false
        practiceDays = try c.decodeIfPresent([String].self, forKey: .practiceDays) ?? []
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
