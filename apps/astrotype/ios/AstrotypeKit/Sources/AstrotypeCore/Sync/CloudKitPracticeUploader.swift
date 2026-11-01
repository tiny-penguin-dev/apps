#if canImport(CloudKit)
import CloudKit
import Foundation

/// Practice recordings to the public database, one `PracticeSession` record per
/// recording named after its ID, where `ml/download_samples.py` can pick them up.
/// Only the app uses it, and only with "Send practice sessions" on.
public struct CloudKitPracticeUploader: PracticeUploader {
    public static let recordType = "PracticeSession"
    private let containerID: String

    public init(containerID: String = CloudKitSync.containerID) {
        self.containerID = containerID
    }

    public func upload(_ recordings: [PracticeRecording]) async throws -> [UUID] {
        guard !recordings.isEmpty else { return [] }
        let container = CKContainer(identifier: containerID)
        guard try await container.accountStatus() == .available else { return [] }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let records: [CKRecord] = try recordings.map { recording in
            let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: recording.id.uuidString))
            record["json"] = String(decoding: try encoder.encode(recording), as: UTF8.self)
            record["kind"] = recording.kind
            record["label"] = recording.label
            record["writer"] = recording.writer
            record["version"] = Int64(recording.version)
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
