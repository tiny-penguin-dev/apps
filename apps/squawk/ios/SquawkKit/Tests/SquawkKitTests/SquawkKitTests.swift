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

@Suite struct StoreTests {
    @Test func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alarms-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileAlarmStore(url: url)
        #expect(try store.load().isEmpty)
        let alarms = [
            Alarm(dayTimes: [.friday: TimeOfDay(hour: 7, minute: 30)], label: "Work"),
            Alarm(date: LocalDate(year: 2026, month: 11, day: 7), label: "Hike day"),
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
