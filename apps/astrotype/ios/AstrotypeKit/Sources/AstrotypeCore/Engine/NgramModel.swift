import Foundation

/// Which words tend to follow which, for ranking guesses by the sentence so far
/// (features/smart-matching/FEATURE.md). A word-pair model in a compact binary the
/// keyboard loads in one read, about 1 MB for 300,000 pairs:
///
///     "ASNG" · version UInt16 · flags UInt16 · vocabulary N UInt32 · pairs M UInt32
///     · lambda Float32 · scale Float32
///     · N words, each UInt8 length + UTF-8 bytes, sorted ascending (binary search)
///     · N + 1 UInt32 offsets into the pairs, one per previous word
///     · M UInt16 next-word ids (UInt32 when flags bit 0 is set), ascending per previous word
///     · M UInt8 quantised costs: round(−log P(next | previous) × scale), 255 at most
///
/// `<s>` is a word of its own, the start of a sentence. The same type writes the
/// format (`Builder`), so `astrotype-tools build-ngrams` and the tests share it.
///
///     let model = try NgramModel(contentsOf: url)
///     model.logProbability(of: "store", after: "the")          // log P(store | the), nil if unseen
///     model.contextBonus(for: "store", after: "the", unigramLogProbability: -9.1)
public struct NgramModel: Sendable, Equatable {
    public static let sentenceStart = "<s>"
    static let magic: [UInt8] = Array("ASNG".utf8)
    public static let formatVersion: UInt16 = 1

    /// Interpolation weight on the pair probability: `λ·P(w|prev) + (1−λ)·P(w)`.
    public var lambda: Float
    /// Quantisation: costs are `−log P × scale`, rounded to a byte.
    public var scale: Float
    /// The vocabulary, sorted.
    public private(set) var words: [String]
    private var offsets: [UInt32]
    private var nexts: [UInt32]
    private var costs: [UInt8]

    public var vocabularyCount: Int { words.count }
    public var pairCount: Int { nexts.count }

    // MARK: Reading

    public init(contentsOf url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    public init(data: Data) throws {
        var reader = ByteReader(data)
        guard try reader.bytes(4) == Self.magic else { throw Failure.notAModel }
        let version = try reader.uint16()
        guard version == Self.formatVersion else { throw Failure.unsupportedVersion(Int(version)) }
        let flags = try reader.uint16()
        let wide = flags & 1 != 0
        let count = Int(try reader.uint32())
        let pairs = Int(try reader.uint32())
        lambda = try reader.float()
        scale = try reader.float()
        var words: [String] = []
        words.reserveCapacity(count)
        for _ in 0..<count {
            let length = Int(try reader.uint8())
            words.append(String(decoding: try reader.bytes(length), as: UTF8.self))
        }
        self.words = words
        offsets = try (0...count).map { _ in try reader.uint32() }
        nexts = try (0..<pairs).map { _ in wide ? try reader.uint32() : UInt32(try reader.uint16()) }
        costs = try reader.bytes(pairs)
        guard offsets.last.map(Int.init) == pairs else { throw Failure.corrupt }
    }

    public enum Failure: Error, Equatable {
        case notAModel, unsupportedVersion(Int), corrupt
    }

    // MARK: Lookup

    /// The id of a word, by binary search over the sorted vocabulary.
    public func id(of word: String) -> Int? {
        var low = 0
        var high = words.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if words[mid] == word { return mid }
            if words[mid] < word { low = mid + 1 } else { high = mid - 1 }
        }
        return nil
    }

    /// `log P(word | previous)`, nil when either word is unknown or the pair was not seen.
    public func logProbability(of word: String, after previous: String) -> Float? {
        guard let p = id(of: previous), let w = id(of: word) else { return nil }
        let target = UInt32(w)
        var low = Int(offsets[p])
        var high = Int(offsets[p + 1]) - 1
        while low <= high {
            let mid = (low + high) / 2
            if nexts[mid] == target { return -Float(costs[mid]) / scale }
            if nexts[mid] < target { low = mid + 1 } else { high = mid - 1 }
        }
        return nil
    }

    /// How much more (or less) likely `word` is after `previous` than on its own, in
    /// log space: `log(λ·P(w|prev) + (1−λ)·P(w)) − log P(w)`. Zero without a usable
    /// previous word; a little below zero for a pair never seen after a known word
    /// (`log(1−λ)`); clamped at `maximumBonus` so one strong pair cannot drown the shape
    /// of the swipe.
    public func contextBonus(for word: String, after previous: String?, unigramLogProbability: Float) -> Float {
        guard let previous, id(of: previous) != nil else { return 0 }
        let unigram = exp(unigramLogProbability)
        let pair = logProbability(of: word, after: previous).map { exp($0) } ?? 0
        let mixed = lambda * pair + (1 - lambda) * unigram
        guard unigram > 0, mixed > 0 else { return 0 }
        return min(Self.maximumBonus, log(mixed) - log(unigram))
    }

    public static let maximumBonus: Float = 6

    /// The most likely words after `previous`, best first, for practice prompts and tests.
    public func likelyWords(after previous: String, limit: Int) -> [String] {
        topNext(after: previous, limit: limit).map(\.word)
    }

    /// The `limit` most likely words after `previous` with `log P(word | previous)`,
    /// best first (ties by vocabulary order). One pass over the previous word's pairs,
    /// keeping the best few, so even "the" (thousands of pairs) costs microseconds:
    /// the bar asks after every word (features/next-word).
    public func topNext(after previous: String, limit: Int) -> [(word: String, logProbability: Float)] {
        guard limit > 0, let p = id(of: previous) else { return [] }
        // The best so far, sorted by (cost, next id); the worst kept is last.
        var best: [(cost: UInt8, next: UInt32)] = []
        best.reserveCapacity(limit + 1)
        for i in Int(offsets[p])..<Int(offsets[p + 1]) {
            let entry = (cost: costs[i], next: nexts[i])
            if best.count == limit, let worst = best.last,
               entry.cost > worst.cost || (entry.cost == worst.cost && entry.next > worst.next) { continue }
            var at = best.count
            while at > 0, entry.cost < best[at - 1].cost || (entry.cost == best[at - 1].cost && entry.next < best[at - 1].next) {
                at -= 1
            }
            best.insert(entry, at: at)
            if best.count > limit { best.removeLast() }
        }
        return best.map { (words[Int($0.next)], -Float($0.cost) / scale) }
    }

    // MARK: Building

    /// Counts in, the binary out. Pairs are `P(next | previous) = count / total(previous)`,
    /// kept most common first up to `maxPairs`.
    ///
    ///     var builder = NgramModel.Builder()
    ///     builder.add(previous: "<s>", word: "i", count: 3)
    ///     let data = builder.build()
    public struct Builder: Sendable {
        public var lambda: Float
        public var scale: Float
        private var counts: [String: [String: Int]] = [:]

        public init(lambda: Float = 0.7, scale: Float = 16) {
            self.lambda = lambda
            self.scale = scale
        }

        public mutating func add(previous: String, word: String, count: Int) {
            guard count > 0 else { return }
            counts[previous, default: [:]][word, default: 0] += count
        }

        /// A `previous<TAB>next<TAB>count` line, as `ml/ngrams/count_pairs.py` writes them.
        public mutating func add(line: Substring) {
            let parts = line.split(separator: "\t")
            guard parts.count == 3, let count = Int(parts[2]) else { return }
            add(previous: String(parts[0]), word: String(parts[1]), count: count)
        }

        public func build(maxPairs: Int = 300_000) -> Data {
            // The pairs to keep: the most common overall, then every word they mention.
            var all: [(previous: String, word: String, count: Int)] = []
            for (previous, nexts) in counts {
                for (word, count) in nexts { all.append((previous, word, count)) }
            }
            all.sort { $0.count > $1.count || ($0.count == $1.count && ($0.previous, $0.word) < ($1.previous, $1.word)) }
            let kept = Array(all.prefix(maxPairs))
            let words = Array(Set(kept.flatMap { [$0.previous, $0.word] })).sorted()
            var ids: [String: Int] = [:]
            for (i, word) in words.enumerated() { ids[word] = i }
            // Probabilities over the previous word's full count, so dropped pairs
            // still take their share and nothing kept sums to more than one.
            var totals: [String: Int] = [:]
            for (previous, nexts) in counts { totals[previous] = nexts.values.reduce(0, +) }
            var perPrevious: [[(next: Int, cost: UInt8)]] = Array(repeating: [], count: words.count)
            for pair in kept {
                let p = Float(pair.count) / Float(totals[pair.previous] ?? pair.count)
                let cost = min(255, Int((-log(p) * scale).rounded()))
                perPrevious[ids[pair.previous]!].append((ids[pair.word]!, UInt8(cost)))
            }
            let wide = words.count > Int(UInt16.max)
            var out = Data()
            out.append(contentsOf: NgramModel.magic)
            out.append(uint16: NgramModel.formatVersion)
            out.append(uint16: wide ? 1 : 0)
            out.append(uint32: UInt32(words.count))
            out.append(uint32: UInt32(kept.count))
            out.append(float: lambda)
            out.append(float: scale)
            for word in words {
                let bytes = Array(word.utf8.prefix(255))
                out.append(UInt8(bytes.count))
                out.append(contentsOf: bytes)
            }
            var offset: UInt32 = 0
            for list in perPrevious {
                out.append(uint32: offset)
                offset += UInt32(list.count)
            }
            out.append(uint32: offset)
            var costBytes = Data()
            for list in perPrevious {
                for entry in list.sorted(by: { $0.next < $1.next }) {
                    if wide { out.append(uint32: UInt32(entry.next)) } else { out.append(uint16: UInt16(entry.next)) }
                    costBytes.append(entry.cost)
                }
            }
            out.append(costBytes)
            return out
        }
    }
}

// MARK: - Bytes

struct ByteReader {
    private let data: Data
    private var index: Int

    init(_ data: Data) {
        self.data = data
        index = data.startIndex
    }

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, index + count <= data.endIndex else { throw NgramModel.Failure.corrupt }
        defer { index += count }
        return [UInt8](data[index..<(index + count)])
    }

    mutating func uint8() throws -> UInt8 { try bytes(1)[0] }

    mutating func uint16() throws -> UInt16 {
        let b = try bytes(2)
        return UInt16(b[0]) | UInt16(b[1]) << 8
    }

    mutating func uint32() throws -> UInt32 {
        let b = try bytes(4)
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    mutating func float() throws -> Float {
        Float(bitPattern: try uint32())
    }
}

extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func append(uint32 value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }

    mutating func append(float value: Float) {
        append(uint32: value.bitPattern)
    }
}
