import Foundation

// MARK: Both thumbs at once

/// Two thumbs that swipe at the same time (the right thumb g-i-l while the left swipes
/// r-s, for "girls"; Gabriel's own recordings, 3 Nov 2026): the word's letters come
/// from both swipes in the order the fingers reached their keys, not one swipe after
/// the other. A finger may arrive at a key early and wait there (the left thumb on the
/// "d" of "find" while the right swipes i-n), so a key counts from when the finger
/// reached it until it moved on, give or take `swapWindow`.
extension Matcher {
    /// When the finger reached each key the piece crossed, and when it moved on to the
    /// next (the last key's is the lift). Without the point times, spread evenly.
    func keyTimes(of piece: Piece) -> (arrive: [TimeInterval], depart: [TimeInterval]) {
        let count = piece.keys.count
        guard count > 0 else { return ([], []) }
        var arrive: [TimeInterval] = []
        if !piece.isTap, piece.times.count == piece.points.count, piece.points.count > 1 {
            // The same 4 pt walk the keys came from, with a time for each step.
            var current: Character?
            func visit(_ point: CGPoint, _ time: TimeInterval) {
                guard arrive.count < count, let letter = layout.key(at: point)?.character, letter != current else { return }
                current = letter
                if letter == piece.keys[arrive.count] { arrive.append(time) }
            }
            visit(piece.points[0], piece.times[0])
            for i in 1..<piece.points.count {
                let a = piece.points[i - 1], b = piece.points[i]
                let n = max(1, Int(Geometry.distance(a, b) / 4))
                for k in 1...n {
                    let t = CGFloat(k) / CGFloat(n)
                    visit(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                          piece.times[i - 1] + (piece.times[i] - piece.times[i - 1]) * Double(t))
                }
            }
        }
        if arrive.count != count {
            let span = piece.end - piece.start
            arrive = (0..<count).map { piece.start + span * Double($0) / Double(max(1, count)) }
        }
        // A tap counts when it landed; a swipe's key until the finger reached the next,
        // and its last key until the lift (a thumb may wait there for the other).
        guard !piece.isTap else { return (arrive, arrive) }
        let depart = (0..<count).map { $0 + 1 < count ? arrive[$0 + 1] : max(piece.end, arrive[$0]) }
        return (arrive, depart)
    }

    /// Whether any piece landed while an earlier one was still down.
    static func overlap(_ pieces: [Piece]) -> Bool {
        var lifted = -TimeInterval.infinity
        for piece in pieces.sorted(by: { $0.start < $1.start }) {
            if piece.start < lifted { return true }
            lifted = max(lifted, piece.end)
        }
        return false
    }

    private struct TogetherState: Hashable {
        var node: Int32
        /// Per piece (8 bits each), how many of its keys are behind the word: one more
        /// than the last key taken, 0 for none yet.
        var taken: UInt64
        var lastPiece: Int8
        var doubled: Bool
        /// The trie label of the last letter taken (its key's own, or a neighbour's).
        var letter: UInt8
    }

    /// The words in `lexicon` that all the pieces spell together, each piece giving its
    /// letters in its own order (starting on its first key, ending on its last), the
    /// pieces' letters woven by time: a key can come next only if the finger had not
    /// moved on from it (less `swapWindow`) before the last letter's key was reached.
    func together(_ pieces: [Piece], in lexicon: Lexicon, prior fixedPrior: ((String) -> Float)?) -> [String: Double] {
        let n = pieces.count
        guard n > 1, n <= 8, pieces.allSatisfy({ !$0.keys.isEmpty && $0.keys.count < 255 }) else { return [:] }
        let slack = swapWindow
        let times = pieces.map(keyTimes(of:))
        let counts = pieces.map(\.keys.count)
        // Per piece and trie label, the keys that may give it and whether as a stand-in.
        let options: [[[Int]]] = pieces.map { piece in
            let near = nearKeys(of: piece)
            return piece.keys.indices.map { j in
                ([piece.keys[j]] + (near.indices.contains(j) ? near[j] : [])).map(Self.index(of:))
            }
        }
        let keysFor: [[[(key: Int, standIn: Bool)]]] = options.map { piece in
            var out = Array(repeating: [(key: Int, standIn: Bool)](), count: 27)
            for (j, labels) in piece.enumerated() {
                for (k, label) in labels.enumerated() { out[label].append((j, k > 0)) }
            }
            return out
        }
        func taken(_ packed: UInt64, _ p: Int) -> Int { Int((packed >> (8 * UInt64(p))) & 0xFF) }
        func setting(_ packed: UInt64, _ p: Int, _ value: Int) -> UInt64 {
            (packed & ~(0xFF << (8 * UInt64(p)))) | (UInt64(value) << (8 * UInt64(p)))
        }
        let done: UInt64 = (0..<n).reduce(0) { setting($0, $1, counts[$1]) }

        struct Entry {
            var state: TogetherState
            var parent: Int32
            var piece: Int8
            var standIns: Int
            /// How long after the fingers had moved on from them the letters were taken,
            /// added up: a word read against the order the keys were reached pays for it.
            var late: TimeInterval = 0
        }
        var queue = [Entry(state: TogetherState(node: 0, taken: 0, lastPiece: -1, doubled: false, letter: 0), parent: -1, piece: -1, standIns: 0)]
        queue.reserveCapacity(4096)
        var cheapest: [TogetherState: Double] = [:]
        var best: [String: Double] = [:]
        var scored: [String: [([Int8], Double)]] = [:]
        var expanded = 0
        var index = 0
        while index < queue.count, expanded < budget {
            let entry = queue[index]
            let state = entry.state
            index += 1
            // A state reached again more cheaply is searched again.
            let cost = nearPenalty * Double(entry.standIns) + latePenalty * entry.late / max(slack, 0.01)
            if let cheapest = cheapest[state], cheapest <= cost { continue }
            cheapest[state] = cost
            expanded += 1

            // Every piece used up: a word if the trie says so (and a doubled last letter
            // may still follow, as in "coffee").
            if state.taken == done, let own = lexicon.logPrior(at: state.node) {
                // Which piece gave each letter, back along the parents.
                var owners: [Int8] = []
                var at = index - 1
                while queue[at].parent >= 0 {
                    owners.append(queue[at].piece)
                    at = Int(queue[at].parent)
                }
                owners.reverse()
                let word = lexicon.word(at: state.node)
                let path: Double
                if let known = scored[word]?.first(where: { $0.0 == owners })?.1 {
                    path = known
                } else {
                    let letters = Array(word)
                    var swipes: [(points: [CGPoint], letters: [Character])] = []
                    var taps: [(point: CGPoint, letter: Character)] = []
                    for (p, piece) in pieces.enumerated() {
                        let mine = owners.indices.filter { owners[$0] == Int8(p) }.map { letters[$0] }
                        if piece.isTap {
                            if let point = piece.points.first, let letter = mine.first { taps.append((point, letter)) }
                        } else {
                            swipes.append((piece.points, mine))
                        }
                    }
                    path = score(word: word, prior: fixedPrior?(word) ?? own, swipes: swipes, taps: taps)
                    scored[word, default: []].append((owners, path))
                }
                let value = path - nearPenalty * Double(entry.standIns) - latePenalty * entry.late / max(slack, 0.01)
                best[word] = max(best[word] ?? -.infinity, value)
            }

            // The time the word has reached: the latest key taken from any piece.
            var clock = -TimeInterval.infinity
            for p in 0..<n {
                let t = taken(state.taken, p)
                if t > 0 { clock = max(clock, times[p].arrive[t - 1]) }
            }
            // A second letter from the key just taken (a doubled letter, or the key and a
            // neighbour it brushed), as the one-piece search allows.
            if state.lastPiece >= 0, !state.doubled, !pieces[Int(state.lastPiece)].isTap {
                let p = Int(state.lastPiece)
                let here = options[p][taken(state.taken, p) - 1]
                for k in -1..<here.count {
                    let label = k < 0 ? Int(state.letter) : here[k]
                    guard k < 0 || label != Int(state.letter), let child = lexicon.child(of: state.node, label: label) else { continue }
                    let extra = (label == Int(state.letter) || label == here[0]) ? 0 : 1
                    queue.append(Entry(state: TogetherState(node: child, taken: state.taken, lastPiece: state.lastPiece, doubled: true, letter: UInt8(label)),
                                       parent: Int32(index - 1), piece: state.lastPiece, standIns: entry.standIns + extra, late: entry.late))
                }
            }
            for edge in lexicon.edges(of: state.node) {
                let label = lexicon.edgeLabel(edge)
                let child = lexicon.edgeTarget(edge)
                for p in 0..<n {
                    let t = taken(state.taken, p)
                    guard t < counts[p] else { continue }
                    for way in keysFor[p][label] {
                        // A piece's first letter is its first key; later ones any key after the last.
                        let late = clock - times[p].depart[way.key]
                        guard t == 0 ? way.key == 0 : way.key >= t, late <= slack else { continue }
                        let now = max(clock, times[p].arrive[way.key])
                        let next = setting(state.taken, p, way.key + 1)
                        // Every other piece must still be able to give its next letter.
                        var alive = true
                        for q in 0..<n where q != p {
                            let tq = taken(next, q)
                            guard tq < counts[q] else { continue }
                            let latest = tq == 0 ? times[q].depart[0] : times[q].depart[counts[q] - 1]
                            if latest + slack < now { alive = false; break }
                        }
                        guard alive else { continue }
                        queue.append(Entry(state: TogetherState(node: child, taken: next, lastPiece: Int8(p), doubled: false, letter: UInt8(label)),
                                           parent: Int32(index - 1), piece: Int8(p), standIns: entry.standIns + (way.standIn ? 1 : 0),
                                           late: entry.late + max(0, late)))
                    }
                }
            }
        }
        return best
    }
}
