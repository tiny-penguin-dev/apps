import Foundation

/// The typing engine (BUILD.md "Core pieces"). Touches and key presses in, text edits
/// out. Pure: it keeps no timers and reads no clock, the caller passes the time, so
/// tests replay recorded touches and autospace is a function of time.
///
///     var composer = Composer(dictionary: lexicon, layout: layout)
///     composer.touchDown(id: 1, at: p, time: t)     // each returns [Effect]
///     composer.touchMoved(id: 1, to: p, time: t)
///     composer.touchUp(id: 1, at: p, time: t)
///     composer.tick(time: t)                        // autospace
///     composer.press(.space, time: t)               // or .backspace, .shift, .returnKey
///     composer.press(character: ",", time: t)       // punctuation commits too
///     composer.choose(guess: 1)                     // from the bar
///     composer.state.openWord                       // "something"
///     composer.state.bar                            // .idle | .guesses | .fix
///
/// The open word is shown as marked text (underlined in the field) until it commits,
/// so the host turns `.mark` into `setMarkedText` and `.commit` into `unmarkText`.
public struct Composer: Sendable {
    public struct Settings: Sendable, Equatable {
        /// Commit the open word after this long with no finger down. Nil turns autospace off.
        public var autospaceDelay: TimeInterval? = 0.9
        /// A touch that lifts within this distance of where it landed is a tap.
        public var tapThreshold: CGFloat = 18
        /// Capitalise the first word of a sentence.
        public var autoCapitalize = true
        /// How many guesses the bar shows.
        public var guessCount = 3
        /// Both thumbs may type at once (Pro, PRODUCT.md §6). Off, a second finger down
        /// while one is still on the keys does nothing but a `.notice`.
        public var twoThumbs = true
        /// How sure the keyboard must be of a real word to write it in place of pecked
        /// letters that spell none (`Matcher.strictness`).
        public var strictness = 0.8
        public init() {}
    }

    /// A line the bar shows for a moment (DESIGN.md "Free mode").
    public enum Notice: Sendable, Equatable {
        /// A second thumb landed on the free keyboard: "Two thumbs is in Astrotype Pro".
        case twoThumbsIsPro
    }

    /// What the bar above the keys shows (DESIGN.md "The keyboard").
    public enum Bar: Sendable, Equatable {
        case idle
        /// Up to three guesses for the open word; `chosen` is the one space writes.
        case guesses([String], chosen: Int)
        /// Right after a commit: the readings of the last word; `chosen` is the one in the field.
        case fix([String], chosen: Int)
    }

    public enum Shift: Sendable, Equatable {
        case off, on, locked
    }

    public enum Haptic: Sendable, Equatable {
        case key, commit
    }

    /// A change the host makes to the text field, in order.
    public enum Effect: Sendable, Equatable {
        case insert(String)
        case deleteBackward(Int)
        /// Show this as the open word: marked text, underlined, replaced by the next `.mark`.
        case mark(String)
        /// Turn the marked text into this, as ordinary text.
        case commit(String)
        /// Remove the marked text.
        case clearMark
        case haptic(Haptic)
        /// A word pecked out letter by letter that the keyboard did not know went in:
        /// the host adds it to the learned words (and keeps them).
        case learn(String)
        /// Something to say in the bar for a moment; nothing changed in the field.
        case notice(Notice)
        /// A word written earlier is final: the person went on without changing it (or
        /// fixed it from the bar first). The host learns from it (`PersonalModel`).
        case settled(SettledWord)
    }

    public struct State: Sendable, Equatable {
        public var bar: Bar = .idle
        /// The guess that space would write, cased as it will be typed.
        public var openWord: String?
        public var shift: Shift = .off
        /// Whether letters type as capitals right now (shift, caps lock or a sentence start).
        public var isShifted = false
    }

    /// The last word written, kept so backspace can reopen it and the bar can fix it.
    struct Committed: Sendable, Equatable {
        var word: String
        var trailing: String
        var pieces: [Piece]
        var guesses: [String]
        var casing: Casing
        /// The word before it, as the matcher saw it.
        var previous: String?
        /// The guess first written, when the bar swapped it for another.
        var fixedFrom: String?
    }

    enum Casing: Sendable, Equatable {
        case lower, capital, upper
    }

    /// A touch in flight: where it landed and where it has been.
    private struct Open: Sendable {
        var side: Side
        var start: TimeInterval
        /// Where the finger was, as the screen reported it (before `personal`'s offsets).
        var points: [CGPoint]
        var times: [TimeInterval]
        var startKey: Character
    }

    public var settings: Settings {
        didSet { matcher.strictness = settings.strictness }
    }
    public var layout: Layout {
        didSet { matcher.layout = layout }
    }
    public var matcher: Matcher
    public private(set) var state = State()
    /// The closed pieces of the open word, in order.
    public private(set) var pieces: [Piece] = []
    public private(set) var candidates: [Candidate] = []
    /// When autospace would commit the open word, if nothing else happens first.
    public private(set) var autospaceDue: TimeInterval?

    private var open: [Int: Open] = [:]
    private var casing: Casing = .lower
    private var shift: Shift = .off
    private var lastShiftPress: TimeInterval?
    private var committed: Committed?
    private var contextBefore = ""

    public init(dictionary: Lexicon, learned: LearnedWords = LearnedWords(), layout: Layout, settings: Settings = Settings()) {
        self.layout = layout
        self.settings = settings
        self.matcher = Matcher(dictionary: dictionary, layout: layout, learned: learned)
        matcher.strictness = settings.strictness
        refreshState()
    }

    /// With the language's word pairs: guesses follow the sentence so far.
    public init(language: Language, learned: LearnedWords = LearnedWords(), layout: Layout, settings: Settings = Settings()) {
        self.layout = layout
        self.settings = settings
        self.matcher = Matcher(language: language, layout: layout, learned: learned)
        matcher.strictness = settings.strictness
        refreshState()
    }

    public var hasOpenWord: Bool { !pieces.isEmpty }

    /// What the keyboard learned from the person (features/smart-matching Phase B): the
    /// matcher ranks with their words and pairs, and each touch is read through where
    /// that thumb really lands on the key. The host sets it from its store.
    public var personal: PersonalIndex {
        get { matcher.personal }
        set { matcher.personal = newValue }
    }

    /// What the person taught the keyboard. The host sets it from its store and after
    /// a sync; the matcher reads it.
    public var learned: LearnedWords {
        get { matcher.learned }
        set { matcher.learned = newValue }
    }

    /// Autospace is for swiped words: a word pecked out tap by tap waits for space, so
    /// a pause between letters never cuts it short (Gabriel, 1 Nov 2026).
    private var autospaceApplies: Bool { pieces.contains { !$0.isTap } }

    // MARK: Touches

    /// A finger landed. Only letter keys start a piece; the host sends the other keys
    /// through `press` when the finger lifts.
    public mutating func touchDown(id: Int, at point: CGPoint, time: TimeInterval) -> [Effect] {
        let side = layout.side(at: point)
        guard let letter = layout.key(at: Self.corrected(point, side: side, layout: layout, personal: personal))?.character else { return [] }
        // Free mode: one active thumb at a time. The second touch is not a piece and
        // does not disturb the first; the bar says why (DESIGN.md "Free mode").
        if !settings.twoThumbs, !open.isEmpty { return [.notice(.twoThumbsIsPro)] }
        var effects: [Effect] = []
        if pieces.isEmpty, open.isEmpty {
            // A new word: its case is decided now, and one-shot shift is spent.
            casing = effectiveShift == .locked ? .upper : effectiveShift == .on ? .capital : .lower
            if shift == .on { shift = .off }
            if committed != nil {
                effects += settle()
                state.bar = .idle
            }
        }
        open[id] = Open(side: side, start: time, points: [point], times: [time], startKey: letter)
        autospaceDue = nil
        effects.append(.haptic(.key))
        refreshState()
        return effects
    }

    public mutating func touchMoved(id: Int, to point: CGPoint, time: TimeInterval) -> [Effect] {
        open[id]?.points.append(point)
        open[id]?.times.append(time)
        return []
    }

    public mutating func touchUp(id: Int, at point: CGPoint, time: TimeInterval) -> [Effect] {
        guard var touch = open.removeValue(forKey: id) else { return [] }
        touch.points.append(point)
        touch.times.append(time)
        let piece = Self.piece(from: touch, id: id, end: time, layout: layout, tapThreshold: settings.tapThreshold, personal: personal)
        guard !piece.keys.isEmpty else { return [] }
        pieces.append(piece)
        pieces.sort { $0.start < $1.start }
        return reguess(time: time)
    }

    public mutating func touchCancelled(id: Int, time: TimeInterval) -> [Effect] {
        open[id] = nil
        if open.isEmpty, autospaceApplies { autospaceDue = settings.autospaceDelay.map { time + $0 } }
        return []
    }

    /// Time passed: commits the open word by autospace when it is due.
    public mutating func tick(time: TimeInterval) -> [Effect] {
        guard let due = autospaceDue, time >= due, open.isEmpty, !pieces.isEmpty else { return [] }
        return commit(trailing: " ", time: time)
    }

    // MARK: Keys

    public mutating func press(_ key: Key, time: TimeInterval) -> [Effect] {
        var effects: [Effect] = [.haptic(.key)]
        switch key {
        case .letter(let c):
            // A letter sent as a press (no touch stream): a tap on its key.
            guard let frame = layout.frame(of: .letter(c)) else { return [] }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return touchDown(id: -1, at: center, time: time) + touchUp(id: -1, at: center, time: time + 0.05)
        case .space:
            if hasOpenWord {
                effects += commit(trailing: " ", time: time)
            } else {
                effects.append(.insert(" "))
                effects += leaveFix()
            }
        case .returnKey:
            if hasOpenWord {
                effects += commit(trailing: "\n", time: time)
            } else {
                effects.append(.insert("\n"))
                effects += leaveFix()
            }
        case .backspace:
            effects += backspace(time: time)
        case .shift:
            if let last = lastShiftPress, time - last < 0.35 {
                shift = shift == .locked ? .off : .locked
            } else {
                shift = shift == .off ? .on : .off
            }
            lastShiftPress = time
        case .symbol(let c):
            return press(character: c, time: time)
        case .numbers, .symbols, .letters, .globe:
            return [] // The host handles these: the pages and the next keyboard.
        }
        refreshState()
        return effects
    }

    /// Punctuation or any other character typed as itself. Commits the open word first,
    /// with the character right after it (no space before a comma).
    public mutating func press(character: Character, time: TimeInterval) -> [Effect] {
        var effects: [Effect] = [.haptic(.key)]
        if hasOpenWord {
            effects += commit(trailing: String(character), time: time)
        } else {
            effects.append(.insert(String(character)))
            effects += leaveFix()
        }
        refreshState()
        return effects
    }

    /// A guess tapped on the bar: with an open word it is written; after a commit it
    /// replaces the word just written.
    public mutating func choose(guess index: Int, time: TimeInterval = 0) -> [Effect] {
        switch state.bar {
        case .guesses(let words, _):
            guard words.indices.contains(index) else { return [] }
            state.bar = .guesses(words, chosen: index)
            return commit(trailing: " ", time: time, byHand: true)
        case .fix(let words, let chosen):
            guard words.indices.contains(index), index != chosen, var last = committed else { return [] }
            let word = words[index]
            let effects: [Effect] = [
                .deleteBackward(last.word.count + last.trailing.count),
                .insert(word + last.trailing),
                .haptic(.key),
            ]
            let original = last.fixedFrom ?? last.word
            last.word = word
            last.fixedFrom = word == original ? nil : original
            committed = last
            state.bar = .fix(words, chosen: index)
            return effects
        case .idle:
            return []
        }
    }

    /// The text before the cursor, after the host applied the effects or the field
    /// changed on its own. Sentence starts capitalise from it, and the matcher reads
    /// the words before the open one from it.
    public mutating func setContext(before: String?) {
        contextBefore = before ?? ""
        matcher.context = WordContext.words(before: contextBefore)
        refreshState()
    }

    /// The learned words changed under us (a boost or forget from the bar, a sync): the
    /// open word is guessed again, and a forgotten reading leaves the fix bar.
    public mutating func learnedDidChange(time: TimeInterval) -> [Effect] {
        if hasOpenWord { return reguess(time: time) }
        if case .fix(let words, let chosen) = state.bar {
            let kept = words.enumerated()
                .filter { $0.offset == chosen || matcher.learned.weight(of: $0.element.lowercased()) >= 0 }
                .map(\.element)
            state.bar = kept.count > 1 ? .fix(kept, chosen: kept.firstIndex(of: words[chosen]) ?? 0) : .idle
            refreshState()
        }
        return []
    }

    /// Forget the open word and the last commit without touching the field, for when
    /// the field changed under us (the cursor moved, the app cleared the text).
    @discardableResult
    public mutating func reset() -> [Effect] {
        let effects = settle()
        pieces = []
        open = [:]
        candidates = []
        autospaceDue = nil
        state.bar = .idle
        refreshState()
        return effects
    }

    /// Swipe left on backspace: drop the open word, or delete back through the last word
    /// and the spaces after it.
    public mutating func deleteWord(time: TimeInterval) -> [Effect] {
        committed = nil
        state.bar = .idle
        autospaceDue = nil
        if !pieces.isEmpty {
            pieces = []
            candidates = []
            refreshState()
            return [.haptic(.key), .clearMark]
        }
        var count = 0
        var rest = Substring(contextBefore)
        while let last = rest.last, last.isWhitespace || last.isNewline { count += 1; rest = rest.dropLast() }
        while let last = rest.last, !(last.isWhitespace || last.isNewline) { count += 1; rest = rest.dropLast() }
        refreshState()
        return [.haptic(.key), .deleteBackward(max(1, count))]
    }

    /// The cursor is about to move (a slide on the space bar): the open word goes in as
    /// it stands, with nothing after it, and the fix bar closes.
    public mutating func cursorWillMove() -> [Effect] {
        guard hasOpenWord else {
            let effects = settle()
            state.bar = .idle
            refreshState()
            return effects
        }
        var effects = commit(trailing: "", time: 0)
        effects.removeAll { $0 == .insert("") }
        effects += settle()
        state.bar = .idle
        refreshState()
        return effects
    }

    // MARK: Words

    private mutating func reguess(time: TimeInterval) -> [Effect] {
        candidates = matcher.candidates(for: pieces, limit: settings.guessCount, final: false)
        committed = nil
        autospaceDue = open.isEmpty && autospaceApplies ? settings.autospaceDelay.map { time + $0 } : nil
        guard let first = candidates.first else {
            state.bar = .idle
            refreshState()
            return [.clearMark]
        }
        state.bar = .guesses(candidates.map { cased($0.word) }, chosen: 0)
        refreshState()
        return [.mark(cased(first.word))]
    }

    private mutating func commit(trailing: String, time: TimeInterval, byHand: Bool = false) -> [Effect] {
        if !byHand { settleGuesses() }
        guard case .guesses(let words, let chosen) = state.bar, words.indices.contains(chosen) else {
            pieces = []
            candidates = []
            autospaceDue = nil
            state.bar = .idle
            refreshState()
            return [.clearMark, .insert(trailing)]
        }
        let word = words[chosen]
        let learn = wordToLearn(word)
        committed = Committed(word: word, trailing: trailing, pieces: pieces, guesses: words, casing: casing,
                              previous: matcher.context.last)
        pieces = []
        candidates = []
        autospaceDue = nil
        state.bar = words.count > 1 ? .fix(words, chosen: chosen) : .idle
        refreshState()
        var effects: [Effect] = [.commit(word), .insert(trailing), .haptic(.commit)]
        if let learn { effects.append(.learn(learn)) }
        return effects
    }

    /// The word is going in as it stands: pecked letters left as they were because a
    /// word could still follow them ("bri" for "bring") must now make a word, as
    /// strictness says, so the guesses are made again as final.
    private mutating func settleGuesses() {
        guard case .guesses(let words, 0) = state.bar, let first = words.first,
              !matcher.isKnown(first.lowercased()), pieces.allSatisfy(\.isTap) else { return }
        candidates = matcher.candidates(for: pieces, limit: settings.guessCount, final: true)
        state.bar = candidates.isEmpty ? .idle : .guesses(candidates.map { cased($0.word) }, chosen: 0)
    }

    /// A word pecked out tap by tap that neither the dictionary nor the person's words
    /// know is learned on commit (DESIGN.md "Learning"); one that was forgotten is
    /// learned again. Swiped words are guesses, so they never are.
    private func wordToLearn(_ word: String) -> String? {
        guard pieces.count >= 2, pieces.allSatisfy(\.isTap) else { return nil }
        let lower = word.lowercased()
        guard lower.count >= 2, lower.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 }),
              !matcher.dictionary.contains(lower), !matcher.learned.contains(lower) else { return nil }
        return lower
    }

    private mutating func backspace(time: TimeInterval) -> [Effect] {
        if !pieces.isEmpty {
            pieces.removeLast()
            if pieces.isEmpty {
                candidates = []
                autospaceDue = nil
                state.bar = .idle
                refreshState()
                return [.clearMark]
            }
            return reguess(time: time)
        }
        if let last = committed, contextBefore.isEmpty || contextBefore.hasSuffix(last.word + last.trailing) {
            // Reopen the word just written, so it can be changed or added to.
            committed = nil
            pieces = last.pieces
            casing = last.casing
            candidates = matcher.candidates(for: pieces, limit: settings.guessCount, final: false)
            let words = candidates.map { cased($0.word) }
            let chosen = words.firstIndex(of: last.word) ?? 0
            let shown = words.isEmpty ? [last.word] : words
            state.bar = .guesses(shown, chosen: chosen)
            autospaceDue = nil
            refreshState()
            return [.deleteBackward(last.word.count + last.trailing.count), .mark(shown[chosen])]
        }
        committed = nil
        state.bar = .idle
        return [.deleteBackward(1)]
    }

    private mutating func leaveFix() -> [Effect] {
        let effects = settle()
        state.bar = .idle
        return effects
    }

    /// The last word is final: what to learn from it, if anything.
    private mutating func settle() -> [Effect] {
        guard let last = committed else { return [] }
        committed = nil
        return Self.settled(last, layout: layout).map { [.settled($0)] } ?? []
    }

    /// A settled word with where the thumbs landed for its letters, when the touches
    /// line up with them: one tap per letter, or the start of a lone swipe on the
    /// first letter. A touch more than a key away from its letter is left out.
    static func settled(_ last: Committed, layout: Layout) -> SettledWord? {
        let word = last.word.lowercased()
        guard PersonalModel.isLearnable(word) else { return nil }
        let letters = Array(word)
        let source: SettledWord.Source = last.fixedFrom != nil ? .fixed : last.pieces.allSatisfy(\.isTap) ? .tapped : .swiped
        var touches: [SettledWord.Touch] = []
        func touch(_ letter: Character, _ piece: Piece, weight: Float) {
            guard let frame = layout.frame(of: .letter(letter)), frame.width > 0, frame.height > 0 else { return }
            let landed = piece.landing ?? piece.points.first ?? CGPoint(x: frame.midX, y: frame.midY)
            let dx = (landed.x - frame.midX) / frame.width
            let dy = (landed.y - frame.midY) / frame.height
            guard abs(dx) <= 1, abs(dy) <= 1 else { return }
            touches.append(SettledWord.Touch(letter: letter, side: piece.side, dx: dx, dy: dy, weight: weight))
        }
        let pieces = last.pieces.sorted { $0.start < $1.start }
        if pieces.allSatisfy(\.isTap), pieces.count == letters.count {
            for (letter, piece) in zip(letters, pieces) { touch(letter, piece, weight: 1) }
        } else if pieces.count == 1, let swipe = pieces.first, !swipe.isTap, letters.count >= 2 {
            touch(letters[0], swipe, weight: 0.3)
        }
        let strokes = pieces.map { SettledWord.Stroke(side: $0.side, points: $0.raw ?? $0.points, times: $0.times) }
        return SettledWord(word: word, previous: last.previous, source: source,
                           fixedFrom: last.fixedFrom?.lowercased(), touches: touches, strokes: strokes)
    }

    private func cased(_ word: String) -> String {
        switch casing {
        case .lower: word
        case .upper: word.uppercased()
        case .capital: word.prefix(1).uppercased() + word.dropFirst()
        }
    }

    private var effectiveShift: Shift {
        if shift != .off { return shift }
        guard settings.autoCapitalize, pieces.isEmpty, open.isEmpty else { return .off }
        return Self.startsSentence(contextBefore) ? .on : .off
    }

    static func startsSentence(_ before: String) -> Bool {
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        guard let last = before.last else { return true }
        guard last.isWhitespace || last.isNewline else { return false }
        return trimmed.isEmpty || trimmed.hasSuffix(".") || trimmed.hasSuffix("?") || trimmed.hasSuffix("!") || last.isNewline
    }

    private mutating func refreshState() {
        state.shift = shift
        state.isShifted = effectiveShift != .off
        if case .guesses(let words, let chosen) = state.bar, words.indices.contains(chosen) {
            state.openWord = words[chosen]
        } else {
            state.openWord = nil
        }
    }

    // MARK: Pieces

    /// Closes a touch into a piece: a tap on the key it landed on, or a swipe with the
    /// letter keys its path crossed, in order.
    private static func piece(from touch: Open, id: Int, end: TimeInterval, layout: Layout, tapThreshold: CGFloat,
                              personal: PersonalIndex) -> Piece {
        let raw = touch.points
        let origin = raw[0]
        let travel = raw.map { Geometry.distance($0, origin) }.max() ?? 0
        // Read through where this thumb lands: each point moves by its key's offset.
        let points = raw.map { corrected($0, side: touch.side, layout: layout, personal: personal) }
        var keys: [Character] = []
        if travel >= tapThreshold {
            for point in Geometry.walk(points, step: 4) {
                guard let letter = layout.key(at: point)?.character else { continue }
                if keys.last != letter { keys.append(letter) }
            }
        }
        let isTap = travel < tapThreshold || keys.count <= 1
        if isTap { keys = [touch.startKey] }
        return Piece(id: id, side: touch.side, start: touch.start, end: end, points: points, times: touch.times, keys: keys,
                     isTap: isTap, raw: raw)
    }

    /// `point` moved by the person's offset for the key under it, for this thumb: if
    /// their left thumb lands a third of a key low on "e", a touch there reads as the
    /// key's centre. Unchanged while nothing is learned.
    static func corrected(_ point: CGPoint, side: Side, layout: Layout, personal: PersonalIndex) -> CGPoint {
        guard !personal.isEmpty, let letter = layout.key(at: point)?.character,
              let frame = layout.frame(of: .letter(letter)) else { return point }
        let offset = personal.offset(for: letter, side: side)
        guard offset != .zero else { return point }
        return CGPoint(x: point.x - offset.dx * frame.width, y: point.y - offset.dy * frame.height)
    }
}
