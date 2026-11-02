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
public struct SyntheticTyping: Sendable {
    public var layout: Layout
    /// How far each turn of a swipe misses its key's centre, in key widths (one
    /// standard deviation).
    public var noise: Double
    /// Each thumb's habit, in key widths and heights: the left thumb landing low and
    /// right, say.
    public var left: KeyOffset
    public var right: KeyOffset
    private var generator: SeededGenerator

    public init(layout: Layout, noise: Double, left: KeyOffset = .zero, right: KeyOffset = .zero, seed: UInt64) {
        self.layout = layout
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

    static let device = PracticeRecording.Device(model: "synthetic", system: "", app: "", writer: "synthetic")

    /// A standard normal draw (Box–Muller).
    private mutating func gaussian() -> Double {
        let u = max(Double.leastNonzeroMagnitude, Double.random(in: 0..<1, using: &generator))
        let v = Double.random(in: 0..<1, using: &generator)
        return sqrt(-2 * log(u)) * cos(2 * .pi * v)
    }
}
