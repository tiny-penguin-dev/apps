import Foundation

/// The harness (features/smart-matching/FEATURE.md): plays a practice recording through
/// a fresh `Composer` with the same language and layout, presses space where the
/// person's words went in, and says how often the engine's first guess was the word
/// asked for. Every change to the matcher is measured against it before it ships;
/// `astrotype-tools replay <folder>` prints the report for a folder of sessions.
///
///     let outcome = Replay.run(recording, language: english)
///     outcome.firstGuessRate            // 0.9
///     Replay.Report(outcomes).summary   // "48 words · first guess 91.7% · top three 97.9% · 2 misses"
public enum Replay {
    /// One word of a session: what was asked, what the bar offered when it went in.
    public struct Word: Sendable, Equatable {
        public var expected: String
        /// The bar's guesses, the one space would write first.
        public var guesses: [String]
        public var isFirstGuess: Bool { guesses.first == expected }
        public var isInTopThree: Bool { guesses.prefix(3).contains(expected) }
    }

    public struct Outcome: Sendable, Equatable {
        public var id: UUID
        public var kind: String
        public var words: [Word]

        public var firstGuesses: Int { words.filter(\.isFirstGuess).count }
        public var topThrees: Int { words.filter(\.isInTopThree).count }
        public var misses: [Word] { words.filter { !$0.isFirstGuess } }
        public var firstGuessRate: Double { words.isEmpty ? 0 : Double(firstGuesses) / Double(words.count) }
    }

    /// Why a recording cannot be replayed.
    public enum Skip: Error, Equatable {
        /// Version 1 recordings have no commit times.
        case noCommits
        case noTouches
    }

    /// Replays one recording. The layout is rebuilt from the recording's width, split
    /// and height, and the touches scaled onto it; the context before each word is what
    /// the replay itself has written so far.
    public static func run(_ recording: PracticeRecording, language: Language,
                           settings: Composer.Settings = Replay.settings, before: String = "",
                           weights: Matcher.Weights? = nil) throws(Skip) -> Outcome {
        guard !recording.commits.isEmpty else { throw .noCommits }
        guard !recording.touches.isEmpty else { throw .noTouches }
        let layout = Layout.qwerty(width: recording.layoutWidth, split: recording.split, maxHeight: recording.layoutHeight)
        var composer = Composer(language: language, layout: layout, settings: settings)
        if let weights { composer.matcher.weights = weights }
        let expected = recording.expected.split(separator: " ").map(String.init)
        var events = events(of: recording, layout: layout)
        events.sort { $0.time == $1.time ? $0.order < $1.order : $0.time < $1.time }

        var words: [Word] = []
        var text = before
        var pointer = 0
        composer.setContext(before: text)
        for event in events {
            switch event.kind {
            case .down(let point): _ = composer.touchDown(id: event.id, at: point, time: event.time)
            case .move(let point): _ = composer.touchMoved(id: event.id, to: point, time: event.time)
            case .up(let point): _ = composer.touchUp(id: event.id, at: point, time: event.time)
            case .commit(let typed):
                guard pointer < expected.count else { continue }
                let guesses: [String]
                if case .guesses(let offered, let chosen) = composer.state.bar, !offered.isEmpty {
                    // The one space writes first, then the others in the bar's order.
                    guesses = [offered[chosen]] + offered.enumerated().filter { $0.offset != chosen }.map(\.element)
                } else {
                    guesses = []
                }
                let word = expected[pointer]
                words.append(Word(expected: word, guesses: guesses.map { SpeedTest.normalize($0) }))
                _ = composer.press(.space, time: event.time)
                // What the person wrote is what the field holds: it is the context of
                // the next word, and a right word moves them on to the next one asked.
                text += typed + " "
                composer.setContext(before: text)
                if typed == word { pointer += 1 }
            }
        }
        return Outcome(id: recording.id, kind: recording.kind, words: words)
    }

    /// One shared word (Phase C): its touches with the word before it as the context.
    public static func run(_ word: SharedWord, language: Language, weights: Matcher.Weights? = nil) throws(Skip) -> Outcome {
        let before = word.previous.map { $0 == NgramModel.sentenceStart ? "" : $0 + " " } ?? ""
        return try run(word.recording, language: language, before: before, weights: weights)
    }

    /// What the harness replays: a whole recording (versions 1 and 2) or one shared word.
    public enum Item: Sendable {
        case recording(PracticeRecording)
        case word(SharedWord)

        /// Either kind from a file's JSON, nil for anything else. Recordings come with
        /// ISO 8601 dates, as the app stores and uploads them, or plain ones.
        public init?(json data: Data) {
            let iso = JSONDecoder()
            iso.dateDecodingStrategy = .iso8601
            if let word = try? JSONDecoder().decode(SharedWord.self, from: data) {
                self = .word(word)
            } else if let recording = (try? iso.decode(PracticeRecording.self, from: data))
                        ?? (try? JSONDecoder().decode(PracticeRecording.self, from: data)) {
                self = .recording(recording)
            } else {
                return nil
            }
        }

        public func run(language: Language, weights: Matcher.Weights? = nil) throws(Skip) -> Outcome {
            switch self {
            case .recording(let recording): try Replay.run(recording, language: language, weights: weights)
            case .word(let word): try Replay.run(word, language: language, weights: weights)
            }
        }
    }

    /// Many items through the engine with one set of weights.
    public static func report(_ items: [Item], language: Language, weights: Matcher.Weights? = nil) -> Report {
        var outcomes: [Outcome] = []
        var skipped = 0
        for item in items {
            do { outcomes.append(try item.run(language: language, weights: weights)) } catch { skipped += 1 }
        }
        return Report(outcomes, skipped: skipped)
    }

    /// The composer as the keyboard runs it in practice: two thumbs, no capitals (the
    /// words compared are lowercase), no autospace (the commits say when).
    public static var settings: Composer.Settings {
        var settings = Composer.Settings()
        settings.autoCapitalize = false
        settings.autospaceDelay = nil
        return settings
    }

    private enum Kind {
        case down(CGPoint), move(CGPoint), up(CGPoint), commit(String)
    }

    private struct Event {
        var time: TimeInterval
        var id: Int
        var kind: Kind
        /// At one instant: lifts, then landings, then commits, as the keyboard saw them.
        var order: Int {
            switch kind {
            case .up: 0
            case .move: 1
            case .down: 2
            case .commit: 3
            }
        }
    }

    private static func events(of recording: PracticeRecording, layout: Layout) -> [Event] {
        var events: [Event] = []
        for touch in recording.touches {
            let points = touch.points.filter { $0.count >= 3 }
            guard let first = points.first, let last = points.last else { continue }
            func point(_ p: [Double]) -> CGPoint { CGPoint(x: p[0] * layout.width, y: p[1] * layout.height) }
            events.append(Event(time: first[2], id: touch.id, kind: .down(point(first))))
            for p in points.dropFirst().dropLast() {
                events.append(Event(time: p[2], id: touch.id, kind: .move(point(p))))
            }
            // A touch with one point lifted where it landed, right after.
            events.append(Event(time: points.count == 1 ? last[2] + 0.001 : last[2], id: touch.id, kind: .up(point(last))))
        }
        for commit in recording.commits {
            events.append(Event(time: commit.t, id: 0, kind: .commit(commit.word)))
        }
        return events
    }

    // MARK: Report

    /// The numbers over many sessions, as `astrotype-tools replay` prints them.
    public struct Report: Sendable, Equatable {
        public var outcomes: [Outcome]
        public var skipped: Int

        public init(_ outcomes: [Outcome], skipped: Int = 0) {
            self.outcomes = outcomes
            self.skipped = skipped
        }

        public var wordCount: Int { outcomes.reduce(0) { $0 + $1.words.count } }
        public var firstGuesses: Int { outcomes.reduce(0) { $0 + $1.firstGuesses } }
        public var topThrees: Int { outcomes.reduce(0) { $0 + $1.topThrees } }
        public var firstGuessRate: Double { wordCount == 0 ? 0 : Double(firstGuesses) / Double(wordCount) }
        public var topThreeRate: Double { wordCount == 0 ? 0 : Double(topThrees) / Double(wordCount) }

        /// The misses, most frequent word first: "store → stare, stir" per expected word.
        public var missLines: [String] {
            var byWord: [String: [String]] = [:]
            for outcome in outcomes {
                for miss in outcome.misses { byWord[miss.expected, default: []].append(miss.guesses.first ?? "∅") }
            }
            let ordered = byWord.sorted { a, b in
                if a.value.count != b.value.count { return a.value.count > b.value.count }
                return a.key < b.key
            }
            return ordered.map { word, got in
                var counted: [String: Int] = [:]
                for guess in got { counted[guess, default: 0] += 1 }
                let parts = counted.sorted { a, b in
                    if a.value != b.value { return a.value > b.value }
                    return a.key < b.key
                }.map { entry -> String in
                    entry.value > 1 ? "\(entry.key) ×\(entry.value)" : entry.key
                }
                return "\(word) → " + parts.joined(separator: ", ")
            }
        }

        public var summary: String {
            func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
            var line = "\(outcomes.count) sessions · \(wordCount) words · first guess \(percent(firstGuessRate)) · top three \(percent(topThreeRate)) · \(wordCount - firstGuesses) misses"
            if skipped > 0 { line += " · \(skipped) skipped (no commit times)" }
            return line
        }
    }
}
