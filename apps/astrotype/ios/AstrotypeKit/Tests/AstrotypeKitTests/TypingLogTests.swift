import Foundation
import Testing
@testable import AstrotypeCore

/// The typing recorder (Settings → Debug → "Keep recording"): the event format, the
/// rolling files, the stretch that gets sent, and the replay through the engine.
@Suite struct TypingLogTests {
    static let english = ContextMatcherTests.english
    private let t0 = Date(timeIntervalSince1970: 1_793_491_200)
    private let device = TypingSnapshot.Device(app: "1.0 (202611060412)", system: "iOS 26.1", model: "iPhone17,1")

    private func snapshot(at date: Date, settings: KeyboardSettings = KeyboardSettings(), context: String = "") -> TypingSnapshot {
        TypingSnapshot(date: date, settings: settings, field: .text, layout: Synth.layout, page: .letters,
                       languages: ["en"], preferred: ["en-US"], pro: true, context: context, device: device)
    }

    /// Types like the keyboard does, writing down each event and what it wrote, the way
    /// `KeyboardModel` records it.
    struct Phone {
        var composer: Composer
        var events: [TypingEvent] = []
        var text = ""
        var marked = ""

        init(settings: KeyboardSettings, snapshot: TypingSnapshot, time: Double) {
            composer = Composer(language: TypingLogTests.english, layout: Synth.layout)
            var s = Field.text.composerSettings(settings.composerSettings(from: composer.settings))
            s.twoThumbs = true
            composer.settings = s
            text = snapshot.context
            composer.setContext(before: text)
            events.append(TypingEvent(t: time, e: .snapshot, snap: snapshot))
        }

        mutating func record(_ event: TypingEvent, _ effects: [Composer.Effect]) {
            events.append(event)
            for effect in effects {
                switch effect {
                case .insert(let s): text += s
                case .mark(let s): marked = s
                case .commit(let s): text += s; marked = ""
                case .clearMark: marked = ""
                case .deleteBackward(let n): for _ in 0..<n { if !marked.isEmpty { marked.removeLast() } else { text.removeLast() } }
                default: break
                }
            }
            composer.setContext(before: text)
            let codes = TypingEvent.codes(of: effects)
            if !codes.isEmpty { events.append(TypingEvent(t: event.t, e: .effects, fx: codes)) }
        }

        mutating func swipe(_ letters: String, id: Int, at time: Double) {
            let points = Synth.path(letters)
            let down = TypingEvent(t: time, e: .down, i: id, x: points[0].x, y: points[0].y)
            record(down, composer.touchDown(id: id, at: CGPoint(x: down.x!, y: down.y!), time: down.t))
            for (i, p) in points.enumerated().dropFirst() {
                let t = time + 0.3 * Double(i) / Double(points.count)
                // Rounded as the recorder rounds, so the replay sees the same numbers.
                let event = TypingEvent(t: t, e: .move, i: id, x: p.x, y: p.y)
                record(event, composer.touchMoved(id: id, to: CGPoint(x: event.x!, y: event.y!), time: event.t))
            }
            let last = points[points.count - 1]
            let up = TypingEvent(t: time + 0.3, e: .up, i: id, x: last.x, y: last.y)
            record(up, composer.touchUp(id: id, at: CGPoint(x: up.x!, y: up.y!), time: up.t))
        }

        mutating func press(_ key: Key, at time: Double) {
            record(TypingEvent(t: time, e: .key, s: TypingEvent.code(of: key)), composer.press(key, time: time))
        }
    }

    private func log(_ events: [TypingEvent]) -> TypingLog {
        TypingLog(createdAt: t0, from: t0, to: t0.addingTimeInterval(60), marks: [], writer: "test", app: "1.0", events: events)
    }

    // MARK: Format

    @Test func keyCodesGoBothWays() {
        let keys: [Key] = [.letter("a"), .symbol("@"), .text(".com"), .shift, .backspace, .numbers, .symbols, .letters,
                           .globe, .emoji, .space, .returnKey]
        for key in keys {
            #expect(TypingEvent.key(code: TypingEvent.code(of: key)) == key)
        }
        #expect(TypingEvent.key(code: "nonsense") == nil)
    }

    @Test func effectsAreShortAndSkipWhatChangesNothing() {
        let codes = TypingEvent.codes(of: [.mark("hel"), .commit("hello"), .insert(" "), .deleteBackward(2), .clearMark,
                                           .haptic(.key), .learn("zork")])
        #expect(codes == ["~hel", "=hello", "+ ", "-2", "0", "L:zork"])
    }

    @Test func layoutIsBuiltAgainTheSame() {
        let layouts = [
            Synth.layout,
            Layout.qwerty(width: 390, height: 200),
            Layout.qwerty(width: 951, split: true, extraLetters: true, globe: true, height: 230, bottom: .email),
        ]
        for layout in layouts {
            #expect(TypingLayout(layout).layout == layout)
        }
    }

    @Test func eventsRoundTripAndLeaveOutWhatIsEmpty() throws {
        let event = TypingEvent(t: 812.40249, e: .down, i: 31, x: 40.54, y: 121.01)
        let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        #expect(!json.contains("snap"))
        #expect(!json.contains("fx"))
        let back = try JSONDecoder().decode(TypingEvent.self, from: Data(json.utf8))
        #expect(back == event)
        #expect(back.t == 812.402)
        #expect(back.x == 40.5)

        let snap = TypingEvent(t: 1, e: .snapshot, snap: snapshot(at: t0, context: String(repeating: "word ", count: 50)))
        let read = try JSONDecoder().decode(TypingEvent.self, from: JSONEncoder().encode(snap))
        #expect(read == snap)
        #expect(read.snap?.context.count == TypingSnapshot.contextLength)
        let field = Field(keyboard: .email, returnKey: .next)
        #expect(try JSONDecoder().decode(Field.self, from: JSONEncoder().encode(field)) == field)
    }

    @Test func settingsReadWithoutTheNewSwitch() throws {
        let old = try JSONDecoder().decode(KeyboardSettings.self, from: Data(#"{"autospace":false}"#.utf8))
        #expect(old.recordsTyping == false)
        var settings = KeyboardSettings()
        settings.recordsTyping = true
        #expect(try JSONDecoder().decode(KeyboardSettings.self, from: JSONEncoder().encode(settings)).recordsTyping)
    }

    // MARK: Windows

    @Test func windowStartsAtTheSnapshotBeforeIt() {
        let events = [
            TypingEvent(t: 5, e: .down, i: 1, x: 1, y: 1), // before any snapshot: no time
            TypingEvent(t: 10, e: .snapshot, snap: snapshot(at: t0)),
            TypingEvent(t: 20, e: .key, s: "space"),
            TypingEvent(t: 100, e: .snapshot, snap: snapshot(at: t0.addingTimeInterval(90))),
            TypingEvent(t: 130, e: .mark),
            TypingEvent(t: 200, e: .key, s: "space"),
        ]
        let dates = TypingLog.dates(of: events)
        #expect(dates[0] == nil)
        #expect(dates[2] == t0.addingTimeInterval(10))
        #expect(dates[5] == t0.addingTimeInterval(190))
        let now = t0.addingTimeInterval(200)
        // The last minute starts at 140 s, after the second snapshot (90 s): from there.
        #expect(TypingLog.window(events, last: 60, now: now).count == 3)
        // Five minutes reaches back before both: from the first.
        #expect(TypingLog.window(events, last: 300, now: now).count == 5)
        #expect(TypingLog.marks(in: events) == [t0.addingTimeInterval(120)])
    }

    // MARK: Files

    @MainActor @Test func recorderWritesRotatesAndPrunes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("typing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = TypingLogFiles(folder: folder)
        var clock = t0
        let recorder = TypingRecorder(files: files, now: { clock })
        #expect(recorder.needsSnapshot(at: 0))
        recorder.snapshot(snapshot(at: clock), time: 0)
        #expect(!recorder.needsSnapshot(at: 5))
        #expect(recorder.needsSnapshot(at: 25))
        recorder.record(TypingEvent(t: 1, e: .key, s: "space"))
        recorder.flush()
        #expect(files.files().count == 1)
        #expect(files.events().map(\.e) == [.snapshot, .key])

        // A snapshot under five minutes later stays in the same file; past it, a new one.
        clock = t0.addingTimeInterval(60)
        recorder.snapshot(snapshot(at: clock), time: 60)
        clock = t0.addingTimeInterval(400)
        recorder.snapshot(snapshot(at: clock), time: 400)
        recorder.record(TypingEvent(t: 401, e: .mark))
        recorder.flush()
        #expect(files.files().count == 2)
        #expect(files.marks() == [t0.addingTimeInterval(401)])

        // A line cut short when the keyboard ended is skipped.
        try files.append(Data(#"{"t":402,"e":"k","s":"spa"#.utf8), to: files.files().last!)
        #expect(files.events().count == 5)

        // An hour on, the old files go when the next one starts.
        clock = t0.addingTimeInterval(3_600 + 400)
        recorder.snapshot(snapshot(at: clock), time: 4_000)
        recorder.flush()
        #expect(files.files().count == 2)
        #expect(files.files().first.flatMap(TypingLogFiles.started) == t0.addingTimeInterval(400))
        files.removeAll()
        #expect(files.files().isEmpty)
    }

    @MainActor @Test func logIsTheLastStretchWithItsMarks() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("typing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = TypingLogFiles(folder: folder)
        let recorder = TypingRecorder(files: files, now: { self.t0 })
        recorder.snapshot(snapshot(at: t0), time: 0)
        #expect(files.log(last: 60, now: t0.addingTimeInterval(30), writer: "w", app: "1.0") == nil) // nothing typed yet
        recorder.record(TypingEvent(t: 10, e: .key, s: "space"))
        recorder.record(TypingEvent(t: 12, e: .mark))
        recorder.flush()
        let log = files.log(last: 60, now: t0.addingTimeInterval(30), writer: "w", app: "1.0")
        #expect(log?.events.count == 3)
        #expect(log?.marks == [t0.addingTimeInterval(12)])
        #expect(log?.device == device)
        #expect(log?.from == t0)
        #expect(log?.summary == "1 min · 0 touches · 1 mark")
    }

    @Test func partsCutTheCompressedLogUp() throws {
        let log = log([])
        let data = Data((0..<(TypingLog.partSize)).map { UInt8($0 % 251) })
        let parts = log.parts(compressed: data)
        #expect(parts.count == 2)
        #expect(parts[0].id == log.id)
        #expect(parts[1].label == "\(log.id.uuidString) 2/2")
        var joined = ""
        for part in parts {
            let object = try JSONSerialization.jsonObject(with: Data(part.json.utf8)) as! [String: Any]
            #expect(object["log"] as? String == log.id.uuidString)
            joined += object["deflate"] as! String
        }
        #expect(Data(base64Encoded: joined) == data)
        let back = try TypingLog.decode(log.encoded())
        #expect(back == log)
    }

    // MARK: Replay

    @Test func replayWritesWhatThePhoneWrote() throws {
        let settings = KeyboardSettings()
        var phone = Phone(settings: settings, snapshot: snapshot(at: t0, settings: settings, context: "I said "), time: 100)
        phone.swipe("hello", id: 1, at: 101)
        phone.press(.space, at: 101.6)
        phone.swipe("world", id: 2, at: 102)
        phone.press(.space, at: 102.6)
        let result = TypingReplay.run(log(phone.events), loadLanguage: { _ in Self.english })
        #expect(result.differences.isEmpty, "\(result.differences)")
        #expect(result.text == phone.text)
        #expect(result.text.lowercased() == "i said hello world ")
        #expect(result.commits.map { $0.lowercased() } == ["hello", "world"])

        // The timeline reads as touches and what they wrote.
        let timeline = log(phone.events).timeline()
        #expect(timeline.contains("swipe #1 h"))
        #expect(timeline.contains("key space"))
        #expect(timeline.contains("\"=hello\"") || timeline.contains("\"=Hello\""))
    }

    @Test func replayShowsWhereTheEngineNowDiffers() throws {
        let settings = KeyboardSettings()
        var phone = Phone(settings: settings, snapshot: snapshot(at: t0, settings: settings), time: 0)
        phone.swipe("hello", id: 1, at: 1)
        phone.press(.space, at: 1.6)
        var events = phone.events
        // Say the phone wrote another word: the replay shows the space as different.
        let space = try #require(events.lastIndex { $0.e == .effects })
        events[space].fx = ["=help", "+ "]
        let result = TypingReplay.run(log(events), loadLanguage: { _ in Self.english })
        #expect(result.differences.count == 1)
        #expect(result.differences.first?.event == .key)
        #expect(result.differences.first?.recorded == ["=help", "+ "])
    }

    @Test func replayFollowsTheFieldAndContext() {
        var phone = Phone(settings: KeyboardSettings(), snapshot: snapshot(at: t0), time: 0)
        phone.events.append(TypingEvent(t: 0.5, e: .context, s: "Dear Sam, "))
        phone.text = "Dear Sam, "
        phone.composer.setContext(before: phone.text)
        phone.swipe("thanks", id: 1, at: 1)
        phone.press(.space, at: 1.6)
        let result = TypingReplay.run(log(phone.events), loadLanguage: { _ in Self.english })
        #expect(result.differences.isEmpty, "\(result.differences)")
        #expect(result.text.hasPrefix("Dear Sam, "))
    }
}
