import Foundation
import Testing
@testable import SquawkKit

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// Sunday 2026-11-01 22:00 UTC.
private let sundayNight = utc.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 22))!

@Suite struct TimeTests {
    @Test func wrapsAroundMidnight() {
        #expect(TimeOfDay(hour: 0, minute: 5).adding(minutes: -10) == TimeOfDay(hour: 23, minute: 55))
        #expect(TimeOfDay(hour: 23, minute: 55).adding(minutes: 10) == TimeOfDay(hour: 0, minute: 5))
    }

    @Test func formats() {
        #expect(TimeOfDay(hour: 7, minute: 5).full == "7:05 AM")
        #expect(TimeOfDay(hour: 0, minute: 0).full == "12:00 AM")
        #expect(TimeOfDay(hour: 13, minute: 30).full == "1:30 PM")
    }

    @Test func weekdayFromDate() {
        #expect(Weekday(of: sundayNight, calendar: utc) == .sunday)
        #expect(Weekday.monday.calendarWeekday == 2)
        #expect(Weekday.sunday.calendarWeekday == 1)
    }
}

@Suite struct ScheduleLineTests {
    @Test func namedGroups() {
        #expect(Alarm(days: Weekday.weekdays).scheduleLine(calendar: utc) == "Weekdays")
        #expect(Alarm(days: Set(Weekday.allCases)).scheduleLine(calendar: utc) == "Every day")
        #expect(Alarm(days: Weekday.weekend).scheduleLine(calendar: utc) == "Weekends")
        #expect(Alarm(days: [.monday, .wednesday, .friday]).scheduleLine(calendar: utc) == "Mon, Wed, Fri")
        #expect(Alarm(days: [.monday, .tuesday, .wednesday, .saturday]).scheduleLine(calendar: utc) == "Mon–Wed, Sat")
    }

    @Test func differentTimeOnSomeDays() {
        let alarm = Alarm(days: Weekday.weekdays, dayTimes: [.friday: TimeOfDay(hour: 7, minute: 30)])
        #expect(alarm.scheduleLine(calendar: utc) == "Mon–Thu 7:00 · Fri 7:30")
    }

    @Test func oneTime() {
        let alarm = Alarm(date: LocalDate(year: 2026, month: 11, day: 7))
        #expect(alarm.scheduleLine(calendar: utc) == "Sat, Nov 7")
    }
}

@Suite struct PlannerTests {
    @Test func oneWeeklyAlarmPerTimeGroupAndRing() {
        let alarm = Alarm(days: Weekday.weekdays, dayTimes: [.friday: TimeOfDay(hour: 7, minute: 30)],
                          rings: [Ring(), Ring(offsetMinutes: -10)])
        let plan = AlarmPlanner.plan(alarm, now: sundayNight, calendar: utc)
        #expect(plan.count == 4)
        #expect(plan.contains { $0.schedule == .weekly(TimeOfDay(hour: 6, minute: 50), [.monday, .tuesday, .wednesday, .thursday]) })
        #expect(plan.contains { $0.schedule == .weekly(TimeOfDay(hour: 7, minute: 30), [.friday]) })
        #expect(plan.filter(\.isLastRing).count == 2)
    }

    @Test func ringBeforeMidnightMovesToThePreviousDay() {
        let alarm = Alarm(time: TimeOfDay(hour: 0, minute: 5), days: [.monday], rings: [Ring(offsetMinutes: -10)])
        let plan = AlarmPlanner.plan(alarm, now: sundayNight, calendar: utc)
        #expect(plan.first?.schedule == .weekly(TimeOfDay(hour: 23, minute: 55), [.sunday]))
    }

    @Test func oneTimeSkipsRingsInThePast() {
        let alarm = Alarm(time: TimeOfDay(hour: 22, minute: 5), date: LocalDate(year: 2026, month: 11, day: 1),
                          rings: [Ring(offsetMinutes: -10), Ring()])
        let plan = AlarmPlanner.plan(alarm, now: sundayNight, calendar: utc)
        #expect(plan.count == 1)
    }

    @Test func offAlarmsAreNotPlanned() {
        #expect(AlarmPlanner.plan([Alarm(isOn: false)], now: sundayNight, calendar: utc).isEmpty)
    }

    @Test func idsAreStable() {
        let alarm = Alarm()
        let a = AlarmPlanner.plan(alarm, now: sundayNight, calendar: utc).map(\.id)
        let b = AlarmPlanner.plan(alarm, now: sundayNight, calendar: utc).map(\.id)
        #expect(a == b)
        #expect(Set(a).count == a.count)
    }

    @Test func nextRingAndSleep() {
        let alarm = Alarm(days: Weekday.weekdays, dayTimes: [.monday: TimeOfDay(hour: 6, minute: 30)])
        let next = alarm.nextRing(after: sundayNight, calendar: utc)
        #expect(next == utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 6, minute: 30)))
    }
}

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private let monday = LocalDate(year: 2026, month: 11, day: 2)

private func onceDates(_ plan: [PlannedRing]) -> [Date] {
    plan.compactMap { ring -> Date? in
        guard case .once(let date) = ring.schedule else { return nil }
        return date
    }.sorted()
}

@Suite struct MorningTests {
    @Test func skippingNextMondayKeepsTheMondaysAfter() {
        var alarm = Alarm(days: Weekday.weekdays)
        #expect(alarm.upcomingMorning(after: sundayNight, calendar: utc) == monday)
        alarm.setChange(.skip, on: monday)
        let plan = AlarmPlanner.plan(alarm, now: sundayNight, calendar: utc)
        #expect(plan.contains { $0.schedule == .weekly(.sevenAM, [.tuesday, .wednesday, .thursday, .friday]) })
        #expect(onceDates(plan) == [at(9, 7), at(16, 7), at(23, 7), at(30, 7)])
        #expect(alarm.nextRing(after: sundayNight, calendar: utc) == at(3, 7))
        // Still the upcoming morning, so it can be un-skipped.
        #expect(alarm.upcomingMorning(after: sundayNight, calendar: utc) == monday)
    }

    @Test func changingNextMorningOnly() {
        var alarm = Alarm(days: Weekday.weekdays, rings: [Ring(), Ring(offsetMinutes: -10)])
        alarm.setChange(.time(TimeOfDay(hour: 8, minute: 30)), on: monday)
        let dates = onceDates(AlarmPlanner.plan(alarm, now: sundayNight, calendar: utc))
        #expect(Array(dates.prefix(3)) == [at(2, 8, 20), at(2, 8, 30), at(9, 6, 50)])
        #expect(dates.count == 10)
        #expect(alarm.nextRing(after: sundayNight, calendar: utc) == at(2, 8, 20))
    }

    @Test func imUpCancelsTheRestOfThisMorning() {
        var alarm = Alarm(days: Weekday.weekdays, rings: [Ring(), Ring(offsetMinutes: 5)])
        // Before the first ring, nothing is cancelled.
        let tooEarly = alarm.markUp(at: at(2, 6, 55), calendar: utc)
        #expect(!tooEarly)
        let up = alarm.markUp(at: at(2, 7, 2), calendar: utc)
        #expect(up)
        #expect(alarm.change(on: monday) == .done)
        let plan = AlarmPlanner.plan(alarm, now: at(2, 7, 2), calendar: utc)
        #expect(!onceDates(plan).contains(at(2, 7, 5)))
        #expect(onceDates(plan).first == at(9, 7))
        #expect(alarm.nextRing(after: at(2, 7, 2), calendar: utc) == at(3, 7))
        // Once the morning is over, Monday goes back to repeating weekly.
        let later = AlarmPlanner.plan(alarm, now: at(2, 8), calendar: utc)
        #expect(onceDates(later).isEmpty)
        #expect(later.contains { $0.schedule == .weekly(.sevenAM, Array(Weekday.weekdays).sorted()) })
    }

    @Test func imUpOnAOneTimeAlarm() {
        var alarm = Alarm(date: monday, rings: [Ring(), Ring(offsetMinutes: 5)])
        alarm.markUp(at: at(2, 7, 1), calendar: utc)
        #expect(AlarmPlanner.plan(alarm, now: at(2, 7, 1), calendar: utc).isEmpty)
        #expect(alarm.upcomingMorning(after: sundayNight, calendar: utc) == nil)
    }

    @Test func oldChangesAreDropped() {
        var alarm = Alarm()
        alarm.setChange(.skip, on: LocalDate(year: 2026, month: 10, day: 20))
        alarm.setChange(.skip, on: monday)
        alarm.dropOldChanges(now: sundayNight, calendar: utc)
        #expect(alarm.changes == [MorningChange(date: monday, kind: .skip)])
    }

    @Test func extraRings() {
        var alarm = Alarm()
        alarm.addSoftRing()
        alarm.addLoudRing()
        alarm.addSoftRing()
        #expect(alarm.sortedRings.map(\.offsetMinutes) == [-20, -10, 0, 5])
        #expect(alarm.sortedRings[0].offsetText == "20 min before")
        #expect(alarm.sortedRings[3].summary(wake: .sevenAM) == "7:05 · Rush")
        #expect(Ring(offsetMinutes: 65).offsetText == "1 h 5 min after")
    }

    @Test func localDates() {
        #expect(monday.adding(days: 6, calendar: utc) == LocalDate(year: 2026, month: 11, day: 8))
        #expect(monday.adding(days: -2, calendar: utc) == LocalDate(year: 2026, month: 10, day: 31))
        #expect(monday.weekday(calendar: utc) == .monday)
        #expect(monday.description == "2026-11-02")
    }
}

@Suite struct CheckTests {
    private func tagAlarm(rings: [Ring] = [Ring(offsetMinutes: -10), Ring()]) -> Alarm {
        Alarm(days: Weekday.weekdays, rings: rings, checks: [WakeUpCheck(kind: .tag, secret: "04A1B2", place: "Bathroom")])
    }

    @Test func lastRingComesBackEvery30SecondsWithBackups() {
        let plan = AlarmPlanner.plan(tagAlarm(), now: sundayNight, calendar: utc)
        // Five mornings ahead: Mon to Fri. Each: one early ring, the first 2 minutes of
        // repeats (5), then a backup every 2 minutes (7:04, 7:06, 7:08).
        #expect(plan.count == 5 * 9)
        #expect(plan.allSatisfy { $0.needsCheck })
        let monday = onceDates(plan).filter { $0 < at(3, 0) }
        #expect(monday == [
            at(2, 6, 50), at(2, 7), at(2, 7).addingTimeInterval(30), at(2, 7, 1),
            at(2, 7, 1).addingTimeInterval(30), at(2, 7, 2), at(2, 7, 4), at(2, 7, 6), at(2, 7, 8),
        ])
    }

    @Test func snoozeTopsUpTheRepeats() {
        // Snoozed at 7:01:10: the next 2 minutes of repeats, then the backups.
        let alarm = tagAlarm()
        let now = at(2, 7, 1).addingTimeInterval(10)
        let monday = onceDates(AlarmPlanner.plan(alarm, now: now, calendar: utc)).filter { $0 < at(3, 0) }
        #expect(monday == [
            at(2, 7, 1).addingTimeInterval(30), at(2, 7, 2), at(2, 7, 2).addingTimeInterval(30),
            at(2, 7, 3), at(2, 7, 4), at(2, 7, 6), at(2, 7, 8),
        ])
        // Re-planning keeps the same ids, so rings already scheduled stay as they are.
        let before = Set(AlarmPlanner.plan(alarm, now: sundayNight, calendar: utc).map(\.id))
        let after = AlarmPlanner.plan(alarm, now: now, calendar: utc).filter { $0.nextFire(after: now, calendar: utc)! < at(2, 7, 2) }
        #expect(!after.isEmpty)
        #expect(after.allSatisfy { before.contains($0.id) })
    }

    @Test func nextFire() {
        let weekly = PlannedRing(
            id: UUID(), alarmID: UUID(), ringID: UUID(),
            schedule: .weekly(TimeOfDay(hour: 7, minute: 0), [.wednesday, .tuesday]),
            title: "", sound: AlarmSound.all[0], color: RingColor.allCases[0], isLastRing: true
        )
        #expect(weekly.nextFire(after: sundayNight, calendar: utc) == at(3, 7))
        let once = PlannedRing(
            id: UUID(), alarmID: UUID(), ringID: UUID(), schedule: .once(at(2, 7)),
            title: "", sound: AlarmSound.all[0], color: RingColor.allCases[0], isLastRing: true
        )
        #expect(once.nextFire(after: sundayNight, calendar: utc) == at(2, 7))
        #expect(once.nextFire(after: at(2, 8), calendar: utc) == nil)
    }

    @Test func doingTheCheckCancelsTheRepeats() {
        var alarm = tagAlarm()
        let now = at(2, 7, 3)
        #expect(alarm.morningInProgress(at: now, calendar: utc) == monday)
        #expect(alarm.checkDeadline(at: now, calendar: utc) == at(2, 7, 10))
        alarm.markUp(at: now, calendar: utc)
        let dates = onceDates(AlarmPlanner.plan(alarm, now: now, calendar: utc))
        #expect(dates.first == at(3, 6, 50))
    }

    @Test func remindsTheEveningBeforeTheLastPlannedMorning() {
        // Planned Mon to Fri; Friday's first ring is 6:50, so the reminder is Thursday 20:00.
        let alarm = tagAlarm()
        #expect(AlarmPlanner.runOutReminder([alarm], now: sundayNight, calendar: utc) == at(5, 20))
        // Opening the app on Tuesday plans Wed to next Tue, which moves it out.
        #expect(AlarmPlanner.runOutReminder([alarm], now: at(3, 9), calendar: utc) == at(9, 20))
        // Off alarms don't count.
        var off = alarm
        off.isOn = false
        #expect(AlarmPlanner.runOutReminder([off], now: sundayNight, calendar: utc) == nil)
    }

    @Test func reminderSkipsASkippedLastMorning() {
        var alarm = tagAlarm()
        alarm.setChange(.skip, on: LocalDate(year: 2026, month: 11, day: 6))
        // Friday is skipped, so Thursday is the last morning that rings.
        #expect(AlarmPlanner.runOutReminder([alarm], now: sundayNight, calendar: utc) == at(4, 20))
    }

    @Test func noReminderForAlarmsThatDontRunOut() {
        let weekly = Alarm(days: Weekday.weekdays)
        let once = Alarm(time: .sevenAM, date: LocalDate(year: 2026, month: 11, day: 20), checks: [WakeUpCheck(kind: .game)])
        #expect(AlarmPlanner.runOutReminder([weekly, once], now: sundayNight, calendar: utc) == nil)
    }

    @Test func reminderForAChangedWeekdayAfterItsOneOffWeeks() {
        // Skipping Monday rings Mondays as one-off alarms through Nov 30.
        var alarm = Alarm(days: Weekday.weekdays)
        alarm.setChange(.skip, on: monday)
        #expect(AlarmPlanner.runOutReminder([alarm], now: sundayNight, calendar: utc) == at(29, 20))
        // The earliest alarm to run out wins.
        #expect(AlarmPlanner.runOutReminder([alarm, tagAlarm()], now: sundayNight, calendar: utc) == at(5, 20))
    }

    @Test func stillInProgressWhileTheLastRingRepeats() {
        let alarm = tagAlarm(rings: [Ring()])
        #expect(alarm.morningInProgress(at: at(2, 7, 9), calendar: utc) == monday)
        #expect(alarm.morningInProgress(at: at(2, 7, 11), calendar: utc) == nil)
        // Repeats still to come this morning are kept.
        let dates = onceDates(AlarmPlanner.plan(alarm, now: at(2, 7, 5), calendar: utc))
        #expect(dates.first == at(2, 7, 5).addingTimeInterval(30))
    }

    @Test func shortcutTurnsOffOnlyWhatItMay() {
        let ringing = at(2, 7, 3)
        let plain = Alarm(days: Weekday.weekdays, rings: [Ring(offsetMinutes: -5), Ring()])
        #expect(plain.shortcutTurnOff(at: at(2, 6, 0), calendar: utc) == .notRinging)
        #expect(plain.shortcutTurnOff(at: at(2, 6, 56), calendar: utc) == .up(monday))
        // Its last ring keeps going until it's stopped, so the action can still silence it.
        #expect(plain.shortcutTurnOff(at: at(2, 7, 3), calendar: utc) == .lastRing)
        #expect(plain.shortcutTurnOff(at: at(2, 7, 11), calendar: utc) == .notRinging)
        // It never skips another check.
        #expect(tagAlarm().shortcutTurnOff(at: ringing, calendar: utc) == .needsOtherCheck)
        let shortcutOnly = Alarm(days: Weekday.weekdays, checks: [WakeUpCheck(kind: .shortcut)])
        #expect(shortcutOnly.shortcutTurnOff(at: ringing, calendar: utc) == .up(monday))
        var both = tagAlarm()
        both.checks.append(WakeUpCheck(kind: .shortcut))
        #expect(both.shortcutTurnOff(at: ringing, calendar: utc) == .shortcutDone(monday))
        // Once the morning is done, there's nothing left to turn off.
        var done = shortcutOnly
        done.markUp(at: ringing, calendar: utc)
        #expect(done.shortcutTurnOff(at: ringing, calendar: utc) == .notRinging)
    }

    @Test func matching() {
        let check = WakeUpCheck(kind: .code, secret: "1234567890128")
        #expect(check.matches("1234567890128\n"))
        #expect(!check.matches("999"))
        #expect(!WakeUpCheck(kind: .game).matches(""))
    }
}

@Suite struct MorningsLogTests {
    private let threeRings = Alarm(days: Weekday.weekdays, rings: [Ring(offsetMinutes: -10), Ring(), Ring(offsetMinutes: 5)])

    @Test func outcomeDependsOnWhichRingYouGotUpOn() {
        #expect(threeRings.record(upAt: at(2, 6, 52), calendar: utc)?.outcome == .firstRing)
        let middle = threeRings.record(upAt: at(2, 7, 1), calendar: utc)
        #expect(middle?.outcome == .fine)
        #expect(middle?.ringNumber == 2)
        #expect(middle?.ringCount == 3)
        // The last ring has gone off, but the morning is already over for a plain alarm.
        #expect(threeRings.record(upAt: at(2, 7, 5), calendar: utc) == nil)
        #expect(threeRings.record(upAt: at(2, 6, 0), calendar: utc) == nil)
    }

    @Test func lastRingWithACheck() {
        var alarm = threeRings
        alarm.checks = [WakeUpCheck(kind: .game)]
        let record = alarm.record(upAt: at(2, 7, 8), calendar: utc)
        #expect(record?.outcome == .lastRing)
        #expect(record?.ringNumber == 3)
    }

    @Test func faintsWhenTheCheckRunsOut() {
        var alarm = threeRings
        alarm.checks = [WakeUpCheck(kind: .game)]
        #expect(alarm.faintedMornings(before: at(2, 7, 10), calendar: utc).isEmpty)
        let fainted = alarm.faintedMornings(before: at(2, 7, 16), calendar: utc)
        #expect(fainted.map(\.date) == [monday])
        #expect(fainted.first?.outcome == .fainted)
        alarm.setChange(.done, on: monday)
        #expect(alarm.faintedMornings(before: at(2, 7, 16), calendar: utc).isEmpty)
    }

    private func record(_ day: Int, _ outcome: MorningRecord.Outcome, alarm: UUID = UUID()) -> MorningRecord {
        MorningRecord(alarmID: alarm, date: LocalDate(year: 2026, month: 11, day: day), outcome: outcome,
                      upAt: nil, ringNumber: 1, ringCount: 1)
    }

    @Test func streakCountsFirstRingMorningsInARow() {
        var log = MorningsLog()
        for (day, outcome) in [(2, .lastRing), (3, .firstRing), (4, .firstRing), (6, .firstRing)] as [(Int, MorningRecord.Outcome)] {
            log.add(record(day, outcome), calendar: utc)
        }
        #expect(log.streak == 3)
        // A harder second alarm on the same morning breaks it.
        log.add(record(6, .fine), calendar: utc)
        #expect(log.streak == 0)
    }

    @Test func sameAlarmAndMorningReplaces() {
        let id = UUID()
        var log = MorningsLog()
        log.add(record(2, .lastRing, alarm: id), calendar: utc)
        log.add(record(2, .firstRing, alarm: id), calendar: utc)
        #expect(log.records.count == 1)
        #expect(log.streak == 1)
    }

    @Test func weekAndUnseen() {
        var log = MorningsLog()
        log.add(record(1, .fine), calendar: utc)      // Sunday of the week before
        log.add(record(2, .firstRing), calendar: utc) // Monday
        log.add(record(4, .lastRing), calendar: utc)  // Wednesday
        let week = log.week(of: at(5, 9), calendar: utc)
        #expect(week == [.monday: .firstRing, .wednesday: .lastRing])
        let unseen = log.unseen(now: at(5, 9), calendar: utc)
        #expect(unseen?.date == LocalDate(year: 2026, month: 11, day: 4))
        log.markSeen(unseen!.id)
        #expect(log.unseen(now: at(5, 9), calendar: utc) == nil)
    }

    @Test func storeRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mornings-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileMorningsStore(url: url)
        #expect(try store.load().records.isEmpty)
        var log = MorningsLog()
        log.add(record(2, .firstRing), calendar: utc)
        try store.save(log)
        #expect(try store.load() == log)
    }
}

@Suite struct ProTests {
    @Test func freeAlarmsStopAtTwoRings() {
        let one = Alarm()
        let two = Alarm(rings: [Ring(), Ring(offsetMinutes: -10)])
        #expect(ProAccess.free.canAddRing(to: one))
        #expect(!ProAccess.free.canAddRing(to: two))
        #expect(ProAccess.pro.canAddRing(to: two))
    }

    @Test func proFeaturesNeedPro() {
        for feature in ProFeature.allCases {
            #expect(ProAccess.pro.allows(feature))
            #expect(ProAccess.free.allows(feature) == ProFeature.free.contains(feature))
        }
    }

    @Test func quickAddRingSoundsAreFree() {
        #expect(ProAccess.free.allows(sound: .standard))
        #expect(ProAccess.free.allows(sound: .soft))
        #expect(ProAccess.free.allows(sound: .loud))
        #expect(!ProAccess.free.allows(sound: AlarmSound.with(id: "sound_garden")))
        #expect(ProAccess.pro.allows(sound: AlarmSound.with(id: "sound_garden")))
    }

    @Test func outfitsAreEarnedWithAStreakOrPro() {
        #expect(!ProAccess.free.allows(.scarf, bestStreak: 2))
        #expect(ProAccess.free.allows(.scarf, bestStreak: 3))
        #expect(!ProAccess.free.allows(.sunglasses, bestStreak: 13))
        #expect(!ProAccess.free.allows(.partyHat, bestStreak: 100))
        #expect(ProAccess.pro.allows(.partyHat, bestStreak: 0))
    }

    @Test func newlyEarnedOnlyTheFirstTime() {
        #expect(Outfit.newlyEarned(streak: 3, bestStreak: 3) == .scarf)
        #expect(Outfit.newlyEarned(streak: 7, bestStreak: 7) == .beanie)
        #expect(Outfit.newlyEarned(streak: 3, bestStreak: 9) == nil)
        #expect(Outfit.newlyEarned(streak: 4, bestStreak: 4) == nil)
    }

    private func firstRing(_ day: Int) -> MorningRecord {
        MorningRecord(alarmID: UUID(), date: LocalDate(year: 2026, month: 11, day: day), outcome: .firstRing,
                      upAt: nil, ringNumber: 1, ringCount: 1)
    }

    @Test func bestStreakSurvivesABadMorning() throws {
        var log = MorningsLog()
        for day in 2...5 { log.add(firstRing(day), calendar: utc) }
        #expect(log.bestStreak == 4)
        log.add(MorningRecord(alarmID: UUID(), date: LocalDate(year: 2026, month: 11, day: 6), outcome: .lastRing,
                              upAt: nil, ringNumber: 2, ringCount: 2), calendar: utc)
        #expect(log.streak == 0)
        #expect(log.bestStreak == 4)
        let data = try JSONEncoder().encode(log)
        #expect(try JSONDecoder().decode(MorningsLog.self, from: data).bestStreak == 4)
    }

    @Test func olderLogsWithoutBestStreakLoad() throws {
        let json = #"{"records":[]}"#
        #expect(try JSONDecoder().decode(MorningsLog.self, from: Data(json.utf8)).bestStreak == 0)
    }

    @Test func memoryStoreTellsListeners() async {
        let store = MemoryProStore()
        #expect(await store.isPro() == false)
        var changes = store.changes().makeAsyncIterator()
        store.set(isPro: true)
        let change: Void? = await changes.next()
        #expect(change != nil)
        #expect(await store.isPro())
    }
}

@Suite struct WidgetSnapshotTests {
    @Test func nextWakeUpsCountChanges() {
        // Sunday night: weekday alarm at 7:00, Monday skipped, Tuesday moved to 6:30.
        var weekdays = Alarm(days: Weekday.weekdays, rings: [Ring(), Ring(offsetMinutes: -10)], label: "Work")
        weekdays.setChange(.skip, on: monday)
        weekdays.setChange(.time(TimeOfDay(hour: 6, minute: 30)), on: monday.adding(days: 1, calendar: utc))
        let off = Alarm(time: TimeOfDay(hour: 5, minute: 0), isOn: false)
        let once = Alarm(time: TimeOfDay(hour: 9, minute: 0), date: monday)
        let snapshot = WidgetSnapshot(alarms: [weekdays, off, once], streak: 4, now: sundayNight, calendar: utc)
        #expect(snapshot.streak == 4)
        #expect(snapshot.wakeUps.first?.at == at(2, 9))
        #expect(snapshot.wakeUps.first?.title == "Wake up")
        let second = snapshot.wakeUps[1]
        #expect(second.at == at(3, 6, 30))
        #expect(second.title == "Work")
        #expect(second.ringCount == 2)
        #expect(snapshot.wakeUps.count <= WidgetSnapshot.limit)
        #expect(!snapshot.wakeUps.contains { utc.component(.hour, from: $0.at) == 5 })
    }

    @Test func nextSkipsPastWakeUps() {
        let snapshot = WidgetSnapshot(alarms: [Alarm(days: Set(Weekday.allCases))], streak: 0, now: sundayNight, calendar: utc)
        #expect(snapshot.next(after: sundayNight)?.at == at(2, 7))
        #expect(snapshot.next(after: at(2, 7, 1))?.at == at(3, 7))
    }

    @Test func storeSavesOnlyChanges() {
        let store = WidgetSnapshotStore(suiteName: "squawk-tests-\(UUID())")
        let snapshot = WidgetSnapshot(wakeUps: [.init(at: sundayNight, title: "Wake up", ringCount: 1)], streak: 2)
        #expect(store.load() == WidgetSnapshot())
        #expect(store.save(snapshot))
        #expect(!store.save(snapshot))
        #expect(store.load() == snapshot)
    }
}

@Suite struct StoreTests {
    @Test func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alarms-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileAlarmStore(url: url)
        #expect(try store.load().isEmpty)
        let alarms = [
            Alarm(dayTimes: [.friday: TimeOfDay(hour: 7, minute: 30)], label: "Work"),
            Alarm(date: LocalDate(year: 2026, month: 11, day: 7), label: "Hike day"),
            Alarm(changes: [MorningChange(date: monday, kind: .skip),
                            MorningChange(date: monday.adding(days: 1, calendar: utc), kind: .time(.sevenAM))]),
            Alarm(checks: [WakeUpCheck(kind: .tag, secret: "04A1", place: "Kitchen"), WakeUpCheck(kind: .game),
                           WakeUpCheck(kind: .shortcut)]),
        ]
        try store.save(alarms)
        #expect(try store.load() == alarms)
    }

    @Test func loadsOlderFilesWithMissingFields() throws {
        let json = #"{"version":1,"alarms":[{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","time":{"hour":6,"minute":45}}]}"#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("old-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(json.utf8).write(to: url)
        let alarm = try #require(try FileAlarmStore(url: url).load().first)
        #expect(alarm.rings.count == 1)
        #expect(alarm.isOn)
    }
}

@Suite struct StepsTests {
    private let lamp = HomeTarget(id: UUID(), name: "Bedroom lamp", room: "Bedroom")

    @Test func newAlarmHasOneWakeUpStep() {
        let steps = Alarm().steps
        #expect(steps.count == 1)
        #expect(steps[0].isWakeUp)
        #expect(steps[0].rings.count == 1)
    }

    @Test func groupsRingsAndHomeThingsByTime() {
        var alarm = Alarm()
        alarm.addSoftRing()
        alarm.homeActions.append(HomeAction(offsetMinutes: -10, kind: .light, targets: [lamp]))
        alarm.homeActions.append(HomeAction(offsetMinutes: -30, kind: .light, targets: [lamp]))
        #expect(alarm.steps.map(\.offsetMinutes) == [-30, -10, 0])
        let soft = alarm.steps[1]
        #expect(soft.rings.count == 1)
        #expect(soft.actions.count == 1)
    }

    @Test func wakeUpStepIsAlwaysThere() {
        var alarm = Alarm(rings: [Ring(offsetMinutes: -5)])
        alarm.homeActions = []
        #expect(alarm.steps.map(\.offsetMinutes) == [-5, 0])
        #expect(alarm.step(at: 0)?.rings.isEmpty == true)
        #expect(alarm.step(at: 20) == nil)
    }

    @Test func movingAStepMovesEverythingInIt() {
        var alarm = Alarm()
        alarm.addSoftRing()
        alarm.homeActions.append(HomeAction(offsetMinutes: -10, kind: .light, targets: [lamp]))
        alarm.moveStep(from: -10, to: -20)
        #expect(alarm.steps.map(\.offsetMinutes) == [-20, 0])
        #expect(alarm.steps[0].rings.count == 1 && alarm.steps[0].actions.count == 1)
    }

    @Test func wakeUpStepDoesntMoveOrGo() {
        var alarm = Alarm()
        alarm.moveStep(from: 0, to: 10)
        alarm.removeStep(at: 0)
        #expect(alarm.steps.map(\.offsetMinutes) == [0])
        #expect(alarm.rings.count == 1)
    }

    @Test func removingAStepRemovesEverythingInIt() {
        var alarm = Alarm()
        alarm.addLoudRing()
        alarm.homeActions.append(HomeAction(offsetMinutes: 5, kind: .plug, targets: [lamp]))
        alarm.removeStep(at: 5)
        #expect(alarm.steps.map(\.offsetMinutes) == [0])
        #expect(alarm.homeActions.isEmpty)
    }

    @Test func sunriseAddsOneStepThatEndsAtWakeUp() {
        var alarm = Alarm()
        alarm.addSunrise(lights: [lamp])
        #expect(alarm.steps.map(\.offsetMinutes) == [-30, 0])
        #expect(alarm.homeActions.map(\.kind) == [.sunrise])
        #expect(alarm.homeActions[0].sunrise == .standard)
        alarm.addSunrise(lights: [lamp], sunrise: Sunrise(minutes: 45))
        #expect(alarm.homeActions.count == 1)
        #expect(alarm.homeActions[0].offsetMinutes == -45)
        #expect(alarm.homeActions[0].detail == "45 min · 5% → 100%")
    }

    @Test func sunrisePoints() {
        let points = Sunrise.standard.points
        #expect(points.map(\.minutes) == [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30])
        #expect(points.first?.setting == HomeSetting(isOn: true, brightness: 5, warmth: 0))
        #expect(points.last?.setting == HomeSetting(isOn: true, brightness: 100, warmth: 70))
        // Eases in: the first half brightens much less than the second.
        #expect(points[5].setting.brightness! < 40)
        let brightness = points.compactMap(\.setting.brightness)
        #expect(brightness == brightness.sorted())
    }

    @Test func shortSunriseChangesEveryMinute() {
        #expect(Sunrise(minutes: 5).points.map(\.minutes) == [0, 1, 2, 3, 4, 5])
        #expect(Sunrise(minutes: 60).points.count == Sunrise.maxChanges + 1)
    }

    @Test func sunriseCanGetDimmerAndWarmer() {
        let sunset = Sunrise(minutes: 10, startBrightness: 80, endBrightness: 10, startWarmth: 60, endWarmth: 0)
        #expect(sunset.points.last?.setting == HomeSetting(isOn: true, brightness: 10, warmth: 0))
    }

    @Test func homeStepsSpreadTheSunrise() {
        var alarm = Alarm()
        alarm.addSunrise(lights: [lamp], sunrise: Sunrise(minutes: 10))
        alarm.homeActions.append(HomeAction(offsetMinutes: -5, kind: .plug, targets: [lamp]))
        let steps = alarm.homeSteps
        #expect(steps.map(\.offsetMinutes) == Array(-10...0))
        #expect(steps.first { $0.offsetMinutes == -5 }?.actions.map(\.kind) == [.light, .plug])
        #expect(steps.allSatisfy { $0.actions.allSatisfy { $0.kind != .sunrise } })
        // Same ids every time, so planning stays stable.
        #expect(alarm.homeSteps.flatMap(\.actions).map(\.id) == steps.flatMap(\.actions).map(\.id))
    }

    @Test func movingTheStepMovesTheSunrise() {
        var alarm = Alarm()
        alarm.addSunrise(lights: [lamp])
        alarm.moveStep(from: -30, to: -40)
        #expect(alarm.homeSteps.first?.offsetMinutes == -40)
        #expect(alarm.homeSteps.last?.offsetMinutes == -10)
    }

    @Test func oldLightActionsLoadWithoutSunrise() throws {
        let action = HomeAction(kind: .light, targets: [lamp], setting: HomeSetting(brightness: 50))
        let json = String(decoding: try JSONEncoder().encode(action), as: UTF8.self)
        #expect(!json.contains("sunrise"))
        let back = try JSONDecoder().decode(HomeAction.self, from: Data(json.utf8))
        #expect(back.sunrise == nil && back == action)
    }

    @Test func summaries() {
        let light = HomeAction(kind: .light, targets: [lamp], setting: HomeSetting(brightness: 50, warmth: 10))
        #expect(light.summary == "Bedroom lamp · 50% · warm")
        let two = HomeAction(kind: .light, targets: [lamp, HomeTarget(id: UUID(), name: "Ceiling")])
        #expect(two.name == "Bedroom lamp + 1")
        let blinds = HomeAction(kind: .blinds, targets: [lamp], setting: HomeSetting(position: 50))
        #expect(blinds.detail == "50% open")
    }

    @Test func oldAlarmsLoadWithNoHomeThings() throws {
        let json = #"{"id":"6A1E9A7C-1D32-4C55-9C52-3B7B5E1C1A10","time":{"hour":7,"minute":0},"rings":[]}"#
        let alarm = try JSONDecoder().decode(Alarm.self, from: Data(json.utf8))
        #expect(alarm.homeActions.isEmpty && alarm.upActions.isEmpty)
        #expect(alarm.steps.count == 1)
    }

    @Test func homeThingsSaveAndLoad() throws {
        var alarm = Alarm()
        alarm.addSunrise(lights: [lamp])
        alarm.upActions = [HomeAction(kind: .blinds, targets: [lamp], setting: HomeSetting(position: 100))]
        let back = try JSONDecoder().decode(Alarm.self, from: JSONEncoder().encode(alarm))
        #expect(back == alarm)
    }
}

@Suite struct GuideTests {
    private let lamp = HomeTarget(id: UUID(), name: "Bedroom lamp")

    @Test func defaultsMakeABasicAlarm() {
        let alarm = NewAlarmGuide().alarm
        #expect(alarm.rings.count == 1)
        #expect(alarm.checks.isEmpty && !alarm.usesHome)
        #expect(NewAlarmGuide().proFeatures.isEmpty)
    }

    @Test func wakeChoices() {
        #expect(NewAlarmGuide(wake: .gentle).alarm.sortedRings.map(\.offsetMinutes) == [-10, 0])
        #expect(NewAlarmGuide(wake: .nudge).alarm.sortedRings.map(\.offsetMinutes) == [0, 5])
    }

    @Test func lightsAndUpActions() {
        let up = HomeAction(kind: .plug, targets: [lamp])
        let guide = NewAlarmGuide(lights: .sunrise, lightTargets: [lamp], check: WakeUpCheck(kind: .game), upActions: [up])
        let alarm = guide.alarm
        #expect(alarm.steps.map(\.offsetMinutes) == [-30, 0])
        #expect(alarm.homeActions.map(\.kind) == [.sunrise])
        #expect(alarm.upActions == [up])
        #expect(alarm.checks.map(\.kind) == [.game])
        #expect(guide.proFeatures == [.home, .checks])
        let free = guide.freeAlarm
        #expect(!free.usesHome && free.checks.isEmpty)
    }

    @Test func lightsWithoutALampDoNothing() {
        let guide = NewAlarmGuide(lights: .atWakeUp, upActions: [HomeAction(kind: .plug, targets: [lamp])])
        #expect(!guide.alarm.usesHome)
        #expect(guide.proFeatures.isEmpty)
    }
}

@Suite struct HomePlannerTests {
    private let lamp = HomeTarget(id: UUID(), name: "Bedroom lamp")

    /// Lamp to 10% at 6:30, 50% at 6:50, 100% at 7:00.
    private func sunriseAlarm() -> Alarm {
        var alarm = Alarm(time: .sevenAM, days: Weekday.weekdays)
        for (offset, brightness) in [(-30, 10), (-10, 50), (0, 100)] {
            alarm.homeActions.append(HomeAction(
                offsetMinutes: offset, kind: .light, targets: [lamp],
                setting: HomeSetting(isOn: true, brightness: brightness)
            ))
        }
        alarm.homeActions.append(HomeAction(offsetMinutes: -20, kind: .plug, targets: [lamp]))
        return alarm
    }

    @Test func sunriseLightsPlanOneAutomationPerChange() {
        var alarm = Alarm(time: .sevenAM, days: Weekday.weekdays)
        alarm.addSunrise(lights: [lamp])
        let plan = HomePlanner.plan(alarm, now: sundayNight, calendar: utc)
        #expect(plan.count == 11)
        #expect(plan.first?.name == "Squawk · Wake up · 6:30")
        #expect(plan.last?.name == "Squawk · Wake up · 7:00")
        #expect(plan.last?.actions.first?.setting.brightness == 100)
        #expect(plan.allSatisfy { $0.actions.allSatisfy { $0.kind == .light } })
    }

    @Test func noHomeThingsNoAutomations() {
        #expect(HomePlanner.plan(Alarm(), now: sundayNight, calendar: utc).isEmpty)
    }

    @Test func weeklyAutomationPerStep() {
        let plan = HomePlanner.plan(sunriseAlarm(), now: sundayNight, calendar: utc)
        #expect(plan.count == 4)
        #expect(plan.map(\.name) == ["Squawk · Wake up · 6:30", "Squawk · Wake up · 6:40", "Squawk · Wake up · 6:50", "Squawk · Wake up · 7:00"])
        #expect(plan[0].schedule == .weekly(TimeOfDay(hour: 6, minute: 30), Weekday.weekdays.sorted()))
    }

    @Test func skippedMorningGoesOneOff() {
        var alarm = sunriseAlarm()
        alarm.setChange(.skip, on: LocalDate(year: 2026, month: 11, day: 2))
        let plan = HomePlanner.plan(alarm, now: sundayNight, calendar: utc)
        let once = plan.filter { if case .once = $0.schedule { true } else { false } }
        let weekly = plan.filter { if case .weekly = $0.schedule { true } else { false } }
        #expect(weekly.count == 4)
        #expect(weekly.allSatisfy { if case .weekly(_, let days) = $0.schedule { !days.contains(.monday) } else { false } })
        #expect(once.count == 4 * AlarmPlanner.weeksAhead)
        let firstMonday = utc.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 6, minute: 30))!
        #expect(once.contains { $0.schedule == .once(firstMonday) })
    }

    @Test func newTimeMovesEveryStep() {
        var alarm = sunriseAlarm()
        alarm.setChange(.time(TimeOfDay(hour: 6, minute: 0)), on: LocalDate(year: 2026, month: 11, day: 2))
        let plan = HomePlanner.plan(alarm, now: sundayNight, calendar: utc)
        let early = utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 5, minute: 30))!
        #expect(plan.contains { $0.schedule == .once(early) && $0.name == "Squawk · Wake up · 5:30" })
    }

    @Test func stepBeforeMidnightMovesToTheDayBefore() {
        var alarm = Alarm(time: TimeOfDay(hour: 0, minute: 10), days: [.monday])
        alarm.homeActions = [HomeAction(offsetMinutes: -30, kind: .light, targets: [lamp])]
        let plan = HomePlanner.plan(alarm, now: sundayNight.addingTimeInterval(-6 * 3600), calendar: utc)
        #expect(plan.count == 1)
        #expect(plan[0].schedule == .weekly(TimeOfDay(hour: 23, minute: 40), [.sunday]))
    }

    @Test func fingerprintChangesWithTheSetting() {
        var alarm = sunriseAlarm()
        let before = HomePlanner.plan(alarm, now: sundayNight, calendar: utc).map(\.fingerprint)
        #expect(before == HomePlanner.plan(alarm, now: sundayNight, calendar: utc).map(\.fingerprint))
        alarm.homeActions[0].setting.brightness = 20
        let after = HomePlanner.plan(alarm, now: sundayNight, calendar: utc).map(\.fingerprint)
        #expect(before[0] != after[0])
        #expect(before[1] == after[1])
    }

    @Test func offAlarmsPlanNothing() {
        var alarm = sunriseAlarm()
        alarm.isOn = false
        #expect(HomePlanner.plan([alarm], now: sundayNight, calendar: utc).isEmpty)
    }
}

@Suite struct MorningSummaryTests {
    /// Tuesday 2026-11-03 at `hour`:`minute` UTC.
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 3) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func firstEventIsTheNextOneThatHasntEnded() {
        let events = [
            AgendaEvent(title: "Lunch", start: at(12), end: at(13)),
            AgendaEvent(title: "Gym", start: at(6), end: at(7)),
            AgendaEvent(title: "Standup", start: at(9, 30), end: at(9, 45)),
            AgendaEvent(title: "Holiday", start: at(0), end: at(0, day: 4), isAllDay: true),
            AgendaEvent(title: "Tomorrow", start: at(9, day: 4), end: at(10, day: 4)),
        ]
        let agenda = Agenda(events: events, now: at(7, 15), calendar: utc)
        #expect(agenda == .next(events[2], started: false, more: 1))
    }

    @Test func anEventThatIsOnCountsAsStarted() {
        let event = AgendaEvent(title: "Flight", start: at(5), end: at(9))
        #expect(Agenda(events: [event], now: at(7), calendar: utc) == .next(event, started: true, more: 0))
    }

    @Test func noEventsLeftIsEmpty() {
        let events = [
            AgendaEvent(title: "Gym", start: at(6), end: at(7)),
            AgendaEvent(title: "Holiday", start: at(0), end: at(0, day: 4), isAllDay: true),
        ]
        #expect(Agenda(events: events, now: at(7, 30), calendar: utc) == .empty)
        #expect(Agenda(events: [], now: at(7), calendar: utc) == .empty)
    }

    @Test func rainComesBeforeWind() {
        let hours = [
            HourForecast(date: at(7), windKmh: 45),
            HourForecast(date: at(15), precipitationChance: 0.7, precipitation: .rain),
            HourForecast(date: at(16), precipitationChance: 0.9, precipitation: .snow),
        ]
        #expect(WeatherNote.pick(from: hours, now: at(7, 20), calendar: utc) == .rain(from: at(15)))
    }

    @Test func unlikelyRainAndPastHoursDontCount() {
        let hours = [
            HourForecast(date: at(5), precipitationChance: 0.9, precipitation: .rain),
            HourForecast(date: at(10), precipitationChance: 0.3, precipitation: .rain),
            HourForecast(date: at(12), windKmh: 50),
            HourForecast(date: at(9, day: 4), precipitationChance: 0.9, precipitation: .snow),
        ]
        #expect(WeatherNote.pick(from: hours, now: at(7, 20), calendar: utc) == .windy)
    }

    @Test func rainThisHourCountsAsNow() {
        let hours = [HourForecast(date: at(7), precipitationChance: 0.8, precipitation: .snow)]
        #expect(WeatherNote.pick(from: hours, now: at(7, 40), calendar: utc) == .snow(from: at(7)))
    }

    @Test func calmDayHasNoNote() {
        let hours = [HourForecast(date: at(8), precipitationChance: 0.1, precipitation: .rain, windKmh: 10)]
        #expect(WeatherNote.pick(from: hours, now: at(7), calendar: utc) == nil)
    }

    @Test func offerShowsAFewTimesUntilDismissedOrOn() {
        var settings = SummarySettings()
        #expect(settings.shouldOffer)
        settings.offersShown = SummarySettings.maxOffers
        #expect(!settings.shouldOffer)
        #expect(!SummarySettings(offerDismissed: true).shouldOffer)
        #expect(!SummarySettings(calendar: true).shouldOffer)
    }

    @Test func timeoutThrowsWhenSlow() async throws {
        let fast = try await withTimeout(seconds: 1) { 42 }
        #expect(fast == 42)
        await #expect(throws: TimedOut.self) {
            try await withTimeout(seconds: 0.05) {
                try await Task.sleep(for: .seconds(5))
                return 1
            }
        }
    }

    @MainActor @Test func fakeSourcesAskOnce() async {
        let weather = FakeWeatherSource(access: .notAsked)
        weather.answer = .denied
        #expect(await weather.requestAccess() == false)
        #expect(weather.access == .denied)
        let agenda = FakeAgendaSource(access: .notAsked)
        #expect(await agenda.requestAccess())
        #expect(agenda.access == .allowed)
    }
}
