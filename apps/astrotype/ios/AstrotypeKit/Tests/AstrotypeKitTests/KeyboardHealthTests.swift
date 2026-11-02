import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct KeyboardHealthTests {
    private let t0 = Date(timeIntervalSince1970: 1_793_491_200)

    @Test func sessionKeepsPeakAndLowestHeadroom() {
        var health = KeyboardHealth()
        health.begin(at: t0, footprintMB: 20, headroomMB: 40)
        #expect(health.sample(footprintMB: 20.5, headroomMB: 39.5) == false) // under 1 MB: not worth a write
        #expect(health.sample(footprintMB: 22, headroomMB: 38) == true)
        #expect(health.sample(footprintMB: 21, headroomMB: 39) == false)
        health.end(footprintMB: 19, headroomMB: 41)
        let session = health.sessions[0]
        #expect(session.peakMB == 22)
        #expect(session.lowestHeadroomMB == 38)
        #expect(session.ended)
        // Nothing open: readings and ends do nothing.
        #expect(health.sample(footprintMB: 30, headroomMB: 10) == false)
        health.end(footprintMB: 30, headroomMB: 10)
        #expect(health.sessions[0].peakMB == 22)
    }

    @Test func keepsTheLastThirty() {
        var health = KeyboardHealth()
        for i in 0..<40 { health.begin(at: t0.addingTimeInterval(Double(i)), footprintMB: Double(i), headroomMB: 40) }
        #expect(health.sessions.count == KeyboardHealth.limit)
        #expect(health.sessions.first?.peakMB == 10)
    }

    @Test func sendsFinishedSessionsOnceAndWaitsForAnOpenOne() {
        var health = KeyboardHealth()
        health.begin(at: t0, footprintMB: 20, headroomMB: 40)
        health.end(footprintMB: 21, headroomMB: 39)
        health.begin(at: t0.addingTimeInterval(60), footprintMB: 25, headroomMB: 30) // killed while showing
        health.begin(at: t0.addingTimeInterval(120), footprintMB: 20, headroomMB: 40)
        health.end(footprintMB: 20, headroomMB: 40)

        // Two minutes on, the open one might still be up: only the first goes.
        let soon = health.toSend(after: nil, now: t0.addingTimeInterval(180))
        #expect(soon.map(\.started) == [t0])

        let metrics = RecordingMetrics()
        let sent = KeyboardHealth.report(soon, to: metrics)
        #expect(sent == t0)
        #expect(metrics.sent.map(\.name) == ["keyboard.memory_peak", "keyboard.memory_headroom"])
        #expect(metrics.sent.map(\.value) == [21, 39])

        // Later, the open one counts as ended while showing, and the last goes with it.
        let later = health.toSend(after: sent, now: t0.addingTimeInterval(3_600))
        #expect(later.map(\.started) == [t0.addingTimeInterval(60), t0.addingTimeInterval(120)])
        let more = RecordingMetrics()
        #expect(KeyboardHealth.report(later, to: more) == t0.addingTimeInterval(120))
        #expect(more.sent.filter { $0.name == "keyboard.ended_while_showing" }.count == 1)
        #expect(health.toSend(after: t0.addingTimeInterval(120), now: t0.addingTimeInterval(3_600)).isEmpty)
    }

    @Test func filesRoundTripAndUsageSharingDefaultsOff() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AstrotypeKitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileKeyboardHealthStore(url: folder.appendingPathComponent("keyboard-health.json"))
        #expect(store.load() == nil)
        var health = KeyboardHealth()
        health.begin(at: t0, footprintMB: 20, headroomMB: 40)
        store.save(health)
        #expect(store.load() == health)

        let usage = folder.appendingPathComponent("usage-sharing.json")
        #expect(UsageSharing.load(from: usage) == false)
        #expect(UsageSharing.load(from: nil) == false)
        UsageSharing.save(true, to: usage)
        #expect(UsageSharing.load(from: usage) == true)
        UsageSharing.save(false, to: usage)
        #expect(UsageSharing.load(from: usage) == false)
    }
}
