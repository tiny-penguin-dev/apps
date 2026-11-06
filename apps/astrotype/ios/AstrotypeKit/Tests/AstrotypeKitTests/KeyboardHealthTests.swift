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

    @Test func tagsWhatWasOpenAndHowItEnded() throws {
        var health = KeyboardHealth()
        #expect(health.use(.emoji) == false) // nothing open
        health.begin(at: t0, footprintMB: 20, headroomMB: 150)
        #expect(health.use(.emoji) == true)
        #expect(health.use(.emoji) == false) // already counted: no write
        health.use(.settings)
        health.end(footprintMB: 25, headroomMB: 145)
        health.begin(at: t0.addingTimeInterval(60), footprintMB: 20, headroomMB: 150)
        health.use(.metal)
        health.sample(footprintMB: 170, headroomMB: 5)
        // The next process finds it still open: iOS ended it, no crash.
        #expect(health.restarted(crashed: false) == true)
        #expect(health.restarted(crashed: true) == false) // already said
        health.begin(at: t0.addingTimeInterval(120), footprintMB: 20, headroomMB: 150)

        #expect(KeyboardHealth.label([]) == "keys")
        #expect(KeyboardHealth.label([.settings, .emoji, .emojiSearch]) == "emoji+emoji_search+settings")

        let metrics = RecordingMetrics()
        KeyboardHealth.report(Array(health.sessions.prefix(2)), to: metrics)
        let memory = metrics.sent.filter { $0.name.hasPrefix("keyboard.memory") }
        #expect(memory.map { $0.attributes["parts"] } == ["emoji+settings", "emoji+settings", "metal", "metal"])
        let ended = metrics.sent.filter { $0.name == "keyboard.ended_while_showing" }
        #expect(ended.map(\.attributes) == [["parts": "metal", "how": "killed"]])

        // Saved and read back, and an older file without them reads as none.
        let data = try JSONEncoder().encode(health)
        #expect(try JSONDecoder().decode(KeyboardHealth.self, from: data) == health)
        let old = try JSONDecoder().decode(KeyboardHealth.Session.self, from: Data(
            #"{"started": 0, "peakMB": 20, "lowestHeadroomMB": 30, "ended": false, "parts": ["emoji", "later"]}"#.utf8))
        #expect(old.parts == [.emoji])
        #expect(old.crashed == nil)
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

    @Test func countsFirstGuessesPerSessionAndSendsThem() {
        var health = KeyboardHealth()
        let kept = SettledWord(word: "the", previous: nil, source: .swiped, firstGuess: "the")
        let picked = SettledWord(word: "pit", previous: nil, source: .swiped, firstGuess: "pot")
        let fixed = SettledWord(word: "pit", previous: nil, source: .fixed, fixedFrom: "pot", firstGuess: "pot")
        let pecked = SettledWord(word: "hope", previous: nil, source: .tapped, firstGuess: "hope")
        let unguessed = SettledWord(word: "hope", previous: nil, source: .tapped)

        // Nothing open: nothing counted.
        #expect(health.settled(kept) == false)
        health.begin(at: t0, footprintMB: 20, headroomMB: 40)
        for _ in 0..<8 { health.settled(kept) }
        health.settled(picked)
        #expect(health.settled(fixed) == true) // the tenth word: worth a write
        health.settled(pecked)
        #expect(health.settled(unguessed) == false)
        health.end(footprintMB: 20, headroomMB: 40)
        #expect(health.sessions[0].guesses == GuessTally(swiped: 10, swipedFirst: 8, pecked: 1, peckedFirst: 1))

        let metrics = RecordingMetrics()
        KeyboardHealth.report(health.sessions, to: metrics)
        let guesses = metrics.sent.filter { $0.name.hasPrefix("guess.") }
        #expect(guesses.map(\.name) == ["guess.words", "guess.first", "guess.first_share", "guess.words", "guess.first"])
        #expect(guesses.map(\.value) == [10, 8, 80, 1, 1])
        #expect(guesses.map { $0.attributes["kind"] } == ["swipe", "swipe", "swipe", "tap", "tap"])
    }

    @Test func oldHealthFilesReadWithNoGuesses() throws {
        let old = #"{"version":1,"sessions":[{"started":0,"peakMB":20,"lowestHeadroomMB":40,"ended":true}]}"#
        let health = try JSONDecoder().decode(KeyboardHealth.self, from: Data(old.utf8))
        #expect(health.sessions.first?.guesses == GuessTally())
        let metrics = RecordingMetrics()
        KeyboardHealth.report(health.sessions, to: metrics)
        #expect(!metrics.sent.contains { $0.name.hasPrefix("guess.") })
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
