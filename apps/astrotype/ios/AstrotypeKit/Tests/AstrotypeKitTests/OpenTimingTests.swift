import Testing
@testable import AstrotypeCore

@Suite struct OpenTimingTests {
    /// Each step is the time since the one before, and the total is since the start.
    @Test func stepsAndTotal() {
        var timing = OpenTiming(now: 100)
        timing.step("model", now: 100.040)
        timing.step("keys", now: 100.075)
        #expect(timing.steps.map(\.name) == ["model", "keys"])
        #expect(timing.steps.map(\.millis) == [40, 35])
        #expect(timing.line(now: 100.2) == "model 40 · keys 35 · 200 ms in all")
        #expect(timing.line(now: 100.2, notes: ["metal 210 off the main thread"]).hasSuffix("in all · metal 210 off the main thread"))
    }
}
