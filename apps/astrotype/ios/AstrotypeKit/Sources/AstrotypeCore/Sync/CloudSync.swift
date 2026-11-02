import Foundation

/// Everything that syncs, as one value: the learned words, the keyboard settings with
/// when they last changed, and the personal model. Two copies merge word by word (the
/// later change wins), settings as a whole (the later copy wins) and the personal model
/// device by device (`PersonalModel.merged`).
public struct SyncSnapshot: Codable, Sendable, Equatable {
    public static let version = 1

    public var version = SyncSnapshot.version
    public var words: LearnedWords
    public var settings: KeyboardSettings
    public var settingsChanged: Date
    /// Nil from a copy written before Phase B, or by a host that keeps none.
    public var personal: PersonalModel?

    public init(words: LearnedWords, settings: KeyboardSettings, settingsChanged: Date, personal: PersonalModel? = nil) {
        self.words = words
        self.settings = settings
        self.settingsChanged = settingsChanged
        self.personal = personal
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.version
        words = try c.decodeIfPresent(LearnedWords.self, forKey: .words) ?? LearnedWords()
        settings = try c.decodeIfPresent(KeyboardSettings.self, forKey: .settings) ?? KeyboardSettings()
        settingsChanged = try c.decodeIfPresent(Date.self, forKey: .settingsChanged) ?? .distantPast
        personal = try? c.decodeIfPresent(PersonalModel.self, forKey: .personal)
    }

    public func merged(with other: SyncSnapshot) -> SyncSnapshot {
        var out = self
        out.words = words.merged(with: other.words)
        if other.settingsChanged > settingsChanged {
            out.settings = other.settings
            out.settingsChanged = other.settingsChanged
        }
        switch (personal, other.personal) {
        case (let mine?, let theirs?): out.personal = mine.merged(with: theirs)
        case (nil, let theirs?): out.personal = theirs
        default: break
        }
        return out
    }
}

public enum CloudSyncError: Error, Equatable, LocalizedError {
    /// Something else wrote to the cloud since `fetch`; here is what it holds now.
    case conflict(SyncSnapshot?)
    /// iCloud cannot be used right now (no account, no network): the message to show.
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .conflict: "Another device was writing at the same time."
        case .unavailable(let message): message
        }
    }
}

/// The copy of the snapshot in the cloud (BUILD.md "Data"). One record per iCloud
/// account that every device reads, merges with its own copy and writes back; a write
/// that lands on a copy it has not seen is refused with the newer copy, and the device
/// merges again. `CloudKitSync` is the live one, `FakeCloudSync` the test one.
public protocol CloudSync: Sendable {
    /// The cloud's copy, nil when there is none yet.
    func fetch() async throws -> SyncSnapshot?
    /// Writes `snapshot` over the copy `fetch` last returned. Throws
    /// `CloudSyncError.conflict` when the cloud changed in between.
    func save(_ snapshot: SyncSnapshot) async throws
}

/// One round of sync: fetch, merge, write back, merging again if something else wrote
/// first. Pure apart from the cloud calls, so the same code runs in the keyboard and
/// the app.
///
///     let merged = try await Syncer.sync(local: snapshot, cloud: cloud)
///     // keep `merged` locally; it is also what the cloud holds now
public enum Syncer {
    public static func sync(local: SyncSnapshot, cloud: CloudSync, attempts: Int = 3) async throws -> SyncSnapshot {
        var remote = try await cloud.fetch()
        for _ in 0..<max(1, attempts) {
            let merged = remote.map { local.merged(with: $0) } ?? local
            if let remote, merged == remote { return merged }
            do {
                try await cloud.save(merged)
                return merged
            } catch CloudSyncError.conflict(let newer) {
                remote = newer
            }
        }
        throw CloudSyncError.conflict(remote)
    }
}

/// A cloud in memory, for tests and previews: holds one snapshot and refuses a write
/// over a copy the writer has not fetched.
public final class FakeCloudSync: CloudSync, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SyncSnapshot?
    private var generation = 0
    private var fetchedGeneration = -1
    public private(set) var saves = 0
    public private(set) var fetches = 0
    /// Set to make the next call fail with this.
    public var failure: CloudSyncError?
    /// Runs once, right after the next fetch: another device writing in the gap.
    public var afterFetch: (@Sendable () -> Void)?

    public init(_ snapshot: SyncSnapshot? = nil) {
        stored = snapshot
    }

    public var snapshot: SyncSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    /// Another device wrote this, behind the next writer's back.
    public func write(fromElsewhere snapshot: SyncSnapshot) {
        lock.lock(); defer { lock.unlock() }
        stored = snapshot
        generation += 1
    }

    public func fetch() async throws -> SyncSnapshot? {
        let (out, hook) = try fetchNow()
        hook?()
        return out
    }

    public func save(_ snapshot: SyncSnapshot) async throws {
        try saveNow(snapshot)
    }

    // The lock is taken in synchronous helpers: NSLock may not be held across an await.
    private func fetchNow() throws -> (SyncSnapshot?, (@Sendable () -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        fetches += 1
        fetchedGeneration = generation
        let hook = afterFetch
        afterFetch = nil
        return (stored, hook)
    }

    private func saveNow(_ snapshot: SyncSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        saves += 1
        guard fetchedGeneration == generation else {
            fetchedGeneration = generation
            throw CloudSyncError.conflict(stored)
        }
        stored = snapshot
        generation += 1
        fetchedGeneration = generation
    }
}
