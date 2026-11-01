import Foundation
import Observation
import AstrotypeCore

/// Training samples on disk: one JSON file per word in Documents/Samples
/// (also visible in the Files app). Once uploaded, a file moves to
/// Samples/Uploaded, so the folder itself is the upload queue.
@MainActor @Observable
final class SampleStore {
    private(set) var count = 0
    /// Samples not uploaded yet.
    private(set) var pendingCount = 0
    private let folder: URL
    private let uploaded: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("Samples", isDirectory: true)
        uploaded = folder.appendingPathComponent("Uploaded", isDirectory: true)
        try? FileManager.default.createDirectory(at: uploaded, withIntermediateDirectories: true)
        refreshCounts()
    }

    func save(_ sample: StrokeSample) throws {
        let data = try StrokeSample.encoder.encode(sample)
        try data.write(to: url(for: sample.id), options: .atomic)
        refreshCounts()
    }

    /// Removes a sample. Returns true if it had already been uploaded.
    @discardableResult
    func delete(_ id: UUID) -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(at: url(for: id))
        let wasUploaded = (try? fm.removeItem(at: url(for: id, in: uploaded))) != nil
        refreshCounts()
        return wasUploaded
    }

    func deleteAll() {
        for file in files(in: folder) + files(in: uploaded) { try? FileManager.default.removeItem(at: file) }
        refreshCounts()
    }

    /// Samples waiting to upload, oldest first, as (id, JSON data).
    func pending(limit: Int) -> [(id: UUID, data: Data)] {
        let files = files(in: folder).sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
        return files.prefix(limit).compactMap { file in
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: file) else { return nil }
            return (id, data)
        }
    }

    func markUploaded(_ ids: [UUID]) {
        for id in ids {
            try? FileManager.default.moveItem(at: url(for: id), to: url(for: id, in: uploaded))
        }
        refreshCounts()
    }

    /// Zips the samples folder into a temporary file for the share sheet.
    func exportArchive() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Astrotype-samples-\(stamp).zip")
        try? FileManager.default.removeItem(at: destination)
        var coordinatorError: NSError?
        var copyError: Error?
        // Reading a folder "for uploading" hands back a zip of it.
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { zip in
            do { try FileManager.default.copyItem(at: zip, to: destination) } catch { copyError = error }
        }
        if let error = coordinatorError ?? copyError { throw error }
        return destination
    }

    private func refreshCounts() {
        pendingCount = files(in: folder).count
        count = pendingCount + files(in: uploaded).count
    }

    private func url(for id: UUID, in directory: URL? = nil) -> URL {
        (directory ?? folder).appendingPathComponent("\(id.uuidString).json")
    }

    private func files(in directory: URL) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension == "json" }
    }
}
