import Foundation

/// Port of `ml/decode_phrase.py` `beam_search`: CTC prefix beam search over a
/// dictionary trie that can move from one word to the next.
///
/// The model's space is evidence, not a rule. A space after a dictionary word
/// commits it; a space inside a word can be ignored for a penalty ("televi" +
/// "sion" → "television"); and a word can end with no space for a penalty.
public struct PhraseDecoder: Sendable {
    public struct Candidate: Hashable, Sendable {
        public var text: String
        public var score: Double
        public var words: [String] { text.split(separator: " ").map(String.init) }
    }

    /// Model classes: 0 blank, 1...26 a–z, 27 space.
    public static let classes = 28
    static let space = 27

    public var lexicon: Lexicon
    public var beam = 32
    public var lmWeight = 0.5
    public var wordBonus = 0.5
    public var breakPenalty = -4.0
    public var swallowPenalty = -1.5
    public var charPrune: Float = -8
    public var topK = 5

    public init(lexicon: Lexicon) {
        self.lexicon = lexicon
    }

    /// Hypothesis tokens: letters 1...26, a committed space, a break without a
    /// space, or a space the decoder ignored.
    private static let breakToken: Int8 = -1
    private static let swallowToken: Int8 = -2

    /// Every prefix seen during one decode, as a tree: each prefix is an index.
    private struct Prefixes {
        var parent: [Int32] = [-1]
        var token: [Int8] = [0]
        /// The CTC label a repeat would continue (0 for none).
        var lastLabel: [Int8] = [0]
        var index: [Int64: Int32] = [:]

        mutating func child(_ p: Int32, _ tok: Int8) -> Int32 {
            let key = Int64(p) << 8 | Int64(UInt8(bitPattern: tok))
            if let c = index[key] { return c }
            let c = Int32(parent.count)
            parent.append(p)
            token.append(tok)
            switch tok {
            case PhraseDecoder.breakToken: lastLabel.append(lastLabel[Int(p)])
            case PhraseDecoder.swallowToken: lastLabel.append(Int8(PhraseDecoder.space))
            default: lastLabel.append(tok)
            }
            index[key] = c
            return c
        }

        func text(_ p: Int32) -> String {
            var bytes = [UInt8]()
            var n = p
            while n > 0 {
                let tok = token[Int(n)]
                if tok > 0 && tok < Int8(PhraseDecoder.space) {
                    bytes.append(UInt8(96 + Int(tok)))
                } else if tok == Int8(PhraseDecoder.space) || tok == PhraseDecoder.breakToken {
                    bytes.append(32)
                }
                n = parent[Int(n)]
            }
            let raw = String(decoding: bytes.reversed(), as: UTF8.self)
            return raw.split(separator: " ").joined(separator: " ")
        }
    }

    private struct Beam {
        var prefix: Int32
        var node: Int32
        var lm: Double
        var pb: Double
        var pnb: Double
        var order: Int
        var score: Double { lse(pb, pnb) + lm }
    }

    /// `logprobs` is `frames × 28` row by row. `partial` keeps hypotheses whose
    /// last word is unfinished, for live typing.
    public func decode(logprobs: [Float], frames: Int, partial: Bool = false) -> [Candidate] {
        let classes = Self.classes
        precondition(logprobs.count >= frames * classes)
        var prefixes = Prefixes()
        var beams = [Beam(prefix: 0, node: 0, lm: 0, pb: 0, pnb: -.infinity, order: 0)]
        var next = [Int32: Int]()
        var nextBeams = [Beam]()
        func wordScore(_ node: Int32) -> Double { lmWeight * Double(lexicon.wordLogPrior[Int(node)]) + wordBonus }
        func isWord(_ node: Int32) -> Bool { node != 0 && !lexicon.wordLogPrior[Int(node)].isNaN }

        for t in 0..<frames {
            let row = t * classes
            next.removeAll(keepingCapacity: true)
            nextBeams.removeAll(keepingCapacity: true)
            func add(_ prefix: Int32, _ node: Int32, _ lm: Double, nonBlank: Bool, _ p: Double) {
                let i: Int
                if let found = next[prefix] {
                    i = found
                } else {
                    i = nextBeams.count
                    next[prefix] = i
                    nextBeams.append(Beam(prefix: prefix, node: node, lm: lm, pb: -.infinity, pnb: -.infinity, order: i))
                }
                if nonBlank { nextBeams[i].pnb = lse(nextBeams[i].pnb, p) } else { nextBeams[i].pb = lse(nextBeams[i].pb, p) }
            }
            let spaceLP = Double(logprobs[row + Self.space])
            for b in beams {
                let total = lse(b.pb, b.pnb)
                let last = Int(prefixes.lastLabel[Int(b.prefix)])
                add(b.prefix, b.node, b.lm, nonBlank: false, total + Double(logprobs[row]))
                if last != 0 {
                    add(b.prefix, b.node, b.lm, nonBlank: true, b.pnb + Double(logprobs[row + last]))
                }
                // A letter in this word, or (no space seen) the first of a new word.
                let wordEnds = isWord(b.node)
                let breakPrefix = wordEnds ? prefixes.child(b.prefix, Self.breakToken) : -1
                let breakLM = wordEnds ? b.lm + wordScore(b.node) + breakPenalty : 0
                for k in 1..<Self.space {
                    let lp = logprobs[row + k]
                    guard lp > charPrune else { continue }
                    let src = (last == k ? b.pb : total) + Double(lp)
                    if let child = lexicon.child(of: b.node, label: k) {
                        add(prefixes.child(b.prefix, Int8(k)), child, b.lm, nonBlank: true, src)
                    }
                    if wordEnds, let child = lexicon.child(of: 0, label: k) {
                        add(prefixes.child(breakPrefix, Int8(k)), child, breakLM, nonBlank: true, src)
                    }
                }
                guard Float(spaceLP) > charPrune else { continue }
                let src = (last == Self.space ? b.pb : total) + spaceLP
                if wordEnds {
                    add(prefixes.child(b.prefix, Int8(Self.space)), 0, b.lm + wordScore(b.node), nonBlank: true, src)
                }
                if b.node != 0 {
                    add(prefixes.child(b.prefix, Self.swallowToken), b.node, b.lm + swallowPenalty, nonBlank: true, src)
                } else if last != Self.space {
                    add(prefixes.child(b.prefix, Self.swallowToken), b.node, b.lm, nonBlank: true, src)
                }
            }
            // Best first; ties keep the order they were found in, like Python's stable sort.
            nextBeams.sort { a, b in
                let sa = a.score, sb = b.score
                return sa != sb ? sa > sb : a.order < b.order
            }
            if nextBeams.count > beam { nextBeams.removeLast(nextBeams.count - beam) }
            beams = nextBeams
            for i in beams.indices { beams[i].order = i }
        }

        // Complete phrases; if none survived (the writing stopped mid-word),
        // the unfinished ones, so there is always a reading.
        var best = [String: Double]()
        var unfinished = [String: Double]()
        for b in beams {
            var s = b.score
            var complete = true
            if b.node != 0 {
                if isWord(b.node) {
                    s += wordScore(b.node)
                } else if !partial {
                    complete = false
                }
            }
            let text = prefixes.text(b.prefix)
            guard !text.isEmpty, s.isFinite else { continue }
            if complete {
                if s > best[text] ?? -.infinity { best[text] = s }
            } else if s > unfinished[text] ?? -.infinity {
                unfinished[text] = s
            }
        }
        let out = (best.isEmpty ? unfinished : best)
            .map { Candidate(text: $0.key, score: $0.value) }.sorted { $0.score > $1.score }
        return Array(out.prefix(topK))
    }
}

extension PhraseDecoder {
    /// Argmax letters with repeats and blanks collapsed, and the first frame
    /// of each space that made it into the text.
    public static func greedy(_ logprobs: [Float], frames: Int) -> (String, [Int]) {
        let classes = Self.classes
        var bytes = [UInt8]()
        var spaces = [Int]()
        var previous = 0
        for t in 0..<frames {
            let row = logprobs[(t * classes)..<(t * classes + classes)]
            let best = row.indices.max { row[$0] < row[$1] }! - t * classes
            if best != 0 && best != previous {
                if best == Self.space {
                    if !bytes.isEmpty && bytes.last != 32 {
                        bytes.append(32)
                        spaces.append(t)
                    }
                } else {
                    bytes.append(UInt8(96 + best))
                }
            }
            previous = best
        }
        if bytes.last == 32 {
            bytes.removeLast()
            spaces.removeLast()
        }
        return (String(decoding: bytes, as: UTF8.self), spaces)
    }

    /// The stroke whose first row is nearest `row`: a space shows up where
    /// the finger lifted before the next word.
    public static func stroke(atRow row: Int, starts: [Int]) -> Int {
        guard starts.count > 1 else { return 0 }
        return (1..<starts.count).min { abs(starts[$0] - row) < abs(starts[$1] - row) }!
    }
}

@inline(__always)
func lse(_ a: Double, _ b: Double) -> Double {
    if a == -.infinity { return b }
    if b == -.infinity { return a }
    let m = max(a, b)
    return m + log(exp(a - m) + exp(b - m))
}
