import Foundation
import StackWriteKit

/// Picks words to write, weighted toward common words but with a long tail,
/// the same weighting the synthetic training data uses (`freq ^ 0.3`).
struct PromptGenerator {
    private let words: [String]
    private let cumulative: [Double]

    init(entries: [Lexicon.Entry], limit: Int = 20_000) {
        let top = entries.prefix(limit)
        words = top.map(\.word)
        var total = 0.0
        cumulative = top.map { total += pow($0.frequency, 0.3); return total }
    }

    var isEmpty: Bool { words.isEmpty }

    func word<R: RandomNumberGenerator>(using rng: inout R) -> String {
        let r = Double.random(in: 0..<(cumulative.last ?? 1), using: &rng)
        var lo = 0, hi = cumulative.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= r { lo = mid + 1 } else { hi = mid }
        }
        return words[lo]
    }

    /// A short "phrase" of distinct words.
    func phrase(count: Int = 5) -> [String] {
        guard !isEmpty else { return [] }
        var rng = SystemRandomNumberGenerator()
        var out = [String]()
        while out.count < count {
            let w = word(using: &rng)
            if !out.contains(w) { out.append(w) }
        }
        return out
    }
}
