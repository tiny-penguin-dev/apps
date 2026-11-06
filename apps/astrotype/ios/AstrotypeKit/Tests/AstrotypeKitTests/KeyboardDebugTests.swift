import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct KeyboardDebugTests {
    private let t0 = Date(timeIntervalSince1970: 1_793_491_200)

    private func reading(_ footprint: Double, _ headroom: Double = 30) -> MemoryReading {
        MemoryReading(footprintMB: footprint, headroomMB: headroom)
    }

    @Test func overlayIsOneShortLine() {
        #expect(reading(23.44, 31.9).overlay(peakMB: 25.12) == "23.4/40 MB · peak 25.1 · 31 left")
        // The peak is never below now, and no headroom (not iOS) leaves it out.
        #expect(reading(26, 0).overlay(peakMB: 20) == "26.0/40 MB · peak 26.0")
    }

    @Test func breakdownSplitsHeapFromTheRest() {
        #expect(MemoryReading.breakdown(footprintMB: 30, heapMB: 12.34, layers: 412) == "heap 12.3 · other 17.7 · 412 layers")
        #expect(MemoryReading.breakdown(footprintMB: 10, heapMB: 12, layers: 3) == "heap 12.0 · other 0.0 · 3 layers")
        #expect(MemoryReading.breakdown(footprintMB: 10, heapMB: nil, layers: 3) == "3 layers")
        #expect(MemoryReading.breakdown(footprintMB: 30, heapMB: 10, layers: 9, views: 4, metal: true)
                == "heap 10.0 · other 20.0 · 9 layers · 4 views · metal")
    }

    @Test func limitAndBudget() {
        #expect(reading(20, 30).limitMB == 50)
        #expect(reading(20, 0).limitMB == nil)
        #expect(reading(30).budgetFraction == 0.75)
    }

    @Test func sessionKeepsPeaksAndWritesOnlyWhenWorthIt() {
        var debug = KeyboardDebug()
        debug.loaded(at: t0)
        debug.shown(at: t0, reading: reading(20, 40))
        #expect(debug.shows == 1)
        #expect(debug.showing)
        // Under half a MB and under five seconds: not written, but the peak counts.
        #expect(debug.sample(reading(20.3, 39.7), at: t0.addingTimeInterval(1)) == false)
        #expect(debug.peakMB == 20.3)
        #expect(debug.last == reading(20, 40))
        #expect(debug.sample(reading(21, 39), at: t0.addingTimeInterval(2)) == true)
        #expect(debug.sample(reading(21, 39), at: t0.addingTimeInterval(8)) == true) // stale
        debug.memoryWarning(at: t0.addingTimeInterval(9), reading: reading(19, 41))
        #expect(debug.memoryWarnings == 1)
        #expect(debug.peakMB == 21)
        #expect(debug.lowestHeadroomMB == 39)
        debug.hidden(at: t0.addingTimeInterval(10), reading: reading(18, 42))
        #expect(!debug.showing)

        // The next time it shows starts a new session; the process peak stays.
        debug.shown(at: t0.addingTimeInterval(60), reading: reading(17, 43))
        #expect(debug.shows == 2)
        #expect(debug.peakMB == 17)
        #expect(debug.memoryWarnings == 0)
        #expect(debug.processPeakMB == 21)
    }

    @Test func countsAProcessEndedWhileShowing() {
        var debug = KeyboardDebug()
        #expect(debug.loaded(at: t0) == false)
        debug.shown(at: t0, reading: reading(35))
        // iOS ended it while showing: the next process start finds it still showing.
        let later = t0.addingTimeInterval(30)
        #expect(debug.loaded(at: later) == true)
        #expect(debug.endedWhileShowing == 1)
        #expect(debug.lastEndedWhileShowing == later)
        #expect(debug.shows == 0)
        #expect(debug.processPeakMB == 0)
        // A normal hide and restart counts nothing.
        debug.shown(at: later, reading: reading(20))
        debug.hidden(at: later, reading: nil)
        #expect(debug.loaded(at: later.addingTimeInterval(60)) == false)
        #expect(debug.endedWhileShowing == 1)
    }

    @Test func splitsCrashesFromKills() {
        var debug = KeyboardDebug()
        debug.loaded(at: t0)
        for crashed in [true, false, nil] as [Bool?] {
            debug.shown(at: t0, reading: reading(30))
            debug.loaded(at: t0.addingTimeInterval(10), crashed: crashed)
        }
        #expect(debug.endedWhileShowing == 3)
        #expect(debug.crashedWhileShowing == 1)
        #expect(debug.killedWhileShowing == 1)
        // Not showing: a crash flag counts nothing.
        debug.loaded(at: t0.addingTimeInterval(20), crashed: true)
        #expect(debug.crashedWhileShowing == 1)
    }

    @Test func savesAndReadsOlderFiles() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("keyboard-debug.json")
        let store = FileKeyboardDebugStore(url: url)
        var debug = KeyboardDebug()
        debug.loaded(at: t0)
        debug.shown(at: t0, reading: reading(22, 30))
        store.save(debug)
        #expect(store.load() == debug)

        let old = try JSONDecoder().decode(KeyboardDebug.self, from: Data(#"{"shows": 3}"#.utf8))
        #expect(old.shows == 3)
        #expect(old.endedWhileShowing == 0)
        #expect(old.last == nil)
    }

    @Test func statsSettingDefaultsOffAndRoundTrips() throws {
        #expect(KeyboardSettings().showsStats == false)
        var settings = KeyboardSettings()
        settings.showsStats = true
        let read = try JSONDecoder().decode(KeyboardSettings.self, from: JSONEncoder().encode(settings))
        #expect(read.showsStats)
    }
}
