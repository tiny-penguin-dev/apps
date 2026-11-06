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

    @Test func memoryEventsRoundTripAndShowInTheTimeline() throws {
        let event = TypingEvent(t: 1.5, e: .memory, s: "hide", mem: sample(48))
        let decoded = try JSONDecoder().decode(TypingEvent.self, from: JSONEncoder().encode(event))
        #expect(decoded == event)
        #expect(!event.isInput)
    }
}
