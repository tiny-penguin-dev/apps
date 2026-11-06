import Foundation

/// A small JSON file, written whole and atomically. The stores below are thin wrappers
/// over one of these, so a word list or a settings value is one file in one place.
public struct JSONFile<Value: Codable & Sendable>: Sendable {
    public let url: URL

    public init(_ url: URL) {
        self.url = url
    }

    /// The saved value, nil when there is none or it cannot be read.
    public func read() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    /// Saves `value`, creating the folder on the way. A failure (no room, a container we
    /// may not write to) is swallowed: the caller keeps its copy in memory.
    public func write(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

/// A value with the time it was last changed, for picking the newer of two copies.
public struct Stamped<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public var changed: Date
    public var value: Value

    public init(changed: Date, value: Value) {
        self.changed = changed
        self.value = value
    }
}

// MARK: Words

/// Where the learned words are kept.
public protocol WordStore: Sendable {
    func load() -> LearnedWords?
    func save(_ words: LearnedWords)
}

/// Learned words as a JSON file (BUILD.md "Data"): the extension's own container, or
/// the App Group's.
public struct FileWordStore: WordStore {
    private let file: JSONFile<LearnedWords>

    public init(url: URL) {
        file = JSONFile(url)
    }

    public func load() -> LearnedWords? { file.read() }
    public func save(_ words: LearnedWords) { file.write(words) }
}

/// Words kept in memory, for tests and previews.
public final class MemoryWordStore: WordStore, @unchecked Sendable {
    private var words: LearnedWords?
    private let lock = NSLock()

    public init(_ words: LearnedWords? = nil) {
        self.words = words
    }

    public func load() -> LearnedWords? {
        lock.lock(); defer { lock.unlock() }
        return words
    }

    public func save(_ words: LearnedWords) {
        lock.lock(); defer { lock.unlock() }
        self.words = words
    }
}

/// Two copies of the words kept in step: the extension's own and the App Group's.
/// Loading merges them (the later change wins per word), saving writes both, so a word
/// learned in the keyboard reaches the app and one forgotten in the app leaves the
/// keyboard, whichever side wrote last.
public struct MirroredWordStore: WordStore {
    public let own: WordStore
    public let shared: WordStore

    public init(own: WordStore, shared: WordStore) {
        self.own = own
        self.shared = shared
    }

    public func load() -> LearnedWords? {
        switch (own.load(), shared.load()) {
        case (let mine?, let theirs?): mine.merged(with: theirs)
        case (let mine?, nil): mine
        case (nil, let theirs?): theirs
        case (nil, nil): nil
        }
    }

    public func save(_ words: LearnedWords) {
        own.save(words)
        shared.save(words)
    }
}

// MARK: Personal model

/// Where the personal model is kept (features/smart-matching Phase B).
public protocol PersonalStore: Sendable {
    func load() -> PersonalModel?
    func save(_ model: PersonalModel)
}

/// The personal model as a JSON file: the extension's own container, or the App Group's.
public struct FilePersonalStore: PersonalStore {
    private let file: JSONFile<PersonalModel>

    public init(url: URL) {
        file = JSONFile(url)
    }

    public func load() -> PersonalModel? { file.read() }
    public func save(_ model: PersonalModel) { file.write(model) }
}

/// A personal model kept in memory, for tests and previews.
public final class MemoryPersonalStore: PersonalStore, @unchecked Sendable {
    private var model: PersonalModel?
    private let lock = NSLock()

    public init(_ model: PersonalModel? = nil) {
        self.model = model
    }

    public func load() -> PersonalModel? {
        lock.lock(); defer { lock.unlock() }
        return model
    }

    public func save(_ model: PersonalModel) {
        lock.lock(); defer { lock.unlock() }
        self.model = model
    }
}

/// Two copies of the personal model kept in step, like `MirroredWordStore`: loading
/// merges them, saving writes both.
public struct MirroredPersonalStore: PersonalStore {
    public let own: PersonalStore
    public let shared: PersonalStore

    public init(own: PersonalStore, shared: PersonalStore) {
        self.own = own
        self.shared = shared
    }

    public func load() -> PersonalModel? {
        switch (own.load(), shared.load()) {
        case (let mine?, let theirs?): mine.merged(with: theirs)
        case (let mine?, nil): mine
        case (nil, let theirs?): theirs
        case (nil, nil): nil
        }
    }

    /// Merged with the shared copy first, so what the app wrote there since (pairs the
    /// person deleted, a forget) isn't written over by a keyboard that loaded earlier.
    public func save(_ model: PersonalModel) {
        let merged = shared.load().map { model.merged(with: $0) } ?? model
        own.save(merged)
        shared.save(merged)
    }
}

/// A random ID for this install of the keyboard, made the first time it is asked for
/// and kept in a file: the personal model's shard for this device. Never sent anywhere
/// but the person's own iCloud.
public enum InstallID {
    public static func load(from url: URL) -> String {
        let file = JSONFile<String>(url)
        if let id = file.read(), !id.isEmpty { return id }
        let id = UUID().uuidString
        file.write(id)
        return id
    }
}

// MARK: Settings

/// Settings as a JSON file with the time they changed, so two copies can be compared.
public struct FileSettingsStore: SettingsStore {
    private let file: JSONFile<Stamped<KeyboardSettings>>
    private let now: @Sendable () -> Date

    public init(url: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        file = JSONFile(url)
        self.now = now
    }

    public func load() -> KeyboardSettings? { file.read()?.value }
    public func save(_ settings: KeyboardSettings) { file.write(Stamped(changed: now(), value: settings)) }
    public func lastChanged() -> Date? { file.read()?.changed }

    /// Writes `settings` with a given change time (a copy that came from elsewhere).
    public func save(_ settings: KeyboardSettings, changed: Date) {
        file.write(Stamped(changed: changed, value: settings))
    }
}

/// Two copies of the settings kept in step: loading takes the one changed last, saving
/// writes both.
public struct MirroredSettingsStore: SettingsStore {
    public let own: SettingsStore
    public let shared: SettingsStore

    public init(own: SettingsStore, shared: SettingsStore) {
        self.own = own
        self.shared = shared
    }

    public func load() -> KeyboardSettings? {
        switch (own.load(), shared.load()) {
        case (let mine?, let theirs?):
            (shared.lastChanged() ?? .distantPast) > (own.lastChanged() ?? .distantPast) ? theirs : mine
        case (let mine?, nil): mine
        case (nil, let theirs?): theirs
        case (nil, nil): nil
        }
    }

    public func save(_ settings: KeyboardSettings) {
        own.save(settings)
        shared.save(settings)
    }

    public func lastChanged() -> Date? {
        [own.lastChanged(), shared.lastChanged()].compactMap { $0 }.max()
    }
}
