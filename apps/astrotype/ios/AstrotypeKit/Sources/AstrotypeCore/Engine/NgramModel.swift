import Foundation

/// Which words tend to follow which, for ranking guesses by the sentence so far
/// (features/smart-matching/FEATURE.md). A word-pair model in a compact binary read in
/// place (`MappedBytes`), mapped from the file, so it costs the keyboard no memory iOS
/// counts: about 1.2 MB for 300,000 pairs. Version 2, little-endian, each table on a
/// 4-byte boundary:
///
///     "ASNG" · version UInt16 · flags UInt16 · vocabulary N UInt32 · pairs M UInt32
///     · lambda Float32 · scale Float32 · word bytes W UInt32
///     · wordStart UInt32[N + 1] into the word bytes, words sorted by their UTF-8 bytes
///     · offsets UInt32[N + 1] into the pairs, one per previous word
///     · M next-word ids, UInt16 (UInt32 when flags bit 0 is set), ascending per previous word
///     · M UInt8 quantised costs: round(−log P(next | previous) × scale), 255 at most
///     · the words' UTF-8 bytes, W of them
///
/// Version 1 (length-prefixed words, no word table) still reads, into memory.
/// `<s>` is a word of its own, the start of a sentence. The same type writes the
/// format (`Builder`), so `astrotype-tools build-ngrams` and the tests share it.
///
///     let model = try NgramModel(contentsOf: url)
///     model.logProbability(of: "store", after: "the")          // log P(store | the), nil if unseen
///     model.contextBonus(for: "store", after: "the", unigramLogProbability: -9.1)
public struct NgramModel: @unchecked Sendable, Equatable {
    public static let sentenceStart = "<s>"
    static let magic: [UInt8] = Array("ASNG".utf8)
    public static let formatVersion: UInt16 = 2
    static let headerSize = 28

    /// Interpolation weight on the pair probability: `λ·P(w|prev) + (1−λ)·P(w)`.
    public let lambda: Float
    /// Quantisation: costs are `−log P × scale`, rounded to a byte.
    public let scale: Float
    /// The bytes the tables point into, kept alive with them; read-only.
    private let bytes: MappedBytes
    private let wordStart: UnsafeBufferPointer<UInt32>
    private let wordBytes: UnsafeBufferPointer<UInt8>
    private let offsets: UnsafeBufferPointer<UInt32>
    private let narrowNexts: UnsafeBufferPointer<UInt16>
    private let wideNexts: UnsafeBufferPointer<UInt32>
    private let costs: UnsafeBufferPointer<UInt8>

    public var vocabularyCount: Int { wordStart.count - 1 }
    public var pairCount: Int { costs.count }
    /// Whether the tables are read from a mapped file rather than held in memory.
    public var isMapped: Bool { bytes.isMapped }

    /// The vocabulary, sorted. Made on each call: for tests and tools.
    public var words: [String] { (0..<vocabularyCount).map(word(at:)) }

    public static func == (a: NgramModel, b: NgramModel) -> Bool {
        a.bytes === b.bytes || a.bytes.sameBytes(as: b.bytes)
    }

    // MARK: Reading

    /// The model in the file at `url`: mapped in place when it is version 2.
    public init(contentsOf url: URL) throws {
        let mapped = try MappedBytes(mapping: url)
        if mapped.count >= 6, mapped.buffer(at: 4, count: 1, as: UInt16.self)[0] == Self.formatVersion {
            try self.init(bytes: mapped)
        } else {
            try self.init(data: try Data(contentsOf: url))
        }
    }

    /// A model from a file's bytes (either version), held in memory.
    public init(data: Data) throws {
        guard data.count >= 6, Array(data.prefix(4)) == Self.magic else {
            throw data.starts(with: Self.magic) ? Failure.corrupt : Failure.notAModel
        }
        let version = UInt16(data[data.startIndex + 4]) | UInt16(data[data.startIndex + 5]) << 8
        switch version {
        case Self.formatVersion: try self.init(bytes: MappedBytes(copying: data))
        case 1: try self.init(bytes: MappedBytes(copying: Self.upgrade(data)))
        default: throw Failure.unsupportedVersion(Int(version))
        }
    }

    private init(bytes: MappedBytes) throws {
        guard bytes.count >= Self.headerSize,
              Array(bytes.buffer(at: 0, count: 4, as: UInt8.self)) == Self.magic else { throw Failure.corrupt }
        let flags = bytes.buffer(at: 6, count: 1, as: UInt16.self)[0]
        let counts = bytes.buffer(at: 8, count: 2, as: UInt32.self).map(Int.init)
        let (vocabulary, pairs) = (counts[0], counts[1])
        lambda = bytes.buffer(at: 16, count: 1, as: Float.self)[0]
        scale = bytes.buffer(at: 20, count: 1, as: Float.self)[0]
        let wordByteCount = Int(bytes.buffer(at: 24, count: 1, as: UInt32.self)[0])
        self.bytes = bytes
        do {
            var reader = SectionReader(bytes, after: Self.headerSize)
            wordStart = try reader.next(vocabulary + 1)
            offsets = try reader.next(vocabulary + 1)
            if flags & 1 != 0 {
                wideNexts = try reader.next(pairs)
                narrowNexts = UnsafeBufferPointer(start: nil, count: 0)
            } else {
                narrowNexts = try reader.next(pairs)
                wideNexts = UnsafeBufferPointer(start: nil, count: 0)
            }
            costs = try reader.next(pairs)
            wordBytes = try reader.next(wordByteCount)
        } catch {
            throw Failure.corrupt
        }
        guard offsets.last.map(Int.init) == pairs, wordStart.last.map(Int.init) == wordByteCount else { throw Failure.corrupt }
    }

    public enum Failure: Error, Equatable {
        case notAModel, unsupportedVersion(Int), corrupt
    }

    /// A version 1 file as version 2.
    /// A file's bytes in the current version, for `astrotype-tools upgrade-ngrams`.
    public static func upgraded(_ data: Data) throws -> Data {
        _ = try NgramModel(data: data)
        let version = UInt16(data[data.startIndex + 4]) | UInt16(data[data.startIndex + 5]) << 8
        return version == formatVersion ? data : try upgrade(data)
    }

    static func upgrade(_ data: Data) throws -> Data {
        var reader = ByteReader(data)
        guard try reader.bytes(4) == Self.magic else { throw Failure.notAModel }
        let version = try reader.uint16()
        guard version == 1 else { throw Failure.unsupportedVersion(Int(version)) }
        let wide = try reader.uint16() & 1 != 0
        let count = Int(try reader.uint32())
        let pairs = Int(try reader.uint32())
        let lambda = try reader.float()
        let scale = try reader.float()
        var words: [String] = []
        words.reserveCapacity(count)
        for _ in 0..<count {
            let length = Int(try reader.uint8())
            words.append(String(decoding: try reader.bytes(length), as: UTF8.self))
        }
        let offsets = try (0...count).map { _ in Int(try reader.uint32()) }
        let nexts = try (0..<pairs).map { _ in wide ? Int(try reader.uint32()) : Int(try reader.uint16()) }
        let costs = try reader.bytes(pairs)
        guard offsets.last == pairs else { throw Failure.corrupt }
        let perPrevious = (0..<count).map { p in
            (offsets[p]..<offsets[p + 1]).map { (next: nexts[$0], cost: costs[$0]) }
        }
        return encode(lambda: lambda, scale: scale, words: words, perPrevious: perPrevious)
    }

    /// The version 2 file: words sorted by their UTF-8 bytes, ids and pairs renumbered
    /// to match.
    static func encode(lambda: Float, scale: Float, words: [String], perPrevious: [[(next: Int, cost: UInt8)]]) -> Data {
        let utf8 = words.map { Array($0.utf8) }
        let order = utf8.indices.sorted { utf8[$0].lexicographicallyPrecedes(utf8[$1]) }
        var newID = [Int](repeating: 0, count: words.count)
        for (new, old) in order.enumerated() { newID[old] = new }
        let wide = words.count > Int(UInt16.max)

        var wordStart: [UInt32] = [0]
        var wordBytes: [UInt8] = []
        var offsets: [UInt32] = [0]
        var nexts: [UInt32] = []
        var costs: [UInt8] = []
        for old in order {
            wordBytes.append(contentsOf: utf8[old])
            wordStart.append(UInt32(wordBytes.count))
            for entry in perPrevious[old].map({ (next: newID[$0.next], cost: $0.cost) }).sorted(by: { $0.next < $1.next }) {
                nexts.append(UInt32(entry.next))
                costs.append(entry.cost)
            }
            offsets.append(UInt32(nexts.count))
        }
        var out = SectionWriter()
        for byte in Self.magic { out.append(byte) }
        out.append(Self.formatVersion)
        out.append(UInt16(wide ? 1 : 0))
        out.append(UInt32(words.count))
        out.append(UInt32(nexts.count))
        out.append(lambda)
        out.append(scale)
        out.append(UInt32(wordBytes.count))
        out.section(wordStart)
        out.section(offsets)
        if wide { out.section(nexts) } else { out.section(nexts.map { UInt16($0) }) }
        out.section(costs)
        out.section(wordBytes)
        out.pad()
        return out.data
    }

    // MARK: Lookup

    /// The word with id `id`.
    public func word(at id: Int) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: wordBytes[Int(wordStart[id])..<Int(wordStart[id + 1])]), as: UTF8.self)
    }

    @inline(__always)
    private func next(_ i: Int) -> UInt32 {
        wideNexts.isEmpty ? UInt32(narrowNexts[i]) : wideNexts[i]
    }

    /// The id of a word, by binary search over the vocabulary's bytes.
    public func id(of word: String) -> Int? {
        var word = word
        return word.withUTF8 { target in
            var low = 0
            var high = vocabularyCount - 1
            while low <= high {
                let mid = (low + high) / 2
                let start = Int(wordStart[mid])
                let length = Int(wordStart[mid + 1]) - start
                var order = memcmp(wordBytes.baseAddress! + start, target.baseAddress ?? wordBytes.baseAddress!, min(length, target.count))
                if order == 0 { order = length == target.count ? 0 : (length < target.count ? -1 : 1) }
                if order == 0 { return mid }
                if order < 0 { low = mid + 1 } else { high = mid - 1 }
            }
            return nil
        }
    }

    /// `log P(word | previous)`, nil when either word is unknown or the pair was not seen.
    public func logProbability(of word: String, after previous: String) -> Float? {
        guard let p = id(of: previous), let w = id(of: word) else { return nil }
        let target = UInt32(w)
        var low = Int(offsets[p])
        var high = Int(offsets[p + 1]) - 1
        while low <= high {
            let mid = (low + high) / 2
            let candidate = next(mid)
            if candidate == target { return -Float(costs[mid]) / scale }
            if candidate < target { low = mid + 1 } else { high = mid - 1 }
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
            let entry = (cost: costs[i], next: next(i))
            if best.count == limit, let worst = best.last,
               entry.cost > worst.cost || (entry.cost == worst.cost && entry.next > worst.next) { continue }
            var at = best.count
            while at > 0, entry.cost < best[at - 1].cost || (entry.cost == best[at - 1].cost && entry.next < best[at - 1].next) {
                at -= 1
            }
            best.insert(entry, at: at)
            if best.count > limit { best.removeLast() }
        }
        return best.map { (word(at: Int($0.next)), -Float($0.cost) / scale) }
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
            return NgramModel.encode(lambda: lambda, scale: scale, words: words,
                                     perPrevious: perPrevious.map { $0.map { (next: $0.next, cost: $0.cost) } })
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
