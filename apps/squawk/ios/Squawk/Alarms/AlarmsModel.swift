import Foundation
import Observation
import SquawkKit

/// The app's alarms. Every change is saved, then re-planned and handed to AlarmKit.
@MainActor
@Observable
final class AlarmsModel {
    private(set) var alarms: [Alarm] = []
    private(set) var access: AlarmAccess
    /// Shown as a banner when scheduling fails.
    var errorMessage: String?

    private let store: any AlarmStore
    private let scheduler: any RingScheduler

    init(store: any AlarmStore, scheduler: any RingScheduler) {
        self.store = store
        self.scheduler = scheduler
        self.access = scheduler.access
        do {
            alarms = try store.load()
        } catch {
            Telemetry.report(error)
        }
    }

    /// The real thing: alarms on disk, rung by AlarmKit.
    static func live() -> AlarmsModel {
        let store: any AlarmStore = (try? FileAlarmStore.standard()) ?? MemoryAlarmStore()
        return AlarmsModel(store: store, scheduler: AlarmKitScheduler.shared)
    }

    static func preview(_ alarms: [Alarm] = [
        Alarm(dayTimes: [.friday: TimeOfDay(hour: 7, minute: 30)]),
        Alarm(time: TimeOfDay(hour: 6, minute: 15), date: LocalDate(Date().addingTimeInterval(86_400 * 6)), label: "Hike day"),
    ]) -> AlarmsModel {
        AlarmsModel(store: MemoryAlarmStore(alarms), scheduler: PreviewScheduler())
    }

    // MARK: Changes

    func save(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
            Telemetry.count("alarm.created", ["kind": alarm.isOneTime ? "once" : "repeat"])
        }
        commit()
    }

    func delete(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }
        Telemetry.count("alarm.deleted")
        commit()
    }

    func setOn(_ isOn: Bool, for alarm: Alarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index].isOn = isOn
        commit()
    }

    // MARK: Access

    func requestAccess() async {
        _ = await scheduler.requestAccess()
        access = scheduler.access
        await reschedule()
    }

    /// Call when the app comes back to the front: access may have changed in Settings,
    /// and one-time alarms may have passed.
    func refresh() async {
        access = scheduler.access
        await reschedule()
    }

    // MARK: Ordering and sleep

    /// Alarms in the order Home shows them: on first, then by time.
    var sortedAlarms: [Alarm] {
        alarms.sorted { a, b in
            if a.isOn != b.isOn { return a.isOn }
            return a.time < b.time
        }
    }

    /// The next ring of any alarm.
    func nextRing(after now: Date = Date()) -> Date? {
        alarms.compactMap { $0.nextRing(after: now) }.min()
    }

    // MARK: Private

    private func commit() {
        do {
            try store.save(alarms)
        } catch {
            Telemetry.report(error)
            errorMessage = Self.failureMessage
        }
        Task { await reschedule() }
    }

    private func reschedule() async {
        let plan = AlarmPlanner.plan(alarms, now: Date())
        let failures = await scheduler.replaceAll(with: plan)
        if failures > 0 {
            Telemetry.count("alarm.schedule_failed", ["count": String(min(failures, 9))])
            errorMessage = Self.failureMessage
        }
        Telemetry.gauge("alarms.total", value: Double(alarms.count))
    }

    static let failureMessage = "I couldn't set this alarm. Try again, and if it keeps happening, restart your iPhone."
}
