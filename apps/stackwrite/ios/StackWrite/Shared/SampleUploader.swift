import CloudKit
import Foundation
import Observation
import StackWriteKit

/// Sends saved samples to the public CloudKit database, where
/// `ml/download_samples.py` picks them up for training. Each sample is a
/// `Sample` record named after the sample's ID, holding its JSON.
@MainActor @Observable
final class SampleUploader {
    static let containerID = "iCloud.com.tinypenguin.stackwrite"
    private static let enabledKey = "uploadSamples"
    private static let batchSize = 100

    var isEnabled: Bool = UserDefaults.standard.bool(forKey: enabledKey) {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { upload() }
        }
    }

    private(set) var isUploading = false
    /// The last result or problem, for the home screen.
    private(set) var status: String?

    private let store: SampleStore
    // Created on first use, so the app never touches CloudKit unless uploads are on.
    @ObservationIgnored private lazy var database = CKContainer(identifier: Self.containerID).publicCloudDatabase

    init(store: SampleStore) {
        self.store = store
    }

    /// Uploads everything pending, in the background. Safe to call often.
    func upload() {
        guard isEnabled, !isUploading, store.pendingCount > 0 else { return }
        isUploading = true
        Task {
            await uploadPending()
            isUploading = false
        }
    }

    /// Takes a deleted sample back out of the database too.
    func remove(_ id: UUID) {
        guard isEnabled else { return }
        Task {
            _ = try? await database.deleteRecord(withID: CKRecord.ID(recordName: id.uuidString))
        }
    }

    private func uploadPending() async {
        do {
            let account = try await CKContainer(identifier: Self.containerID).accountStatus()
            guard account == .available else {
                status = "Sign in to iCloud in Settings to upload."
                return
            }
            var total = 0
            while true {
                let batch = store.pending(limit: Self.batchSize)
                if batch.isEmpty { break }
                let records = batch.compactMap(Self.record)
                let (saved, _) = try await database.modifyRecords(
                    saving: records, deleting: [], savePolicy: .allKeys, atomically: false
                )
                let done = saved.compactMap { id, result -> UUID? in
                    guard case .success = result else { return nil }
                    return UUID(uuidString: id.recordName)
                }
                store.markUploaded(done)
                total += done.count
                if done.count < batch.count {
                    let errors = saved.values.compactMap { result -> Error? in
                        if case .failure(let error) = result { return error }
                        return nil
                    }
                    status = "Upload stopped: \(errors.first?.localizedDescription ?? "a sample couldn't be read")"
                    return
                }
            }
            status = total > 0 ? "Uploaded \(total) words." : status
        } catch {
            status = "Upload failed: \(error.localizedDescription)"
        }
    }

    private static func record(_ item: (id: UUID, data: Data)) -> CKRecord? {
        guard let sample = try? StrokeSample.decoder.decode(StrokeSample.self, from: item.data) else { return nil }
        let record = CKRecord(recordType: "Sample", recordID: CKRecord.ID(recordName: item.id.uuidString))
        record["json"] = String(decoding: item.data, as: UTF8.self)
        record["label"] = sample.label
        record["labelSource"] = sample.labelSource.rawValue
        record["writer"] = sample.writer
        record["version"] = Int64(sample.version)
        return record
    }
}
