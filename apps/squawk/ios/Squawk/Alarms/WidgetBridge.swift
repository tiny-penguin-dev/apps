import Foundation
import SquawkKit
import WidgetKit

/// Hands the next wake-ups to the widget (through the App Group) and reloads it when
/// they changed.
enum WidgetBridge {
    static func publish(alarms: [Alarm], streak: Int, now: Date = Date()) {
        let snapshot = WidgetSnapshot(alarms: alarms, streak: streak, now: now)
        if WidgetSnapshotStore.shared.save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
