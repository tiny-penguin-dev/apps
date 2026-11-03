import Foundation
import UserNotifications

/// The one notification Squawk sends itself: "Open Squawk to keep your alarms", on the
/// evening before alarms that are only planned a few mornings ahead run out
/// (`AlarmPlanner.runOutReminder`). Every re-plan moves it further out, so it only
/// shows when nobody has opened Squawk or snoozed an alarm for days. Opening the app
/// from it re-plans, which plans the next few mornings.
@MainActor
final class RunOutReminder {
    static let shared = RunOutReminder()

    private let center = UNUserNotificationCenter.current()
    private let id = "squawk.run-out"

    private init() {}

    /// Shows the iOS "allow notifications" prompt if it hasn't been answered yet.
    func requestAccess() async {
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Telemetry.report(error)
        }
    }

    /// Replaces the pending reminder with one at `date`, or removes it when nil.
    func set(_ date: Date?) async {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let date else { return }
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }
        let content = UNMutableNotificationContent()
        content.title = "Open Squawk to keep your alarms"
        content.body = "Some of your alarms are only set through tomorrow. Open Squawk and I'll set up the next few mornings."
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        } catch {
            Telemetry.report(error)
        }
    }
}
