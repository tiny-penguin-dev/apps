import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct MemorySampleTests {
    private func sample(_ mb: Double, models: Int = 1) -> MemorySample {
        MemorySample(reading: MemoryReading(footprintMB: mb, headroomMB: 120), heapMB: mb - 10, layers: 130,
                     counts: LiveCount.Counts(keyboards: 1, models: models, loads: 1, syncs: 1))
    }

    @Test func logsEveryTenSecondsOnJumpsAndOnCountChanges() {
        var pacer = MemoryLogPacer()
        #expect(pacer.reason(for: sample(30), at: 0) == "tick")
        #expect(pacer.reason(for: sample(31), at: 1) == nil)
        #expect(pacer.reason(for: sample(32), at: 9.5) == nil)
        #expect(pacer.reason(for: sample(32), at: 10) == "tick")
        #expect(pacer.reason(for: sample(37.5), at: 11) == "jump")
        #expect(pacer.reason(for: sample(37.5, models: 2), at: 12) == "count")
        #expect(pacer.reason(for: sample(37.5, models: 2), at: 13) == nil)
        pacer.logged(sample(37.5, models: 2), at: 20)
        #expect(pacer.reason(for: sample(38, models: 2), at: 25) == nil)
    }

    @Test func roundsAndReadsAsOneLine() {
        let s = MemorySample(reading: MemoryReading(footprintMB: 52.14, headroomMB: 125.3), heapMB: 40.16, layers: 130,
                             metal: true, counts: LiveCount.Counts(keyboards: 1, models: 2, loads: 2, syncs: 3, waiting: 1))
        #expect(s.mb == 52.1)
        #expect(s.heap == 40.2)
        #expect(s.line == "52.1 MB · heap 40.2 · 125 left · 130 layers · metal · 1 keyboard · 2 models · 2 loads · 3 syncs, 1 waiting")
    }

    @Test func splitsOtherMemoryLeavingOutEmptyParts() throws {
        let s = MemorySample(reading: MemoryReading(footprintMB: 86, headroomMB: 90), heapMB: 26, layers: 130,
                             counts: LiveCount.Counts(keyboards: 1, models: 1, loads: 1, syncs: 1),
                             split: MemorySplit(graphics: 41.26, neural: 0.04, compressed: 2.13))
        #expect(s.split?.line == "gfx 41.3 · zip 2.1")
        #expect(s.line.hasPrefix("86.0 MB · heap 26.0 · gfx 41.3 · zip 2.1 · 90 left"))
        #expect(try JSONDecoder().decode(MemorySample.self, from: JSONEncoder().encode(s)) == s)
        #expect(MemorySplit().line.isEmpty)
    }

    @Test func namesRegionKindsBiggestFirst() {
        let line = MemoryRegions.line([51: 31.24, 1: 20, 2: 6, 88: 8.1, 0: 0.3, 240: 1])
        #expect(line == "CA 31.2 · malloc 26.0 · IOSurface 8.1 · tag 240 1.0")
        var s = sample(40)
        s.regions = line
        #expect(s.line.contains("[CA 31.2 · malloc 26.0"))
    }

    @Test func countsKeyViewsOnlyWhenMoreThanKeyboards() throws {
        #expect(LiveCount.Counts(keyboards: 1, models: 1, loads: 1, syncs: 1, views: 1).line == "1 keyboard · 1 model · 1 load · 1 sync")
        #expect(LiveCount.Counts(keyboards: 1, models: 1, loads: 1, syncs: 1, views: 4).line
                == "1 keyboard · 4 key views · 1 model · 1 load · 1 sync")
        let old = #"{"keyboards":1,"models":1,"loads":1,"syncs":2}"#
        let decoded = try JSONDecoder().decode(LiveCount.Counts.self, from: Data(old.utf8))
        #expect(decoded == LiveCount.Counts(keyboards: 1, models: 1, loads: 1, syncs: 2))
    }

    @Test func memoryEventsRoundTripAndShowInTheTimeline() throws {
        let event = TypingEvent(t: 1.5, e: .memory, s: "hide", mem: sample(48))
        let decoded = try JSONDecoder().decode(TypingEvent.self, from: JSONEncoder().encode(event))
        #expect(decoded == event)
        #expect(!event.isInput)
    }

    @Test func briefSaysOnlyWhatIsOutOfRange() {
        let quiet = MemorySample(reading: MemoryReading(footprintMB: 23.44, headroomMB: 120), heapMB: 13.2, layers: 130,
                                 counts: .init(keyboards: 1, models: 1, loads: 1, syncs: 3, views: 1))
        #expect(quiet.brief(peakMB: 48.12) == "23.4 MB · peak 48.1")
        // The peak is never below now.
        #expect(quiet.brief(peakMB: 10) == "23.4 MB · peak 23.4")
        let loud = MemorySample(reading: MemoryReading(footprintMB: 86, headroomMB: 12.7), heapMB: 26, layers: 130,
                                counts: .init(keyboards: 3, models: 2, loads: 2, syncs: 3, waiting: 1, views: 5))
        #expect(loud.brief(peakMB: 90) == "86.0 MB · peak 90.0 · 12 left · heap 26.0 · 3 keyboards · 5 key views · 2 models · 2 loads · 1 waiting")
        // No headroom reading (not iOS) is not "0 left".
        let linux = MemorySample(reading: MemoryReading(footprintMB: 20, headroomMB: 0), heapMB: nil)
        #expect(linux.brief(peakMB: 20) == "20.0 MB · peak 20.0")
    }
}
