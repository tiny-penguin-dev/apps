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
/// The open word is shown in the field as ordinary text, replaced by each new reading
/// (`.mark`) until it commits (`.commit`). It is never marked (underlined) text: that hid
/// the person's taps and selections from the keyboard (removed 8 Nov 2026).
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
        /// The text replacements (features/text-replacements): a word that is a
        /// shortcut goes in as its phrase, variables filled in.
        public var replacements = TextReplacements()
        /// Whether replacements apply in this field: not in a password, a code or a
        /// number, nor where corrections are off (`Field.replacesText`).
        public var replacesText = true
        /// What `{name}`, `{email}`, `{phone}` and `{address}` write.
        public var details = PersonalDetails()
        /// The bar offers the person's details (features/autofill): the person's switch.
        public var autofills = true
        /// The details the field wants while it is empty, best first (`Field.autofillSlots`).
        public var autofill: [Autofill.Slot] = []
        /// When the next word, typed fast, shows the word before was the wrong reading
        /// of its swipe or taps, swap it for the right one (features/look-back).
        public var fixesAsYouGo = true
        /// Return is the field's action key (search, go, send, next, ...), not a new
        /// line (`Field.ReturnKey.acts`). Nothing may change the text once the "\n" has
        /// gone, since the app has already acted on it.
        public var returnActs = false
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
        /// The person put the cursor in a word written earlier, or selected it
        /// (features/fix-earlier-word): that word (`chosen`) and its other readings.
        /// Tapping one swaps it in (`choose(guess:)`); "Not it?" types the word meant.
        case earlier([String], chosen: Int)
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
        /// Show this as the open word, replaced by the next `.mark`.
        case mark(String)
        /// The open word goes in as this.
        case commit(String)
        /// Take the open word out.
        case clearMark
        case haptic(Haptic)
        /// A word pecked out letter by letter that the keyboard did not know went in and
        /// stayed in (it settled): the host adds it to the learned words (and keeps them).
        /// A word fixed before the next one starts is never learned (features/word-control).
        case learn(String)
        /// Takes back one use of a learned word (`LearnedWords.unlearn`). No longer sent
        /// since words are learned when they settle; kept so old typing logs still read.
        case unlearn(String)
        /// Something to say in the bar for a moment; nothing changed in the field.
        case notice(Notice)
        /// Move the cursor by this many characters (negative is left), to reach a word
        /// written earlier and to come back after fixing it (features/fix-earlier-word).
        case moveCursor(Int)
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
        /// What space would write for the open word when it is a text replacement's
        /// shortcut: the phrase, variables filled in (features/text-replacements). The
        /// bar shows it in the chosen word's place.
        public var replacement: String?
        /// The same for every guess on the bar that is a shortcut, by the guess as shown:
        /// the bar shows each one's phrase. A shortcut being typed shows as a guess too
        /// (`TextReplacements.completion`).
        public var previews: [String: String] = [:]
        /// A replacement is asking for its `{?blanks}` (features/text-replacements): the
        /// one being typed, by name. The bar shows `.correcting` with what is typed so far.
        public var fillPrompt: String?
        /// With no word open, a shortcut of symbols right before the cursor ("@@"), or
        /// one being typed ("@"): its phrase, which the bar offers (`writeShortcut`).
        /// Space writes it too once the shortcut is whole.
        public var shortcutPhrase: String?
        /// The person's details the bar offers (features/autofill): for an empty field
        /// that asks for them, after "my email is ", or the one being typed. Tapped with
        /// `fill(autofill:)`.
        public var autofill: [Autofill.Offer] = []
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
        /// The word to learn when it settles (`.learn`), if it is still there then.
        var learned: String?
        /// A next-word guess tapped on the bar, not typed: nothing to reopen.
        var picked = false
        /// The person typed this word with "Not it?" in place of the swipe's guess.
        var missed = false
        /// When autospace wrote the space after it; nil when anything else did.
        var autospaced: TimeInterval?
        /// The shortcut typed, when the word in the field is its replacement's phrase:
        /// nothing is learned from it.
        var replaced: String?
        /// Its readings with their scores, lowercase, for looking back at it once the
        /// next word is in (features/look-back). Empty when it had no other.
        var readings: [Candidate] = []
        /// When it went in.
        var time: TimeInterval?
        /// The text before it, for the next-word model to read each reading after.
        var before = ""
        /// Picked from the bar while it was open, not the keyboard's own guess.
        var byHand = false
        /// Swapped by looking back (features/look-back): never looked back at again,
        /// and the word after it isn't either.
        var lookedBack = false
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
            matcher.shortcuts = Self.shortcuts(settings)
            if settings.autofills != oldValue.autofills || settings.autofill != oldValue.autofill
                || settings.details != oldValue.details || settings.replacesText != oldValue.replacesText {
                refreshAutofill()
            }
        }
    }
    /// The date and time variables in replacements fill in with (`TextReplacements.expand`).
    /// The one clock the composer reads; tests set a fixed day.
    public var wallClock: @Sendable () -> Date = { Date() }
    /// The language and time zone the variables are written in.
    public var replacementLocale = Locale.current
    public var replacementTimeZone = TimeZone.current
    /// What was copied, for `{clipboard}`: read only when a phrase going in asks for it.
    /// The host gives it the pasteboard (Full Access).
    public var clipboard: @Sendable () -> String? = { nil }
    /// A number below the one given, for `{pick:…}`; tests make it fixed.
    public var random: @Sendable (Int) -> Int = { Int.random(in: 0..<max(1, $0)) } {
        didSet { pickRoll = random(Self.rollRange) }
    }
    /// The roll `{pick:…}` uses, kept until a phrase goes in, so the bar shows the pick
    /// that space would write.
    private var pickRoll = Int.random(in: 0..<Composer.rollRange)
    private static let rollRange = 720_720
    /// A replacement asking for its blanks, while it does.
    private var filling: Filling?
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
    /// Shift was tapped to turn off the capital a sentence start would give (Apple's
    /// keyboard does the same): the next word starts lowercase. Spent like one-shot shift,
    /// and gone once anything else is typed or the text before the cursor changes.
    private var autoShiftDismissed = false
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
    /// The last next-word guesses, lowercase, by the word they follow and how many: the
    /// context is passed back after every change, mostly unchanged.
    private var nextCache: (previous: String, count: Int, words: [String])?
    /// The next-word models of the languages loaded (features/next-word-model), set by
    /// the keyboard once they load; empty uses the word pairs alone. With a sentence
    /// locked to one language only that language's model guesses.
    public var nextWordModels: [NextWordModel] = [] {
        didSet { if pieces.isEmpty, open.isEmpty { offerNextWords(); refreshState() } }
    }
    /// The word meant, while "Not it?" is open, and the bar to go back to on cancel.
    private var correction: String?
    private var barBeforeCorrection: Bar = .idle
    /// The word written earlier that the cursor is in, while the bar shows it.
    private var earlier: Earlier?
    /// The last words that went in, newest last, with their pieces and readings, so a
    /// word fixed later shows what the swipe could have been (features/fix-earlier-word).
    /// Kept in memory only, and dropped when the keyboard goes away.
    private var recentWords: [Committed] = []
    static let recentLimit = 20
    /// The last earlier word swapped, until anything else happens: Undo puts it back.
    private var lastEarlierFix: EarlierFix?
    /// The word before the open one, when it may still be looked back at: it settles
    /// (and is learned) only once the next word is in and the check is done, so a
    /// swapped word teaches the right word (features/look-back).
    private var waiting: Committed?
    /// The last swap by looking back, until anything else happens: Undo puts it back.
    private var lastLookBack: LookBackFix?
    /// How many swaps looking back has made, for the host to notice a new one and say so.
    public private(set) var lookBackCount = 0
    /// How much better another reading must fit to replace the one written
    /// (`LookBack.margin`); the harness tries others.
    public var lookBackMargin = LookBack.margin

    public init(dictionary: Lexicon, learned: LearnedWords = LearnedWords(), layout: Layout, settings: Settings = Settings()) {
        self.layout = layout
        self.settings = settings
        self.matcher = Matcher(dictionary: dictionary, layout: layout, learned: learned)
        matcher.strictness = settings.strictness
        matcher.splitStrictness = settings.splitStrictness
        matcher.shortcuts = Self.shortcuts(settings)
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
        matcher.shortcuts = Self.shortcuts(settings)
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
            autoShiftDismissed = false
            joinable = committed.flatMap { last in
                last.autospaced.map { time - $0 <= Self.joinWindow } == true && contextBefore.hasSuffix(last.word + last.trailing) ? last : nil
            }
            if committed != nil { effects += settle(nextAt: time) }
            leaveEarlier()
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
        matcher.learnedLanguage = code
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
        if key != .shift { leaveEarlier() }
        var effects: [Effect] = [.haptic(.key)]
        let spaced = autoSpaced
        let previousSpace = lastSpace
        if key != .shift {
            autoSpaced = false
            wordSpace = false
            lastSpace = nil
            // A letter press is a tap: `touchDown` reads the dismissal first, then spends it.
            if key.character == nil { autoShiftDismissed = false }
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
            } else if let replaced = replaceToken(trailing: " ") {
                effects += replaced
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
            } else if let replaced = replaceToken(trailing: "\n") {
                effects += replaced
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
                autoShiftDismissed = false
            } else if shift == .on {
                // Off again: lowercase, even where a sentence start would capitalise.
                shift = .off
                autoShiftDismissed = true
            } else if shift == .locked {
                shift = .off
            } else if effectiveShift != .off {
                // A sentence start's capital: one tap turns it off for this word.
                autoShiftDismissed = true
            } else {
                shift = .on
                autoShiftDismissed = false
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
            if filling != nil {
                typeCorrection(text)
                return [.haptic(.key)]
            }
            // Only what can be part of a word: "don't", "e-mail".
            guard text.count == 1, let character = text.first, character == "'" || character == "-" || character == "’" else { return [] }
            typeCorrection(character == "’" ? "'" : character)
            return [.haptic(.key)]
        }
        leaveEarlier()
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
        leaveEarlier()
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
        case .earlier(let words, let chosen):
            guard words.indices.contains(index), index != chosen else { return [] }
            return fixEarlier(to: words[index], missed: false)
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
        autoShiftDismissed = false
        let learn = wordToLearn(word)
        committed = Committed(word: word, trailing: " ", pieces: [], guesses: [word], casing: casing,
                              previous: matcher.context.last, firstGuess: word, learned: learn, picked: true)
        effects += [.insert(gap + word + " "), .haptic(.commit)]
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
        leaveEarlier()
        recentWords = []
        guard !hasOpenWord, committed != nil || waiting != nil else { return [] }
        let effects = settle()
        state.bar = .idle
        refreshState()
        return effects
    }

    /// Back to the bar as it was, nothing changed.
    public mutating func cancelCorrection(time: TimeInterval = 0) {
        guard correction != nil else { return }
        correction = nil
        // A replacement asking for blanks: the shortcut stays in the field as typed.
        if filling != nil {
            filling = nil
            state.fillPrompt = nil
            barBeforeCorrection = .idle
        }
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
        if filling != nil { return saveFill(typed, time: time) }
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
                                  firstGuess: words.first, missed: true)
            pieces = []
            candidates = []
            autospaceDue = nil
            autoSpaced = true
            wordSpace = true
            joinable = nil
            effects = [.commit(word), .insert(" "), .haptic(.commit)]
        } else if let spot = earlier {
            effects = fixEarlier(to: Self.cased(meant, as: spot.casing), missed: true)
        } else if var last = committed {
            let word = Self.cased(meant, as: last.casing)
            let original = last.fixedFrom ?? last.word
            effects = [.deleteBackward(last.word.count + last.trailing.count), .insert(word + last.trailing), .haptic(.commit)]
            last.word = word
            last.fixedFrom = original.lowercased() == meant ? nil : original
            last.missed = true
            // Learned now, below: the word was spelled out on purpose.
            last.learned = nil
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
        if filling != nil { return typeCorrection(String(letter)) }
        guard var typed = correction, typed.count < 40 else { return }
        typed.append(Character(letter.lowercased()))
        correction = typed
        state.bar = .correcting(typed)
    }

    /// Text typed into a blank: kept as typed, a capital where shift says.
    private mutating func typeCorrection(_ text: String) {
        guard var typed = correction, typed.count + text.count <= Self.blankLimit else { return }
        if shift != .off, text.count == 1 {
            typed += text.uppercased()
            if shift == .on { shift = .off }
        } else {
            typed += text
        }
        correction = typed
        state.bar = .correcting(typed)
        refreshState()
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
        case .space where filling != nil:
            typeCorrection(" ")
        case .shift where filling != nil:
            if let last = lastShiftPress, time - last < 0.35 {
                shift = shift == .locked ? .off : .locked
            } else {
                shift = shift == .off ? .on : .off
            }
            lastShiftPress = time
            refreshState()
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
        if (before ?? "") != contextBefore { autoShiftDismissed = false }
        contextBefore = before ?? ""
        // The cursor moved, or the app changed the text: that space is gone from under it.
        if let before, !before.hasSuffix(" ") {
            autoSpaced = false
            wordSpace = false
            lastSpace = nil
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
        case .guesses, .correcting, .earlier: return
        case .idle: fix = nil
        case .fix(let words, let chosen): fix = (words, chosen)
        case .next(_, let words, let chosen): fix = words.count > 1 ? (words, chosen) : nil
        }
        let count = settings.guessCount
        var next: [String] = []
        let models = nextWordModels.filter { lockedLanguage == nil || $0.code == lockedLanguage }
        if settings.nextWords, count > 0, !models.isEmpty {
            // The next-word model reads the whole sentence (features/next-word-model);
            // it keeps its own last answer, so this is cheap when nothing changed.
            var fromModel: [String: Float] = [:]
            for model in models {
                for (word, p) in model.guesses(before: contextBefore, limit: count + 8) {
                    fromModel[word] = max(fromModel[word] ?? 0, p)
                }
            }
            if !fromModel.isEmpty {
                let ranked = fromModel.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
                next = NextWords.guesses(after: matcher.context.last ?? "", models: [], personal: personal,
                                         learned: matcher.learned, count: count,
                                         fromModel: ranked.map { (word: $0.key, probability: $0.value) })
                    .map { casedNext(matcher.dictionary.spellings(of: $0).first?.word ?? $0) }
            }
        }
        if next.isEmpty, settings.nextWords, count > 0, let previous = matcher.context.last {
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
        if case .earlier(let words, let chosen) = state.bar, var spot = earlier {
            // A blocked reading goes; the word in the field stays.
            let kept = words.enumerated()
                .filter { $0.offset == chosen || matcher.learned.weight(of: $0.element.lowercased()) >= 0 }
                .map(\.element)
            spot.chosen = kept.firstIndex(of: words[chosen]) ?? 0
            spot.words = kept
            earlier = spot
            state.bar = .earlier(kept, chosen: spot.chosen)
            refreshState()
        } else if case .fix(let words, let chosen) = state.bar {
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
        filling = nil
        state.fillPrompt = nil
        leaveEarlier()
        let effects = settle()
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
        committed = nil
        leaveEarlier()
        state.bar = .idle
        autospaceDue = nil
        autoSpaced = false
        wordSpace = false
        joinable = nil
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
        let effects: [Effect] = [.haptic(.key), .deleteBackward(max(1, count))]
        return effects
    }

    /// The cursor is about to move (a slide on the space bar): the open word goes in as
    /// it stands, with nothing after it, and the fix bar closes.
    public mutating func cursorWillMove() -> [Effect] {
        cancelCorrection()
        leaveEarlier()
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

    // MARK: Earlier words

    /// The word written earlier that the bar shows (features/fix-earlier-word).
    private struct Earlier {
        var spot: EarlierSpot
        var words: [String]
        var chosen: Int
        var casing: Casing
        /// The word before it, as the matcher reads it.
        var previous: String?
        /// Its place in `recentWords`, when it is one of the last words written.
        var recent: Int?
    }

    /// The last swap, for Undo: what was there, what went in, and how far the cursor
    /// came back past it.
    private struct EarlierFix {
        var old: String
        var new: String
        var rest: Int
        var recent: Int?
    }

    /// The person put the cursor in or right after a word written earlier, or selected
    /// it (`EarlierSpot.find`): the bar shows that word and its other readings. The
    /// readings are the swipe's when it is one of the last words written, otherwise the
    /// nearest words to its letters. Nil, or a word open, closes it. The last word is
    /// final then: the person moved on from it.
    public mutating func cursorLanded(at spot: EarlierSpot?) -> [Effect] {
        guard correction == nil, pieces.isEmpty, open.isEmpty else { return [] }
        lastEarlierFix = nil
        guard let spot else {
            if earlier != nil {
                earlier = nil
                state.bar = .idle
                offerNextWords()
                refreshState()
            }
            return []
        }
        let effects = settle()
        autoSpaced = false
        wordSpace = false
        joinable = nil
        autospaceDue = nil
        let lower = spot.word.lowercased()
        let before = spot.offset <= contextBefore.count ? String(contextBefore.dropLast(spot.offset)) : ""
        let previous = WordContext.words(before: before).last
        let casing: Casing = spot.word.count > 1 && spot.word == spot.word.uppercased() ? .upper
            : spot.word.first?.isUppercase == true ? .capital : .lower
        var words: [String] = []
        var recent: Int?
        if let index = recentWords.lastIndex(where: { $0.word.lowercased() == lower && $0.guesses.count > 1
                                                      && ($0.previous == nil || previous == nil || $0.previous == previous) }) {
            recent = index
            for guess in recentWords[index].guesses {
                let word = Self.cased(guess.lowercased(), as: casing)
                if !words.contains(word) { words.append(word) }
            }
        } else {
            var reader = matcher
            reader.context = WordContext.words(before: before)
            reader.nextWords = []
            let near = reader.nearestWords(to: Lexicon.fold(lower), points: [], limit: settings.guessCount + 2)
            words = [spot.word]
            for candidate in near where candidate.word != lower && !matcher.learned.isBlocked(candidate.word) {
                let word = Self.cased(candidate.word, as: casing)
                if !words.contains(word) { words.append(word) }
                if words.count >= max(2, settings.guessCount) { break }
            }
        }
        let chosen = words.firstIndex(of: spot.word) ?? words.firstIndex { $0.lowercased() == lower } ?? {
            words.insert(spot.word, at: 0)
            return 0
        }()
        earlier = Earlier(spot: spot, words: words, chosen: chosen, casing: casing, previous: previous, recent: recent)
        state.bar = .earlier(words, chosen: chosen)
        refreshState()
        return effects
    }

    /// Swaps the earlier word for `new` in place, then puts the cursor back where the
    /// person was typing. Learned like a fix of the last word when it is one of the last
    /// words written (its swipe is known): `missed` when it was typed with "Not it?".
    private mutating func fixEarlier(to new: String, missed: Bool) -> [Effect] {
        guard let spot = earlier else { return [] }
        let old = spot.spot.word
        var effects: [Effect] = []
        if spot.spot.selected {
            effects.append(.insert(new))
        } else {
            let tail = old.count - spot.spot.offset
            if tail > 0 { effects.append(.moveCursor(tail)) }
            effects += [.deleteBackward(old.count), .insert(new)]
        }
        if spot.spot.rest > 0 { effects.append(.moveCursor(spot.spot.rest)) }
        effects.append(.haptic(.commit))
        if let index = spot.recent, recentWords.indices.contains(index) {
            let entry = recentWords[index]
            let fixed = Committed(word: new, trailing: "", pieces: entry.pieces, guesses: entry.guesses, casing: spot.casing,
                                  previous: spot.previous, fixedFrom: old, firstGuess: entry.firstGuess, missed: missed)
            if let settled = Self.settled(fixed, layout: layout) { effects.append(.settled(settled)) }
            recentWords[index].word = new
        }
        lastEarlierFix = EarlierFix(old: old, new: new, rest: spot.spot.rest, recent: spot.recent)
        earlier = nil
        state.bar = .idle
        refreshState()
        return effects
    }

    /// Undo after a swap: the word that was there goes back, the cursor where it is.
    /// Nothing once anything else happened.
    public mutating func undoEarlierFix() -> [Effect] {
        if lastLookBack != nil { return undoLookBack() }
        guard let fix = lastEarlierFix else { return [] }
        lastEarlierFix = nil
        var effects: [Effect] = []
        if fix.rest > 0 { effects.append(.moveCursor(-fix.rest)) }
        effects += [.deleteBackward(fix.new.count), .insert(fix.old)]
        if fix.rest > 0 { effects.append(.moveCursor(fix.rest)) }
        if let index = fix.recent, recentWords.indices.contains(index) { recentWords[index].word = fix.old }
        effects.append(.haptic(.key))
        return effects
    }

    /// Whether Undo can still put back the last earlier word swapped.
    public var canUndoEarlierFix: Bool { lastEarlierFix != nil || lastLookBack != nil }

    /// The last swap Undo would put back was made by looking back (features/look-back),
    /// not by the person.
    public var undoesLookBack: Bool { lastLookBack != nil }

    /// The last swap made by looking back, while Undo can still put it back: the word
    /// that was there and the one that went in.
    public var lookBackChange: (old: String, new: String)? { lastLookBack.map { ($0.old, $0.new) } }

    /// The word written earlier that the bar shows, as it stands in the field.
    public var earlierWord: String? { earlier?.spot.word }

    /// Anything else happened: the bar stops showing the earlier word, and Undo is gone.
    private mutating func leaveEarlier() {
        lastEarlierFix = nil
        lastLookBack = nil
        guard earlier != nil else { return }
        earlier = nil
        if case .earlier = state.bar { state.bar = .idle }
    }

    // MARK: Looking back

    /// A swap made by looking back, for Undo: the word that was there, the one that went
    /// in, and what was typed after it (its space, the next word and what followed).
    private struct LookBackFix {
        var old: String
        var new: String
        var rest: String
    }

    /// How soon after a word went in the next one must start for the keyboard to look
    /// back at it: later, the person had time to read it and kept it (Gabriel, 11 Nov
    /// 2026: "it should only happen when typing fast").
    public static let lookBackStart: TimeInterval = 1.0
    /// How soon after a word went in the next one must be finished (its last finger up):
    /// a word on screen longer than this never changes.
    public static let lookBackEnd: TimeInterval = 2.0

    /// Whether `last`, about to settle as the next word starts, may still be looked back
    /// at once that word is in: the keyboard's own guess, with other readings, typed
    /// as one word with a space after it, and not right after a word already swapped.
    private func mayLookBack(at last: Committed) -> Bool {
        guard settings.fixesAsYouGo, !settings.exactTaps, last.readings.count > 1, !last.byHand, !last.picked,
              !last.missed, last.fixedFrom == nil, last.replaced == nil, !last.lookedBack, last.trailing == " " else { return false }
        return recentWords.last?.lookedBack != true
    }

    /// The open word's readings with their scores, lowercase, for looking back at it
    /// later (`chosen` is the one going in). Pecked letters that spell a word have only
    /// longer words behind them on the bar, so the real words their taps were close to
    /// are added ("thai" tapped for "this").
    private func lookBackReadings(chosen: String) -> [Candidate] {
        guard !pieces.isEmpty else { return [] }
        var best: [String: Double] = [:]
        for candidate in candidates { best[candidate.word.lowercased()] = max(best[candidate.word.lowercased()] ?? -.infinity, candidate.score) }
        let taps = pieces.sorted { $0.start < $1.start }
        if taps.allSatisfy(\.isTap) {
            let letters = String(taps.flatMap(\.keys)).lowercased()
            if letters.count >= 2, letters.count == taps.count {
                for candidate in matcher.tappedReadings(of: letters, points: taps.map { $0.landing ?? $0.points.first }, limit: 3) {
                    // Scored alike, the context included: these replace what the bar had.
                    best[candidate.word] = candidate.score
                }
            }
        }
        let lower = chosen.lowercased()
        guard best[lower] != nil, best.count > 1 else { return [] }
        return Matcher.ranked(best).filter { !matcher.learned.isBlocked($0.word) }
    }

    /// The text before the open word: the context without the word shown in the field.
    static func withoutOpenWord(_ text: String) -> String {
        var rest = Substring(text)
        while let last = rest.last, !(last.isWhitespace || last.isNewline) { rest = rest.dropLast() }
        return String(rest)
    }

    /// The word just written (`committed`) went in fast after the one before
    /// (`waiting`): when it shows that word was a wrong reading, swap it
    /// (features/look-back). One word back, from the readings it already had; the text
    /// is deleted back to it and written again, so the cursor stays where it is.
    private mutating func lookBack() -> [Effect] {
        guard settings.fixesAsYouGo, var earlier = waiting, var last = committed, let went = earlier.time,
              let start = last.pieces.map(\.start).min(), let end = last.pieces.map(\.end).max(),
              start - went <= Self.lookBackStart, end - went <= Self.lookBackEnd,
              last.replaced == nil, Self.withoutOpenWord(contextBefore).hasSuffix(earlier.word + earlier.trailing),
              // The app has acted on the return already (searched, sent): leave the text.
              !(settings.returnActs && last.trailing.contains("\n")),
              let current = earlier.readings.firstIndex(where: { $0.word == earlier.word.lowercased() }) else { return [] }
        let models = nextWordModels.filter { lockedLanguage == nil || $0.code == lockedLanguage }
        let next = last.word
        let before = earlier.before
        let reader = matcher
        let pick = LookBack.choose(readings: earlier.readings, current: current, margin: lookBackMargin) { reading in
            let scores = models.compactMap { $0.scores(before: before + reading + " ") }
            return reader.followBonus(next, after: reading, models: scores)
        }
        guard let pick else { return [] }
        let old = earlier.word
        let new = Self.cased(earlier.readings[pick].word, as: earlier.casing)
        guard new != old else { return [] }
        let rest = earlier.trailing + last.word + last.trailing
        earlier.word = new
        earlier.firstGuess = new
        earlier.learned = nil
        earlier.lookedBack = true
        last.previous = Lexicon.fold(new.lowercased())
        waiting = earlier
        committed = last
        lastLookBack = LookBackFix(old: old, new: new, rest: rest)
        lookBackCount += 1
        return [.deleteBackward(old.count + rest.count), .insert(new + rest)]
    }

    /// Undo after a swap by looking back: the word that was there goes back, when the
    /// text after it is still what was typed.
    private mutating func undoLookBack() -> [Effect] {
        guard let fix = lastLookBack else { return [] }
        lastLookBack = nil
        guard contextBefore.hasSuffix(fix.new + fix.rest) else { return [] }
        if waiting?.word == fix.new { waiting?.word = fix.old }
        if committed != nil { committed?.previous = Lexicon.fold(fix.old.lowercased()) }
        return [.deleteBackward(fix.new.count + fix.rest.count), .insert(fix.old + fix.rest), .haptic(.key)]
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
        // The next-word model weighs in on which guess fits the sentence; it read this
        // sentence already for the bar, so this is mostly its kept answer.
        matcher.nextWords = nextWordModels.filter { lockedLanguage == nil || $0.code == lockedLanguage }
            .compactMap { $0.scores(before: contextBefore) }
        candidates = matcher.candidates(for: pieces, limit: settings.guessCount, final: final)
        var words = candidates.map { cased($0.word) }
        if let tapped = tappedLetters {
            let typed = cased(tapped)
            words.removeAll { $0 == typed }
            words = Array(([typed] + words).prefix(max(1, settings.guessCount)))
        }
        // A shortcut being typed shows on the bar, its phrase in place (features/text-
        // replacements: suggest as you type); it takes the last guess's place.
        if let first = words.first, let shortcut = completion(of: first), !words.contains(shortcut) {
            if words.count < max(1, settings.guessCount) { words.append(shortcut) } else if words.count > 1 { words[words.count - 1] = shortcut }
        }
        return words
    }

    /// The shortcut that the open word (with what is typed before it) begins, as the
    /// open word would be to finish it, cased like it.
    private func completion(of word: String) -> String? {
        guard settings.replacesText, !settings.replacements.isEmpty else { return nil }
        let prefix = tokenBefore
        guard let shortcut = settings.replacements.completion(of: prefix + word) else { return nil }
        let rest = String(shortcut.dropFirst(prefix.count))
        return rest.isEmpty ? nil : cased(rest)
    }

    /// The open word comes right after an @ or a # ("@vady" on the way to a GitHub
    /// handle, "#tbt"): a name or a tag, rarely a dictionary word, so taps go in
    /// exactly as tapped (the nearest words wait in the bar), are never learned, and
    /// are never looked back at. Swipes still read as words (Gabriel, 13 Nov 2026:
    /// "@vady" kept turning into "day").
    var afterTag: Bool {
        guard let last = tokenBefore.last else { return false }
        return last == "@" || last == "#"
    }

    /// The open word's letters exactly as tapped, when taps are typed exactly (the
    /// field says so, or the word follows an @ or a #) and every piece is a tap.
    private var tappedLetters: String? {
        guard settings.exactTaps || afterTag, !pieces.isEmpty, pieces.allSatisfy(\.isTap) else { return nil }
        return String(pieces.sorted { $0.start < $1.start }.flatMap(\.keys))
    }

    /// What goes in after a word: nothing, or its own insert, so a return's "\n" reaches
    /// the app alone and the app runs its action (search, go, send) instead of taking it
    /// as a new line.
    static func trailing(_ trailing: String) -> [Effect] { trailing.isEmpty ? [] : [.insert(trailing)] }

    private mutating func commit(trailing: String, time: TimeInterval, byHand: Bool = false) -> [Effect] {
        // A return that acts (search, go, send) takes pecked letters as they are: "sli"
        // searched once the app offered Slickdeals, not fixed to a word ("i"; Gabriel,
        // 13 Nov 2026). A search is often the start of a word or a name.
        let searched = settings.returnActs && trailing == "\n"
        if !byHand, !searched { settleGuesses() }
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
        if let found = shortcut(for: word) { return replace(word, with: found, guesses: words, chosen: chosen, trailing: trailing) }
        if !byHand, let before, let joined = join(word, to: before, trailing: trailing) { return joined }
        // Letters searched as they are are not learned as a new word: they are mostly
        // the start of one.
        let learn = searched && !matcher.learned.contains(word.lowercased()) ? nil : wordToLearn(word)
        committed = Committed(word: word, trailing: trailing, pieces: pieces, guesses: words, casing: casing,
                              previous: matcher.context.last, firstGuess: words.first, learned: learn,
                              readings: settings.fixesAsYouGo && !byHand && !afterTag ? lookBackReadings(chosen: word) : [],
                              time: time, before: Self.withoutOpenWord(contextBefore), byHand: byHand)
        pieces = []
        candidates = []
        autospaceDue = nil
        state.bar = words.count > 1 ? .fix(words, chosen: chosen) : .idle
        refreshState()
        var effects: [Effect] = [.commit(word)] + Self.trailing(trailing) + [.haptic(.commit)]
        effects += lookBack()
        return effects
    }

    /// The shortcuts the matcher offers as words: none where replacements are off. A
    /// shortcut with symbols in it (";addr", "addr1") offers its letters, so they type
    /// as written.
    private static func shortcuts(_ settings: Settings) -> Set<String> {
        guard settings.replacesText else { return [] }
        var words = settings.replacements.shortcuts
        for key in settings.replacements.phrases.keys where !TextReplacements.isWord(key) {
            for letters in key.split(whereSeparator: { !$0.isLetter }) where letters.count >= 2 { words.insert(String(letters)) }
        }
        return words
    }

    // MARK: Text replacements

    /// A replacement asking for its blanks before it goes in (`{?name}`).
    private struct Filling: Sendable {
        var phrase: String
        var blanks: [String]
        var values: [String: String] = [:]
        /// What is in the field before the cursor that the phrase takes the place of:
        /// the shortcut as typed. Empty from the snippet page.
        var original: String
        var trailing: String
        var capital: Bool
        var gap: String
    }

    /// The longest a blank's answer can be.
    static let blankLimit = 200

    /// The characters right before the open word that are no space ("；" of ";addr").
    private var tokenBefore: String {
        String(contextBefore.reversed().prefix { !$0.isWhitespace && !$0.isNewline }.reversed())
    }

    /// The shortcut the open word `word` finishes, with what was typed before it
    /// (";" then "addr"), when there is one: its phrase, and the text it replaces.
    private func shortcut(for word: String) -> (phrase: String, prefix: String)? {
        guard settings.replacesText, !settings.replacements.isEmpty else { return nil }
        let prefix = tokenBefore
        if !prefix.isEmpty, let phrase = settings.replacements.phrase(for: prefix + word) { return (phrase, prefix) }
        return settings.replacements.phrase(for: word).map { ($0, "") }
    }

    /// What the variables fill in from right now.
    private func replacementContext(filled: [String: String] = [:], preview: Bool) -> TextReplacements.Context {
        let roll = pickRoll
        var copied = clipboard
        if preview { copied = { "[clipboard]" } }
        return TextReplacements.Context(
            date: wallClock(), locale: replacementLocale, timeZone: replacementTimeZone,
            // The bar never reads the pasteboard; only writing the phrase does.
            clipboard: copied,
            details: settings.details, random: { roll % max(1, $0) }, filled: filled)
    }

    /// `phrase` filled in: a capital on the shortcut (a sentence start, shift)
    /// capitalises the phrase too.
    private func expansion(of phrase: String, capital: Bool, filled: [String: String] = [:],
                           preview: Bool = false) -> TextReplacements.Expansion {
        var out = TextReplacements.expand(phrase, in: replacementContext(filled: filled, preview: preview))
        if capital, let first = out.text.first, first.isLowercase { out.text = first.uppercased() + out.text.dropFirst() }
        return out
    }

    /// What the bar shows for `word` as the open word: its phrase filled in, if it's a shortcut.
    private func replacement(for word: String) -> String? {
        guard let found = shortcut(for: word) else { return nil }
        return expansion(of: found.phrase, capital: word.first?.isUppercase == true, preview: true).text
    }

    /// The open word is a shortcut: its phrase goes in, and the bar offers the shortcut
    /// as typed behind it, to take the replacement back. Backspace reopens the shortcut.
    private mutating func replace(_ word: String, with found: (phrase: String, prefix: String), guesses words: [String],
                                  chosen: Int, trailing: String) -> [Effect] {
        let others = words.enumerated().filter { $0.offset != chosen }.map(\.element)
        return putReplacement(found.phrase, original: found.prefix + word, open: word, trailing: trailing,
                              capital: word.first?.isUppercase == true, others: others)
    }

    /// Writes `phrase` in place of `original` (what is before the cursor, with the open
    /// word `open` still marked when there is one), then `trailing`. A phrase with
    /// blanks asks for them first (`State.fillPrompt`), with the shortcut left as typed.
    /// `literal` writes `phrase` as it is, with no variables (a detail from autofill).
    private mutating func putReplacement(_ phrase: String, original: String, open word: String?, trailing: String,
                                         capital: Bool, others: [String] = [], gap: String = "",
                                         literal: Bool = false) -> [Effect] {
        let typed = pieces
        pieces = []
        candidates = []
        autospaceDue = nil
        committed = nil
        let blanks = literal ? [] : TextReplacements.blanks(in: phrase)
        if let first = blanks.first {
            filling = Filling(phrase: phrase, blanks: blanks, original: original, trailing: trailing, capital: capital, gap: gap)
            correction = ""
            barBeforeCorrection = .idle
            open = [:]
            state.bar = .correcting("")
            state.fillPrompt = first
            refreshState()
            return (word.map { [.commit($0)] } ?? []) + [.haptic(.commit)]
        }
        let prefix = String(original.dropLast(word?.count ?? 0))
        let text = literal ? TextReplacements.Expansion(text: phrase, cursorFromEnd: nil) : expansion(of: phrase, capital: capital)
        var effects: [Effect]
        if word != nil, prefix.isEmpty {
            effects = [.commit(gap + text.text)]
        } else {
            effects = (word != nil ? [.clearMark] : []) + (prefix.isEmpty ? [] : [.deleteBackward(prefix.count)])
                + [.insert(gap + text.text)]
        }
        return effects + finishReplacement(text, original: original, typed: word != nil && prefix.isEmpty ? typed : [],
                                           trailing: trailing, others: others)
    }

    /// After the phrase is in: the trailing text, the cursor to `{cursor}`, and the bar
    /// offering the shortcut back.
    private mutating func finishReplacement(_ text: TextReplacements.Expansion, original: String, typed: [Piece],
                                            trailing: String, others: [String]) -> [Effect] {
        pickRoll = random(Self.rollRange)
        var effects: [Effect] = []
        if let back = text.cursorFromEnd {
            // The cursor goes back into the phrase: a space after it would be in the way.
            let after = trailing.allSatisfy { $0.isWhitespace || $0.isNewline } ? "" : trailing
            if !after.isEmpty { effects.append(.insert(after)) }
            if back + after.count > 0 { effects.append(.moveCursor(-(back + after.count))) }
            committed = nil
            state.bar = .idle
        } else {
            if !trailing.isEmpty { effects.append(.insert(trailing)) }
            let fix = original.isEmpty || original == text.text ? [text.text]
                : Array(([text.text, original] + others.filter { $0 != text.text && $0 != original })
                    .prefix(max(2, settings.guessCount)))
            committed = Committed(word: text.text, trailing: trailing, pieces: typed, guesses: fix, casing: casing,
                                  previous: matcher.context.last, firstGuess: fix.count > 1 ? fix[1] : nil, learned: nil,
                                  picked: typed.isEmpty, replaced: original.isEmpty ? text.text : original)
            state.bar = fix.count > 1 ? .fix(fix, chosen: 0) : .idle
        }
        refreshState()
        return effects + [.haptic(.commit)]
    }

    /// A blank's answer saved: the next blank, or the phrase goes in.
    private mutating func saveFill(_ typed: String, time: TimeInterval) -> [Effect] {
        guard var fill = filling else { return [] }
        let blank = fill.blanks[fill.values.count]
        fill.values[blank] = typed
        open = [:]
        if fill.values.count < fill.blanks.count {
            filling = fill
            correction = ""
            state.bar = .correcting("")
            state.fillPrompt = fill.blanks[fill.values.count]
            refreshState()
            return [.haptic(.key)]
        }
        filling = nil
        correction = nil
        state.fillPrompt = nil
        let text = expansion(of: fill.phrase, capital: fill.capital, filled: fill.values)
        let effects: [Effect] = (fill.original.isEmpty ? [] : [.deleteBackward(fill.original.count)]) + [.insert(fill.gap + text.text)]
        return effects + finishReplacement(text, original: fill.original, typed: [], trailing: fill.trailing, others: [])
    }

    /// No open word, and space or return pressed after a shortcut with symbols in it
    /// ("@@", "addr1"), which the keys don't type as a word: its phrase takes its place.
    /// A shortcut the keys don't type as a word ("@@", ";addr" before its letters) right
    /// before the cursor, or one it begins: the shortcut's phrase and the text it
    /// takes the place of. Nil while a word is open or the bar is busy.
    private var shortcutAtCursor: (phrase: String, token: String)? {
        guard settings.replacesText, !settings.replacements.isEmpty, pieces.isEmpty, open.isEmpty,
              correction == nil, earlier == nil else { return nil }
        let token = tokenBefore
        let key = token.lowercased()
        guard !token.isEmpty, token.count <= 24, !TextReplacements.isWord(key) else { return nil }
        if let phrase = settings.replacements.phrase(for: key) { return (phrase, token) }
        let longer = settings.replacements.phrases.keys
            .filter { $0.count > key.count && $0.hasPrefix(key) && !TextReplacements.isWord($0) }
            .min { ($0.count, $0) < ($1.count, $1) }
        return longer.flatMap { settings.replacements.phrase(for: $0) }.map { ($0, token) }
    }

    /// The phrase the bar offers for the shortcut at the cursor (`State.shortcutPhrase`)
    /// tapped: it takes the shortcut's place, a space after it as after a word.
    public mutating func writeShortcut(time: TimeInterval) -> [Effect] {
        guard let found = shortcutAtCursor else { return [] }
        leaveEarlier()
        autoSpaced = false
        wordSpace = false
        lastSpace = nil
        return settle() + putReplacement(found.phrase, original: found.token, open: nil,
                                         trailing: settings.spacesWords ? " " : "",
                                         capital: found.token.first?.isUppercase == true)
    }

    private mutating func replaceToken(trailing: String) -> [Effect]? {
        guard settings.replacesText, !settings.replacements.isEmpty else { return nil }
        let token = tokenBefore
        guard !token.isEmpty, !TextReplacements.isWord(token.lowercased()),
              let phrase = settings.replacements.phrase(for: token) else { return nil }
        return settle() + putReplacement(phrase, original: token, open: nil, trailing: trailing,
                                         capital: token.first?.isUppercase == true)
    }

    /// The person picked a replacement on the snippet page: an open word goes in first,
    /// then the phrase, a space before it when the text needs one and after it as a
    /// word would have.
    public mutating func write(replacement shortcut: String, time: TimeInterval) -> [Effect] {
        guard let phrase = settings.replacements.phrase(for: shortcut) else { return [] }
        if correction != nil { cancelCorrection(time: time) }
        leaveEarlier()
        var effects: [Effect] = []
        // After the open word goes in the field ends in its space; the context comes later.
        let wrote = hasOpenWord
        if wrote { effects += commit(trailing: " ", time: time).filter { $0 != .haptic(.commit) } }
        if filling != nil { return effects }
        effects += settle()
        let gap = wrote || (contextBefore.last.map { $0.isWhitespace || $0.isNewline } ?? true) ? "" : " "
        autoSpaced = false
        wordSpace = false
        lastSpace = nil
        let capital = wrote ? false : Self.startsSentence(contextBefore + gap) && settings.autoCapitalize
            && settings.capitals == .sentences
        return effects + putReplacement(phrase, original: "", open: nil, trailing: settings.spacesWords ? " " : "",
                                        capital: capital, gap: gap)
    }

    // MARK: Autofill

    /// The details the bar offers now (features/autofill): none while a word is being
    /// fixed or a blank asked for.
    private mutating func refreshAutofill() {
        state.autofill = autofillOffers()
    }

    private func autofillOffers() -> [Autofill.Offer] {
        guard settings.autofills, !settings.details.isEmpty, correction == nil, filling == nil else { return [] }
        switch state.bar {
        case .guesses(let words, let chosen):
            // Typing: where replacements apply, or the field asks for a detail.
            guard settings.replacesText || !settings.autofill.isEmpty, words.indices.contains(chosen) else { return [] }
            let word = words[chosen]
            var typed: [String] = []
            // The whole field so far ("Ada " then "By"), when it is one short line.
            let field = contextBefore + word
            if contextBefore.count <= 60, !contextBefore.contains(where: \.isNewline) { typed.append(field) }
            let token = tokenBefore + word
            if !typed.contains(token) { typed.append(token) }
            return Autofill.completion(of: typed, slots: settings.autofill, details: settings.details).map { [$0] } ?? []
        case .idle, .next, .fix:
            guard settings.replacesText || !settings.autofill.isEmpty else { return [] }
            return Autofill.offers(for: settings.autofill, details: settings.details, before: contextBefore)
        case .correcting, .earlier:
            return []
        }
    }

    /// A detail tapped on the bar (`State.autofill`): it goes in at the cursor, in place
    /// of what was typed of it, with no space after. The bar then offers what was typed
    /// back, and backspace reopens it, as after a replacement. Nothing is learned from it.
    public mutating func fill(autofill index: Int, time: TimeInterval) -> [Effect] {
        guard state.autofill.indices.contains(index) else { return [] }
        let offer = state.autofill[index]
        if !offer.replacing.isEmpty {
            guard hasOpenWord, let word = state.openWord, offer.replacing.hasSuffix(word),
                  contextBefore.hasSuffix(String(offer.replacing.dropLast(word.count))) else { return [] }
            joinable = nil
            return putReplacement(offer.text, original: offer.replacing, open: word, trailing: "", capital: false,
                                  literal: true)
        }
        if correction != nil { cancelCorrection(time: time) }
        leaveEarlier()
        var effects: [Effect] = []
        if hasOpenWord { effects += commit(trailing: settings.spacesWords ? " " : "", time: time).filter { $0 != .haptic(.commit) } }
        if filling != nil { return effects }
        effects += settle()
        let gap = contextBefore.last.map { $0.isWhitespace || $0.isNewline } ?? true ? "" : " "
        autoSpaced = false
        wordSpace = false
        lastSpace = nil
        return effects + putReplacement(offer.text, original: "", open: nil, trailing: "", capital: false, gap: gap,
                                        literal: true)
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
        // The model's answer is for the sentence after the first word: the pairs judge.
        matcher.nextWords = []
        guard let whole = matcher.join(before.pieces, pieces, written: (before.word, word)) else { return nil }
        let joined = Self.cased(matcher.dictionary.spellings(of: whole.word).first?.word ?? whole.word, as: before.casing)
        let apart = before.word + " " + word
        let all = (before.pieces + pieces).sorted { $0.start < $1.start }
        pieces = all
        let learn = wordToLearn(joined)
        committed = Committed(word: joined, trailing: trailing, pieces: all, guesses: [joined, apart], casing: before.casing,
                              previous: before.previous, firstGuess: joined, learned: learn)
        pieces = []
        candidates = []
        autospaceDue = nil
        state.bar = .fix([joined, apart], chosen: 0)
        refreshState()
        let effects: [Effect] = [
            .commit(word),
            .deleteBackward(before.word.count + before.trailing.count + word.count),
            .insert(joined),
        ] + Self.trailing(trailing) + [.haptic(.commit)]
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

    /// A word pecked out tap by tap that neither the dictionary nor the person's words
    /// know is learned when it settles (DESIGN.md "Learning", features/word-control).
    /// A word of the person's own counts one more use each time it goes in, however it
    /// was typed, so the words they write often rise. Swiped words the keyboard did not
    /// know are guesses, so they never are; nor are blocked words (Never suggest), nor
    /// letters that read as two words with the space missed ("textseparately"), which
    /// wait in the bar for "Learn it".
    private func wordToLearn(_ word: String) -> String? {
        guard !settings.exactTaps, !afterTag else { return nil }
        let lower = word.lowercased()
        let key = Lexicon.fold(lower)
        guard lower.count >= 2, key.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 }),
              !matcher.dictionary.spellings(of: key).contains(where: { $0.word == lower }) else { return nil }
        if matcher.learned.contains(lower) { return lower }
        guard pieces.count >= 2, pieces.allSatisfy(\.isTap), !matcher.learned.isBlocked(lower),
              matcher.split(key) == nil else { return nil }
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
        if let last = committed, !last.picked, contextBefore.isEmpty || contextBefore.hasSuffix(last.word + last.trailing) {
            // Reopen the word just written, so it can be changed or added to.
            committed = nil
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
    /// `nextAt` is when the next word started, when that is why: a word it may still be
    /// looked back at from waits for it (features/look-back).
    private mutating func settle(nextAt: TimeInterval? = nil) -> [Effect] {
        let effects = settleWaiting()
        guard let last = committed else { return effects }
        committed = nil
        if let nextAt, let went = last.time, nextAt - went <= Self.lookBackStart, mayLookBack(at: last) {
            waiting = last
            return effects
        }
        return effects + finish(last)
    }

    /// The word waiting for the look-back check is final now.
    private mutating func settleWaiting() -> [Effect] {
        guard let last = waiting else { return [] }
        waiting = nil
        return finish(last)
    }

    /// Keeps `last` among the recent words and says what to learn from it.
    private mutating func finish(_ last: Committed) -> [Effect] {
        recentWords.append(last)
        if recentWords.count > Self.recentLimit { recentWords.removeFirst(recentWords.count - Self.recentLimit) }
        // Learned only now, so a word fixed before the next one began (backspace into
        // it, "helo" to "hello") never is (Gabriel, 7 Nov 2026: fixed typos piled up).
        var effects: [Effect] = last.learned.map { [.learn($0)] } ?? []
        if let settled = Self.settled(last, layout: layout) { effects.append(.settled(settled)) }
        return effects
    }

    /// A settled word with where the thumbs landed for its letters, when the touches
    /// line up with them: one tap per letter, or the start of a lone swipe on the
    /// first letter. A touch more than a key away from its letter is left out.
    static func settled(_ last: Committed, layout: Layout) -> SettledWord? {
        // A replacement's phrase was never typed: nothing to learn from its touches.
        guard last.replaced == nil else { return nil }
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
        guard settings.autoCapitalize, !autoShiftDismissed, pieces.isEmpty, open.isEmpty else { return .off }
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
        guard let last = before.last else { return true }
        guard last.isWhitespace || last.isNewline else { return false }
        if last.isNewline { return true }
        // Read back from the end to the last mark, instead of trimming the whole text:
        // this runs on every keystroke, and a long paragraph before the cursor made it
        // cost as much as the guesses.
        guard let mark = before.last(where: { !Self.isSpace($0) }) else { return true }
        return mark == "." || mark == "?" || mark == "!"
    }

    /// A space or a tab (`CharacterSet.whitespaces`): not a line break.
    static func isSpace(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }

    private mutating func refreshState() {
        state.shift = shift
        state.isShifted = effectiveShift != .off
        if case .guesses(let words, let chosen) = state.bar, words.indices.contains(chosen) {
            state.openWord = words[chosen]
            var previews: [String: String] = [:]
            for word in words where previews[word] == nil {
                if let phrase = replacement(for: word) { previews[word] = phrase }
            }
            state.previews = previews
            state.replacement = previews[words[chosen]]
        } else {
            state.openWord = nil
            state.replacement = nil
            state.previews = [:]
        }
        state.shortcutPhrase = shortcutAtCursor.map {
            expansion(of: $0.phrase, capital: $0.token.first?.isUppercase == true, preview: true).text
        }
        refreshAutofill()
        // "Not it?" for a swiped word only: pecked letters were typed as meant.
        let swiped = { (pieces: [Piece]) in pieces.contains { !$0.isTap } }
        state.canCorrect = correction == nil && open.isEmpty
            && (hasOpenWord ? swiped(pieces)
                : earlier != nil || (committed.map { !$0.missed && swiped($0.pieces) } ?? false))
    }

    // MARK: Pieces

    /// Closes a touch into a piece: a tap on the key it landed on, or a swipe with the
    /// letter keys its path crossed, in order.
    /// How long a touch can last and still read as a tap however it slid (see `piece`).
    static let quickTouch: TimeInterval = 0.1

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
        // A quick touch that slid less than a key is a tap that rolled as the thumb
        // lifted: "home" tapped fast read its "h" as a swipe from h to j and came out
        // "hulks" (12 Nov 2026). A real swipe takes longer or goes further.
        let flick = end - touch.start < quickTouch && travel < layout.distanceUnit
        let isTap = travel < tapThreshold || keys.count <= 1 || flick
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
