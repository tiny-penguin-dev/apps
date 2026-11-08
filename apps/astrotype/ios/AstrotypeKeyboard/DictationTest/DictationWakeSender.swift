import CloudKit
import Foundation
import UserNotifications

// THROWAWAY SPIKE (Gabriel, 8 Nov 2026), see DictationProbeIntent.swift. Round 3, the
// keyboard's side of waking the app without opening it (the app's side is
// Astrotype/DictationTest/DictationWake.swift).

enum DictationWakeSender {
    /// Posts a notification whose "Start dictation" button runs in the app, in the
    /// background.
    static func notify() async {
        let content = UNMutableNotificationContent()
        content.title = "Start dictation?"
        content.body = "Hold or pull down, then tap Start dictation."
        content.categoryIdentifier = DictationProbeLog.notificationCategory
        let request = UNNotificationRequest(identifier: "dictationProbe", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            DictationProbeLog.write("Keyboard Notify: posted the notification at \(Date().formatted(date: .omitted, time: .standard)).")
        } catch {
            DictationProbeLog.write("Keyboard Notify: couldn't post (\(error.localizedDescription)).")
        }
    }

    /// Saves the wake record, so CloudKit sends the app a silent push.
    static func nudgeCloud() async {
        let database = CKContainer(identifier: "iCloud.com.tinypenguin.astrotype").privateCloudDatabase
        let id = CKRecord.ID(recordName: DictationProbeLog.wakeRecordName)
        let record = CKRecord(recordType: "KeyboardData", recordID: id)
        record["changed"] = Date()
        let sent = Date()
        do {
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: true)
            let took = Date().timeIntervalSince(sent)
            DictationProbeLog.write(String(format: "Keyboard Cloud: saved the nudge in %.1f s at %@. Waiting for the app…", took,
                                           Date().formatted(date: .omitted, time: .standard)))
        } catch {
            DictationProbeLog.write("Keyboard Cloud: couldn't save (\(error.localizedDescription)).")
        }
    }
}
