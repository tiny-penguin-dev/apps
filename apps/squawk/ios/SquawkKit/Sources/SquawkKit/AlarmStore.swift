import Foundation

/// Where alarms are saved. Screens only talk to this, so iCloud sync can be added
/// later by swapping the store, without touching them (PRODUCT.md 8b).
public protocol AlarmStore: Sendable {
    func load() throws -> [Alarm]
    func save(_ alarms: [Alarm]) throws
}

/// Saves alarms as a small JSON file on the phone.
public struct FileAlarmStore: AlarmStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Application Support/alarms.json`.
    public static func standard() throws -> FileAlarmStore {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return FileAlarmStore(url: folder.appendingPathComponent("alarms.json"))
    }

    public func load() throws -> [Alarm] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SavedAlarms.self, from: data).alarms
    }

    public func save(_ alarms: [Alarm]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(SavedAlarms(version: 1, alarms: alarms))
        try data.write(to: url, options: [.atomic])
    }
}

/// The file format, versioned so it can change later.
struct SavedAlarms: Codable {
    var version: Int
    var alarms: [Alarm]
}

/// Keeps alarms in memory, for previews and tests.
public final class MemoryAlarmStore: AlarmStore, @unchecked Sendable {
    private let lock = NSLock()
    private var alarms: [Alarm]

    public init(_ alarms: [Alarm] = []) {
        self.alarms = alarms
    }

    public func load() throws -> [Alarm] {
        lock.lock(); defer { lock.unlock() }
        return alarms
    }

    public func save(_ alarms: [Alarm]) throws {
        lock.lock(); defer { lock.unlock() }
        self.alarms = alarms
    }
}
