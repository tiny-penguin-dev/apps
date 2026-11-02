import Foundation

/// The decoder's dictionary as a compact trie in flat arrays (no per-node
/// objects), so it stays small enough for a keyboard extension.
/// Node 0 is the root. Letters are 1...26 for a–z, matching the model's classes.
public struct Lexicon: Sendable {
    public struct Entry: Sendable {
        public var word: String
        public var frequency: Double
    }

    /// For each node: where its edges start in `edgeLabels`/`edgeTargets`, and how many.
    var edgeStart: [Int32] = []
    var edgeCount: [UInt8] = []
    var edgeLabels: [UInt8] = []
    var edgeTargets: [Int32] = []
    /// For each node: its parent, the letter that leads to it, and the word prior
    /// `log(freq / maxFreq)` when a word ends here (NaN otherwise).
    var parent: [Int32] = []
    var label: [UInt8] = []
    var wordLogPrior: [Float] = []
    /// For each node: the best word prior at or below it, for ranking completions.
    var bestBelow: [Float] = []
    /// Added to a word's log prior gives `log P(word)` over the whole dictionary:
    /// `log(maxFreq / sum of frequencies)`.
    public private(set) var logProbabilityOffset: Float = 0

    public var nodeCount: Int { parent.count }

    /// Reads `lexicon.tsv` (`word<TAB>frequency` per line).
    public static func readEntries(from url: URL) throws -> [Entry] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var entries = [Entry]()
        entries.reserveCapacity(40_000)
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let freq = Double(parts[1]) else { continue }
            entries.append(Entry(word: String(parts[0]), frequency: freq))
        }
        return entries
    }

    public init(contentsOf url: URL) throws {
        self.init(entries: try Self.readEntries(from: url))
    }

    /// The 40,000-word English dictionary that ships in the package
    /// (`Language.bundled("en").lexicon`).
    public static func bundled() throws -> Lexicon {
        try Lexicon(contentsOf: Language.resource("lexicon", "tsv", language: "en"))
    }

    public init(entries: [Entry]) {
        let maxFreq = entries.map(\.frequency).max() ?? 1
        let sum = entries.reduce(0) { $0 + $1.frequency }
        logProbabilityOffset = sum > 0 ? Float(log(maxFreq / sum)) : 0
        // Build with per-node child lists first, then flatten.
        var children: [[(UInt8, Int32)]] = [[]]
        parent = [-1]
        label = [0]
        wordLogPrior = [.nan]
        for entry in entries {
            var node: Int32 = 0
            var valid = true
            for byte in entry.word.utf8 {
                guard byte >= 97, byte <= 122 else { valid = false; break }
                let k = byte - 96
                if let next = children[Int(node)].first(where: { $0.0 == k })?.1 {
                    node = next
                } else {
                    let next = Int32(children.count)
                    children.append([])
                    parent.append(node)
                    label.append(k)
                    wordLogPrior.append(.nan)
                    children[Int(node)].append((k, next))
                    node = next
                }
            }
            if valid, node != 0 {
                wordLogPrior[Int(node)] = Float(log(entry.frequency / maxFreq))
            }
        }
        edgeStart.reserveCapacity(children.count)
        edgeCount.reserveCapacity(children.count)
        for list in children {
            edgeStart.append(Int32(edgeLabels.count))
            edgeCount.append(UInt8(list.count))
            for (k, target) in list.sorted(by: { $0.0 < $1.0 }) {
                edgeLabels.append(k)
                edgeTargets.append(target)
            }
        }
        // Children are created after their parents, so a reverse pass sees every
        // child's best before its parent's.
        bestBelow = [Float](repeating: -.infinity, count: parent.count)
        for node in stride(from: parent.count - 1, through: 0, by: -1) {
            var best = wordLogPrior[node].isNaN ? -Float.infinity : wordLogPrior[node]
            let start = Int(edgeStart[node])
            for i in start..<(start + Int(edgeCount[node])) {
                best = max(best, bestBelow[Int(edgeTargets[i])])
            }
            bestBelow[node] = best
        }
    }

    /// Spells the word that ends at `node`.
    public func word(at node: Int32) -> String {
        var bytes = [UInt8]()
        var n = node
        while n > 0 {
            bytes.append(label[Int(n)] + 96)
            n = parent[Int(n)]
        }
        return String(decoding: bytes.reversed(), as: UTF8.self)
    }

    /// The node reached by spelling `word`, if it's a path in the trie.
    public func node(for word: String) -> Int32? {
        var node: Int32 = 0
        for byte in word.utf8 {
            let k = byte &- 96
            let start = Int(edgeStart[Int(node)])
            let end = start + Int(edgeCount[Int(node)])
            guard let i = (start..<end).first(where: { edgeLabels[$0] == k }) else { return nil }
            node = edgeTargets[i]
        }
        return node
    }

    /// The node one letter (1...26) below `node`, if any.
    @inline(__always)
    func child(of node: Int32, label k: Int) -> Int32? {
        let start = Int(edgeStart[Int(node)])
        for i in start..<(start + Int(edgeCount[Int(node)])) where Int(edgeLabels[i]) == k {
            return edgeTargets[i]
        }
        return nil
    }

    public func contains(_ word: String) -> Bool {
        guard let n = node(for: word) else { return false }
        return !wordLogPrior[Int(n)].isNaN
    }

    /// `log(frequency / max frequency)` of the word ending at `node`, nil if none does.
    public func logPrior(at node: Int32) -> Float? {
        let p = wordLogPrior[Int(node)]
        return p.isNaN ? nil : p
    }

    public func logPrior(of word: String) -> Float? {
        node(for: word).flatMap { logPrior(at: $0) }
    }

    /// Calls `body` for each child of `node` with its letter (1...26) and node.
    @inline(__always)
    func forEachChild(of node: Int32, _ body: (Int, Int32) -> Void) {
        let start = Int(edgeStart[Int(node)])
        for i in start..<(start + Int(edgeCount[Int(node)])) {
            body(Int(edgeLabels[i]), edgeTargets[i])
        }
    }

    /// The most common words that start with `prefix` and are longer than it, best
    /// first. Best-first search guided by `bestBelow`, so it touches few nodes.
    public func completions(of prefix: String, limit: Int) -> [String] {
        guard limit > 0, let start = node(for: prefix) else { return [] }
        var frontier: [(node: Int32, best: Float)] = []
        forEachChild(of: start) { _, child in frontier.append((child, bestBelow[Int(child)])) }
        var out: [String] = []
        var visited = 0
        while out.count < limit, !frontier.isEmpty, visited < 4000 {
            var bestIndex = 0
            for i in 1..<frontier.count where frontier[i].best > frontier[bestIndex].best { bestIndex = i }
            let (node, _) = frontier.remove(at: bestIndex)
            visited += 1
            if let prior = logPrior(at: node), prior == bestBelow[Int(node)] {
                out.append(word(at: node))
            }
            forEachChild(of: node) { _, child in
                if bestBelow[Int(child)] > -.infinity { frontier.append((child, bestBelow[Int(child)])) }
            }
        }
        return out
    }
}
