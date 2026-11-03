import Foundation

/// One word someone chose to share to tune the keyboard (features/smart-matching Phase
/// C, "Sharing you can see"): the word, the paths their thumbs drew for it, and where
/// it was made. Never a sentence: a practice session goes up as its words, each on its
/// own with no order or time of day, and a correction from another app is the word
/// alone with the keyboard's first guess. The app shows exactly these values on "What
/// gets shared" before they go, and sends them as `PracticeSession` records.
///
///     let words = SharedWord.words(of: recording)            // a speed test, word by word
///     let fix = SharedWord.correction(settled, layout: layout, now: now)
///     let ready = words.map { $0.stamped(with: device) }    // the app adds the device
public struct SharedWord: Codable, Sendable, Equatable, Identifiable {
    /// After the session recordings' 1 and 2, so the tools tell them apart.
    public static let currentVersion = 3
    /// The kinds: a practice word from the app ("word.speedtest", "word.drill.pairs")
    /// and a fix made in another app.
    public static let correctionKind = "word.correction"
    /// A word the keyboard missed, typed with "Not it?" in another app
    /// (features/missed-words): like a correction, the word meant and the swipe.
    public static let missKind = "word.miss"

    public var version = SharedWord.currentVersion
    public var id: UUID
    public var kind: String
    /// The word meant, lowercase.
    public var word: String
    /// What went in first, when it was not the word meant (a miss).
    public var typed: String?
    /// The word before it, for practice words only: the word asked for before this one
    /// (our prompt, never the person's text). Nil for corrections.
    public var previous: String?
    public var layoutWidth: Double
    public var layoutHeight: Double
    public var split: Bool
    /// Points in layout units, `t` in seconds since this word's first touch.
    public var touches: [PracticeRecording.Touch]
    /// A random ID per install; empty until the app stamps it.
    public var writer: String
    public var device: String
    public var system: String
    public var app: String
    /// The day only ("2026-11-02"), so words cannot be put back in order.
    public var day: String

    public init(id: UUID = UUID(), kind: String, word: String, typed: String? = nil, previous: String? = nil,
                layoutWidth: Double, layoutHeight: Double, split: Bool, touches: [PracticeRecording.Touch],
                writer: String = "", device: String = "", system: String = "", app: String = "", day: String) {
        self.id = id
        self.kind = kind
        self.word = word
        self.typed = typed
        self.previous = previous
        self.layoutWidth = layoutWidth
        self.layoutHeight = layoutHeight
        self.split = split
        self.touches = touches
        self.writer = writer
        self.device = device
        self.system = system
        self.app = app
        self.day = day
    }

    /// Made in another app: a fix from the bar or a miss typed with "Not it?". Both go
    /// only with "Include corrections" on.
    public var isCorrection: Bool { kind == Self.correctionKind || kind == Self.missKind }
    public var isMiss: Bool { kind == Self.missKind }

    /// With where it was made, as the app knows it (the extension does not).
    public func stamped(with device: PracticeRecording.Device) -> SharedWord {
        var out = self
        out.writer = device.writer
        out.device = device.model
        out.system = device.system
        out.app = device.app
        return out
    }

    /// "2026-11-02" in UTC.
    public static func day(of date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Making them

    /// A practice session as its words, each with its own touches (those that landed
    /// after the word before went in), in a random order. The word meant is the one
    /// asked for, matched as the replay does: a wrong word keeps the same one asked.
    public static func words(of recording: PracticeRecording) -> [SharedWord] {
        guard !recording.commits.isEmpty else { return [] }
        let expected = recording.expected.split(separator: " ").map(String.init)
        let day = day(of: recording.createdAt)
        var out: [SharedWord] = []
        var pointer = 0
        var after = -Double.infinity
        for commit in recording.commits {
            defer { after = commit.t }
            guard pointer < expected.count else { break }
            let meant = expected[pointer]
            let previous = pointer == 0 ? NgramModel.sentenceStart : expected[pointer - 1]
            if commit.word == meant { pointer += 1 }
            let mine = recording.touches.filter { touch in
                guard let start = touch.points.first, start.count >= 3 else { return false }
                return start[2] > after && start[2] <= commit.t
            }
            guard let first = mine.compactMap({ $0.points.first?[2] }).min() else { continue }
            let rebased = mine.map { touch in
                PracticeRecording.Touch(id: touch.id, points: touch.points.map { p in
                    p.count >= 3 ? [p[0], p[1], round4(p[2] - first)] : p
                })
            }
            out.append(SharedWord(kind: "word." + recording.kind, word: meant, typed: commit.word == meant ? nil : commit.word,
                                  previous: previous, layoutWidth: recording.layoutWidth, layoutHeight: recording.layoutHeight,
                                  split: recording.split, touches: rebased, day: day))
        }
        return out.shuffled()
    }

    /// A fix made from the bar in another app: the word chosen, the guess it replaced,
    /// and the touches; nothing around it. Nil when the word was not a fix.
    public static func correction(_ settled: SettledWord, layout: Layout, now: Date) -> SharedWord? {
        guard let typed = settled.fixedFrom, typed != settled.word, !settled.strokes.isEmpty,
              layout.width > 0, layout.height > 0 else { return nil }
        let first = settled.strokes.compactMap(\.times.first).min() ?? 0
        let touches = settled.strokes.enumerated().map { index, stroke in
            PracticeRecording.Touch(id: index + 1, points: stroke.points.enumerated().map { i, point in
                let t = stroke.times.indices.contains(i) ? stroke.times[i] - first : 0
                return [round4(point.x / layout.width), round4(point.y / layout.height), round4(t)]
            })
        }
        return SharedWord(kind: settled.missed ? missKind : correctionKind, word: settled.word, typed: typed, layoutWidth: layout.width,
                          layoutHeight: layout.height, split: layout.split, touches: touches, day: day(of: now))
    }

    // MARK: Replaying them

    /// The word as a one-word recording, for `Replay` (with `previous` before it).
    public var recording: PracticeRecording {
        let end = touches.compactMap { $0.points.last?[2] }.max() ?? 0
        return PracticeRecording(id: id, kind: kind, label: word, expected: word, layoutWidth: layoutWidth,
                                 layoutHeight: layoutHeight, split: split, touches: touches,
                                 commits: [PracticeRecording.Commit(word: typed ?? word, t: end + 0.01)],
                                 wordsPerMinute: nil, fixes: nil, writer: writer, device: device, system: system,
                                 app: app, createdAt: Date(timeIntervalSince1970: 0))
    }

    private static func round4(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
}

/// Shared words waiting to go up, one file each in a folder: the app's practice words
/// and, with Full Access, the corrections the keyboard writes into the App Group.
/// Sent ones move to `Uploaded/`; at most `limit` wait, the oldest dropped first.
public struct SharedWordStore: Sendable {
    public let folder: URL
    public let limit: Int

    public init(folder: URL, limit: Int = 500) {
        self.folder = folder
        self.limit = limit
    }

    public func save(_ words: [SharedWord]) {
        guard !words.isEmpty else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for word in words {
            guard let data = try? encoder.encode(word) else { continue }
            try? data.write(to: url(word.id), options: .atomic)
        }
        trim()
    }

    /// What is waiting, oldest file first.
    public func pending() -> [SharedWord] {
        let decoder = JSONDecoder()
        return files().compactMap { (try? Data(contentsOf: $0)).flatMap { try? decoder.decode(SharedWord.self, from: $0) } }
    }

    public var pendingCount: Int { files().count }

    /// Taken off the list before it went ("What gets shared", or sharing turned off).
    public func remove(_ ids: [UUID]) {
        for id in ids { try? FileManager.default.removeItem(at: url(id)) }
    }

    public func markUploaded(_ ids: [UUID]) {
        let uploaded = folder.appendingPathComponent("Uploaded", isDirectory: true)
        try? FileManager.default.createDirectory(at: uploaded, withIntermediateDirectories: true)
        for id in ids {
            let to = uploaded.appendingPathComponent(url(id).lastPathComponent)
            try? FileManager.default.removeItem(at: to)
            try? FileManager.default.moveItem(at: url(id), to: to)
        }
    }

    private func files() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return items.filter { $0.pathExtension == "json" }.sorted { modified($0) < modified($1) || (modified($0) == modified($1) && $0.path < $1.path) }
    }

    private func trim() {
        let all = files()
        guard all.count > limit else { return }
        for file in all.prefix(all.count - limit) { try? FileManager.default.removeItem(at: file) }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func url(_ id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}

/// Sends shared words up. CloudKit live (`CloudKitPracticeUploader`), a fake in tests.
public protocol SharedWordUploader: Sendable {
    /// Uploads the words and returns the IDs that made it.
    func upload(_ words: [SharedWord]) async throws -> [UUID]
}

public final class FakeSharedWordUploader: SharedWordUploader, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var uploaded: [SharedWord] = []
    public var error: Error?

    public init() {}

    public func upload(_ words: [SharedWord]) async throws -> [UUID] {
        if let error { throw error }
        lock.withLock { uploaded += words }
        return words.map(\.id)
    }
}
