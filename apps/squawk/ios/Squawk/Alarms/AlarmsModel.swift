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
    /// The alarm whose wake-up check is on screen.
    private(set) var activeCheckID: UUID?

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

    /// The app's one model. Shared with the "I'm up" button, which can run while the
    /// app is in the background.
    static let shared = AlarmsModel.live()

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

    // MARK: One morning only

    /// Skips the next morning (the one "Skip tomorrow" names).
    func skipNext(_ alarm: Alarm) {
        changeNext(alarm, to: .skip)
    }

    /// Rings at a different time on the next morning only.
    func changeNext(_ alarm: Alarm, time: TimeOfDay) {
        changeNext(alarm, to: .time(time))
    }

    /// Puts the next morning back to normal.
    func undoNext(_ alarm: Alarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }),
              let day = alarms[index].upcomingMorning(after: Date()) else { return }
        alarms[index].setChange(nil, on: day)
        commit()
    }

    private func changeNext(_ alarm: Alarm, to kind: MorningChange.Kind) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }),
              let day = alarms[index].upcomingMorning(after: Date()) else { return }
        alarms[index].setChange(kind, on: day)
        if case .time = kind {
            Telemetry.count("morning.changed", ["kind": "time"])
        } else {
            Telemetry.count("morning.changed", ["kind": "skip"])
        }
        commit()
    }

    /// "I'm up" on the ringing screen: cancels the rest of that alarm's rings this morning.
    func imUp(alarmID: String) async {
        guard let index = alarms.firstIndex(where: { $0.id.uuidString == alarmID }),
              alarms[index].markUp(at: Date()) else { return }
        Telemetry.count("morning.up", ["from": "button"])
        save()
        await reschedule()
    }

    // MARK: Wake-up checks

    var activeCheckAlarm: Alarm? {
        alarms.first { $0.id == activeCheckID }
    }

    /// The checks are done (or the math way out was used): the morning is over.
    /// `how` is "checks" or "math", for the `check.finished` metric.
    func finishChecks(how: String) async {
        guard let index = alarms.firstIndex(where: { $0.id == activeCheckID }) else { return }
        alarms[index].markUp(at: Date())
        Telemetry.count("check.finished", ["how": how])
        save()
        await reschedule()
    }

    /// Closes the check screen (after Good morning, or when the morning ran out).
    func closeCheck() {
        activeCheckID = nil
    }

    // MARK: Access

    func requestAccess() async {
        _ = await scheduler.requestAccess()
        access = scheduler.access
        await reschedule()
    }

    /// Call when the app comes back to the front: access may have changed in Settings,
    /// and one-time alarms may have passed.
    /// Opening the app during a morning counts as being up, so the rest of that
    /// morning's rings are cancelled (PRODUCT.md 5.3).
    func refresh() async {
        access = scheduler.access
        let now = Date()
        var anyUp = false
        for index in alarms.indices {
            if alarms[index].hasChecks {
                // Its morning ends when the check is done, not when the app opens.
                if activeCheckID == nil, alarms[index].morningInProgress(at: now) != nil {
                    activeCheckID = alarms[index].id
                }
            } else if alarms[index].markUp(at: now) {
                anyUp = true
            }
        }
        if anyUp {
            Telemetry.count("morning.up", ["from": "app"])
            save()
        }
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
        save()
        Task { await reschedule() }
    }

    private func save() {
        let now = Date()
        for index in alarms.indices {
            alarms[index].dropOldChanges(now: now)
        }
        do {
            try store.save(alarms)
        } catch {
            Telemetry.report(error)
            errorMessage = Self.failureMessage
        }
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
