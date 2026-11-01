import Foundation

/// Path arithmetic for the matcher: resampling by arc length and dynamic time warping.
enum Geometry {
    /// `count` points spread evenly along the polyline. A single point repeats.
    static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard count > 0, let first = points.first else { return [] }
        guard points.count > 1 else { return Array(repeating: first, count: count) }
        var lengths: [CGFloat] = [0]
        for i in 1..<points.count {
            lengths.append(lengths[i - 1] + distance(points[i - 1], points[i]))
        }
        let total = lengths[lengths.count - 1]
        guard total > 0 else { return Array(repeating: first, count: count) }
        var out: [CGPoint] = []
        out.reserveCapacity(count)
        var segment = 1
        for n in 0..<count {
            let target = total * CGFloat(n) / CGFloat(count - 1)
            while segment < points.count - 1, lengths[segment] < target { segment += 1 }
            let a = points[segment - 1], b = points[segment]
            let span = lengths[segment] - lengths[segment - 1]
            let t = span > 0 ? (target - lengths[segment - 1]) / span : 0
            out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return out
    }

    /// Dynamic time warping distance between two paths of the same length, with a
    /// Sakoe-Chiba band, averaged per point so paths of different lengths compare.
    static func dtw(_ a: [CGPoint], _ b: [CGPoint], band: Int = 6) -> CGFloat {
        let n = a.count, m = b.count
        guard n > 0, m > 0 else { return .infinity }
        let inf = CGFloat.greatestFiniteMagnitude
        var prev = [CGFloat](repeating: inf, count: m + 1)
        var cur = [CGFloat](repeating: inf, count: m + 1)
        prev[0] = 0
        for i in 1...n {
            cur = [CGFloat](repeating: inf, count: m + 1)
            let lo = max(1, i - band), hi = min(m, i + band)
            if lo > hi { continue }
            for j in lo...hi {
                let cost = distance(a[i - 1], b[j - 1])
                cur[j] = cost + min(prev[j], prev[j - 1], cur[j - 1])
            }
            prev = cur
        }
        return prev[m] / CGFloat(max(n, m))
    }

    /// The length of a polyline.
    static func length(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<points.count { total += distance(points[i - 1], points[i]) }
        return total
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Points every `step` along a polyline, for finding the keys a swipe crossed.
    static func walk(_ points: [CGPoint], step: CGFloat) -> [CGPoint] {
        guard points.count > 1 else { return points }
        var out: [CGPoint] = [points[0]]
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let d = distance(a, b)
            let n = max(1, Int(d / step))
            for k in 1...n {
                let t = CGFloat(k) / CGFloat(n)
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return out
    }
}
