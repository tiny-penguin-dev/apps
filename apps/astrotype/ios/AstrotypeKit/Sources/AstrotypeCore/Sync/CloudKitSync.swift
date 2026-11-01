#if canImport(CloudKit)
import CloudKit
import Foundation

/// The snapshot in iCloud: one `KeyboardData` record in the private database of the
/// app's container (`cloudkit/schema.ckdb`), shared by all of the account's devices.
/// Saves go with `ifServerRecordUnchanged`, so a write over a copy this process has
/// not fetched comes back as `CloudSyncError.conflict` with the server's copy, and the
/// caller merges again. Used by the keyboard with Full Access and by the app.
public actor CloudKitSync: CloudSync {
    public static let containerID = "iCloud.com.tinypenguin.astrotype"
    public static let recordType = "KeyboardData"
    public static let recordName = "keyboard"

    private let container: CKContainer
    private var lastRecord: CKRecord?

    public init(containerID: String = CloudKitSync.containerID) {
        container = CKContainer(identifier: containerID)
    }

    private var database: CKDatabase { container.privateCloudDatabase }
    private var recordID: CKRecord.ID { CKRecord.ID(recordName: Self.recordName) }

    public func fetch() async throws -> SyncSnapshot? {
        try await checkAccount()
        do {
            let record = try await database.record(for: recordID)
            lastRecord = record
            return Self.snapshot(in: record)
        } catch let error as CKError where error.code == .unknownItem {
            lastRecord = nil
            return nil
        }
    }

    public func save(_ snapshot: SyncSnapshot) async throws {
        try await checkAccount()
        let record = lastRecord ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        let data = try JSONEncoder().encode(snapshot)
        record["json"] = String(decoding: data, as: UTF8.self)
        record["changed"] = Date()
        do {
            let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
            for (_, result) in saved {
                switch result {
                case .success(let stored):
                    lastRecord = stored
                case .failure(let error):
                    try raise(error)
                }
            }
        } catch let error as CKError {
            try raise(error)
        }
    }

    /// A server-side conflict becomes `.conflict` with the server's copy; anything else
    /// is thrown as it came.
    private func raise(_ error: Error) throws {
        guard let ck = error as? CKError else { throw error }
        if ck.code == .serverRecordChanged, let server = ck.serverRecord {
            lastRecord = server
            throw CloudSyncError.conflict(Self.snapshot(in: server))
        }
        if ck.code == .partialFailure,
           let inner = ck.partialErrorsByItemID?[recordID] as? CKError,
           inner.code == .serverRecordChanged, let server = inner.serverRecord {
            lastRecord = server
            throw CloudSyncError.conflict(Self.snapshot(in: server))
        }
        throw error
    }

    private func checkAccount() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw CloudSyncError.unavailable("I couldn't sync your words. Check that iCloud is on for Astrotype in Settings.")
        }
    }

    private static func snapshot(in record: CKRecord) -> SyncSnapshot? {
        guard let json = record["json"] as? String else { return nil }
        return try? JSONDecoder().decode(SyncSnapshot.self, from: Data(json.utf8))
    }
}
#endif
