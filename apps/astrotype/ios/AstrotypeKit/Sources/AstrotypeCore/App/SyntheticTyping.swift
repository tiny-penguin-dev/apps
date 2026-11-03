import Foundation

/// Typing made up for the harness (features/smart-matching Phase D): words swiped
/// through their keys by a thumb that lands off-centre by a habit of its own and
/// wobbles, recorded as the app records a practice session. It stands in for real
/// sessions until enough are shared, so a change to the matcher can be measured on
/// thousands of words, and it is what `astrotype-tools synth` writes.
///
///     var typing = SyntheticTyping(layout: .qwerty(width: 390), noise: 0.2, seed: 1)
///     let recording = typing.record(["going", "to", "the", "store"])
///     try Replay.run(recording, language: english).firstGuessRate
///
/// With `thumbs` at `.two`, each word is typed as a person types with both thumbs: the
/// letters on each half of the keyboard go to that half's thumb, a run of them is one
/// swipe (one letter, or the same letter again, is a tap), and the next thumb lands
/// before the last one lifts, `wobble` off its turn, so fast touches land out of order.
public struct SyntheticTyping: Sendable {
    /// How the words are typed.
    public enum Thumbs: Sendable, Equatable {
        /// Each word is one swipe (or one tap).
        case one
        /// Each word is runs from both thumbs. `wobble` is how far each touch lands off
        /// its turn, in seconds (one standard deviation): 0 keeps them in order.
        case two(wobble: TimeInterval)
    }

    public var thumbs: Thumbs = .one
    public var layout: Layout
    /// How far each turn of a swipe misses its key's centre, in key widths (one
    /// standard deviation).
    public var noise: Double
    /// Each thumb's habit, in key widths and heights: the left thumb landing low and
    /// right, say.
    public var left: KeyOffset
    public var right: KeyOffset
    private var generator: SeededGenerator

    public init(layout: Layout, noise: Double, left: KeyOffset = .zero, right: KeyOffset = .zero, thumbs: Thumbs = .one, seed: UInt64) {
        self.layout = layout
        self.thumbs = thumbs
        self.noise = noise
        self.left = left
        self.right = right
        generator = SeededGenerator(seed: seed)
    }

    /// The words typed one after another, space after each, as one recording whose
    /// expected text is the words.
    public mutating func record(_ words: [String], kind: String = "synthetic", now: Date = Date(timeIntervalSince1970: 0)) -> PracticeRecording {
        var recorder = TouchRecorder(kind: kind, layoutWidth: layout.width, layoutHeight: layout.height, split: layout.split)
        guard let unit = layout.frame(of: .letter("q")) else {
            return recorder.recording(expected: "", device: Self.device, now: now)
        }
        var time = 1.0
        var id = 1
        for word in words {
            if case .two(let wobble) = thumbs {
                time = typeWithTwoThumbs(word, wobble: wobble, at: time, id: &id, unit: unit, into: &recorder)
                time += 0.25
                recorder.committed(word, time: time)
                time += 0.3
                continue
            }
            let letters = Array(word).filter { layout.frame(of: .letter($0)) != nil }
            guard let firstLetter = letters.first, let firstFrame = layout.frame(of: .letter(firstLetter)) else { continue }
            let side = layout.side(at: CGPoint(x: firstFrame.midX, y: firstFrame.midY))
            let habit = side == .left ? left : right
            // Each letter's aim: its centre, moved by the habit and a miss of its own.
            let aims = letters.map { letter -> CGPoint in
                let frame = layout.frame(of: .letter(letter))!
                return CGPoint(x: frame.midX + (habit.dx + gaussian() * noise) * unit.width,
                               y: frame.midY + (habit.dy + gaussian() * noise * 0.8) * unit.height)
            }
            let duration = 0.12 + 0.06 * Double(aims.count)
            let path = aims.count == 1 ? aims : Geometry.walk(aims, step: 6)
            for (i, point) in path.enumerated() {
                let t = time + duration * Double(i) / Double(max(1, path.count - 1))
                let phase: TouchRecorder.Phase = i == 0 ? .began : i == path.count - 1 ? .ended : .moved
                recorder.touch(phase, id: id, x: point.x, y: point.y, time: t)
            }
            if path.count == 1 { recorder.touch(.ended, id: id, x: path[0].x, y: path[0].y, time: time + 0.08) }
            time += duration + 0.25
            recorder.committed(word, time: time)
            time += 0.3
            id += 1
        }
        return recorder.recording(expected: words.joined(separator: " "), device: Self.device, now: now)
    }

    /// One word from both thumbs, from `start`; returns when the last touch lifts.
    private mutating func typeWithTwoThumbs(_ word: String, wobble: TimeInterval, at start: TimeInterval, id: inout Int,
                                            unit: CGRect, into recorder: inout TouchRecorder) -> TimeInterval {
        var runs: [(letters: [Character], side: Side)] = []
        for letter in word where layout.frame(of: .letter(letter)) != nil {
            let side = layout.side(of: .letter(letter))
            if let last = runs.last, last.side == side {
                runs[runs.count - 1].letters.append(letter)
            } else {
                runs.append(([letter], side))
            }
        }
        // The same letter again is tapped again, not swiped on the spot.
        runs = runs.flatMap { run in
            run.letters.count > 1 && Set(run.letters).count == 1 ? run.letters.map { ([$0], run.side) } : [run]
        }
        var events: [(time: TimeInterval, phase: TouchRecorder.Phase, id: Int, point: CGPoint)] = []
        var previous: (start: TimeInterval, end: TimeInterval)?
        var lifted = start
        for run in runs {
            let habit = run.side == .left ? left : right
            let aims = run.letters.map { letter -> CGPoint in
                let frame = layout.frame(of: .letter(letter))!
                var aim = CGPoint(x: frame.midX + (habit.dx + gaussian() * noise) * unit.width,
                                  y: frame.midY + (habit.dy + gaussian() * noise * 0.8) * unit.height)
                // A thumb that misses the letters altogether (space, shift, delete) is
                // another story: it lands on a letter, if not on the one it meant.
                while layout.key(at: aim)?.character == nil {
                    aim = CGPoint(x: (aim.x + frame.midX) / 2, y: (aim.y + frame.midY) / 2)
                }
                return aim
            }
            let duration = aims.count == 1 ? 0.08 : 0.12 + 0.06 * Double(aims.count)
            // The next thumb lands a little before the last one lifts (or, about one time
            // in four, just after), give or take the wobble.
            var down = start
            if let previous {
                let overlap = -0.05 + 0.19 * Double.random(in: 0..<1, using: &generator)
                down = max(previous.start + 0.02, previous.end - overlap) + gaussian() * wobble
            }
            let path = aims.count == 1 ? aims : Geometry.walk(aims, step: 6)
            for (i, point) in path.enumerated() {
                let t = down + duration * Double(i) / Double(max(1, path.count - 1))
                events.append((t, i == 0 ? .began : i == path.count - 1 ? .ended : .moved, id, point))
            }
            if path.count == 1 { events.append((down + duration, .ended, id, path[0])) }
            previous = (down, down + duration)
            lifted = max(lifted, down + duration)
            id += 1
        }
        // As the screen reports them: in time order, a touch's own events in theirs.
        events.sort { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
        for event in events {
            recorder.touch(event.phase, id: event.id, x: event.point.x, y: event.point.y, time: event.time)
        }
        return lifted
    }

    static let device = PracticeRecording.Device(model: "synthetic", system: "", app: "", writer: "synthetic")

    /// A standard normal draw (Box–Muller).
    private mutating func gaussian() -> Double {
        let u = max(Double.leastNonzeroMagnitude, Double.random(in: 0..<1, using: &generator))
        let v = Double.random(in: 0..<1, using: &generator)
        return sqrt(-2 * log(u)) * cos(2 * .pi * v)
    }
}
