import Foundation
import Observation
import StackWriteKit

/// Training samples on disk: one JSON file per word in Documents/Samples,
/// which also shows up in the Files app.
@MainActor @Observable
final class SampleStore {
    private(set) var count = 0
    private let folder: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("Samples", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        count = files().count
    }

    func save(_ sample: StrokeSample) throws {
        let data = try StrokeSample.encoder.encode(sample)
        try data.write(to: url(for: sample.id), options: .atomic)
        count += 1
    }

    func delete(_ id: UUID) {
        if (try? FileManager.default.removeItem(at: url(for: id))) != nil {
            count -= 1
        }
    }

    func deleteAll() {
        for file in files() { try? FileManager.default.removeItem(at: file) }
        count = 0
    }

    /// Zips the samples folder into a temporary file for the share sheet.
    func exportArchive() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("StackWrite-samples-\(stamp).zip")
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

    private func url(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).json")
    }

    private func files() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension == "json" }
    }
}
