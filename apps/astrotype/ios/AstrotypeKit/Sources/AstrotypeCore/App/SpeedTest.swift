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
/// words turning mint one by one, a wrong word typed again. Pure state with the time
/// passed in; the screen owns one and the keyboard's commits drive it.
///
///     var test = SpeedTest(sentences: SpeedTest.pick())
///     test.start(at: t0)                        // the first touch on the keys
///     test.commit("the", at: t1)                // .next, .sentence, .finished or .miss
///     test.result(date: Date(), keyboard: .astrotype)
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
        /// The word was right; on to the next.
        case next
        /// The word was right and finished its sentence; on to the next sentence.
        case sentence
        /// The word was right and finished the test.
        case finished
        /// Not the word asked for: it stays, to be typed again.
        case miss
    }

    /// The sentences, as words.
    public let sentences: [[String]]
    public private(set) var sentence = 0
    public private(set) var word = 0
    public private(set) var started: TimeInterval?
    public private(set) var finished: TimeInterval?
    public private(set) var fixes = 0
    public private(set) var misses = 0
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
    public var typedWords: Int { sentences.prefix(sentence).reduce(0) { $0 + $1.count } + word }
    /// 0 to 1.
    public var progress: Double { totalWords == 0 ? 0 : Double(typedWords) / Double(totalWords) }

    /// The clock starts at the first touch on the keys, not when the screen opens.
    public mutating func start(at time: TimeInterval) {
        if started == nil { started = time }
    }

    /// A word went into the field.
    public mutating func commit(_ typed: String, at time: TimeInterval) -> Outcome {
        guard let expected = expectedWord else { return .finished }
        start(at: time)
        guard Self.normalize(typed) == expected else {
            misses += 1
            return .miss
        }
        word += 1
        if word < current.count { return .next }
        sentence += 1
        word = 0
        if sentence < sentences.count { return .sentence }
        finished = time
        return .finished
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
    /// words per minute is made from (five characters to a word).
    public var charactersTyped: Int {
        var count = 0
        for (i, words) in sentences.enumerated() {
            let done = i < sentence ? words : (i == sentence ? Array(words.prefix(word)) : [])
            count += done.reduce(0) { $0 + $1.count } + max(0, done.count - 1)
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
