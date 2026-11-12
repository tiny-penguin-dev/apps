import Foundation

/// Which keyboard a speed test was typed on: ours, or Apple's for the comparison on
/// Home (PRODUCT.md §5.4: "next to Apple's keyboard").
public enum PracticeKeyboard: String, Codable, Sendable {
    case astrotype, apple
}

/// One finished speed test, kept in `AppState` (the last few) and on Home (the best).
public struct SpeedResult: Codable, Sendable, Equatable {
    public var wordsPerMinute: Int
    /// Words corrected from the bar after they were written.
    public var fixes: Int
    /// Wrong words that had to be typed again.
    public var misses: Int
    public var words: Int
    public var seconds: Double
    public var date: Date
    public var keyboard: PracticeKeyboard

    public init(wordsPerMinute: Int, fixes: Int, misses: Int, words: Int, seconds: Double, date: Date, keyboard: PracticeKeyboard) {
        self.wordsPerMinute = wordsPerMinute
        self.fixes = fixes
        self.misses = misses
        self.words = words
        self.seconds = seconds
        self.date = date
        self.keyboard = keyboard
    }
}

/// The speed test as it runs (DESIGN.md screens 6 and 7): three sentences, the typed
/// words turning mint one by one, a wrong word red. Pure state with the time passed
/// in; the screen owns one and hands it the field's text after every change.
///
///     var test = SpeedTest(sentences: SpeedTest.pick())
///     test.start(at: t0)                        // the first touch on the keys
///     test.follow(field: "the cat ", at: t1)    // .next, .sentence or .finished
///     test.result(date: Date(), keyboard: .astrotype)
///
/// The test reads the words in the field rather than counting words as they go in, so
/// it can't lose its place: a word fixed with backspace, swapped from the bar or by
/// look-back, two words run together or one typed twice all line up again with the
/// sentence (`align`). It used to count commits, and after a wrong word on the Duo it
/// fell out of step with the field (Gabriel, 12 Nov 2026).
///
/// Words per minute is the usual measure: characters typed (letters and the spaces
/// between words) over five, per minute, so long words count for more than short ones.
public struct SpeedTest: Sendable, Equatable {
    public static let sentenceCount = 3

    /// Simple sentences in everyday words, lowercase, letters only, so every word is
    /// one swipe or a few taps and the dictionary knows them all.
    public static let sentences: [String] = [
        "the cat went to the store for some bread and came back with a hat",
        "we should go out for coffee before the rain starts again",
        "my brother called to say the game is on at seven tonight",
        "she left her keys on the table by the front door",
        "there is a small park at the end of our street",
        "can you send me the photos from the trip when you get home",
        "the train was late so we walked along the river instead",
        "i think the meeting moved to friday but let me check",
        "they planted three trees in the garden last spring",
        "please bring a jacket because it gets cold at night",
        "the kids built a fort out of every pillow in the house",
        "we watched the sun come up from the top of the hill",
    ]

    /// Three sentences for a test, different ones each time. A seed makes the pick
    /// repeatable (tests, and Apple's keyboard typing the same sentences as ours).
    public static func pick(count: Int = sentenceCount, seed: UInt64? = nil) -> [String] {
        var generator = SeededGenerator(seed: seed ?? UInt64.random(in: 0...UInt64.max))
        return Array(sentences.shuffled(using: &generator).prefix(count))
    }

    public enum Outcome: Sendable, Equatable {
        /// Still in this sentence.
        case next
        /// The sentence is done; on to the next one (the screen empties the field).
        case sentence
        /// The last sentence is done.
        case finished
    }

    /// The sentences, as words.
    public let sentences: [[String]]
    public private(set) var sentence = 0
    /// How many words of the current sentence the field has got to.
    public private(set) var word = 0
    public private(set) var started: TimeInterval?
    public private(set) var finished: TimeInterval?
    public private(set) var fixes = 0
    /// Words typed wrong in the sentences already done, by place in the whole test.
    private var missedBefore: Set<Int> = []
    /// Words of the current sentence that are wrong in the field right now. Fixing one
    /// makes it right again.
    private var missedNow: Set<Int> = []
    /// Whether the last call to `follow` moved on past a wrong word (the screen shakes).
    public private(set) var lastMissed = false
    /// The sentences this test was seeded from, for a second run on Apple's keyboard.
    public let seed: UInt64?

    public init(sentences: [String], seed: UInt64? = nil) {
        self.sentences = sentences.map { $0.split(separator: " ").map(String.init) }
        self.seed = seed
    }

    /// A test on three fresh sentences, remembering the seed so the same three can be
    /// typed on Apple's keyboard after.
    public static func fresh() -> SpeedTest {
        let seed = UInt64.random(in: 0...UInt64.max)
        return SpeedTest(sentences: pick(seed: seed), seed: seed)
    }

    public var isStarted: Bool { started != nil }
    public var isFinished: Bool { finished != nil }

    /// The sentence being typed, as words.
    public var current: [String] { sentences.indices.contains(sentence) ? sentences[sentence] : [] }
    /// The words of the current sentence typed so far.
    public var typed: [String] { Array(current.prefix(word)) }
    /// The words of the current sentence still to type.
    public var remaining: [String] { Array(current.dropFirst(word)) }
    /// The word asked for now, nil when finished.
    public var expectedWord: String? { remaining.first }

    public var totalWords: Int { sentences.reduce(0) { $0 + $1.count } }
    public var typedWords: Int { wordsBefore + word }
    /// 0 to 1.
    public var progress: Double { totalWords == 0 ? 0 : Double(typedWords) / Double(totalWords) }

    /// Words typed wrong, by place in the whole test: marked red and left out of the
    /// speed. The test moves on instead of clearing the field (Gabriel, 8 Nov 2026).
    public var missed: Set<Int> { missedBefore.union(missedNow.map { wordsBefore + $0 }) }
    /// Wrong words: the ones left wrong in sentences already done, and the ones wrong
    /// in the field now.
    public var misses: Int { missedBefore.count + missedNow.count }

    private var wordsBefore: Int { sentences.prefix(sentence).reduce(0) { $0 + $1.count } }

    /// The clock starts at the first touch on the keys, not when the screen opens.
    public mutating func start(at time: TimeInterval) {
        if started == nil { started = time }
    }

    /// The field changed: `field` is everything in it, for the current sentence (the
    /// screen empties it when a sentence is done). A word counts once a space (or
    /// punctuation) follows it; the word being typed doesn't count yet.
    @discardableResult
    public mutating func follow(field: String, at time: TimeInterval) -> Outcome {
        lastMissed = false
        guard !isFinished else { return .finished }
        guard !current.isEmpty else { return .next }
        if !field.isEmpty { start(at: time) }
        let done = Self.doneWords(in: field)
        let line = Self.align(done, to: current)
        let before = word
        word = line.count
        missedNow = line.wrong
        if word > before, missedNow.contains(word - 1) { lastMissed = true }
        guard word >= current.count else { return .next }
        missedBefore.formUnion(missedNow.map { wordsBefore + $0 })
        missedNow = []
        sentence += 1
        word = 0
        if sentence < sentences.count { return .sentence }
        finished = time
        return .finished
    }

    /// Whether word `index` of the current sentence is typed wrong.
    public func isMissed(word index: Int) -> Bool {
        missedNow.contains(index)
    }

    /// A word was corrected from the bar after it was written.
    public mutating func fixed() {
        fixes += 1
    }

    /// Seconds on the clock at `time`, zero before the first touch.
    public func elapsed(at time: TimeInterval) -> TimeInterval {
        guard let started else { return 0 }
        return max(0, (finished ?? time) - started)
    }

    /// Characters typed so far, letters and the spaces between words: the measure
    /// words per minute is made from (five characters to a word). Wrong words don't count.
    public var charactersTyped: Int {
        let missed = missed
        var count = 0
        var index = 0
        for (i, words) in sentences.enumerated() {
            let done = i < sentence ? words : (i == sentence ? Array(words.prefix(word)) : [])
            let right = done.enumerated().filter { !missed.contains(index + $0.offset) }.map(\.element)
            count += right.reduce(0) { $0 + $1.count } + max(0, done.count - 1)
            index += words.count
        }
        return count
    }

    /// Words per minute at `time`: characters over five, per minute. Zero before anything was typed.
    public func wordsPerMinute(at time: TimeInterval) -> Int {
        let seconds = elapsed(at: time)
        guard seconds > 0, charactersTyped > 0 else { return 0 }
        return Int((Double(charactersTyped) / 5 / (seconds / 60)).rounded())
    }

    /// The result, once finished.
    public func result(date: Date, keyboard: PracticeKeyboard) -> SpeedResult? {
        guard let started, let finished else { return nil }
        return SpeedResult(wordsPerMinute: wordsPerMinute(at: finished), fixes: fixes, misses: misses,
                           words: totalWords, seconds: finished - started, date: date, keyboard: keyboard)
    }

    /// Lowercase letters only, as the sentences are.
    public static func normalize(_ word: String) -> String {
        String(word.lowercased().filter { $0.isLetter })
    }

    /// The finished words in the field, normalized: every word with a space after it,
    /// and the last one too when punctuation closes it. Bits with no letters are left out.
    public static func doneWords(in field: String) -> [String] {
        var pieces = field.split(whereSeparator: \.isWhitespace).map(String.init)
        if let last = field.last, !last.isWhitespace, !last.isPunctuation, !pieces.isEmpty {
            pieces.removeLast()
        }
        return pieces.map(normalize).filter { !$0.isEmpty }
    }

    /// Lines the words typed up with the sentence's words: how far into the sentence
    /// they got, and which of its words are wrong. A word-level edit distance, so one
    /// slip doesn't throw out every word after it. A wrong word, an extra word and a
    /// skipped word cost 1 each; two words run together or one typed in two pieces line
    /// up with both only when the letters are nearly the same (so "a a jacket" is an
    /// extra "a", not "a" and "jacket" split); and a tie goes to the reading that got
    /// further, so a wrong word stands in for the one asked for and the test moves on.
    public static func align(_ typed: [String], to target: [String]) -> (count: Int, wrong: Set<Int>) {
        let n = typed.count, m = target.count
        guard n > 0, m > 0 else { return (0, []) }
        enum Step { case pair, extra, skip, joined, split }
        let infinity = Double.greatestFiniteMagnitude
        var cost = Array(repeating: Array(repeating: infinity, count: m + 1), count: n + 1)
        var step = Array(repeating: Array(repeating: Step.pair, count: m + 1), count: n + 1)
        cost[0][0] = 0
        func offer(_ i: Int, _ j: Int, _ value: Double, _ how: Step) {
            if value < cost[i][j] - 1e-9 { cost[i][j] = value; step[i][j] = how }
        }
        for i in 0...n {
            for j in 0...m where i + j > 0 {
                if i > 0, j > 0 { offer(i, j, cost[i - 1][j - 1] + (typed[i - 1] == target[j - 1] ? 0 : 1), .pair) }
                if i > 0 { offer(i, j, cost[i - 1][j] + 1, .extra) }
                if j > 0 { offer(i, j, cost[i][j - 1] + 1, .skip) }
                if i > 0, j > 1 {
                    offer(i, j, cost[i - 1][j - 2] + 0.8 + 2 * closeness(typed[i - 1], target[j - 2] + target[j - 1]), .joined)
                }
                if i > 1, j > 0 {
                    offer(i, j, cost[i - 2][j - 1] + 0.8 + 2 * closeness(typed[i - 2] + typed[i - 1], target[j - 1]), .split)
                }
            }
        }
        var count = 0
        for j in 0...m where cost[n][j] <= cost[n][count] + 1e-9 { count = j }
        var wrong: Set<Int> = []
        var i = n, j = count
        while i > 0 || j > 0 {
            switch step[i][j] {
            case .pair:
                if typed[i - 1] != target[j - 1] { wrong.insert(j - 1) }
                i -= 1; j -= 1
            case .extra:
                i -= 1
            case .skip:
                wrong.insert(j - 1)
                j -= 1
            case .joined:
                wrong.insert(j - 1); wrong.insert(j - 2)
                i -= 1; j -= 2
            case .split:
                wrong.insert(j - 1)
                i -= 2; j -= 1
            }
        }
        return (count, wrong)
    }

    /// Letters apart over the longer word's length: 0 the same, 1 nothing alike.
    static func closeness(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        var row = Array(0...b.count)
        for i in a.indices {
            var previous = row[0]
            row[0] = i + 1
            for j in b.indices {
                let above = row[j + 1]
                row[j + 1] = min(above + 1, row[j] + 1, previous + (a[i] == b[j] ? 0 : 1))
                previous = above
            }
        }
        return Double(row[b.count]) / Double(max(a.count, b.count))
    }
}

/// A small repeatable random source for picking sentences (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
