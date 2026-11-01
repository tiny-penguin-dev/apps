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

    @Test func lastRingComesBackEvery30SecondsFor10Minutes() {
        let plan = AlarmPlanner.plan(tagAlarm(), now: sundayNight, calendar: utc)
        // Three mornings ahead: Mon, Tue, Wed. Each: one early ring plus 20 repeats.
        #expect(plan.count == 3 * 21)
        #expect(plan.allSatisfy { $0.needsCheck })
        let monday = onceDates(plan).filter { $0 < at(3, 0) }
        #expect(monday.first == at(2, 6, 50))
        #expect(monday[1] == at(2, 7))
        #expect(monday[2] == at(2, 7, 0).addingTimeInterval(30))
        #expect(monday.last == at(2, 7, 9).addingTimeInterval(30))
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

    @Test func stillInProgressWhileTheLastRingRepeats() {
        let alarm = tagAlarm(rings: [Ring()])
        #expect(alarm.morningInProgress(at: at(2, 7, 9), calendar: utc) == monday)
        #expect(alarm.morningInProgress(at: at(2, 7, 11), calendar: utc) == nil)
        // Repeats still to come this morning are kept.
        let dates = onceDates(AlarmPlanner.plan(alarm, now: at(2, 7, 5), calendar: utc))
        #expect(dates.first == at(2, 7, 5).addingTimeInterval(30))
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
            Alarm(checks: [WakeUpCheck(kind: .tag, secret: "04A1", place: "Kitchen"), WakeUpCheck(kind: .game)]),
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
