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
        /// Each word is one swipe per thumb, both moving at once: each thumb reaches
        /// its letters when the word gets to them, about every 90 ms, `wobble` off.
        case together(wobble: TimeInterval)
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
            if thumbs != .one {
                time = typeWithTwoThumbs(word, at: time, id: &id, unit: unit, into: &recorder)
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
    private mutating func typeWithTwoThumbs(_ word: String, at start: TimeInterval, id: inout Int,
                                            unit: CGRect, into recorder: inout TouchRecorder) -> TimeInterval {
        if case .together(let wobble) = thumbs {
            return typeTogether(word, wobble: wobble, at: start, id: &id, unit: unit, into: &recorder)
        }
        guard case .two(let wobble) = thumbs else { return start }
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
            // in four, just after), but not sooner than 70 ms after it landed (about
            // 170 words a minute), give or take the wobble.
            var down = start
            if let previous {
                let overlap = -0.05 + 0.19 * Double.random(in: 0..<1, using: &generator)
                down = max(previous.start + 0.07, previous.end - overlap) + gaussian() * wobble
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

    /// One word with both thumbs swiping at once, from `start`; returns the last lift.
    private mutating func typeTogether(_ word: String, wobble: TimeInterval, at start: TimeInterval, id: inout Int,
                                       unit: CGRect, into recorder: inout TouchRecorder) -> TimeInterval {
        let letters = Array(word).filter { layout.frame(of: .letter($0)) != nil }
        var events: [(time: TimeInterval, phase: TouchRecorder.Phase, id: Int, point: CGPoint)] = []
        var lifted = start
        let end = start + 0.09 * Double(letters.count)
        // Each thumb's letters, one swipe each, but a letter again on the same key is a
        // new touch (a thumb does not swipe from a key to itself).
        var strokes: [(side: Side, letters: [Int])] = []
        for side in [Side.left, .right] {
            for i in letters.indices where layout.side(of: .letter(letters[i])) == side {
                if let last = strokes.last, last.side == side, letters[last.letters.last!] != letters[i] {
                    strokes[strokes.count - 1].letters.append(i)
                } else {
                    strokes.append((side, [i]))
                }
            }
        }
        for (stroke, (side, mine)) in strokes.enumerated() {
            // A stroke followed by another from the same thumb lifts right after its last letter.
            let followed = strokes.indices.contains(stroke + 1) && strokes[stroke + 1].side == side
            let habit = side == .left ? left : right
            var aims: [CGPoint] = []
            var reached: [TimeInterval] = []
            for i in mine {
                let frame = layout.frame(of: .letter(letters[i]))!
                var aim = CGPoint(x: frame.midX + (habit.dx + gaussian() * noise) * unit.width,
                                  y: frame.midY + (habit.dy + gaussian() * noise * 0.8) * unit.height)
                while layout.key(at: aim)?.character == nil {
                    aim = CGPoint(x: (aim.x + frame.midX) / 2, y: (aim.y + frame.midY) / 2)
                }
                aims.append(aim)
                // When the word gets to this letter, give or take; never before the last.
                reached.append(max(reached.last.map { $0 + 0.03 } ?? 0, start + 0.09 * Double(i) + gaussian() * wobble))
            }
            // The thumb waits on its last key until the word is done, then lifts.
            let lift = followed ? reached[reached.count - 1] + 0.05
                : max(reached[reached.count - 1] + 0.08, end + 0.1 * Double.random(in: 0..<1, using: &generator))
            if aims.count == 1 {
                events.append((reached[0], .began, id, aims[0]))
                events.append((reached[0] + 0.08, .ended, id, aims[0]))
                lifted = max(lifted, reached[0] + 0.08)
            } else {
                events.append((reached[0], .began, id, aims[0]))
                for k in 1..<aims.count {
                    let leg = Geometry.walk([aims[k - 1], aims[k]], step: 6).dropFirst()
                    for (j, point) in leg.enumerated() {
                        let t = reached[k - 1] + (reached[k] - reached[k - 1]) * Double(j + 1) / Double(leg.count)
                        events.append((t, .moved, id, point))
                    }
                }
                events.append((lift, .ended, id, aims[aims.count - 1]))
                lifted = max(lifted, lift)
            }
            id += 1
        }
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
