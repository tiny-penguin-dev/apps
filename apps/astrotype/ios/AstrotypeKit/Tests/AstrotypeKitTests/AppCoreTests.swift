import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct AppStateTests {
    @Test func roundTripsAndReadsOlderJSON() throws {
        var state = AppState()
        state.firstLaunch = Date(timeIntervalSince1970: 1_700_000_000)
        state.onboardingDone = true
        state.practiceDays = ["2026-11-01"]
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
        // A version with fewer keys still reads, with defaults for the rest.
        let older = Data(#"{"version":1,"onboardingDone":true}"#.utf8)
        let read = try JSONDecoder().decode(AppState.self, from: older)
        #expect(read.onboardingDone)
        #expect(read.firstLaunch == nil)
        #expect(read.practiceDays.isEmpty)
    }

    @Test func practiceDaysAreKeptOncePerDay() {
        var state = AppState()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_793_491_200) // 2026-11-01 00:00 UTC
        state.recordPractice(at: day, calendar: calendar)
        state.recordPractice(at: day.addingTimeInterval(3600), calendar: calendar)
        state.recordPractice(at: day.addingTimeInterval(86_400), calendar: calendar)
        #expect(state.practiceDays == ["2026-11-01", "2026-11-02"])
    }

    @Test func storesRoundTrip() {
        var state = AppState()
        state.keyboardOnSeen = true
        let memory = MemoryAppStateStore()
        #expect(memory.load() == nil)
        memory.save(state)
        #expect(memory.load() == state)
        let defaults = UserDefaults(suiteName: "AstrotypeKitTests.appState")!
        defaults.removePersistentDomain(forName: "AstrotypeKitTests.appState")
        let store = UserDefaultsAppStateStore(defaults: defaults, key: "test")
        #expect(store.load() == nil)
        store.save(state)
        #expect(store.load() == state)
        defaults.removePersistentDomain(forName: "AstrotypeKitTests.appState")
    }
}

@Suite struct TrialTests {
    @Test func countsFourteenDaysDown() {
        let start = Date(timeIntervalSince1970: 1_793_491_200)
        let trial = Trial(start: start)
        #expect(trial.daysLeft(now: start) == 14)
        #expect(trial.daysLeft(now: start.addingTimeInterval(3 * 86_400 + 60)) == 11)
        #expect(trial.daysLeft(now: start.addingTimeInterval(13.5 * 86_400)) == 1)
        #expect(trial.daysLeft(now: start.addingTimeInterval(14 * 86_400)) == 0)
        #expect(!trial.isOver(now: start.addingTimeInterval(13 * 86_400)))
        #expect(trial.isOver(now: start.addingTimeInterval(14 * 86_400)))
        #expect(trial.daysLeft(now: start.addingTimeInterval(30 * 86_400)) == 0)
    }
}

@Suite struct KeyboardStatusTests {
    @Test func findsTheKeyboardInApplesList() {
        #expect(!KeyboardStatus.isOn(keyboards: []))
        #expect(!KeyboardStatus.isOn(keyboards: ["en_US@sw=QWERTY;hw=Automatic", "emoji@sw=Emoji"]))
        #expect(KeyboardStatus.isOn(keyboards: ["en_US@sw=QWERTY;hw=Automatic", "com.tinypenguin.astrotype.keyboard"]))
        #expect(KeyboardStatus.isOn(keyboards: ["com.tinypenguin.astrotype.keyboard@sw=Astrotype"]))
        #expect(!KeyboardStatus.isOn(keyboards: ["com.tinypenguin.astrotype.keyboardx"]))
        let fake = FakeKeyboardStatus()
        #expect(!fake.isKeyboardOn())
        fake.isOn = true
        #expect(fake.isKeyboardOn())
    }
}

@Suite struct TryWordsTests {
    @Test func fiveWordsWhoseStrokesSpellThem() {
        #expect(TryWord.all.count == 5)
        let layout = Layout.qwerty(width: 390)
        for word in TryWord.all {
            #expect(word.strokes.map(\.letters).joined() == word.word)
            #expect(Synth.lexicon.contains(word.word))
            // A tap sits on its thumb's half. A swipe may cross the middle (t and g sit
            // at it), so most of its letters must be on its side.
            for stroke in word.strokes {
                let onSide = stroke.letters.filter { layout.side(of: .letter($0)) == stroke.side }.count
                if stroke.isTap {
                    #expect(onSide == 1, "\(word.word): \(stroke.letters) is not on the \(stroke.side) half")
                } else {
                    #expect(onSide * 2 > stroke.letters.count, "\(word.word): \(stroke.letters) is mostly off the \(stroke.side) half")
                }
            }
        }
    }

    @Test func theFirstWordIsSomethingAsTheDesignSays() {
        let something = TryWord.all[0]
        #expect(something.hintText == "Left thumb taps s and e. Right thumb swipes o→m, then t→h→i→n→g. Space when it says something.")
        #expect(something.hint.first?.role == .left)
        #expect(TryWord.all[2].hintText == "Left thumb swipes g→r→e→a→t. Space when it says great.")
        #expect(TryWord.all[1].hintText == "Left thumb taps w and t. Right thumb taps i and h. Space when it says with.")
        #expect(TryWord.all[3].hintText == "Right thumb swipes m→o, then n→i→n→g. Left thumb taps r. Space when it says morning.")
    }

    @Test func theWordsTypeOnTheEngine() {
        for word in TryWord.all {
            var composer = Synth.composer()
            var time: TimeInterval = 0
            var id = 1
            for stroke in word.strokes {
                if stroke.isTap {
                    Synth.tap(&composer, stroke.letters.first!, id: id, at: time)
                    time += 0.2
                } else {
                    Synth.swipe(&composer, stroke.letters, id: id, at: time)
                    time += 0.5
                }
                id += 1
            }
            #expect(composer.state.openWord == word.word, "\(word.word) came out as \(String(describing: composer.state.openWord))")
        }
    }
}

@Suite struct WeekTests {
    @Test func runsMondayToSundayAroundNow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2026-11-01 is a Sunday.
        let sunday = Date(timeIntervalSince1970: 1_793_491_200 + 12 * 3600)
        let week = Week(practiceDays: ["2026-10-26", "2026-10-29", "2026-11-01", "2026-10-20"], now: sunday, calendar: calendar)
        #expect(week.days.map(\.letter) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(week.days.first?.key == "2026-10-26")
        #expect(week.days.last?.key == "2026-11-01")
        #expect(week.days.map(\.practised) == [true, false, false, true, false, false, true])
        #expect(week.days.last?.isToday == true)
        #expect(week.practisedCount == 3)
        let wednesday = Date(timeIntervalSince1970: 1_793_491_200 + 3 * 86_400)
        #expect(Week(practiceDays: [], now: wednesday, calendar: calendar).days.first?.key == "2026-11-02")
    }
}
