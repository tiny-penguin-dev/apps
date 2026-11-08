@preconcurrency import ActivityKit
import CloudKit
import UIKit
@preconcurrency import UserNotifications

// THROWAWAY SPIKE (Gabriel, 8 Nov 2026), see DictationProbeIntent.swift. Round 3: ways to
// wake the app in the background so it can start the dictation session without opening:
//
// 1. Push to start: the Live Activity's push-to-start token goes to the Debug page (Copy),
//    the "Astrotype dictation push" GitHub Action sends a push that starts the Live
//    Activity, iOS wakes the app, and it tries the mic with that activity.
// 2. Notification button: the keyboard posts a local notification; its "Start" button
//    runs here in the background (no .foreground option) and tries a whole start.
// 3. CloudKit nudge: the keyboard saves the "dictation-wake" record; a query subscription
//    sends the app a silent push and it tries a whole start.
//
// Each writes where it got to in "Last result".

@MainActor
final class DictationWakeDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: DictationProbeLog.startAction, title: "Start dictation", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: DictationProbeLog.notificationCategory, actions: [start], intentIdentifiers: []),
        ])
        application.registerForRemoteNotifications()
        DictationWake.watchActivities()
        Task { await DictationWake.subscribeToCloud() }
        return true
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DictationProbeLog.write("Push: couldn't register (\(error.localizedDescription)).")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let note = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
              note.subscriptionID == DictationProbeLog.cloudSubscriptionID,
              note.recordID?.recordName == DictationProbeLog.wakeRecordName
        else { return .noData }
        await DictationSession.shared.wake(source: "CloudKit nudge")
        // Keep the app up a moment longer with the mic going, in case it started.
        try? await Task.sleep(for: .seconds(2))
        return .newData
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == DictationProbeLog.notificationCategory else { return }
        let how = response.actionIdentifier == DictationProbeLog.startAction ? "Notification's Start button" : "Notification tapped"
        await DictationSession.shared.wake(source: how)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@MainActor
enum DictationWake {
    private static var watching = false

    /// Keeps the push-to-start token in the App Group, and takes any Live Activity a
    /// push started as the session's.
    static func watchActivities() {
        guard !watching else { return }
        watching = true
        Task {
            for await data in Activity<DictationActivityAttributes>.pushToStartTokenUpdates {
                DictationProbeLog.pushToken = data.map { String(format: "%02x", $0) }.joined()
            }
        }
        Task {
            for await activity in Activity<DictationActivityAttributes>.activityUpdates {
                await DictationSession.shared.adopt(activity)
            }
        }
    }

    /// The silent push for the keyboard's CloudKit nudge. Saved once per install.
    static func subscribeToCloud() async {
        let doneKey = "dictationProbe.cloudSubscribed"
        guard DictationProbeLog.defaults?.bool(forKey: doneKey) != true else { return }
        let subscription = CKQuerySubscription(
            recordType: "KeyboardData",
            predicate: NSPredicate(value: true),
            subscriptionID: DictationProbeLog.cloudSubscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await CKContainer(identifier: "iCloud.com.tinypenguin.astrotype").privateCloudDatabase.save(subscription)
            DictationProbeLog.defaults?.set(true, forKey: doneKey)
        } catch {
            DictationProbeLog.write("CloudKit nudge: couldn't subscribe (\(error.localizedDescription)).")
        }
    }
}
