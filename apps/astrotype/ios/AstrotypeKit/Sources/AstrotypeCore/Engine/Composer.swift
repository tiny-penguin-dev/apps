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
///     composer.press(text: ".com", time: t)          // and a key that types a string
///     composer.choose(guess: 1)                     // from the bar
///     composer.chooseFix(reading: 2)                // another reading of the last word, from the pencil
///     composer.beginCorrection()                    // "Not it?": the keys type the word meant
///     composer.saveCorrection(time: t)              // it replaces the swiped word
///     composer.state.openWord                       // "something"
///     composer.state.bar                            // .idle | .guesses | .fix | .next | .correcting
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
        /// Which capitals the field asks for (`Field.capitals`): sentence starts by
        /// default, none in an address, each word or every letter where the app says.
        /// `autoCapitalize` off turns all of them off.
        public var capitals: Field.Capitals = .sentences
        /// Taps go in exactly as tapped: the letters tapped are the first guess, and
        /// nothing else replaces them unless picked from the bar (`Field.exactTaps`).
        public var exactTaps = false
        /// Words get a space after them: a guess from the bar, and a double space makes
        /// a period. Off in an address or a number (`Field.spacesWords`).
        public var spacesWords = true
        /// How many guesses the bar shows.
        public var guessCount = 3
        /// Both thumbs may type at once (Pro, PRODUCT.md §6). Off, a second finger down
        /// while one is still on the keys does nothing but a `.notice`.
        public var twoThumbs = true
        /// How sure the keyboard must be of a real word to write it in place of pecked
        /// letters that spell none (`Matcher.strictness`).
        public var strictness = 0.8
        /// How sure the keyboard must be that pecked letters are two words with the
        /// space missed before it writes them split (`Matcher.splitStrictness`), and
        /// that a word autospace wrote apart is one with the next before it joins them.
        public var splitStrictness = 0.8
        /// After a word, offer the likely next ones on the bar (features/next-word).
        /// Needs the language's word pairs or the person's; the host turns it off where
        /// the field does not learn.
        public var nextWords = true
        /// With two languages on, guess from both for every word, for people who mix
        /// them in one sentence. Off (the default), a sentence keeps to the first
        /// language it shows (`Language.lock(for:)`, Gabriel 3 Nov 2026).
        public var mixesLanguages = false
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
        /// No open word: the likely next words (`NextWords`), cased for where they go,
        /// tapped with `choose(guess:)`. When the last word has other readings, `fix`
        /// holds them as `.fix` would (`chosen` in the field); the bar offers them behind
        /// its pencil, tapped with `chooseFix(reading:)` (features/guesses-bar).
        case next([String], fix: [String], chosen: Int)

        /// The reading the FIX chip offers: the first one that is not in the field.
        public var fixChoice: String? {
            guard case .next(_, let fix, let chosen) = self else { return nil }
            return fix.indices.first { $0 != chosen }.map { fix[$0] }
        }
        /// "Not it?" was tapped (features/missed-words): the word meant, as typed so
        /// far. The keys type here, not into the text, until it is saved or cancelled.
        case correcting(String)
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
        /// A word learned (or counted once more) on its commit was deleted straight
        /// away: it was a slip. The host takes the use back (`LearnedWords.unlearn`).
        case unlearn(String)
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
        /// Whether the bar offers "Not it?": a swiped word is open, or just went in and
        /// can still be fixed (features/missed-words).
        public var canCorrect = false
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
        /// The keyboard's first guess when the word went in, which the person may not
        /// have taken (a later guess picked from the bar).
        var firstGuess: String?
        /// The word was learned when it went in (`.learn`).
        var learned: String?
        /// A next-word guess tapped on the bar, not typed: nothing to reopen.
        var picked = false
        /// The person typed this word with "Not it?" in place of the swipe's guess.
        var missed = false
        /// When autospace wrote the space after it; nil when anything else did.
        var autospaced: TimeInterval?
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
        didSet {
            matcher.strictness = settings.strictness
            matcher.splitStrictness = settings.splitStrictness
            if settings.mixesLanguages != oldValue.mixesLanguages { relock(force: true) }
        }
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
    /// The language (or languages, "en+es") the dictionary is in; nil when built from a
    /// bare dictionary.
    public private(set) var languageCode: String?
    /// With two languages on, the one this sentence keeps to, once a word showed which
    /// (`Language.lock(for:)`); nil while the next word may be either, and always nil
    /// with one language or `Settings.mixesLanguages`.
    public private(set) var lockedLanguage: String?
    /// The languages typed in, every one of them (the matcher may hold just the
    /// locked one).
    private var language: Language?

    private var open: [Int: Open] = [:]
    private var casing: Casing = .lower
    private var shift: Shift = .off
    private var lastShiftPress: TimeInterval?
    private var committed: Committed?
    /// The space before the cursor is one the keyboard wrote by itself (autospace or a
    /// guess from the bar), so a space pressed now is not a second one, and punctuation
    /// goes before it. Anything else typed clears it.
    private var autoSpaced = false
    /// The space before the cursor went in right after a word, by autospace, the bar
    /// or the space key, and nothing was typed since: closing punctuation goes before
    /// it ("word ." becomes "word. "). Unlike `autoSpaced`, a space pressed after
    /// autospace keeps it (Gabriel, 3 Nov 2026: a space then the dot).
    private var wordSpace = false
    /// The last word, when autospace wrote the space after it and the open word came
    /// straight after: the two may be one word with a pause in it (`Matcher.join`).
    private var joinable: Committed?
    /// How soon after autospace the next word must start to be joined to the word before.
    static let joinWindow: TimeInterval = 1.5
    /// When space was last pressed with a space after a word to show for it (the word
    /// it committed, or the autospace it stood for). A second press soon after makes
    /// that space a period, like Apple's keyboard.
    private var lastSpace: TimeInterval?
    /// How soon a second space counts as a double tap.
    static let doubleSpaceWindow: TimeInterval = 0.4
    private var contextBefore = ""
    /// A word learned on its commit and reopened by backspace: deleting it all the way
    /// forgets it again.
    private var reopenedLearned: String?
    /// The last next-word guesses, lowercase, by the word they follow and how many: the
    /// context is passed back after every change, mostly unchanged.
    private var nextCache: (previous: String, count: Int, words: [String])?
    /// The word meant, while "Not it?" is open, and the bar to go back to on cancel.
    private var correction: String?
    private var barBeforeCorrection: Bar = .idle

    public init(dictionary: Lexicon, learned: LearnedWords = LearnedWords(), layout: Layout, settings: Settings = Settings()) {
        self.layout = layout
        self.settings = settings
        self.matcher = Matcher(dictionary: dictionary, layout: layout, learned: learned)
        matcher.strictness = settings.strictness
        matcher.splitStrictness = settings.splitStrictness
        refreshState()
    }

    /// With the language's word pairs: guesses follow the sentence so far.
    public init(language: Language, learned: LearnedWords = LearnedWords(), layout: Layout, settings: Settings = Settings()) {
        self.layout = layout
        self.settings = settings
        self.matcher = Matcher(language: language, layout: layout, learned: learned)
        self.languageCode = language.code
        self.language = language
        matcher.strictness = settings.strictness
        matcher.splitStrictness = settings.splitStrictness
        refreshState()
    }

    public var hasOpenWord: Bool { !pieces.isEmpty }

    /// What the keyboard learned from the person (features/smart-matching Phase B): the
    /// matcher ranks with their words and pairs, and each touch is read through where
    /// that thumb really lands on the key. The host sets it from its store.
    public var personal: PersonalIndex {
        get { matcher.personal }
        set {
            matcher.personal = newValue
            nextCache = nil
        }
    }

    /// What the person taught the keyboard. The host sets it from its store and after
    /// a sync; the matcher reads it.
    public var learned: LearnedWords {
        get { matcher.learned }
        set {
            matcher.learned = newValue
            nextCache = nil
        }
    }

    /// Autospace is for every word, swiped or pecked: a pecked-only rule broke one-word
    /// pecks and one-letter words like "I" and "a" (Gabriel, 2 Nov 2026).
    private var autospaceApplies: Bool { !pieces.isEmpty }

    // MARK: Touches

    /// A finger landed. Only letter keys start a piece; the host sends the other keys
    /// through `press` when the finger lifts.
    public mutating func touchDown(id: Int, at point: CGPoint, time: TimeInterval) -> [Effect] {
        let side = layout.side(at: point)
        guard let letter = layout.key(at: Self.corrected(point, side: side, layout: layout, personal: personal))?.character else { return [] }
        if correction != nil {
            // Typing the word meant: the touch is only kept to see whether it is a tap.
            open[id] = Open(side: side, start: time, points: [point], times: [time], startKey: letter)
            return [.haptic(.key)]
        }
        // Free mode: one active thumb at a time. The second touch is not a piece and
        // does not disturb the first; the bar says why (DESIGN.md "Free mode").
        if !settings.twoThumbs, !open.isEmpty { return [.notice(.twoThumbsIsPro)] }
        var effects: [Effect] = []
        if pieces.isEmpty, open.isEmpty {
            // A new word: its case is decided now, and one-shot shift is spent.
            casing = effectiveShift == .locked ? .upper : effectiveShift == .on ? .capital : .lower
            if shift == .on { shift = .off }
            joinable = committed.flatMap { last in
                last.autospaced.map { time - $0 <= Self.joinWindow } == true && contextBefore.hasSuffix(last.word + last.trailing) ? last : nil
            }
            if committed != nil { effects += settle() }
            state.bar = .idle
        }
        open[id] = Open(side: side, start: time, points: [point], times: [time], startKey: letter)
        autoSpaced = false
        wordSpace = false
        lastSpace = nil
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
        if correction != nil {
            // Taps type their letter exactly; a swipe types nothing here.
            if piece.isTap { typeCorrection(piece.keys[0]) }
            return []
        }
        pieces.append(piece)
        pieces.sort { $0.start < $1.start }
        return reguess(time: time)
    }

    /// The touch `id` held a key and picked another letter from it (the accent
    /// callout: "ñ" from n). The touch becomes a tap of that letter, kept as typed: the
    /// guesses must have it where it was picked.
    public mutating func pick(_ letter: Character, touch id: Int, time: TimeInterval) -> [Effect] {
        guard let touch = open.removeValue(forKey: id) else { return [] }
        if correction != nil {
            typeCorrection(Character(letter.lowercased()))
            return []
        }
        let point = touch.points.first ?? .zero
        pieces.append(Piece(id: id, side: touch.side, start: touch.start, end: time, points: [point], times: [touch.start],
                            keys: [Character(letter.lowercased())], isTap: true, raw: [point]))
        pieces.sort { $0.start < $1.start }
        return reguess(time: time)
    }

    /// The languages being typed in changed: the dictionary and word pairs swap, and an
    /// open word is guessed again from them.
    public mutating func setLanguage(_ language: Language, time: TimeInterval = 0) -> [Effect] {
        self.language = language
        languageCode = language.code
        relock(force: true)
        return hasOpenWord && correction == nil ? reguess(time: time) : []
    }

    /// Keeps the matcher to the sentence's language once a word showed it, and to every
    /// language while none has (or with `mixesLanguages`). Read from the text before
    /// the cursor, so a new sentence, a fixed word or a moved cursor decide again.
    private mutating func relock(force: Bool = false) {
        guard let language else { return }
        let code = settings.mixesLanguages ? nil : language.lock(for: WordContext.sentence(before: contextBefore))
        guard force || code != lockedLanguage else { return }
        lockedLanguage = code
        nextCache = nil
        let typing = language.part(code)
        matcher.dictionary = typing.lexicon
        matcher.ngramModels = typing.ngramModels
    }

    public mutating func touchCancelled(id: Int, time: TimeInterval) -> [Effect] {
        open[id] = nil
        if open.isEmpty, autospaceApplies, correction == nil { autospaceDue = settings.autospaceDelay.map { time + $0 } }
        return []
    }

    /// Time passed: commits the open word by autospace when it is due.
    public mutating func tick(time: TimeInterval) -> [Effect] {
        guard let due = autospaceDue, time >= due, open.isEmpty, !pieces.isEmpty, correction == nil else { return [] }
        let effects = commit(trailing: " ", time: time)
        autoSpaced = true
        wordSpace = true
        committed?.autospaced = time
        return effects
    }

    // MARK: Keys

    public mutating func press(_ key: Key, time: TimeInterval) -> [Effect] {
        if correction != nil { return pressWhileCorrecting(key, time: time) }
        var effects: [Effect] = [.haptic(.key)]
        let spaced = autoSpaced
        let previousSpace = lastSpace
        if key != .shift {
            autoSpaced = false
            wordSpace = false
            lastSpace = nil
        }
        switch key {
        case .letter(let c):
            // A letter sent as a press (no touch stream): a tap on its key.
            guard let frame = layout.frame(of: .letter(c)) else { return [] }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return touchDown(id: -1, at: center, time: time) + touchUp(id: -1, at: center, time: time + 0.05)
        case .space:
            if hasOpenWord {
                effects += commit(trailing: " ", time: time)
                wordSpace = settings.spacesWords
                lastSpace = time
            } else if settings.spacesWords, let previousSpace, time - previousSpace < Self.doubleSpaceWindow {
                // A double tap: the space after the word becomes a period and a space.
                effects += [.deleteBackward(1), .insert(". ")]
                effects += leaveFix()
            } else if spaced {
                // The keyboard already put a space here: one space between words, and
                // nothing else. Punctuation still goes before it.
                effects += leaveFix()
                wordSpace = true
                lastSpace = time
            } else {
                effects.append(.insert(" "))
                effects += leaveFix()
            }
        case .returnKey:
            if hasOpenWord {
                effects += commit(trailing: "\n", time: time)
            } else {
                // No space left at the end of the line by autospace.
                if spaced { effects.append(.deleteBackward(1)) }
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
        case .text(let text):
            return press(text: text, time: time)
        case .numbers, .symbols, .letters, .globe, .emoji:
            return [] // The host handles these: the pages and the next keyboard.
        }
        refreshState()
        return effects
    }

    /// Punctuation or any other character typed as itself. Commits the open word first,
    /// with the character right after it (no space before a comma).
    public mutating func press(character: Character, time: TimeInterval) -> [Effect] {
        press(text: String(character), time: time)
    }

    /// A key that types a string (".com"), or one character: the same as
    /// `press(character:)`, the open word going in first with the text right after it.
    public mutating func press(text: String, time: TimeInterval) -> [Effect] {
        if correction != nil {
            // Only what can be part of a word: "don't", "e-mail".
            guard text.count == 1, let character = text.first, character == "'" || character == "-" || character == "’" else { return [] }
            typeCorrection(character == "’" ? "'" : character)
            return [.haptic(.key)]
        }
        var effects: [Effect] = [.haptic(.key)]
        let spaced = wordSpace
        autoSpaced = false
        wordSpace = false
        lastSpace = nil
        if hasOpenWord {
            effects += commit(trailing: text, time: time)
        } else if spaced, text.count == 1, let mark = text.first, Self.closingPunctuation.contains(mark) {
            // "word ." becomes "word. ": the mark goes before the space written after the word.
            effects += [.deleteBackward(1), .insert(text + " ")]
            effects += leaveFix()
            autoSpaced = true
            wordSpace = true
        } else {
            effects.append(.insert(text))
            effects += leaveFix()
        }
        refreshState()
        return effects
    }

    /// An emoji from the emoji page. An open word goes in first with a space after it,
    /// as space would write it, then the emoji; no space follows the emoji, so another
    /// can come right after (features/emoji).
    public mutating func insert(emoji: String, time: TimeInterval) -> [Effect] {
        var effects: [Effect] = [.haptic(.key)]
        autoSpaced = false
        wordSpace = false
        lastSpace = nil
        if hasOpenWord {
            effects += commit(trailing: " " + emoji, time: time)
        } else {
            effects.append(.insert(emoji))
            effects += leaveFix()
        }
        refreshState()
        return effects
    }

    /// Marks that go right after a word, before the space.
    static let closingPunctuation: Set<Character> = [".", ",", "?", "!", ";", ":"]

    /// A guess tapped on the bar: with an open word it is written; after a commit it
    /// replaces the word just written.
    public mutating func choose(guess index: Int, time: TimeInterval = 0) -> [Effect] {
        switch state.bar {
        case .guesses(let words, _):
            guard words.indices.contains(index) else { return [] }
            state.bar = .guesses(words, chosen: index)
            let effects = commit(trailing: settings.spacesWords ? " " : "", time: time, byHand: true)
            autoSpaced = settings.spacesWords
            wordSpace = settings.spacesWords
            return effects
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
        case .next(let words, _, _):
            guard words.indices.contains(index) else { return [] }
            return writeNext(words[index])
        case .idle, .correcting:
            return []
        }
    }

    /// Another reading of the last word while next words show (`Bar.next`'s `fix`):
    /// the word in the field becomes `fix[reading]`, by default the best other one
    /// (`Bar.fixChoice`), so calling it twice goes back. The next words follow the new
    /// word once the host passes the context back.
    public mutating func chooseFix(reading: Int? = nil) -> [Effect] {
        guard case .next(_, let fix, let chosen) = state.bar,
              let index = reading ?? fix.indices.first(where: { $0 != chosen }),
              fix.indices.contains(index), index != chosen else { return [] }
        state.bar = .fix(fix, chosen: chosen)
        let effects = choose(guess: index)
        if case .fix(let words, let now) = state.bar { state.bar = .next([], fix: words, chosen: now) }
        return effects
    }

    /// A next word tapped: written with a space after it, as if typed, and the word
    /// before it is final.
    private mutating func writeNext(_ word: String) -> [Effect] {
        var effects = settle()
        // A sentence ended right before the cursor ("Hi.") still needs its space.
        let gap = contextBefore.last.map { $0.isWhitespace || $0.isNewline } ?? true ? "" : " "
        if shift == .on { shift = .off }
        let learn = wordToLearn(word)
        committed = Committed(word: word, trailing: " ", pieces: [], guesses: [word], casing: casing,
                              previous: matcher.context.last, firstGuess: word, learned: learn, picked: true)
        effects += [.insert(gap + word + " "), .haptic(.commit)]
        if let learn { effects.append(.learn(learn)) }
        autoSpaced = true
        wordSpace = true
        lastSpace = nil
        state.bar = .idle
        refreshState()
        return effects
    }

    // MARK: Not it?

    /// "Not it?" from the bar: the keys now type the word meant into the bar, until
    /// `saveCorrection` writes it or `cancelCorrection` goes back (features/missed-words).
    public mutating func beginCorrection() {
        guard state.canCorrect else { return }
        barBeforeCorrection = state.bar
        correction = ""
        autospaceDue = nil
        state.bar = .correcting("")
        refreshState()
    }

    /// The keyboard is going away: the last word is final, so a "Not it?" miss saved
    /// just before is kept now rather than at the next word, which may never come in
    /// this extension. An open word is left as it is.
    public mutating func keyboardWillHide() -> [Effect] {
        cancelCorrection()
        guard !hasOpenWord, committed != nil else { return [] }
        let effects = settle()
        state.bar = .idle
        refreshState()
        return effects
    }

    /// Back to the bar as it was, nothing changed.
    public mutating func cancelCorrection(time: TimeInterval = 0) {
        guard correction != nil else { return }
        correction = nil
        open = [:]
        state.bar = barBeforeCorrection
        if hasOpenWord { autospaceDue = settings.autospaceDelay.map { time + $0 } }
        refreshState()
    }

    /// The word meant goes in place of the swiped word (open, or just written), cased
    /// as it was, and is learned when the dictionary does not have it. The word settles
    /// as a miss, for the host to keep and share (`SettledWord.missed`). Empty cancels.
    public mutating func saveCorrection(time: TimeInterval) -> [Effect] {
        guard let typed = correction else { return [] }
        let meant = typed.lowercased()
        guard !meant.isEmpty else {
            cancelCorrection(time: time)
            return []
        }
        correction = nil
        open = [:]
        var effects: [Effect]
        let learn = correctionToLearn(meant)
        if hasOpenWord {
            var words: [String] = []
            var chosen = 0
            if case .guesses(let shown, let index) = barBeforeCorrection { words = shown; chosen = index }
            let word = cased(meant)
            let original = words.indices.contains(chosen) ? words[chosen] : nil
            committed = Committed(word: word, trailing: " ", pieces: pieces, guesses: words, casing: casing,
                                  previous: matcher.context.last,
                                  fixedFrom: original.flatMap { $0.lowercased() == meant ? nil : $0 },
                                  firstGuess: words.first, learned: learn, missed: true)
            pieces = []
            candidates = []
            autospaceDue = nil
            autoSpaced = true
            wordSpace = true
            joinable = nil
            effects = [.commit(word), .insert(" "), .haptic(.commit)]
        } else if var last = committed {
            let word = Self.cased(meant, as: last.casing)
            let original = last.fixedFrom ?? last.word
            effects = [.deleteBackward(last.word.count + last.trailing.count), .insert(word + last.trailing), .haptic(.commit)]
            last.word = word
            last.fixedFrom = original.lowercased() == meant ? nil : original
            last.missed = true
            if let learn { last.learned = learn }
            committed = last
        } else {
            state.bar = .idle
            refreshState()
            return []
        }
        if let learn { effects.append(.learn(learn)) }
        state.bar = .idle
        refreshState()
        return effects
    }

    /// A letter typed into the "Not it?" field.
    private mutating func typeCorrection(_ letter: Character) {
        guard var typed = correction, typed.count < 40 else { return }
        typed.append(Character(letter.lowercased()))
        correction = typed
        state.bar = .correcting(typed)
    }

    /// The keys while the "Not it?" field is open: backspace edits it, space and
    /// return save it, letters sent as presses type into it; nothing reaches the text.
    private mutating func pressWhileCorrecting(_ key: Key, time: TimeInterval) -> [Effect] {
        switch key {
        case .letter(let c):
            typeCorrection(c)
        case .backspace:
            guard var typed = correction, !typed.isEmpty else { return [.haptic(.key)] }
            typed.removeLast()
            correction = typed
            state.bar = .correcting(typed)
        case .space, .returnKey:
            return saveCorrection(time: time)
        case .text(let text):
            return press(text: text, time: time)
        case .symbol(let c):
            return press(character: c, time: time)
        case .shift, .numbers, .symbols, .letters, .globe, .emoji:
            return []
        }
        return [.haptic(.key)]
    }

    /// The word meant, to learn: any word the dictionary does not have, as the person
    /// spelled it out for it (like a pecked word, `wordToLearn`).
    private func correctionToLearn(_ word: String) -> String? {
        let key = Lexicon.fold(word)
        guard word.count >= 2, key.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 }),
              !matcher.dictionary.spellings(of: key).contains(where: { $0.word == word }) else { return nil }
        return word
    }

    /// The text before the cursor, after the host applied the effects or the field
    /// changed on its own. Sentence starts capitalise from it, and the matcher reads
    /// the words before the open one from it.
    public mutating func setContext(before: String?) {
        contextBefore = before ?? ""
        // The cursor moved, or the app changed the text: that space is gone from under it.
        if let before, !before.hasSuffix(" ") {
            autoSpaced = false
            wordSpace = false
        }
        matcher.context = WordContext.words(before: contextBefore)
        relock()
        if pieces.isEmpty, open.isEmpty { offerNextWords() }
        refreshState()
    }

    /// With no word open, the bar offers the next words for the context (keeping the
    /// last word's readings for the FIX chip), or falls back to FIX or idle when there
    /// are none (features/next-word).
    private mutating func offerNextWords() {
        let fix: (words: [String], chosen: Int)?
        switch state.bar {
        case .guesses, .correcting: return
        case .idle: fix = nil
        case .fix(let words, let chosen): fix = (words, chosen)
        case .next(_, let words, let chosen): fix = words.count > 1 ? (words, chosen) : nil
        }
        let count = settings.guessCount
        var next: [String] = []
        if settings.nextWords, count > 0, let previous = matcher.context.last {
            let words: [String]
            if let cache = nextCache, cache.previous == previous, cache.count == count {
                words = cache.words
            } else {
                words = NextWords.guesses(after: previous, models: matcher.ngramModels, personal: personal,
                                          learned: matcher.learned, count: count)
                    .map { matcher.dictionary.spellings(of: $0).first?.word ?? $0 }
                nextCache = (previous, count, words)
            }
            next = words.map(casedNext)
        }
        if next.isEmpty {
            state.bar = fix.map { .fix($0.words, chosen: $0.chosen) } ?? .idle
        } else {
            state.bar = .next(next, fix: fix?.words ?? [], chosen: fix?.chosen ?? 0)
        }
    }

    /// A next word as it would be typed now: capitalised at a sentence start or after
    /// shift, all caps with caps lock, and "i" always as "I".
    private func casedNext(_ word: String) -> String {
        switch effectiveShift {
        case .locked: return word.uppercased()
        case .on: return word.prefix(1).uppercased() + word.dropFirst()
        case .off: return word == "i" ? "I" : word
        }
    }

    /// The learned words changed under us (a boost or forget from the bar, a sync): the
    /// open word is guessed again, and a forgotten reading leaves the fix bar.
    public mutating func learnedDidChange(time: TimeInterval) -> [Effect] {
        guard correction == nil else { return [] }
        if hasOpenWord { return reguess(time: time) }
        if case .fix(let words, let chosen) = state.bar {
            let kept = words.enumerated()
                .filter { $0.offset == chosen || matcher.learned.weight(of: $0.element.lowercased()) >= 0 }
                .map(\.element)
            state.bar = kept.count > 1 ? .fix(kept, chosen: kept.firstIndex(of: words[chosen]) ?? 0) : .idle
            offerNextWords()
            refreshState()
        } else if case .next(_, let words, let chosen) = state.bar {
            // A forgotten next word goes, and a forgotten reading leaves the chip.
            let kept = words.enumerated()
                .filter { $0.offset == chosen || matcher.learned.weight(of: $0.element.lowercased()) >= 0 }
                .map(\.element)
            state.bar = kept.count > 1 ? .fix(kept, chosen: kept.firstIndex(of: words[chosen]) ?? 0) : .idle
            offerNextWords()
            refreshState()
        }
        return []
    }

    /// Forget the open word and the last commit without touching the field, for when
    /// the field changed under us (the cursor moved, the app cleared the text).
    @discardableResult
    public mutating func reset() -> [Effect] {
        correction = nil
        let effects = settle()
        reopenedLearned = nil
        pieces = []
        open = [:]
        candidates = []
        autospaceDue = nil
        autoSpaced = false
        wordSpace = false
        joinable = nil
        state.bar = .idle
        refreshState()
        return effects
    }

    /// Swipe left on backspace: drop the open word, or delete back through the last word
    /// and the spaces after it.
    public mutating func deleteWord(time: TimeInterval) -> [Effect] {
        if correction != nil {
            correction = ""
            state.bar = .correcting("")
            return [.haptic(.key)]
        }
        let learned = committed?.learned
        committed = nil
        state.bar = .idle
        autospaceDue = nil
        autoSpaced = false
        wordSpace = false
        joinable = nil
        if !pieces.isEmpty {
            pieces = []
            candidates = []
            refreshState()
            return [.haptic(.key), .clearMark] + unlearnReopened()
        }
        reopenedLearned = nil
        var count = 0
        var rest = Substring(contextBefore)
        while let last = rest.last, last.isWhitespace || last.isNewline { count += 1; rest = rest.dropLast() }
        while let last = rest.last, !(last.isWhitespace || last.isNewline) { count += 1; rest = rest.dropLast() }
        refreshState()
        var effects: [Effect] = [.haptic(.key), .deleteBackward(max(1, count))]
        if let learned { effects.append(.unlearn(learned)) }
        return effects
    }

    /// The cursor is about to move (a slide on the space bar): the open word goes in as
    /// it stands, with nothing after it, and the fix bar closes.
    public mutating func cursorWillMove() -> [Effect] {
        cancelCorrection()
        autoSpaced = false
        wordSpace = false
        joinable = nil
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
        let words = guesses(final: false)
        committed = nil
        autospaceDue = open.isEmpty && autospaceApplies ? settings.autospaceDelay.map { time + $0 } : nil
        guard let first = words.first else {
            state.bar = .idle
            refreshState()
            return [.clearMark]
        }
        state.bar = .guesses(words, chosen: 0)
        refreshState()
        return [.mark(first)]
    }

    /// The open word's guesses, cased, best first; sets `candidates`. With `exactTaps`
    /// and only taps, the letters as tapped come first, then the matcher's other readings.
    private mutating func guesses(final: Bool) -> [String] {
        candidates = matcher.candidates(for: pieces, limit: settings.guessCount, final: final)
        var words = candidates.map { cased($0.word) }
        if let tapped = tappedLetters {
            let typed = cased(tapped)
            words.removeAll { $0 == typed }
            words = Array(([typed] + words).prefix(max(1, settings.guessCount)))
        }
        return words
    }

    /// The open word's letters exactly as tapped, when taps are typed exactly and
    /// every piece is a tap.
    private var tappedLetters: String? {
        guard settings.exactTaps, !pieces.isEmpty, pieces.allSatisfy(\.isTap) else { return nil }
        return String(pieces.sorted { $0.start < $1.start }.flatMap(\.keys))
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
        let before = joinable
        joinable = nil
        if !byHand, let before, let joined = join(word, to: before, trailing: trailing) { return joined }
        let learn = wordToLearn(word)
        reopenedLearned = nil
        committed = Committed(word: word, trailing: trailing, pieces: pieces, guesses: words, casing: casing,
                              previous: matcher.context.last, firstGuess: words.first, learned: learn)
        pieces = []
        candidates = []
        autospaceDue = nil
        state.bar = words.count > 1 ? .fix(words, chosen: chosen) : .idle
        refreshState()
        var effects: [Effect] = [.commit(word)] + (trailing.isEmpty ? [] : [.insert(trailing)]) + [.haptic(.commit)]
        if let learn { effects.append(.learn(learn)) }
        return effects
    }

    /// The open word going in after `before`, which autospace wrote with a space after
    /// it, as one word with it when that reads clearly better (`Matcher.join`): "some"
    /// and "thing" become "something", cased as the first was, and the two words as
    /// written wait behind it in the bar. Nil leaves them apart.
    private mutating func join(_ word: String, to before: Committed, trailing: String) -> [Effect]? {
        guard contextBefore.hasSuffix(before.word + before.trailing) else { return nil }
        var matcher = matcher
        // The words before the first one are the context.
        matcher.context = WordContext.words(before: String(contextBefore.dropLast(before.word.count + before.trailing.count)))
        guard let whole = matcher.join(before.pieces, pieces, written: (before.word, word)) else { return nil }
        let joined = Self.cased(matcher.dictionary.spellings(of: whole.word).first?.word ?? whole.word, as: before.casing)
        let apart = before.word + " " + word
        let all = (before.pieces + pieces).sorted { $0.start < $1.start }
        pieces = all
        let learn = wordToLearn(joined)
        reopenedLearned = nil
        committed = Committed(word: joined, trailing: trailing, pieces: all, guesses: [joined, apart], casing: before.casing,
                              previous: before.previous, firstGuess: joined, learned: learn)
        pieces = []
        candidates = []
        autospaceDue = nil
        state.bar = .fix([joined, apart], chosen: 0)
        refreshState()
        var effects: [Effect] = [
            .commit(word),
            .deleteBackward(before.word.count + before.trailing.count + word.count),
            .insert(joined + trailing),
            .haptic(.commit),
        ]
        if let learn { effects.append(.learn(learn)) }
        return effects
    }

    /// The word is going in as it stands: pecked letters left as they were because a
    /// word could still follow them ("bri" for "bring") must now make a word, as
    /// strictness says, so the guesses are made again as final.
    private mutating func settleGuesses() {
        guard tappedLetters == nil, case .guesses(let words, 0) = state.bar, let first = words.first,
              !matcher.isKnown(Lexicon.fold(first)), pieces.allSatisfy(\.isTap) else { return }
        let settled = guesses(final: true)
        state.bar = settled.isEmpty ? .idle : .guesses(settled, chosen: 0)
    }

    /// The reopened word was learned on its commit and is now gone: forget it.
    private mutating func unlearnReopened() -> [Effect] {
        defer { reopenedLearned = nil }
        return reopenedLearned.map { [.unlearn($0)] } ?? []
    }

    /// A word pecked out tap by tap that neither the dictionary nor the person's words
    /// know is learned on commit (DESIGN.md "Learning"); one that was forgotten is
    /// learned again. A word of the person's own counts one more use each time it goes
    /// in, however it was typed, so the words they write often rise. Swiped words the
    /// keyboard did not know are guesses, so they never are.
    private func wordToLearn(_ word: String) -> String? {
        guard !settings.exactTaps else { return nil }
        let lower = word.lowercased()
        let key = Lexicon.fold(lower)
        guard lower.count >= 2, key.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 }),
              !matcher.dictionary.spellings(of: key).contains(where: { $0.word == lower }) else { return nil }
        if matcher.learned.contains(lower) { return lower }
        guard pieces.count >= 2, pieces.allSatisfy(\.isTap) else { return nil }
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
                return [.clearMark] + unlearnReopened()
            }
            return reguess(time: time)
        }
        if let last = committed, !last.picked, contextBefore.isEmpty || contextBefore.hasSuffix(last.word + last.trailing) {
            // Reopen the word just written, so it can be changed or added to.
            committed = nil
            reopenedLearned = last.learned
            pieces = last.pieces
            casing = last.casing
            let words = guesses(final: false)
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
        guard PersonalModel.isLearnable(Lexicon.fold(word)) else { return nil }
        // The keys the letters are on: "ñ" was typed on n.
        let letters = Array(Lexicon.fold(word))
        let source: SettledWord.Source = last.picked ? .next : last.fixedFrom != nil ? .fixed
            : last.pieces.allSatisfy(\.isTap) ? .tapped : .swiped
        var touches: [SettledWord.Touch] = []
        func touch(_ letter: Character, _ piece: Piece, weight: Float) {
            guard let frame = layout.frame(of: .letter(letter), on: piece.side), frame.width > 0, frame.height > 0 else { return }
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
        // A miss with a swipe in it is remembered for the word (features/missed-words
        // Phase B), every touch as the matcher saw it (two thumbs too), in fractions of
        // the keys' width and height.
        var shape: [CGPoint]?
        if last.missed, last.fixedFrom != nil, (1...PersonalModel.maxShapePieces).contains(pieces.count),
           pieces.contains(where: { !$0.isTap }), layout.width > 0, layout.height > 0 {
            shape = pieces.flatMap { Geometry.resample($0.points, count: PersonalModel.shapePoints) }
                .map { CGPoint(x: $0.x / layout.width, y: $0.y / layout.height) }
        }
        return SettledWord(word: word, previous: last.previous, source: source,
                           fixedFrom: last.fixedFrom?.lowercased(), firstGuess: last.firstGuess?.lowercased(),
                           pecked: !last.picked && last.pieces.allSatisfy(\.isTap), touches: touches, strokes: strokes,
                           missed: last.missed && last.fixedFrom != nil, shape: shape, shapeSplit: layout.split)
    }

    private func cased(_ word: String) -> String { Self.cased(word, as: casing) }

    private static func cased(_ word: String, as casing: Casing) -> String {
        switch casing {
        case .lower: word
        case .upper: word.uppercased()
        case .capital: word.prefix(1).uppercased() + word.dropFirst()
        }
    }

    private var effectiveShift: Shift {
        if shift != .off { return shift }
        guard settings.autoCapitalize, pieces.isEmpty, open.isEmpty else { return .off }
        switch settings.capitals {
        case .none: return .off
        case .all: return .locked
        case .words: return Self.startsWord(contextBefore) ? .on : .off
        case .sentences: return Self.startsSentence(contextBefore) ? .on : .off
        }
    }

    static func startsWord(_ before: String) -> Bool {
        guard let last = before.last else { return true }
        return last.isWhitespace || last.isNewline
    }

    static func startsSentence(_ before: String) -> Bool {
        // "¿" or "¡" opening a sentence: the word after it is its first ("¿Qué").
        if let last = before.last, Accents.openers.contains(last) {
            return startsSentence(String(before.dropLast()))
        }
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
        // "Not it?" for a swiped word only: pecked letters were typed as meant.
        let swiped = { (pieces: [Piece]) in pieces.contains { !$0.isTap } }
        state.canCorrect = correction == nil && open.isEmpty
            && (hasOpenWord ? swiped(pieces) : committed.map { !$0.missed && swiped($0.pieces) } ?? false)
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
              let frame = layout.frame(of: .letter(letter), on: layout.side(at: point)) else { return point }
        let offset = personal.offset(for: letter, side: side)
        guard offset != .zero else { return point }
        return CGPoint(x: point.x - offset.dx * frame.width, y: point.y - offset.dy * frame.height)
    }
}
