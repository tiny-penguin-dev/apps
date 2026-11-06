import Foundation

/// The typing recording on disk (`TypingEvent`, Settings → Debug → "Keep recording"):
/// one JSON line per event, in files of about five minutes named by when they began,
/// each starting with a snapshot. Files older than `keep` are deleted as new ones start,
/// so the folder holds about the last half hour. The keyboard writes it to the App Group
/// (it needs Full Access) and the app reads it to send a stretch; it never leaves the
/// phone on its own.
public struct TypingLogFiles: Sendable {
    public let folder: URL
    /// How much is kept: half an hour, plus the file being written.
    public static let keep: TimeInterval = 35 * 60

    public init(folder: URL) {
        self.folder = folder
    }

    /// The files, oldest first.
    public func files() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.lastPathComponent.hasPrefix("typing-") && $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A new file's name: when it began, in milliseconds, zero-padded so names sort.
    public func newFile(at date: Date) -> URL {
        let ms = Int64((date.timeIntervalSince1970 * 1_000).rounded())
        return folder.appendingPathComponent("typing-\(String(format: "%015lld", ms)).jsonl")
    }

    /// Adds lines to the end of a file, making it (and the folder) first if needed.
    public func append(_ data: Data, to url: URL) throws {
        guard !data.isEmpty else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /// The events in one file. A line cut short (the keyboard ended mid-write) is
    /// skipped, and so is anything before the file's first snapshot.
    public func events(in url: URL) -> [TypingEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        var out: [TypingEvent] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let event = try? decoder.decode(TypingEvent.self, from: Data(line)) else { continue }
            if out.isEmpty, event.e != .snapshot { continue }
            out.append(event)
        }
        return out
    }

    /// Every event kept, oldest first.
    public func events() -> [TypingEvent] {
        files().flatMap(events(in:))
    }

    /// Deletes the files whose newest event is older than `date`: a file's name says
    /// when it began, and the next file's when it ended.
    public func prune(before date: Date) {
        let files = files()
        for (index, url) in files.enumerated() where index + 1 < files.count {
            if let ended = Self.started(files[index + 1]), ended < date { try? FileManager.default.removeItem(at: url) }
        }
    }

    public func removeAll() {
        for url in files() { try? FileManager.default.removeItem(at: url) }
    }

    /// The total size of the files, in bytes.
    public func size() -> Int {
        files().reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// When a file began, from its name.
    public static func started(_ url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("typing-"), let ms = Double(name.dropFirst("typing-".count)) else { return nil }
        return Date(timeIntervalSince1970: ms / 1_000)
    }

    /// The last `seconds` before `now` as a log to send, with what the keyboard had
    /// learned. Nil when nothing was recorded in that time.
    public func log(last seconds: TimeInterval, now: Date, writer: String, app: String,
                    learned: LearnedWords? = nil, personal: PersonalModel? = nil) -> TypingLog? {
        let events = TypingLog.window(events(), last: seconds, now: now)
        guard events.contains(where: \.isInput) else { return nil }
        let first = TypingLog.dates(of: events).compactMap { $0 }.first ?? now
        return TypingLog(createdAt: now, from: max(first, now.addingTimeInterval(-seconds)), to: now,
                         marks: TypingLog.marks(in: events), writer: writer, app: app,
                         learned: learned, personal: personal, events: events)
    }

    /// The marks kept, newest first.
    public func marks() -> [Date] {
        TypingLog.marks(in: events()).reversed()
    }
}

/// Writes the recording as the keyboard types (`TypingLogFiles`): events go into a
/// buffer and out to the file every couple of seconds, so the keyboard does not write
/// a file per touch, and little is lost when iOS ends it. A new file starts at a
/// snapshot once the current one is five minutes old, and old files go then.
///
///     let recorder = TypingRecorder(files: TypingLogFiles(folder: folder))
///     recorder.snapshot(snap, time: now)        // first, and whenever `needsSnapshot`
///     recorder.record(TypingEvent(t: now, e: .down, i: 1, x: 40, y: 120))
///     recorder.flush()                          // the keyboard is going away
@MainActor
public final class TypingRecorder {
    public let files: TypingLogFiles
    /// How long a file runs before the next snapshot starts a new one.
    public var fileLength: TimeInterval = 5 * 60
    /// How often a snapshot is wanted while typing goes on.
    public var snapshotEvery: TimeInterval = 20
    /// How long the buffer waits before it goes to the file.
    public var flushDelay: TimeInterval = 2
    private let now: () -> Date
    private let encoder = JSONEncoder()
    private var buffer = Data()
    private var file: URL?
    private var fileStarted: Date?
    private var lastSnapshot: Double?
    private var flushTask: Task<Void, Never>?

    public init(files: TypingLogFiles, now: @escaping () -> Date = { Date() }) {
        self.files = files
        self.now = now
        encoder.outputFormatting = [.sortedKeys]
    }

    /// Whether a snapshot is due: none yet, or the last is `snapshotEvery` old.
    public func needsSnapshot(at time: Double) -> Bool {
        guard let lastSnapshot, file != nil else { return true }
        return time - lastSnapshot >= snapshotEvery || time < lastSnapshot
    }

    public func record(_ event: TypingEvent) {
        guard var line = try? encoder.encode(event) else { return }
        line.append(UInt8(ascii: "\n"))
        buffer.append(line)
        scheduleFlush()
    }

    /// A snapshot, starting a new file first when the current one is old enough.
    public func snapshot(_ snapshot: TypingSnapshot, time: Double) {
        let date = now()
        if file == nil || date.timeIntervalSince(fileStarted ?? date) >= fileLength {
            flush()
            file = files.newFile(at: date)
            fileStarted = date
            files.prune(before: date.addingTimeInterval(-TypingLogFiles.keep))
        }
        lastSnapshot = time
        record(TypingEvent(t: time, e: .snapshot, snap: snapshot))
    }

    /// Writes the buffer now.
    public func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard !buffer.isEmpty else { return }
        let url = file ?? files.newFile(at: now())
        file = url
        if fileStarted == nil { fileStarted = now() }
        try? files.append(buffer, to: url)
        buffer.removeAll(keepingCapacity: true)
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        let delay = flushDelay
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}
