import Foundation

/// The decoder's dictionary as a compact trie in flat tables (no per-node objects),
/// read in place from one block of bytes (`MappedBytes`): a file mapped into memory
/// for the bundled languages (`Language.cacheFolder`), or a copy in memory for word
/// lists made on the phone. Mapped, the tables cost the keyboard no memory iOS counts.
/// Node 0 is the root. Letters are 1...26 for a–z, matching the model's classes;
/// accented words sit under their plain letters with their spellings kept (`fold`,
/// `spellings(at:)`), since the keys a thumb crosses are a to z.
///
/// The file ("ASLX", `formatVersion`), little-endian, each table on a 4-byte boundary:
///
///     magic · version UInt16 · 0 UInt16 · nodes N · edges E · spelled nodes S
///     · spellings P · spelling text bytes T (UInt32 each) · log probability offset Float32
///     · edgeStart Int32[N] · parent Int32[N] · wordLogPrior Float32[N] · bestBelow Float32[N]
///     · edgeTargets Int32[E] · spelledNodes Int32[S] (ascending) · spellingStart UInt32[S+1]
///     · spellingPrior Float32[P] · spellingTextStart UInt32[P+1]
///     · edgeCount UInt8[N] · label UInt8[N] · edgeLabels UInt8[E] · spelling text UInt8[T]
public struct Lexicon: @unchecked Sendable {
    public struct Entry: Sendable {
        public var word: String
        public var frequency: Double
    }

    static let magic: [UInt8] = Array("ASLX".utf8)
    public static let formatVersion: UInt16 = 1
    static let headerSize = 32

    /// The bytes the tables below point into; kept alive with them. Read-only, so the
    /// lexicon is safe to share between threads.
    private let bytes: MappedBytes
    /// For each node: where its edges start in `edgeLabels`/`edgeTargets`, and how many.
    let edgeStart: UnsafeBufferPointer<Int32>
    let edgeCount: UnsafeBufferPointer<UInt8>
    let edgeLabels: UnsafeBufferPointer<UInt8>
    let edgeTargets: UnsafeBufferPointer<Int32>
    /// For each node: its parent, the letter that leads to it, and the word prior
    /// `log(freq / maxFreq)` when a word ends here (NaN otherwise).
    let parent: UnsafeBufferPointer<Int32>
    let label: UnsafeBufferPointer<UInt8>
    let wordLogPrior: UnsafeBufferPointer<Float>
    /// For each node: the best word prior at or below it, for ranking completions.
    let bestBelow: UnsafeBufferPointer<Float>
    /// Added to a word's log prior gives `log P(word)` over the whole dictionary:
    /// `log(maxFreq / sum of frequencies)`.
    public let logProbabilityOffset: Float

    /// Nodes whose word is written differently from its keys ("canción" under
    /// "cancion") or has more than one spelling ("está" and "esta" under "esta"), and
    /// for each its spellings with their own log priors, likeliest first.
    private let spelledNodes: UnsafeBufferPointer<Int32>
    private let spellingStart: UnsafeBufferPointer<UInt32>
    private let spellingPrior: UnsafeBufferPointer<Float>
    private let spellingTextStart: UnsafeBufferPointer<UInt32>
    private let spellingText: UnsafeBufferPointer<UInt8>

    public var nodeCount: Int { parent.count }

    /// Whether the tables are read from a mapped file rather than held in memory.
    public var isMapped: Bool { bytes.isMapped }

    /// A word as the keys spell it: lowercase, accents and tildes off, so "Año" is
    /// "ano" and "pingüino" is "pinguino". The trie is keyed by these, and the
    /// thumbs only ever hit a to z.
    public static func fold(_ word: String) -> String {
        let lower = word.lowercased()
        guard lower.utf8.contains(where: { $0 >= 0x80 }) else { return lower }
        var out = String.UnicodeScalarView()
        for scalar in lower.decomposedStringWithCanonicalMapping.unicodeScalars
        where !(0x300...0x36F).contains(scalar.value) {
            out.append(scalar)
        }
        return String(out)
    }

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

    /// A lexicon of `entries`, held in memory.
    public init(entries: [Entry]) {
        // Our own encoding always reads back.
        try! self.init(bytes: MappedBytes(copying: Self.encode(entries)))
    }

    /// A lexicon file written by `encode`, mapped from storage.
    public init(mapping url: URL) throws {
        try self.init(bytes: MappedBytes(mapping: url))
    }

    /// A lexicon file written by `encode`, copied into memory.
    public init(data: Data) throws {
        try self.init(bytes: MappedBytes(copying: data))
    }

    private init(bytes: MappedBytes) throws {
        guard bytes.count >= Self.headerSize else { throw TableFileError.corrupt }
        let header = bytes.buffer(at: 0, count: Self.headerSize, as: UInt8.self)
        guard Array(header[0..<4]) == Self.magic,
              bytes.buffer(at: 4, count: 1, as: UInt16.self)[0] == Self.formatVersion else { throw TableFileError.corrupt }
        let counts = bytes.buffer(at: 8, count: 5, as: UInt32.self).map(Int.init)
        let (nodes, edges, spelled, spellings, text) = (counts[0], counts[1], counts[2], counts[3], counts[4])
        var reader = SectionReader(bytes, after: Self.headerSize)
        self.bytes = bytes
        logProbabilityOffset = bytes.buffer(at: 28, count: 1, as: Float.self)[0]
        edgeStart = try reader.next(nodes)
        parent = try reader.next(nodes)
        wordLogPrior = try reader.next(nodes)
        bestBelow = try reader.next(nodes)
        edgeTargets = try reader.next(edges)
        spelledNodes = try reader.next(spelled)
        spellingStart = try reader.next(spelled + 1)
        spellingPrior = try reader.next(spellings)
        spellingTextStart = try reader.next(spellings + 1)
        edgeCount = try reader.next(nodes)
        label = try reader.next(nodes)
        edgeLabels = try reader.next(edges)
        spellingText = try reader.next(text)
        guard nodes > 0 else { throw TableFileError.corrupt }
    }

    /// The file for `entries`: words with accents are stored under their folded keys
    /// (`fold`), with the key's frequency the sum of its spellings', and the spellings
    /// kept for `spellings(at:)`.
    public static func encode(_ rawEntries: [Entry]) -> Data {
        // Only a list with accented words needs keys and spellings sorted out (English
        // has none, and loads as it always did).
        var entries = rawEntries
        var spelled: [String: [Entry]] = [:]
        if rawEntries.contains(where: { $0.word.utf8.contains { $0 >= 0x80 } }) {
            var keyed: [String: Double] = [:]
            var keys: [String] = []
            var all: [String: [Entry]] = [:]
            for entry in rawEntries {
                let key = Self.fold(entry.word)
                if keyed[key] == nil { keys.append(key) }
                keyed[key, default: 0] += entry.frequency
                all[key, default: []].append(entry)
            }
            entries = keys.map { Entry(word: $0, frequency: keyed[$0]!) }
            for (key, list) in all where list.count > 1 || list[0].word != key { spelled[key] = list }
        }
        let maxFreq = entries.map(\.frequency).max() ?? 1
        let sum = entries.reduce(0) { $0 + $1.frequency }
        let logProbabilityOffset = sum > 0 ? Float(log(maxFreq / sum)) : 0
        // Build with per-node child lists first, then flatten.
        var children: [[(UInt8, Int32)]] = [[]]
        var parent: [Int32] = [-1]
        var label: [UInt8] = [0]
        var wordLogPrior: [Float] = [.nan]
        var spellingTable: [Int32: [(word: String, logPrior: Float)]] = [:]
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
                if let spellings = spelled[entry.word] {
                    spellingTable[node] = spellings
                        .sorted { $0.frequency > $1.frequency || ($0.frequency == $1.frequency && $0.word < $1.word) }
                        .map { ($0.word, Float(log($0.frequency / maxFreq))) }
                }
            }
        }
        var edgeStart: [Int32] = []
        var edgeCount: [UInt8] = []
        var edgeLabels: [UInt8] = []
        var edgeTargets: [Int32] = []
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
        children = []
        // Children are created after their parents, so a reverse pass sees every
        // child's best before its parent's.
        var bestBelow = [Float](repeating: -.infinity, count: parent.count)
        for node in stride(from: parent.count - 1, through: 0, by: -1) {
            var best = wordLogPrior[node].isNaN ? -Float.infinity : wordLogPrior[node]
            let start = Int(edgeStart[node])
            for i in start..<(start + Int(edgeCount[node])) {
                best = max(best, bestBelow[Int(edgeTargets[i])])
            }
            bestBelow[node] = best
        }
        // The spellings, by node.
        var spelledNodes: [Int32] = []
        var spellingStart: [UInt32] = [0]
        var spellingPrior: [Float] = []
        var spellingTextStart: [UInt32] = [0]
        var spellingText: [UInt8] = []
        for node in spellingTable.keys.sorted() {
            spelledNodes.append(node)
            for spelling in spellingTable[node]! {
                spellingPrior.append(spelling.logPrior)
                spellingText.append(contentsOf: spelling.word.utf8)
                spellingTextStart.append(UInt32(spellingText.count))
            }
            spellingStart.append(UInt32(spellingPrior.count))
        }

        var out = SectionWriter()
        for byte in Self.magic { out.append(byte) }
        out.append(Self.formatVersion)
        out.append(UInt16(0))
        for count in [parent.count, edgeTargets.count, spelledNodes.count, spellingPrior.count, spellingText.count] {
            out.append(UInt32(count))
        }
        out.append(logProbabilityOffset)
        out.section(edgeStart)
        out.section(parent)
        out.section(wordLogPrior)
        out.section(bestBelow)
        out.section(edgeTargets)
        out.section(spelledNodes)
        out.section(spellingStart)
        out.section(spellingPrior)
        out.section(spellingTextStart)
        out.section(edgeCount)
        out.section(label)
        out.section(edgeLabels)
        out.section(spellingText)
        out.pad()
        return out.data
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

    /// How the word ending at `node` is written, likeliest first, with each one's log
    /// prior: one entry, the key itself, for a word with no accents.
    public func spellings(at node: Int32) -> [(word: String, logPrior: Float)] {
        if let index = spelledIndex(of: node) {
            return (Int(spellingStart[index])..<Int(spellingStart[index + 1])).map { i in
                let text = UnsafeBufferPointer(rebasing: spellingText[Int(spellingTextStart[i])..<Int(spellingTextStart[i + 1])])
                return (String(decoding: text, as: UTF8.self), spellingPrior[i])
            }
        }
        guard let prior = logPrior(at: node) else { return [] }
        return [(word(at: node), prior)]
    }

    /// Where `node` is in `spelledNodes`, by binary search.
    private func spelledIndex(of node: Int32) -> Int? {
        var low = 0
        var high = spelledNodes.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if spelledNodes[mid] == node { return mid }
            if spelledNodes[mid] < node { low = mid + 1 } else { high = mid - 1 }
        }
        return nil
    }

    /// The spellings of a key (`fold`ed letters), likeliest first; empty if it is no word.
    public func spellings(of key: String) -> [(word: String, logPrior: Float)] {
        node(for: key).map { spellings(at: $0) } ?? []
    }

    /// Whether any word is written with letters beyond a to z.
    public var hasSpellings: Bool { !spelledNodes.isEmpty }

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
    /// A node's edges, as indices for `edgeLabel` and `edgeTarget`: a range, so walking
    /// a node's children makes nothing.
    func edges(of node: Int32) -> Range<Int> {
        let start = Int(edgeStart[Int(node)])
        return start..<(start + Int(edgeCount[Int(node)]))
    }

    /// The letter (1...26) an edge from `edges(of:)` is for, and the node it leads to.
    func edgeLabel(_ edge: Int) -> Int { Int(edgeLabels[edge]) }
    func edgeTarget(_ edge: Int) -> Int32 { edgeTargets[edge] }

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
