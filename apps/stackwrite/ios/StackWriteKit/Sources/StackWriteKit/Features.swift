import Foundation

/// Port of `ml/phrases.py` `featurize_strokes`: strokes → `[T, 9]` model input.
/// Must match Python exactly; `golden.json` checks it.
///
/// Per point: `x - 0.5, y - 0.5, cos(dir), sin(dir), turn / π` within its
/// stroke, then a stroke-start flag, the lift before the stroke
/// (`log1p(seconds / 0.25)`), the same lift relative to this writer's usual
/// lift, and `log(stroke length + 0.01)`.
public enum Features {
    /// Resample spacing in box units.
    public static let step = 0.04
    public static let width = 9
    /// The Core ML model's shortest input.
    public static let minFrames = 16

    public struct Output: Sendable {
        /// Rows flattened (`count = rows * width`).
        public var values: [Float]
        /// The first row of each stroke.
        public var strokeStarts: [Int]
        public var rows: Int { values.count / Features.width }
    }

    /// `liftScale` is the writer's usual lift between letters in seconds;
    /// nil measures it from these strokes.
    public static func featurize(_ strokes: [[StrokePoint]], liftScale: Double? = nil, step: Double = step) -> Output {
        let strokes = strokes.filter { !$0.isEmpty }
        let scale = liftScale ?? writerLiftScale(lifts(strokes))
        var out = Output(values: [], strokeStarts: [])
        var previousEnd: Double?
        for stroke in strokes {
            let (p, length) = resample(stroke.map { ($0.x, $0.y) }, step: step)
            let n = p.count
            var ang = [Double](repeating: 0, count: n)
            if n > 1 {
                for i in 0..<(n - 1) { ang[i] = atan2(p[i + 1].1 - p[i].1, p[i + 1].0 - p[i].0) }
                ang[n - 1] = ang[n - 2]
            }
            let moving = n > 1 ? 1.0 : 0.0
            var lift = 0.0, hasLift = false
            if let previousEnd {
                lift = max(0, stroke[0].t - previousEnd)
                hasLift = true
            }
            let logLength = Float(log(length + 0.01))
            out.strokeStarts.append(out.rows)
            for i in 0..<n {
                var turn = i == 0 ? 0 : ang[i] - ang[i - 1]
                turn = floorMod(turn + .pi, 2 * .pi) - .pi
                out.values.append(Float(p[i].0 - 0.5))
                out.values.append(Float(p[i].1 - 0.5))
                out.values.append(Float(cos(ang[i]) * moving))
                out.values.append(Float(sin(ang[i]) * moving))
                out.values.append(Float(turn / .pi))
                out.values.append(i == 0 ? 1 : 0)
                out.values.append(i == 0 && hasLift ? Float(log1p(lift / 0.25)) : 0)
                out.values.append(i == 0 && hasLift ? Float(log1p(lift / scale)) : 0)
                out.values.append(logLength)
            }
            previousEnd = stroke[stroke.count - 1].t
        }
        return out
    }

    /// Seconds the finger was up before each stroke after the first.
    public static func lifts(_ strokes: [[StrokePoint]]) -> [Double] {
        let strokes = strokes.filter { !$0.isEmpty }
        return zip(strokes, strokes.dropFirst()).map { $1[0].t - $0[$0.count - 1].t }
    }

    /// The writer's usual lift between letters: the median of the shorter half
    /// of lifts (word breaks and pauses are the long ones).
    public static func writerLiftScale(_ lifts: [Double], default fallback: Double = 0.2) -> Double {
        let sorted = lifts.filter { $0 > 0 }.sorted()
        guard sorted.count >= 4 else { return fallback }
        let half = Array(sorted.prefix(max(2, sorted.count / 2)))
        let m = half.count
        let median = m % 2 == 1 ? half[m / 2] : (half[m / 2 - 1] + half[m / 2]) / 2
        return min(max(median, 0.05), 1.0)
    }

    /// Pads short inputs up to `minFrames` with copies of the last row that
    /// add nothing new: no turn, no stroke start, no lift.
    public static func padded(_ features: [Float]) -> [Float] {
        let frames = features.count / width
        guard frames > 0, frames < minFrames else { return features }
        var out = features
        var last = Array(features[(frames - 1) * width..<frames * width])
        last[4] = 0; last[5] = 0; last[6] = 0; last[7] = 0
        for _ in frames..<minFrames { out += last }
        return out
    }

    /// Total path length in box units.
    public static func length(_ points: [StrokePoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// Points every `step` along the path, and the path's length. Shorter than
    /// one step (a tap): its first and last point, or one point if it didn't move.
    static func resample(_ path: [(Double, Double)], step: Double) -> ([(Double, Double)], Double) {
        var s = [0.0]
        s.reserveCapacity(path.count)
        for i in 1..<max(path.count, 1) {
            s.append(s[i - 1] + hypot(path[i].0 - path[i - 1].0, path[i].1 - path[i - 1].1))
        }
        let total = s[s.count - 1]
        if total < step {
            return (total > 1e-4 ? [path[0], path[path.count - 1]] : [path[0]], total)
        }
        // Same as numpy: arange(0, total, step) has ceil(total / step) values.
        let count = Int((total / step).rounded(.up))
        var out = [(Double, Double)]()
        out.reserveCapacity(count)
        var j = 0
        for k in 0..<count {
            let t = Double(k) * step
            // np.interp: the last j with s[j] <= t.
            while j + 1 < s.count && s[j + 1] <= t { j += 1 }
            if j >= s.count - 1 {
                out.append(path[path.count - 1])
            } else {
                let f = (t - s[j]) / (s[j + 1] - s[j])
                out.append((path[j].0 + f * (path[j + 1].0 - path[j].0),
                            path[j].1 + f * (path[j + 1].1 - path[j].1)))
            }
        }
        return (out, total)
    }

    private static func floorMod(_ a: Double, _ b: Double) -> Double {
        a - b * (a / b).rounded(.down)
    }
}
