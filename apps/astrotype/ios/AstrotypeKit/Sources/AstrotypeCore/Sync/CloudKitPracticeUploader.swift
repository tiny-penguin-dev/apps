#if canImport(CloudKit)
import CloudKit
import Foundation

/// Practice recordings and shared words to the public database, one `PracticeSession`
/// record each named after its ID, where `ml/download_samples.py` can pick them up.
/// Only the app uses it, and only with "Send practice sessions" on. Shared words
/// (features/smart-matching Phase C) are version 3, kind `word.…`, label the word.
public struct CloudKitPracticeUploader: PracticeUploader, SharedWordUploader {
    public static let recordType = "PracticeSession"
    private let containerID: String

    public init(containerID: String = CloudKitSync.containerID) {
        self.containerID = containerID
    }

    public func upload(_ words: [SharedWord]) async throws -> [UUID] {
        try await save(words.map { word in
            (id: word.id, value: word, kind: word.kind, label: word.word, writer: word.writer, version: word.version)
        })
    }

    public func upload(_ recordings: [PracticeRecording]) async throws -> [UUID] {
        try await save(recordings.map { recording in
            (id: recording.id, value: recording, kind: recording.kind, label: recording.label,
             writer: recording.writer, version: recording.version)
        })
    }

    private func save<Value: Encodable>(_ items: [(id: UUID, value: Value, kind: String, label: String, writer: String, version: Int)]) async throws -> [UUID] {
        guard !items.isEmpty else { return [] }
        let container = CKContainer(identifier: containerID)
        guard try await container.accountStatus() == .available else { return [] }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let records: [CKRecord] = try items.map { item in
            let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: item.id.uuidString))
            record["json"] = String(decoding: try encoder.encode(item.value), as: UTF8.self)
            record["kind"] = item.kind
            record["label"] = item.label
            record["writer"] = item.writer
            record["version"] = Int64(item.version)
            return record
        }
        let result = try await container.publicCloudDatabase.modifyRecords(
            saving: records, deleting: [], savePolicy: .allKeys, atomically: false
        )
        return result.saveResults.compactMap { id, outcome in
            if case .success = outcome { return UUID(uuidString: id.recordName) }
            return nil
        }
    }
}
#endif
