import Foundation

/// Port of `ml/synth.py` `featurize`: one stroke → `[T, 5]` model input rows of
/// `[x - 0.5, y - 0.5, cos(dir), sin(dir), turn / π]`. Must match Python exactly;
/// `golden.json` checks it.
public enum Features {
    /// Resample spacing in box units.
    public static let step = 0.04
    public static let width = 5
    /// The Core ML model's shortest input.
    public static let minFrames = 16

    /// Returns the features flattened row by row (`count = T * 5`).
    public static func featurize(_ points: [StrokePoint], step: Double = step) -> [Float] {
        guard !points.isEmpty else { return [] }
        var p = resample(points.map { ($0.x, $0.y) }, step: step)
        if p.count < 3, let last = p.last {
            p.append((last.0 + 1e-3, last.1 + 1e-3))
            p.append((last.0 + 2e-3, last.1 + 2e-3))
        }
        let n = p.count
        var ang = [Double](repeating: 0, count: n)
        for i in 0..<(n - 1) {
            ang[i] = atan2(p[i + 1].1 - p[i].1, p[i + 1].0 - p[i].0)
        }
        ang[n - 1] = ang[n - 2]
        var out = [Float]()
        out.reserveCapacity(n * width)
        for i in 0..<n {
            var turn = i == 0 ? 0 : ang[i] - ang[i - 1]
            turn = floorMod(turn + .pi, 2 * .pi) - .pi
            out.append(Float(p[i].0 - 0.5))
            out.append(Float(p[i].1 - 0.5))
            out.append(Float(cos(ang[i])))
            out.append(Float(sin(ang[i])))
            out.append(Float(turn / .pi))
        }
        return out
    }

    /// Pads short inputs up to `minFrames` by repeating the last row with no
    /// turn, so the model always gets a valid length.
    public static func padded(_ features: [Float]) -> [Float] {
        let frames = features.count / width
        guard frames > 0, frames < minFrames else { return features }
        var out = features
        var last = Array(features[(frames - 1) * width..<frames * width])
        last[4] = 0
        for _ in frames..<minFrames { out += last }
        return out
    }

    /// Total path length in box units.
    public static func length(_ points: [StrokePoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    static func resample(_ path: [(Double, Double)], step: Double) -> [(Double, Double)] {
        var s = [0.0]
        s.reserveCapacity(path.count)
        for i in 1..<max(path.count, 1) {
            s.append(s[i - 1] + hypot(path[i].0 - path[i - 1].0, path[i].1 - path[i - 1].1))
        }
        let total = s[s.count - 1]
        if total < step { return [path[0], path[path.count - 1]] }
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
        return out
    }

    private static func floorMod(_ a: Double, _ b: Double) -> Double {
        a - b * (a / b).rounded(.down)
    }
}
