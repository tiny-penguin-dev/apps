import Foundation

/// What the keyboard learned about one person's typing (features/smart-matching
/// Phase B, "Learns you"): the words they use more than most people, the pairs of words
/// they write, and where each thumb really lands on each key. Learned in the keyboard as
/// words settle, kept in the keyboard's own files, merged across devices like
/// `LearnedWords`. Nothing in it ever leaves the person's devices and iCloud.
///
///     var model = PersonalModel()
///     model.learn(settled, device: deviceID, at: now)    // after each word settles
///     let index = PersonalIndex(model, at: now)          // what the engine reads
///     model.forget(at: now)                              // "Forget everything"
///
/// Counts fade with a half-life (`halfLifeDays`), so a habit from last year weighs less
/// than this week's. Each device writes only its own `Shard`, so merging two copies is
/// "the newer copy of each shard", and counts are never added twice.
public struct PersonalModel: Codable, Sendable, Equatable {
    public static let version = 1
    /// After this many days a count weighs half.
    public static let halfLifeDays = 90.0
    /// Per shard: past these, the faintest entries go. Sized so a few devices' shards fit
    /// in the iCloud record beside the learned words (well under its 1 MB).
    public static let maxWords = 2_000
    public static let maxPairs = 4_000
    /// Shards from at most this many devices are kept, the most recently changed.
    public static let maxShards = 4
    /// A thumb's landing statistics stop growing here, so the mean keeps following the
    /// person (an exponential average over about this many touches).
    public static let maxTouchWeight: Float = 120

    /// A count that fades: its value as of `day` (days since 2001-01-01).
    public struct Count: Codable, Sendable, Equatable {
        public var value: Float
        public var day: Int

        public init(value: Float, day: Int) {
            self.value = value
            self.day = day
        }

        /// The value as of `today`.
        public func value(on today: Int) -> Float {
            let age = Double(max(0, today - day))
            return value * Float(pow(0.5, age / PersonalModel.halfLifeDays))
        }

        // Compact on disk and in the iCloud record: [value, day].
        public init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            value = try c.decode(Float.self)
            day = try c.decode(Int.self)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode((value * 100).rounded() / 100)
            try c.encode(day)
        }
    }

    /// Where one thumb lands on one key, relative to the key's centre, in key widths
    /// and heights: a running mean and how many touches it stands for.
    public struct TouchStat: Codable, Sendable, Equatable {
        public var dx: Float
        public var dy: Float
        public var weight: Float

        public init(dx: Float = 0, dy: Float = 0, weight: Float = 0) {
            self.dx = dx
            self.dy = dy
            self.weight = weight
        }

        mutating func add(dx x: Float, dy y: Float, weight w: Float) {
            let total = weight + w
            guard total > 0 else { return }
            dx += (x - dx) * w / total
            dy += (y - dy) * w / total
            weight = min(total, PersonalModel.maxTouchWeight)
        }

        public init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            dx = try c.decode(Float.self)
            dy = try c.decode(Float.self)
            weight = try c.decode(Float.self)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode((dx * 1000).rounded() / 1000)
            try c.encode((dy * 1000).rounded() / 1000)
            try c.encode(weight.rounded())
        }
    }

    /// What one device learned.
    public struct Shard: Codable, Sendable, Equatable {
        /// When this shard started learning: a forget after this drops it.
        public var since: Date
        public var changed: Date
        public var words: [String: Count] = [:]
        /// Keyed `"previous next"`; `previous` may be `NgramModel.sentenceStart`.
        public var pairs: [String: Count] = [:]
        /// Keyed `"l:e"` (left thumb, key e) or `"r:e"`.
        public var touches: [String: TouchStat] = [:]

        public init(since: Date) {
            self.since = since
            self.changed = since
        }
    }

    public var version = PersonalModel.version
    /// The last "Forget everything": shards that began before it are dropped.
    public private(set) var forgottenAt: Date?
    /// Each device's shard, by a random ID that device keeps.
    public private(set) var shards: [String: Shard] = [:]

    public init() {}

    public var isEmpty: Bool { shards.values.allSatisfy { $0.words.isEmpty && $0.pairs.isEmpty && $0.touches.isEmpty } }

    /// Days since 2001-01-01, the clock counts fade by.
    public static func day(of date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
    }

    // MARK: Learning

    /// One word that settled (the person moved on without changing it): its count, its
    /// pair with the word before, and where the thumbs landed for its letters.
    public mutating func learn(_ word: SettledWord, device: String, at date: Date) {
        let lower = word.word.lowercased()
        guard Self.isLearnable(lower) else { return }
        let today = Self.day(of: date)
        var shard = shards[device] ?? Shard(since: date)
        let weight = word.source.weight
        Self.bump(&shard.words, lower, by: weight, today: today)
        if let previous = word.previous, previous == NgramModel.sentenceStart || Self.isLearnable(previous) {
            Self.bump(&shard.pairs, previous + " " + lower, by: weight, today: today)
        }
        for touch in word.touches {
            let key = Self.touchKey(touch.letter, touch.side)
            var stat = shard.touches[key] ?? TouchStat()
            stat.add(dx: Float(touch.dx), dy: Float(touch.dy), weight: touch.weight)
            shard.touches[key] = stat
        }
        Self.prune(&shard.words, max: Self.maxWords, today: today)
        Self.prune(&shard.pairs, max: Self.maxPairs, today: today)
        shard.changed = max(shard.changed, date)
        shards[device] = shard
    }

    /// "Forget everything": every shard goes, here and, once merged, on the other devices.
    public mutating func forget(at date: Date) {
        forgottenAt = max(forgottenAt ?? .distantPast, date)
        shards = [:]
    }

    /// Both copies, each device's newer shard winning, the later forget applied.
    public func merged(with other: PersonalModel) -> PersonalModel {
        var out = self
        out.forgottenAt = [forgottenAt, other.forgottenAt].compactMap { $0 }.max()
        for (id, shard) in other.shards {
            if let mine = out.shards[id], mine.changed >= shard.changed { continue }
            out.shards[id] = shard
        }
        if let forgotten = out.forgottenAt {
            out.shards = out.shards.filter { $0.value.since >= forgotten }
        }
        if out.shards.count > Self.maxShards {
            let kept = out.shards.sorted { $0.value.changed > $1.value.changed }.prefix(Self.maxShards)
            out.shards = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        return out
    }

    /// How much is known, for Settings ("214 word pairs, thumbs mapped").
    public struct Summary: Sendable, Equatable {
        public var words: Int
        public var pairs: Int
        /// Letters with enough touches from either thumb to shift their key.
        public var mappedKeys: Int
        public var thumbsMapped: Bool { mappedKeys >= 10 }
    }

    public var summary: Summary {
        var words = Set<String>(), pairs = Set<String>()
        var touches: [String: Float] = [:]
        for shard in shards.values {
            words.formUnion(shard.words.keys)
            pairs.formUnion(shard.pairs.keys.filter { !$0.hasPrefix(NgramModel.sentenceStart + " ") })
            for (key, stat) in shard.touches { touches[key, default: 0] += stat.weight }
        }
        let mapped = Set(touches.filter { $0.value >= PersonalIndex.trustedTouches }.keys.compactMap { $0.last })
        return Summary(words: words.count, pairs: pairs.count, mappedKeys: mapped.count)
    }

    // MARK: Helpers

    /// Lowercase a to z (the lexicon's alphabet; `Language` widens it), and not absurdly long.
    static func isLearnable(_ word: String) -> Bool {
        (1...24).contains(word.utf8.count) && word.utf8.allSatisfy { $0 >= 97 && $0 <= 122 }
    }

    static func touchKey(_ letter: Character, _ side: Side) -> String {
        (side == .left ? "l:" : "r:") + String(letter)
    }

    private static func bump(_ counts: inout [String: Count], _ key: String, by amount: Float, today: Int) {
        let current = counts[key]?.value(on: today) ?? 0
        counts[key] = Count(value: current + amount, day: today)
    }

    /// Drops the faintest entries down to 90% of `max` once there are more than `max`,
    /// so pruning happens every few hundred words, not every word.
    private static func prune(_ counts: inout [String: Count], max: Int, today: Int) {
        guard counts.count > max else { return }
        let keep = counts.sorted { $0.value.value(on: today) > $1.value.value(on: today) }.prefix(max * 9 / 10)
        counts = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }
}

/// A word the person wrote and then left alone (they went on to the next word, or
/// fixed it from the bar and went on): what `PersonalModel.learn` takes. Made by the
/// `Composer`, which knows the touches and the words before.
public struct SettledWord: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// Pecked out letter by letter: the person spelled it, so it counts fully.
        case tapped
        /// A guess for a swipe that was kept: a weaker vote, so the keyboard's own
        /// guesses do not teach it too much.
        case swiped
        /// Picked from the fix bar over the first guess: the strongest vote.
        case fixed

        var weight: Float {
            switch self {
            case .tapped: 1
            case .swiped: 0.6
            case .fixed: 1.5
            }
        }
    }

    /// Where a thumb landed for a letter of the word, from the key's centre, in key
    /// widths (`dx`) and heights (`dy`).
    public struct Touch: Sendable, Equatable {
        public var letter: Character
        public var side: Side
        public var dx: CGFloat
        public var dy: CGFloat
        /// A tap counts 1; the start of a swipe, which is looser, less.
        public var weight: Float

        public init(letter: Character, side: Side, dx: CGFloat, dy: CGFloat, weight: Float = 1) {
            self.letter = letter
            self.side = side
            self.dx = dx
            self.dy = dy
            self.weight = weight
        }
    }

    /// One thumb's whole touch, as the screen reported it, for a correction the person
    /// chose to share (`SharedWord.correction`).
    public struct Stroke: Sendable, Equatable {
        public var side: Side
        public var points: [CGPoint]
        /// When each point was reached, in the composer's clock (empty when unknown).
        public var times: [TimeInterval]

        public init(side: Side, points: [CGPoint], times: [TimeInterval]) {
            self.side = side
            self.points = points
            self.times = times
        }
    }

    /// As written, lowercase.
    public var word: String
    /// The word before it in the sentence (`NgramModel.sentenceStart` at a sentence's
    /// start), nil after a comma or another break.
    public var previous: String?
    public var source: Source
    /// The first guess, when the person fixed the word to another one (Phase C's
    /// corrections read this).
    public var fixedFrom: String?
    public var touches: [Touch]
    /// The word's touches in touch-down order.
    public var strokes: [Stroke]

    public init(word: String, previous: String?, source: Source, fixedFrom: String? = nil, touches: [Touch] = [],
                strokes: [Stroke] = []) {
        self.word = word
        self.previous = previous
        self.source = source
        self.fixedFrom = fixedFrom
        self.touches = touches
        self.strokes = strokes
    }
}

/// The personal model flattened for the engine: one lookup per word, pair or key, the
/// fading applied once when it is built. The `Matcher` reads the words and pairs, the
/// `Composer` the thumbs' offsets. Rebuilt when the model changes (a few hundred
/// microseconds for a full model).
///
///     let index = PersonalIndex(model, at: now)
///     index.pairCount("good", "morning")     // 7.4
///     index.offset(for: "e", side: .left)    // (dx: 0.04, dy: 0.21) key units
public struct PersonalIndex: Sendable, Equatable {
    /// Touches on a key before its own mean is trusted over the thumb's overall mean.
    static let trustedTouches: Float = 8
    /// The furthest a key's centre moves, in key widths or heights.
    public static let maximumOffset: CGFloat = 0.4

    public private(set) var words: [String: Float] = [:]
    public private(set) var pairs: [String: Float] = [:]
    /// The sum of every word count, for comparing a word's share with the dictionary's.
    public private(set) var totalWords: Float = 0
    /// Per thumb, per letter: where the key's centre is for this person, in key units.
    private var offsets: [String: KeyOffset] = [:]

    public init() {}

    public init(_ model: PersonalModel, at date: Date) {
        let today = PersonalModel.day(of: date)
        var touches: [String: PersonalModel.TouchStat] = [:]
        for shard in model.shards.values {
            for (word, count) in shard.words { words[word, default: 0] += count.value(on: today) }
            for (pair, count) in shard.pairs { pairs[pair, default: 0] += count.value(on: today) }
            for (key, stat) in shard.touches {
                var merged = touches[key] ?? PersonalModel.TouchStat()
                merged.add(dx: stat.dx, dy: stat.dy, weight: stat.weight)
                touches[key] = merged
            }
        }
        totalWords = words.values.reduce(0, +)
        offsets = Self.offsets(from: touches)
    }

    public var isEmpty: Bool { words.isEmpty && pairs.isEmpty && offsets.isEmpty }

    public func wordCount(_ word: String) -> Float { words[word] ?? 0 }

    public func pairCount(_ previous: String, _ word: String) -> Float { pairs[previous + " " + word] ?? 0 }

    /// Where this thumb's taps on `letter` land, from the key's centre (key units).
    public func offset(for letter: Character, side: Side) -> KeyOffset {
        offsets[PersonalModel.touchKey(letter, side)] ?? .zero
    }

    /// Each key's offset: its own mean, pulled toward the thumb's overall mean until
    /// it has `trustedTouches` of its own, and capped.
    static func offsets(from touches: [String: PersonalModel.TouchStat]) -> [String: KeyOffset] {
        var out: [String: KeyOffset] = [:]
        for side in ["l:", "r:"] {
            let mine = touches.filter { $0.key.hasPrefix(side) }
            let total = mine.values.reduce(Float(0)) { $0 + $1.weight }
            guard total > 0 else { continue }
            // The thumb's own habit, trusted as it grows.
            let sideTrust = total / (total + trustedTouches * 2)
            let meanX = mine.values.reduce(Float(0)) { $0 + $1.dx * $1.weight } / total * sideTrust
            let meanY = mine.values.reduce(Float(0)) { $0 + $1.dy * $1.weight } / total * sideTrust
            for letter in "abcdefghijklmnopqrstuvwxyz" {
                let key = side + String(letter)
                let stat = mine[key] ?? PersonalModel.TouchStat()
                let trust = stat.weight / (stat.weight + trustedTouches)
                let x = CGFloat(stat.dx * trust + meanX * (1 - trust))
                let y = CGFloat(stat.dy * trust + meanY * (1 - trust))
                guard abs(x) > 0.005 || abs(y) > 0.005 else { continue }
                let cap = maximumOffset
                out[key] = KeyOffset(dx: min(max(x, -cap), cap), dy: min(max(y, -cap), cap))
            }
        }
        return out
    }
}

/// How far a key's centre sits from where it is drawn, for one person's thumb, in key
/// widths (`dx`) and heights (`dy`).
public struct KeyOffset: Sendable, Equatable {
    public var dx: CGFloat
    public var dy: CGFloat

    public init(dx: CGFloat, dy: CGFloat) {
        self.dx = dx
        self.dy = dy
    }

    public static let zero = KeyOffset(dx: 0, dy: 0)
}

/// The personal model as a keyboard holds it: the model, this install's shard, the
/// switch, and the index the engine reads, kept in step. Pure, so the extension's
/// `KeyboardModel` and the tests drive the same rules.
///
///     var learner = PersonalLearner(model: store.load() ?? PersonalModel(), device: id, now: now)
///     learner.apply(settings, now: now)                // the switch, a forget from elsewhere
///     if learner.learn(settled, allowed: field.allowsLearning, now: now) { store.save(learner.model) }
///     composer.personal = learner.index
public struct PersonalLearner: Sendable, Equatable {
    public private(set) var model: PersonalModel
    public let device: String
    /// Whether the keyboard learns and uses what it learned ("Learns from you").
    public private(set) var isOn = true
    /// What the engine reads: empty while the switch is off.
    public private(set) var index: PersonalIndex

    public init(model: PersonalModel, device: String, now: Date) {
        self.model = model
        self.device = device
        self.index = PersonalIndex(model, at: now)
    }

    /// One word settled. Returns whether the model changed (save it, sync it).
    @discardableResult
    public mutating func learn(_ word: SettledWord, allowed: Bool = true, now: Date) -> Bool {
        guard isOn, allowed else { return false }
        let before = model
        model.learn(word, device: device, at: now)
        guard model != before else { return false }
        index = PersonalIndex(model, at: now)
        return true
    }

    /// The settings changed: the switch, or a "Forget everything" made here or on
    /// another device. Returns whether the model changed.
    @discardableResult
    public mutating func apply(_ settings: KeyboardSettings, now: Date) -> Bool {
        var changed = false
        if let forget = settings.forgetPersonalAt, forget > (model.forgottenAt ?? .distantPast) {
            model.forget(at: forget)
            changed = true
        }
        isOn = settings.learnsFromYou
        index = isOn ? PersonalIndex(model, at: now) : PersonalIndex()
        return changed
    }

    /// A copy from elsewhere (the App Group, iCloud) merged in. Returns whether the
    /// model changed.
    @discardableResult
    public mutating func merge(_ other: PersonalModel, now: Date) -> Bool {
        let merged = model.merged(with: other)
        guard merged != model else { return false }
        model = merged
        index = isOn ? PersonalIndex(model, at: now) : PersonalIndex()
        return true
    }
}
