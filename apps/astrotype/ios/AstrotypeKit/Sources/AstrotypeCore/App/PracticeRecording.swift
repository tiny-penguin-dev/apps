import Foundation

/// The touches of one practice session in the app (a speed test or a drill), sent
/// with the words they typed when the person turned "Send practice sessions" on
/// (PRODUCT.md §5.4: off by default, never from other apps). Points are in layout
/// units (x over the keyboard's width, y over its height), `t` in seconds since the
/// first touch. The record on CloudKit is `PracticeSession` (cloudkit/schema.ckdb).
public struct PracticeRecording: Codable, Sendable, Equatable, Identifiable {
    public static let currentVersion = 1

    public struct Touch: Codable, Sendable, Equatable {
        public var id: Int
        /// `[x, y, t]` per point.
        public var points: [[Double]]
    }

    /// Where the recording was made, with no name or account attached.
    public struct Device: Sendable, Equatable {
        public var model: String
        public var system: String
        public var app: String
        /// A random ID per install, so one person's sessions can be grouped.
        public var writer: String

        public init(model: String, system: String, app: String, writer: String) {
            self.model = model
            self.system = system
            self.app = app
            self.writer = writer
        }
    }

    public var version = PracticeRecording.currentVersion
    public var id: UUID
    /// "speedtest", or "drill.pairs", "drill.switching", "drill.doubles".
    public var kind: String
    /// The words that went into the field, lowercase, space separated.
    public var label: String
    /// The words asked for, the same way.
    public var expected: String
    public var layoutWidth: Double
    public var layoutHeight: Double
    public var split: Bool
    public var touches: [Touch]
    public var wordsPerMinute: Int?
    public var fixes: Int?
    public var writer: String
    public var device: String
    public var system: String
    public var app: String
    public var createdAt: Date
}

/// Collects a session's touches as the keyboard sees them, then makes the recording.
///
///     var recorder = TouchRecorder(kind: "speedtest", layoutWidth: w, layoutHeight: h, split: false)
///     recorder.touch(.began, id: 1, x: 40, y: 12, time: t)
///     recorder.committed("hello")
///     let recording = recorder.recording(expected: "hello", device: device, now: Date())
public struct TouchRecorder: Sendable, Equatable {
    public enum Phase: Sendable { case began, moved, ended, cancelled }

    public let kind: String
    public let layoutWidth: Double
    public let layoutHeight: Double
    public let split: Bool
    private var touches: [PracticeRecording.Touch] = []
    private var open: [Int: Int] = [:]
    private var first: TimeInterval?
    private var words: [String] = []

    public init(kind: String, layoutWidth: Double, layoutHeight: Double, split: Bool) {
        self.kind = kind
        self.layoutWidth = layoutWidth
        self.layoutHeight = layoutHeight
        self.split = split
    }

    public var touchCount: Int { touches.count }
    public var wordCount: Int { words.count }

    public mutating func touch(_ phase: Phase, id: Int, x: Double, y: Double, time: TimeInterval) {
        guard layoutWidth > 0, layoutHeight > 0 else { return }
        if first == nil { first = time }
        let point = [round4(x / layoutWidth), round4(y / layoutHeight), round4(time - (first ?? time))]
        switch phase {
        case .began:
            touches.append(PracticeRecording.Touch(id: id, points: [point]))
            open[id] = touches.count - 1
        case .moved:
            guard let index = open[id] else { return }
            touches[index].points.append(point)
        case .ended, .cancelled:
            guard let index = open.removeValue(forKey: id) else { return }
            touches[index].points.append(point)
        }
    }

    public mutating func committed(_ word: String) {
        let clean = SpeedTest.normalize(word)
        if !clean.isEmpty { words.append(clean) }
    }

    public func recording(expected: String, device: PracticeRecording.Device, now: Date,
                          wordsPerMinute: Int? = nil, fixes: Int? = nil, id: UUID = UUID()) -> PracticeRecording {
        PracticeRecording(id: id, kind: kind, label: words.joined(separator: " "), expected: expected,
                          layoutWidth: layoutWidth, layoutHeight: layoutHeight, split: split, touches: touches,
                          wordsPerMinute: wordsPerMinute, fixes: fixes, writer: device.writer, device: device.model,
                          system: device.system, app: device.app, createdAt: now)
    }

    private func round4(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
}

/// Recordings waiting to go up, as files in a folder; each moves to `Uploaded/` once sent.
public struct PracticeStore: Sendable {
    public let folder: URL
    private let fileManager: FileManager

    public init(folder: URL, fileManager: FileManager = .default) {
        self.folder = folder
        self.fileManager = fileManager
    }

    public func save(_ recording: PracticeRecording) throws {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(recording).write(to: url(recording.id), options: .atomic)
    }

    /// The oldest recordings still to send, at most `limit`.
    public func pending(limit: Int = 50) -> [PracticeRecording] {
        let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension == "json" } ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .compactMap { url -> PracticeRecording? in (try? Data(contentsOf: url)).flatMap { try? decoder.decode(PracticeRecording.self, from: $0) } }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    public var pendingCount: Int { pending(limit: .max).count }

    /// Sent: the file moves to `Uploaded/`, kept for export and in case we want it back.
    public func markUploaded(_ ids: [UUID]) {
        let uploaded = folder.appendingPathComponent("Uploaded", isDirectory: true)
        try? fileManager.createDirectory(at: uploaded, withIntermediateDirectories: true)
        for id in ids {
            let from = url(id)
            let to = uploaded.appendingPathComponent(from.lastPathComponent)
            try? fileManager.removeItem(at: to)
            try? fileManager.moveItem(at: from, to: to)
        }
    }

    private func url(_ id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}

/// Sends recordings up. CloudKit live (`CloudKitPracticeUploader`), a fake in tests.
public protocol PracticeUploader: Sendable {
    /// Uploads the recordings and returns the IDs that made it.
    func upload(_ recordings: [PracticeRecording]) async throws -> [UUID]
}

public final class FakePracticeUploader: PracticeUploader, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var uploaded: [PracticeRecording] = []
    public var error: Error?

    public init() {}

    public func upload(_ recordings: [PracticeRecording]) async throws -> [UUID] {
        if let error { throw error }
        lock.withLock { uploaded += recordings }
        return recordings.map(\.id)
    }
}
