import Foundation

/// The typing recorder (Settings → Debug, Gabriel 6 Nov 2026): everything the keyboard
/// did, one event per line, so a bug seen on the phone can be sent and played back
/// through the engine (`TypingReplay`). With "Keep recording" on, the keyboard keeps the
/// last half hour on the phone (`TypingRecorder`, `TypingLogFiles`); nothing leaves it
/// until the person sends a stretch from the app, which makes a `TypingLog`.
///
/// Times are the keyboard's clock (`systemUptime`, the same as `UITouch.timestamp`);
/// each snapshot pairs that clock with the wall clock. Points are in the keys' own
/// points, as the engine gets them. Keys are short so a line stays small:
///
///     {"t":812.402,"e":"d","i":31,"x":40.5,"y":121}          a finger down on the keys
///     {"t":812.433,"e":"fx","fx":["~a"]}                     what that wrote
public struct TypingEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// Everything needed to start a replay here (`TypingSnapshot`): on show, after a
        /// pause, and every so often while no word is open.
        case snapshot = "snap"
        /// The keyboard went away.
        case hide
        /// A finger on the letters, as the engine gets it: down, moved, up, cancelled.
        case down = "d", move = "m", up = "u", cancel = "c"
        /// A held letter's callout gave another letter (`s`) for touch `i`.
        case pick
        /// A key pressed (`s`, `TypingEvent.code(of:)`); a character (`s`) from the
        /// numbers or symbols page; a string key like ".com".
        case key = "k", character = "ch", text = "tx"
        /// An emoji from the emoji page (`s`).
        case emoji
        /// Emoji search opened, closed, cleared; an emoji from its results.
        case searchOpen = "so", searchClose = "sc", searchClear = "sx", searchEmoji = "se"
        /// A guess tapped on the bar (`n`), another reading of the last word (`n`).
        case guess = "g", fix
        /// A slide on space moved the cursor `n` characters.
        case cursor = "cur"
        /// "Not it?" opened, cancelled, saved.
        case notIt = "nit", notItCancel = "nitx", notItSave = "nits"
        /// A swipe left on backspace.
        case deleteWord = "dw"
        /// A guess held and slid up (`n`) or down (`n`).
        case boost, forget
        /// Autospace's timer fired.
        case tick
        /// The text before the cursor (`s`, the end of it) after the app changed it,
        /// and after the field was replaced or the cursor moved (`reset`).
        case context = "ctx", reset
        /// What the field itself reported (`s`), on a change from the app and before a
        /// delete: the end of the text before the cursor, the selection in ⟦ ⟧, the start
        /// of the text after, and the open word as the keyboard holds it. For the
        /// underlined word bugs, where the keyboard and the field disagree (6 Nov 2026).
        case fieldState = "fs"
        /// The keyboard settings changed (`settings`), the field (`field`), the keys'
        /// layout (`layout`), the page showing (`s`), the languages (`s`, "en+es"), Pro (`n`).
        case settings = "set", field, layout = "lay", page, language = "lang", pro
        /// A touch the engine never sees: on space, backspace, shift, 123, return, a
        /// number or symbol, or no key at all. `s` is the phase (b, m, e, x; n for a touch
        /// on no key, which goes nowhere), `k` the key.
        case other = "o"
        /// What the event before did to the field (`fx`, `TypingEvent.code(of:)`).
        case effects = "fx"
        /// The person tapped Mark: something went wrong around here.
        case mark
        /// Recording stopped in a field that never learns (an address, a code, a
        /// password); a snapshot starts it again.
        case pause
        /// A memory reading (`mem`), with why it was logged in `s`: "show", "hide",
        /// "warning", "tick", "jump" or "count" (`MemoryLogPacer`).
        case memory = "mem"
        /// How long the keyboard took to open, step by step (`s`, `OpenTiming.line`).
        case open
        /// The next-word models loaded (features/next-word-model): `s` is the languages,
        /// how long it took and the memory before and after, as "en+es 140 ms 31.2 → 34.0 MB".
        case nextWordLoad = "nwl"
    }

    /// The keyboard's clock, seconds.
    public var t: Double
    public var e: Kind
    /// A touch's ID.
    public var i: Int?
    public var x: Double?
    public var y: Double?
    public var n: Int?
    public var s: String?
    /// A key, for `other`.
    public var k: String?
    public var fx: [String]?
    public var snap: TypingSnapshot?
    public var settings: KeyboardSettings?
    public var field: Field?
    public var layout: TypingLayout?
    public var mem: MemorySample?

    public init(t: Double, e: Kind, i: Int? = nil, x: Double? = nil, y: Double? = nil, n: Int? = nil, s: String? = nil,
                k: String? = nil, fx: [String]? = nil, snap: TypingSnapshot? = nil, settings: KeyboardSettings? = nil,
                field: Field? = nil, layout: TypingLayout? = nil, mem: MemorySample? = nil) {
        self.t = Self.round(t, 1_000)
        self.e = e
        self.i = i
        self.x = x.map { Self.round($0, 10) }
        self.y = y.map { Self.round($0, 10) }
        self.n = n
        self.s = s
        self.k = k
        self.fx = fx
        self.snap = snap
        self.settings = settings
        self.field = field
        self.layout = layout
        self.mem = mem
    }

    /// Whether the person did this (a touch, a key, a tap on the bar), as opposed to
    /// what the keyboard noted about itself.
    public var isInput: Bool {
        switch e {
        case .down, .move, .up, .cancel, .pick, .key, .character, .text, .emoji, .searchOpen, .searchClose, .searchClear,
             .searchEmoji, .guess, .fix, .cursor, .notIt, .notItCancel, .notItSave, .deleteWord, .boost, .forget, .tick, .hide:
            true
        default:
            false
        }
    }

    private static func round(_ value: Double, _ scale: Double) -> Double { (value * scale).rounded() / scale }

    // MARK: Codes

    /// A key as a short string: "space", "back", "l:a", "y:@", "t:.com".
    public static func code(of key: Key) -> String {
        switch key {
        case .letter(let c): "l:\(c)"
        case .symbol(let c): "y:\(c)"
        case .text(let text): "t:\(text)"
        case .shift: "shift"
        case .backspace: "back"
        case .numbers: "123"
        case .symbols: "#+="
        case .letters: "abc"
        case .globe: "globe"
        case .emoji: "emoji"
        case .space: "space"
        case .returnKey: "return"
        }
    }

    /// The key a code names, nil for one this build doesn't know.
    public static func key(code: String) -> Key? {
        if code.hasPrefix("l:"), let c = code.dropFirst(2).first { return .letter(c) }
        if code.hasPrefix("y:"), let c = code.dropFirst(2).first { return .symbol(c) }
        if code.hasPrefix("t:") { return .text(String(code.dropFirst(2))) }
        switch code {
        case "shift": return .shift
        case "back": return .backspace
        case "123": return .numbers
        case "#+=": return .symbols
        case "abc": return .letters
        case "globe": return .globe
        case "emoji": return .emoji
        case "space": return .space
        case "return": return .returnKey
        default: return nil
        }
    }

    /// An effect on the field as a short string, nil for the ones that change nothing
    /// there (haptics, notices, what was settled): "+ " inserted, "-2" deleted, "~wor"
    /// the open word, "=word" written, "0" open word removed, "L:word" learned,
    /// "U:word" unlearned.
    public static func code(of effect: Composer.Effect) -> String? {
        switch effect {
        case .insert(let text): "+" + text
        case .deleteBackward(let count): "-\(count)"
        case .mark(let text): "~" + text
        case .commit(let text): "=" + text
        case .clearMark: "0"
        case .learn(let word): "L:" + word
        case .unlearn(let word): "U:" + word
        case .haptic, .notice, .settled: nil
        }
    }

    public static func codes(of effects: [Composer.Effect]) -> [String] {
        effects.compactMap(code(of:))
    }
}

/// The keys' layout as the engine had it: enough to build it again.
public struct TypingLayout: Codable, Sendable, Equatable {
    public var width: Double
    public var height: Double
    public var split: Bool
    public var extraLetters: Bool
    public var globe: Bool
    public var bottom: Layout.BottomRow

    public init(_ layout: Layout) {
        width = Double(layout.width)
        height = Double(layout.height)
        split = layout.split
        extraLetters = layout.extraLetters
        globe = layout.globe
        bottom = layout.bottomRow
    }

    /// The letters page, as `KeyboardView` makes it for the engine.
    public var layout: Layout {
        Layout.qwerty(width: CGFloat(width), split: split, extraLetters: extraLetters, globe: globe,
                      height: CGFloat(height), bottom: bottom)
    }
}

/// Where a replay can start: what the keyboard was set to and where it was typing.
public struct TypingSnapshot: Codable, Sendable, Equatable {
    /// The phone and the build, as the keyboard extension reads them.
    public struct Device: Codable, Sendable, Equatable {
        /// "1.0 (202611060412)": the build number is the commit's time on `main`.
        public var app: String
        public var system: String
        /// "iPhone17,1".
        public var model: String

        public init(app: String, system: String, model: String) {
            self.app = app
            self.system = system
            self.model = model
        }
    }

    /// The wall clock at this event, seconds since 1970.
    public var date: Double
    public var settings: KeyboardSettings
    public var field: Field
    public var layout: TypingLayout
    public var page: Layout.Page
    /// The languages typing now ("en", "es"), and the phone's.
    public var languages: [String]
    public var preferred: [String]
    public var pro: Bool
    /// The end of the text before the cursor.
    public var context: String
    public var device: Device

    public init(date: Date, settings: KeyboardSettings, field: Field, layout: Layout, page: Layout.Page,
                languages: [String], preferred: [String], pro: Bool, context: String, device: Device) {
        self.date = (date.timeIntervalSince1970 * 1_000).rounded() / 1_000
        self.settings = settings
        self.field = field
        self.layout = TypingLayout(layout)
        self.page = page
        self.languages = languages
        self.preferred = preferred
        self.pro = pro
        self.context = TypingSnapshot.trim(context)
        self.device = device
    }

    /// The most of the text before the cursor that is kept: enough for the sentence's
    /// capitals and the words before, no more.
    public static let contextLength = 120

    public static func trim(_ context: String?) -> String {
        String((context ?? "").suffix(contextLength))
    }
}

/// A stretch of the recording, sent from Settings → Debug: the events from the last
/// snapshot before it began, the phone and build, and what the keyboard had learned
/// when it was sent, so a replay guesses as the phone did. The record on CloudKit is a
/// `PracticeSession` of kind `typing.log`, compressed and cut into parts
/// (`TypingLog.parts`); `ml/download_samples.py` puts them back together.
public struct TypingLog: Codable, Sendable, Equatable {
    public static let version = 1
    public static let kind = "typing.log"

    public var version = TypingLog.version
    public var id: UUID
    public var createdAt: Date
    /// The stretch asked for (the events may start a little before, at a snapshot).
    public var from: Date
    public var to: Date
    /// When the person tapped Mark.
    public var marks: [Date]
    public var writer: String
    /// The app that sent it (the keyboard's own build is in each snapshot).
    public var app: String
    public var learned: LearnedWords?
    public var personal: PersonalModel?
    public var events: [TypingEvent]

    public init(id: UUID = UUID(), createdAt: Date, from: Date, to: Date, marks: [Date], writer: String, app: String,
                learned: LearnedWords? = nil, personal: PersonalModel? = nil, events: [TypingEvent]) {
        self.id = id
        self.createdAt = createdAt
        self.from = from
        self.to = to
        self.marks = marks
        self.writer = writer
        self.app = app
        self.learned = learned
        self.personal = personal
        self.events = events
    }

    /// The first snapshot's phone and build.
    public var device: TypingSnapshot.Device? { events.lazy.compactMap(\.snap).first?.device }

    /// "9 min · 412 touches · 2 marks".
    public var summary: String {
        let touches = events.filter { $0.e == .down || ($0.e == .other && $0.s == "b") }.count
        let minutes = max(1, Int((to.timeIntervalSince(from) / 60).rounded()))
        var parts = ["\(minutes) min", "\(touches) touches"]
        if !marks.isEmpty { parts.append(marks.count == 1 ? "1 mark" : "\(marks.count) marks") }
        return parts.joined(separator: " · ")
    }

    // MARK: Windows

    /// Each event's wall-clock time, from the snapshot before it; nil before the first.
    public static func dates(of events: [TypingEvent]) -> [Date?] {
        var anchor: (t: Double, date: Double)?
        return events.map { event in
            if let snap = event.snap { anchor = (event.t, snap.date) }
            // A clock that went back (the phone restarted) waits for the next snapshot.
            guard let a = anchor, event.t >= a.t else { return nil }
            return Date(timeIntervalSince1970: a.date + (event.t - a.t))
        }
    }

    /// The events of the last `seconds` before `now`, from the snapshot at or before
    /// that start (the first one, if none is that old), so a replay starts in step.
    public static func window(_ events: [TypingEvent], last seconds: TimeInterval, now: Date) -> [TypingEvent] {
        let dates = dates(of: events)
        let start = now.addingTimeInterval(-seconds)
        let snapshots = events.indices.filter { events[$0].e == .snapshot && dates[$0] != nil }
        guard let first = snapshots.first else { return [] }
        let from = snapshots.last { dates[$0]! <= start } ?? first
        return Array(events[from...])
    }

    /// The marks among some events.
    public static func marks(in events: [TypingEvent]) -> [Date] {
        zip(events, dates(of: events)).compactMap { event, date in event.e == .mark ? date : nil }
    }

    // MARK: Sending

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> TypingLog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TypingLog.self, from: data)
    }

    /// One part of a log as it goes to CloudKit: a record holds about a megabyte, so the
    /// compressed log goes in pieces of at most `partSize` characters of base64.
    public struct Part: Sendable, Equatable {
        public var id: UUID
        /// "<log id> 1/3".
        public var label: String
        public var json: String
    }

    public static let partSize = 600_000

    /// The parts of `compressed` (the log's JSON, deflated by the host): each record's
    /// `json` is `{"log":…,"part":1,"of":3,"deflate":"<base64>"}`.
    public func parts(compressed: Data) -> [Part] {
        let base64 = compressed.base64EncodedString()
        var chunks: [Substring] = []
        var rest = Substring(base64)
        while !rest.isEmpty {
            chunks.append(rest.prefix(Self.partSize))
            rest = rest.dropFirst(Self.partSize)
        }
        if chunks.isEmpty { chunks = [""] }
        return chunks.enumerated().map { index, chunk in
            let partID = index == 0 ? id : UUID()
            let json = #"{"deflate":"\#(chunk)","log":"\#(id.uuidString)","of":\#(chunks.count),"part":\#(index + 1)}"#
            return Part(id: partID, label: "\(id.uuidString) \(index + 1)/\(chunks.count)", json: json)
        }
    }
}

/// A typing log the app sent: what to tell the person, and the records to delete.
public struct SentTypingLog: Codable, Sendable, Equatable {
    public var id: UUID
    public var sent: Date
    public var summary: String
    /// The CloudKit record names of its parts.
    public var records: [String]

    public init(id: UUID, sent: Date, summary: String, records: [String]) {
        self.id = id
        self.sent = sent
        self.summary = summary
        self.records = records
    }
}

/// Sends a typing log's parts and deletes them again (CloudKit's public database).
public protocol TypingLogUploader: Sendable {
    /// Uploads the parts and returns the record names that made it.
    func upload(_ parts: [TypingLog.Part]) async throws -> [String]
    func delete(_ records: [String]) async throws
}

// MARK: Reading

extension TypingLog {
    /// The log as lines to read: each snapshot, each touch as one line (the keys it
    /// crossed, where it landed and lifted), each key and tap on the bar, and what it
    /// wrote. For `astrotype-tools typing` and for reading a bug report.
    ///
    ///     15:42:03.120  snapshot  1.0 (202611060412) · iPhone17,1 · en · 390×216 · text · "Hello how are"
    ///     15:42:03.500  swipe #12 a s d f g h j k l  (40,120)→(352,118) 0.42 s
    ///                     → ~all  =all  + 
    public func timeline() -> String {
        let dates = TypingLog.dates(of: events)
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss.SSS"
        clock.timeZone = TimeZone.current
        var layout = Layout.qwerty(width: 390)
        var open: [Int: (start: TypingEvent, keys: [String], last: TypingEvent)] = [:]
        var lines: [String] = []

        func stamp(_ index: Int) -> String {
            dates[index].map { clock.string(from: $0) } ?? String(format: "%12.3f", events[index].t)
        }
        func keyName(_ event: TypingEvent) -> String {
            guard let x = event.x, let y = event.y, let key = layout.key(at: CGPoint(x: x, y: y)) else { return "·" }
            return Self.name(key)
        }
        func point(_ event: TypingEvent) -> String {
            "(\(Int((event.x ?? 0).rounded())),\(Int((event.y ?? 0).rounded())))"
        }

        for (index, event) in events.enumerated() {
            let time = stamp(index)
            switch event.e {
            case .snapshot:
                guard let snap = event.snap else { continue }
                layout = snap.layout.layout
                let size = "\(Int(snap.layout.width))×\(Int(snap.layout.height))\(snap.layout.split ? " split" : "")"
                lines.append("\(time)  snapshot  \(snap.device.app) · \(snap.device.model) · \(snap.device.system) · "
                    + "\(snap.languages.joined(separator: "+")) · \(size) · \(snap.field.kind.rawValue)\(snap.pro ? "" : " · free")"
                    + " · \"\(snap.context.suffix(40))\"")
            case .down:
                open[event.i ?? 0] = (event, [keyName(event)], event)
            case .move:
                guard var touch = open[event.i ?? 0] else { continue }
                let key = keyName(event)
                if touch.keys.last != key { touch.keys.append(key) }
                touch.last = event
                open[event.i ?? 0] = touch
            case .up, .cancel, .pick:
                guard var touch = open.removeValue(forKey: event.i ?? 0) else { continue }
                if event.e == .up {
                    let key = keyName(event)
                    if touch.keys.last != key { touch.keys.append(key) }
                    touch.last = event
                }
                let kind = touch.keys.count > 1 ? "swipe" : "tap"
                let end = event.e == .up ? "→\(point(event))" : event.e == .pick ? " picked \(event.s ?? "")" : " cancelled"
                lines.append("\(time)  \(kind) #\(event.i ?? 0) \(touch.keys.joined(separator: " "))  "
                    + "\(point(touch.start))\(end) \(String(format: "%.2f", event.t - touch.start.t)) s")
            case .other:
                // One line per touch, at its end, like the letters.
                if event.s == "n" {
                    lines.append("\(time)  touch on no key \(point(event))")
                } else if event.s == "b" {
                    open[-1 - (event.i ?? 0)] = (event, [event.k.flatMap(TypingEvent.key(code:)).map(Self.name) ?? "no key"], event)
                } else if event.s == "m" {
                    if var touch = open[-1 - (event.i ?? 0)] { touch.last = event; open[-1 - (event.i ?? 0)] = touch }
                } else if let touch = open.removeValue(forKey: -1 - (event.i ?? 0)) {
                    let dx = Int(((event.x ?? 0) - (touch.start.x ?? 0)).rounded())
                    lines.append("\(time)  touch \(touch.keys[0])  \(point(touch.start))→\(point(event))"
                        + "\(abs(dx) >= 6 ? " slid \(dx) pt" : "")\(event.s == "x" ? " cancelled" : "")"
                        + " \(String(format: "%.2f", event.t - touch.start.t)) s")
                }
            case .effects:
                lines.append(String(repeating: " ", count: 14) + "→ " + (event.fx ?? []).map { "\($0.debugDescription)" }.joined(separator: "  "))
            case .key: lines.append("\(time)  key \(event.s.flatMap(TypingEvent.key(code:)).map(Self.name) ?? event.s ?? "")")
            case .character, .text, .emoji: lines.append("\(time)  \(event.e) \(event.s ?? "")")
            case .guess, .fix, .boost, .forget, .cursor: lines.append("\(time)  \(event.e) \(event.n ?? 0)")
            case .context, .reset: lines.append("\(time)  \(event.e == .reset ? "reset" : "field now") \"\((event.s ?? "").suffix(40))\"")
            case .settings: lines.append("\(time)  settings changed")
            case .field: lines.append("\(time)  field \(event.field?.kind.rawValue ?? "")")
            case .layout: lines.append("\(time)  layout \(Int(event.layout?.width ?? 0))×\(Int(event.layout?.height ?? 0))")
            case .mark: lines.append("\(time)  ★ MARK")
            case .memory: lines.append("\(time)  memory (\(event.s ?? "")) \(event.mem?.line ?? "")")
            default: lines.append("\(time)  \(event.e)\(event.s.map { " \($0)" } ?? "")\(event.n.map { " \($0)" } ?? "")")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func name(_ key: Key) -> String {
        switch key {
        case .letter(let c), .symbol(let c): String(c)
        case .text(let s): s
        default: TypingEvent.code(of: key)
        }
    }
}
