#if canImport(CloudKit)
import CloudKit
import Foundation

/// Practice recordings and shared words to the public database, one `PracticeSession`
/// record each named after its ID, where `ml/download_samples.py` can pick them up.
/// Only the app uses it, and only with "Send practice sessions" on. Shared words
/// (features/smart-matching Phase C) are version 3, kind `word.…`, label the word.
///
/// Typing logs from Settings → Debug (`TypingLog`) go the same way, kind `typing.log`,
/// compressed and in parts (`TypingLog.parts`), label "<log id> <part>/<parts>". The app
/// can delete them again: it created them.
public struct CloudKitPracticeUploader: PracticeUploader, SharedWordUploader, TypingLogUploader {
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

    public func upload(_ parts: [TypingLog.Part]) async throws -> [String] {
        guard !parts.isEmpty else { return [] }
        let container = CKContainer(identifier: containerID)
        guard try await container.accountStatus() == .available else { throw CKError(.notAuthenticated) }
        let records: [CKRecord] = parts.map { part in
            let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: part.id.uuidString))
            record["json"] = part.json
            record["kind"] = TypingLog.kind
            record["label"] = part.label
            record["version"] = Int64(TypingLog.version)
            return record
        }
        // One at a time: each part is most of a megabyte, and a request holds about two.
        var saved: [String] = []
        for record in records {
            let result = try await container.publicCloudDatabase.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            for (id, outcome) in result.saveResults {
                if case .failure(let error) = outcome { throw error }
                saved.append(id.recordName)
            }
        }
        return saved
    }

    public func delete(_ records: [String]) async throws {
        guard !records.isEmpty else { return }
        let container = CKContainer(identifier: containerID)
        _ = try await container.publicCloudDatabase.modifyRecords(
            saving: [], deleting: records.map { CKRecord.ID(recordName: $0) }, atomically: false
        )
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
