import Foundation
import Observation
import SquawkKit

/// The app's alarms and mornings. Every change is saved, then re-planned and handed to
/// AlarmKit.
@MainActor
@Observable
final class AlarmsModel {
    private(set) var alarms: [Alarm] = []
    private(set) var access: AlarmAccess
    /// Shown as a banner when scheduling fails.
    var errorMessage: String?
    /// The alarm whose wake-up check is on screen.
    private(set) var activeCheckID: UUID?
    /// How past mornings went: Squawk's reactions and the streak.
    private(set) var log = MorningsLog()
    /// The morning the Good morning screen is showing.
    private(set) var goodMorning: MorningRecord?

    private let store: any AlarmStore
    private let morningsStore: any MorningsStore
    private let scheduler: any RingScheduler
    /// Lights, scenes and blinds. Nil in previews.
    private let home: (any HomeController)?
    /// "Open Squawk to keep your alarms" before a plan runs out. Nil in previews.
    private let runOut: RunOutReminder?

    init(
        store: any AlarmStore, morningsStore: any MorningsStore, scheduler: any RingScheduler,
        home: (any HomeController)? = nil, runOut: RunOutReminder? = nil
    ) {
        self.store = store
        self.morningsStore = morningsStore
        self.scheduler = scheduler
        self.home = home
        self.runOut = runOut
        self.access = scheduler.access
        do {
            alarms = try store.load()
            log = try morningsStore.load()
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
        let mornings: any MorningsStore = (try? FileMorningsStore.standard()) ?? MemoryMorningsStore()
        return AlarmsModel(store: store, morningsStore: mornings, scheduler: AlarmKitScheduler.shared,
                           home: HomeAccess.shared, runOut: .shared)
    }

    static func preview(_ alarms: [Alarm] = [
        Alarm(dayTimes: [.friday: TimeOfDay(hour: 7, minute: 30)]),
        Alarm(time: TimeOfDay(hour: 6, minute: 15), date: LocalDate(Date().addingTimeInterval(86_400 * 6)), label: "Hike day"),
    ]) -> AlarmsModel {
        AlarmsModel(store: MemoryAlarmStore(alarms), morningsStore: MemoryMorningsStore(), scheduler: PreviewScheduler())
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
        // A repeating alarm with a check is only planned a few mornings ahead, so ask
        // to send the reminder that keeps it going, then plan it in.
        if alarm.hasChecks, !alarm.isOneTime, let runOut {
            Task {
                await runOut.requestAccess()
                await reschedule()
            }
        }
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
        let now = Date()
        guard let index = alarms.firstIndex(where: { $0.id.uuidString == alarmID }) else { return }
        // Logged now, shown on Good morning the next time the app opens.
        logUp(index, at: now, show: false)
        guard alarms[index].markUp(at: now) else { return }
        Telemetry.count("morning.up", ["from": "button"])
        save()
        await home?.runUp(alarms[index].upActions)
        await reschedule()
    }

    /// Stop on the ringing screen, which is labeled Snooze when the alarm has a wake-up
    /// check. Only the next couple of minutes of repeats are scheduled ahead, so a
    /// Snooze re-plans to schedule the next ones.
    func ringStopped(alarmID: String) async {
        guard alarms.contains(where: { $0.id.uuidString == alarmID && $0.hasChecks }) else { return }
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
        let now = Date()
        logUp(index, at: now, show: true)
        alarms[index].markUp(at: now)
        Telemetry.count("check.finished", ["how": how])
        save()
        await home?.runUp(alarms[index].upActions)
        await reschedule()
    }

    // MARK: Mornings

    /// Closes Good morning; its morning won't show again.
    func closeGoodMorning() {
        guard let goodMorning else { return }
        log.markSeen(goodMorning.id)
        self.goodMorning = nil
        saveLog()
    }

    /// Records how the morning in progress went, before it's marked done.
    private func logUp(_ index: Int, at now: Date, show: Bool) {
        guard let record = alarms[index].record(upAt: now) else { return }
        log.add(record)
        Telemetry.count("morning.result", ["outcome": record.outcome.rawValue])
        if show { goodMorning = record }
        saveLog()
    }

    private func saveLog() {
        do {
            try morningsStore.save(log)
        } catch {
            Telemetry.report(error)
        }
        WidgetBridge.publish(alarms: alarms, streak: log.streak)
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
        var upActions: [HomeAction] = []
        // A check screen left open after its morning ran out closes.
        if goodMorning == nil, let alarm = activeCheckAlarm, alarm.morningInProgress(at: now) == nil {
            activeCheckID = nil
        }
        for index in alarms.indices {
            if alarms[index].hasChecks {
                // Its morning ends when the check is done, not when the app opens.
                if activeCheckID == nil, alarms[index].morningInProgress(at: now) != nil {
                    activeCheckID = alarms[index].id
                }
            } else if alarms[index].morningInProgress(at: now) != nil {
                logUp(index, at: now, show: true)
                if alarms[index].markUp(at: now) {
                    anyUp = true
                    upActions += alarms[index].upActions
                }
            }
            // Mornings whose wake-up check rang out: Squawk faints.
            for record in alarms[index].faintedMornings(before: now)
            where !log.contains(alarmID: record.alarmID, date: record.date) {
                log.add(record)
                Telemetry.count("morning.result", ["outcome": record.outcome.rawValue])
                saveLog()
            }
        }
        if anyUp {
            Telemetry.count("morning.up", ["from": "app"])
            save()
            await home?.runUp(upActions)
        }
        // A morning ended from the ringing screen, or one that rang out, shows now.
        if goodMorning == nil, activeCheckID == nil {
            goodMorning = log.unseen(now: now)
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

    /// One re-plan at a time: changes that come in while one runs are planned right
    /// after it, so two never hand AlarmKit the same alarms at once.
    private func reschedule() async {
        if rescheduling { rescheduleAgain = true; return }
        rescheduling = true
        defer { rescheduling = false }
        repeat {
            rescheduleAgain = false
            await rescheduleOnce()
        } while rescheduleAgain
    }

    @ObservationIgnored private var rescheduling = false
    @ObservationIgnored private var rescheduleAgain = false

    private func rescheduleOnce() async {
        let plan = AlarmPlanner.plan(alarms, now: Date())
        let failures = await scheduler.replaceAll(with: plan)
        if failures > 0 {
            Telemetry.count("alarm.schedule_failed", ["count": String(min(failures, 9))])
            errorMessage = Self.failureMessage
        }
        Telemetry.gauge("alarms.total", value: Double(alarms.count))
        WidgetBridge.publish(alarms: alarms, streak: log.streak)
        await runOut?.set(AlarmPlanner.runOutReminder(alarms, now: Date()))
        await home?.sync(HomePlanner.plan(alarms, now: Date()))
    }

    static let failureMessage = "I couldn't set this alarm. Try again, and if it keeps happening, restart your iPhone."
}
