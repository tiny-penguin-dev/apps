import Foundation

/// Port of `ml/decode.py` `beam_search`: CTC prefix beam search that only
/// follows dictionary words, plus a word-frequency prior.
public struct WordDecoder: Sendable {
    public struct Candidate: Hashable, Sendable {
        public var word: String
        public var score: Double
    }

    public var lexicon: Lexicon
    public var beam = 24
    public var lmWeight = 0.35
    public var charPrune: Float = -8
    public var topK = 5

    public init(lexicon: Lexicon) {
        self.lexicon = lexicon
    }

    /// `logprobs` is `frames × 27` row by row (0 = CTC blank, 1...26 = a–z).
    public func decode(logprobs: [Float], frames: Int) -> [Candidate] {
        let classes = 27
        precondition(logprobs.count >= frames * classes)
        // A prefix is identified by its trie node, since each node has one path.
        var beams: [(node: Int32, pb: Double, pnb: Double)] = [(0, 0, -.infinity)]
        var next = [Int32: (pb: Double, pnb: Double)]()
        var order = [Int32]()
        for t in 0..<frames {
            let row = t * classes
            next.removeAll(keepingCapacity: true)
            order.removeAll(keepingCapacity: true)
            func update(_ node: Int32, _ change: (inout (pb: Double, pnb: Double)) -> Void) {
                if next[node] == nil {
                    next[node] = (-.infinity, -.infinity)
                    order.append(node)
                }
                change(&next[node]!)
            }
            for b in beams {
                let total = lse(b.pb, b.pnb)
                let blank = Double(logprobs[row])
                let last = Int(lexicon.label[Int(b.node)])
                update(b.node) { e in
                    e.pb = lse(e.pb, total + blank)
                    if b.node != 0 {
                        e.pnb = lse(e.pnb, b.pnb + Double(logprobs[row + last]))
                    }
                }
                let start = Int(lexicon.edgeStart[Int(b.node)])
                for i in start..<(start + Int(lexicon.edgeCount[Int(b.node)])) {
                    let k = Int(lexicon.edgeLabels[i])
                    let lp = logprobs[row + k]
                    guard lp > charPrune else { continue }
                    let child = lexicon.edgeTargets[i]
                    update(child) { e in
                        if b.node != 0 && last == k {
                            // A doubled letter needs a blank in between.
                            e.pnb = lse(e.pnb, b.pb + Double(lp))
                        } else {
                            e.pnb = lse(e.pnb, total + Double(lp))
                        }
                    }
                }
            }
            beams = order.map { (node: $0, pb: next[$0]!.pb, pnb: next[$0]!.pnb) }
            beams.sort { lse($0.pb, $0.pnb) > lse($1.pb, $1.pnb) }
            if beams.count > beam { beams.removeLast(beams.count - beam) }
        }
        var out = [Candidate]()
        for b in beams {
            let prior = lexicon.wordLogPrior[Int(b.node)]
            guard !prior.isNaN else { continue }
            let score = lse(b.pb, b.pnb) + lmWeight * Double(prior)
            guard score.isFinite else { continue }
            out.append(Candidate(word: lexicon.word(at: b.node), score: score))
        }
        out.sort { $0.score > $1.score }
        return Array(out.prefix(topK))
    }
}

@inline(__always)
func lse(_ a: Double, _ b: Double) -> Double {
    if a == -.infinity { return b }
    if b == -.infinity { return a }
    let m = max(a, b)
    return m + log(exp(a - m) + exp(b - m))
}
