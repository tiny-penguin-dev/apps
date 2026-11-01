import Foundation
import Testing
@testable import StackWriteCore

/// Synthetic touches for the engine's tests: straight swipes through key centres and
/// taps on them, on the phone layout. Recorded fixtures replace these as they come in.
enum Synth {
    static let layout = Layout.qwerty(width: 390)
    static let lexicon: Lexicon = {
        do { return try Lexicon.bundled() } catch { fatalError("lexicon.tsv missing from the package: \(error)") }
    }()

    static func composer(autoCapitalize: Bool = false) -> Composer {
        var settings = Composer.Settings()
        settings.autoCapitalize = autoCapitalize
        return Composer(dictionary: lexicon, layout: layout, settings: settings)
    }

    static func center(_ letter: Character) -> CGPoint {
        let frame = layout.frame(of: .letter(letter))!
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// The path of a swipe that goes straight from key centre to key centre.
    static func path(_ letters: String, step: CGFloat = 6) -> [CGPoint] {
        Geometry.walk(letters.map(center), step: step)
    }

    /// Swipes `letters` with one finger, over 0.3 s from `time`.
    @discardableResult
    static func swipe(_ composer: inout Composer, _ letters: String, id: Int = 1, at time: TimeInterval = 0) -> [Composer.Effect] {
        let points = path(letters)
        var effects = composer.touchDown(id: id, at: points[0], time: time)
        for (i, point) in points.enumerated().dropFirst() {
            effects += composer.touchMoved(id: id, to: point, time: time + 0.3 * Double(i) / Double(points.count))
        }
        effects += composer.touchUp(id: id, at: points[points.count - 1], time: time + 0.3)
        return effects
    }

    /// Taps a key, 80 ms long.
    @discardableResult
    static func tap(_ composer: inout Composer, _ letter: Character, id: Int = 1, at time: TimeInterval = 0) -> [Composer.Effect] {
        let point = center(letter)
        return composer.touchDown(id: id, at: point, time: time) + composer.touchUp(id: id, at: point, time: time + 0.08)
    }

    /// Taps each letter in turn, 150 ms apart from `time`; returns when the last lifted.
    @discardableResult
    static func taps(_ composer: inout Composer, _ letters: String, at time: TimeInterval = 0) -> TimeInterval {
        var t = time
        for letter in letters {
            tap(&composer, letter, at: t)
            t += 0.15
        }
        return t - 0.15 + 0.08
    }

    /// One thumb's touch in a two-thumb script: a tap (one letter) or a straight swipe,
    /// down at `start` and lifted at `end`.
    struct Stroke {
        var letters: String
        var id: Int
        var start: TimeInterval
        var end: TimeInterval

        static func tap(_ letter: Character, id: Int, at time: TimeInterval) -> Stroke {
            Stroke(letters: String(letter), id: id, start: time, end: time + 0.08)
        }

        static func swipe(_ letters: String, id: Int, from start: TimeInterval, to end: TimeInterval) -> Stroke {
            Stroke(letters: letters, id: id, start: start, end: end)
        }
    }

    /// Plays strokes from both thumbs as the keyboard would see them: every touch event
    /// in time order, with the strokes overlapping as their times say.
    @discardableResult
    static func play(_ composer: inout Composer, _ strokes: [Stroke]) -> [Composer.Effect] {
        enum Kind: Int { case down, move, up }
        var events: [(time: TimeInterval, kind: Kind, id: Int, point: CGPoint)] = []
        for stroke in strokes {
            let points = stroke.letters.count == 1 ? [center(stroke.letters.first!)] : path(stroke.letters)
            events.append((time: stroke.start, kind: .down, id: stroke.id, point: points[0]))
            for (i, point) in points.enumerated().dropFirst() {
                events.append((time: stroke.start + (stroke.end - stroke.start) * Double(i) / Double(points.count - 1), kind: .move, id: stroke.id, point: point))
            }
            events.append((time: stroke.end, kind: .up, id: stroke.id, point: points[points.count - 1]))
        }
        events.sort { $0.time == $1.time ? $0.kind.rawValue < $1.kind.rawValue : $0.time < $1.time }
        var effects: [Composer.Effect] = []
        for event in events {
            switch event.kind {
            case .down: effects += composer.touchDown(id: event.id, at: event.point, time: event.time)
            case .move: effects += composer.touchMoved(id: event.id, to: event.point, time: event.time)
            case .up: effects += composer.touchUp(id: event.id, at: event.point, time: event.time)
            }
        }
        return effects
    }

    struct Fixture: Decodable {
        var word: String
        /// The keys the finger goes through (a doubled letter is crossed once).
        var swipe: String
    }

    static let fixtures: [Fixture] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/swipes.json")
        return try! JSONDecoder().decode([Fixture].self, from: try! Data(contentsOf: url))
    }()
}
