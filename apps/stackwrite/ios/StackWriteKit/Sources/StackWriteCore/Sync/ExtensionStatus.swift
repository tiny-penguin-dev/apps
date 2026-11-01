import Foundation

/// What the keyboard extension last saw, written to the App Group for the app, which
/// cannot ask iOS about Full Access itself. The extension can only write it when Full
/// Access is on, so a recent status means Full Access was on then.
public struct ExtensionStatus: Codable, Sendable, Equatable {
    public static let version = 1

    public var version = ExtensionStatus.version
    public var fullAccess: Bool
    /// When the extension last ran with this status.
    public var seen: Date
    /// When words and settings last synced with iCloud from the keyboard.
    public var lastSync: Date?
    /// Why the last sync from the keyboard failed, if it did.
    public var lastSyncError: String?

    public init(fullAccess: Bool, seen: Date, lastSync: Date? = nil, lastSyncError: String? = nil) {
        self.fullAccess = fullAccess
        self.seen = seen
        self.lastSync = lastSync
        self.lastSyncError = lastSyncError
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.version
        fullAccess = try c.decodeIfPresent(Bool.self, forKey: .fullAccess) ?? false
        seen = try c.decodeIfPresent(Date.self, forKey: .seen) ?? .distantPast
        lastSync = try c.decodeIfPresent(Date.self, forKey: .lastSync)
        lastSyncError = try c.decodeIfPresent(String.self, forKey: .lastSyncError)
    }
}

/// Where the app reads the extension's status.
public protocol ExtensionStatusReading: Sendable {
    func load() -> ExtensionStatus?
}

/// The status as a file in the App Group, read by the app and written by the extension.
public struct FileExtensionStatusStore: ExtensionStatusReading {
    private let file: JSONFile<ExtensionStatus>

    public init(url: URL) {
        file = JSONFile(url)
    }

    public func load() -> ExtensionStatus? { file.read() }
    public func save(_ status: ExtensionStatus) { file.write(status) }
}

public final class FakeExtensionStatus: ExtensionStatusReading, @unchecked Sendable {
    public var status: ExtensionStatus?

    public init(_ status: ExtensionStatus? = nil) {
        self.status = status
    }

    public func load() -> ExtensionStatus? { status }
}
