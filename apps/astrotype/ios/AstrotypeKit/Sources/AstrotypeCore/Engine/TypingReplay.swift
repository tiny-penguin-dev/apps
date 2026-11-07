import Foundation

/// Plays a typing recording (`TypingLog`) through a fresh `Composer`, as the keyboard
/// drove it: the same settings, field, layout, languages, Pro and learned words, every
/// touch and key at its recorded time, the text field kept in memory. Each event's
/// effects are compared with what the phone wrote, so a bug that the recording shows
/// can be seen happening here, and after a fix, seen not to.
///
///     let result = TypingReplay.run(log)
///     result.text            // the field as the replay left it
///     result.differences     // where the engine wrote something else than on the phone
///
/// It does what `KeyboardModel` (AstrotypeUI) does around the composer, which can't
/// run here; a change there that touches the composer should change this too.
public struct TypingReplay: Sendable {
    /// An event whose effects differ from the phone's.
    public struct Difference: Sendable, Equatable, CustomStringConvertible {
        /// The event's index in the log.
        public var index: Int
        public var t: Double
        public var event: TypingEvent.Kind
        /// What the phone wrote, and the replay.
        public var recorded: [String]
        public var replayed: [String]

        public var description: String {
            "[\(index)] \(String(format: "%.3f", t)) \(event.rawValue): phone \(recorded) · replay \(replayed)"
        }
    }

    public struct Result: Sendable, Equatable {
        /// The field as the replay left it (only the end of it, as the recording keeps).
        public var text: String
        /// Each event's effects in the replay, by its index in the log.
        public var effects: [Int: [String]]
        public var differences: [Difference]
        /// The words that went in, in order.
        public var commits: [String]
    }

    /// The field in memory: written text, and the open word apart as marked text.
    struct Field {
        var text = ""
        var marked = ""

        mutating func apply(_ effects: [Composer.Effect]) {
            for effect in effects {
                switch effect {
                case .insert(let s): text += s
                case .deleteBackward(let count):
                    for _ in 0..<count {
                        if !marked.isEmpty { marked.removeLast() } else if !text.isEmpty { text.removeLast() }
                    }
                case .mark(let s): marked = s
                case .commit(let s): text += s; marked = ""
                case .clearMark: marked = ""
                default: break
                }
            }
        }
    }

    public static func run(_ log: TypingLog, weights: Matcher.Weights? = nil,
                           loadLanguage: ([String]) -> Language? = { try? Language.bundled($0) }) -> Result {
        var composer: Composer?
        var languages: [String: Language] = [:]
        var settings = KeyboardSettings()
        var hostField = AstrotypeCore.Field.text
        var searching = false
        var pro = true
        var layout = Layout.qwerty(width: 390)
        var field = Field()
        var learned = log.learned ?? LearnedWords()
        var lastWordChange: (word: String, before: LearnedWords.Entry?)?
        var learner = PersonalLearner(model: log.personal ?? PersonalModel(), device: "replay", now: log.from)
        var effects: [Int: [String]] = [:]
        var differences: [Difference] = []
        var commits: [String] = []
        // The last input's replayed effects, waiting for the phone's (the next `fx`).
        var pending: (index: Int, codes: [String])?

        func language(_ codes: [String]) -> Language? {
            let key = codes.joined(separator: "+")
            if let cached = languages[key] { return cached }
            let loaded = loadLanguage(codes)
            languages[key] = loaded
            return loaded
        }

        func applySettings() {
            guard var c = composer else { return }
            let current = searching ? AstrotypeCore.Field.emojiSearch : hostField
            var s = current.composerSettings(settings.composerSettings(from: c.settings))
            s.nextWords = s.nextWords && current.learns
            s.twoThumbs = pro
            c.settings = s
            composer = c
        }

        func settle(_ out: [Composer.Effect]) {
            for effect in out {
                switch effect {
                case .settled(let word):
                    if learner.learn(word, allowed: hostField.learns && !searching, now: log.from) {
                        composer?.personal = learner.index
                    }
                case .learn(let word) where hostField.learns && !searching:
                    learned.learn(word, at: log.from)
                    composer?.learned = learned
                case .unlearn(let word):
                    learned.unlearn(word, at: log.from)
                    composer?.learned = learned
                case .commit(let word):
                    commits.append(word)
                default: break
                }
            }
        }

        func closePending() {
            guard let p = pending else { return }
            pending = nil
            if !p.codes.isEmpty, let event = log.events[safe: p.index] {
                differences.append(Difference(index: p.index, t: event.t, event: event.e, recorded: [], replayed: p.codes))
            }
        }

        for (index, event) in log.events.enumerated() {
            if event.e == .effects {
                let recorded = event.fx ?? []
                let replayed = pending?.codes ?? []
                let at = pending?.index ?? index
                if recorded != replayed {
                    let source = log.events[safe: at] ?? event
                    differences.append(Difference(index: at, t: source.t, event: source.e, recorded: recorded, replayed: replayed))
                }
                pending = nil
                continue
            }
            if event.isInput || event.e == .language { closePending() }

            switch event.e {
            case .snapshot:
                guard let snap = event.snap else { break }
                settings = snap.settings
                hostField = snap.field
                pro = snap.pro
                layout = snap.layout.layout
                if composer == nil, let lang = language(snap.languages) {
                    composer = Composer(language: lang, learned: learned, layout: layout)
                    learner.apply(settings, now: log.from)
                    composer?.personal = learner.index
                } else if let lang = language(snap.languages), composer?.languageCode != lang.code {
                    _ = composer?.setLanguage(lang, time: event.t)
                }
                composer?.layout = layout
                applySettings()
                // A snapshot starts afresh: whatever was open on the phone is in its text.
                _ = composer?.reset()
                field = Field(text: snap.context)
                composer?.setContext(before: field.text)
                continue
            case .settings:
                if let s = event.settings { settings = s; learner.apply(s, now: log.from); applySettings() }
                continue
            case .field:
                if let f = event.field { hostField = f; applySettings() }
                continue
            case .layout:
                if let l = event.layout { layout = l.layout; composer?.layout = layout }
                continue
            case .pro:
                pro = event.n == 1
                applySettings()
                continue
            case .context, .reset:
                field.text = event.s ?? ""
                if event.e == .reset {
                    if let out = composer?.reset() { settle(out) }
                }
                composer?.setContext(before: field.text)
                continue
            default:
                break
            }

            guard var c = composer else { continue }
            let t = event.t
            var out: [Composer.Effect] = []
            let point = CGPoint(x: event.x ?? 0, y: event.y ?? 0)
            switch event.e {
            case .down: out = c.touchDown(id: event.i ?? 0, at: point, time: t)
            case .move: out = c.touchMoved(id: event.i ?? 0, to: point, time: t)
            case .up: out = c.touchUp(id: event.i ?? 0, at: point, time: t)
            case .cancel: out = c.touchCancelled(id: event.i ?? 0, time: t)
            case .pick:
                if let letter = event.s?.first { out = c.pick(letter, touch: event.i ?? 0, time: t) }
            case .key:
                if let key = event.s.flatMap(TypingEvent.key(code:)) { out = c.press(key, time: t) }
            case .character:
                if let ch = event.s?.first { out = c.press(character: ch, time: t) }
            case .text:
                out = c.press(text: event.s ?? "", time: t)
            case .emoji:
                out = c.insert(emoji: event.s ?? "", time: t)
            case .searchOpen:
                out = c.cursorWillMove()
                out += c.reset()
                searching = true
                field = Field()
            case .searchClose, .searchClear:
                _ = c.reset()
                if event.e == .searchClose { searching = false }
                field = Field()
            case .searchEmoji:
                break // It goes into the app, not through the engine.
            case .guess: out = c.choose(guess: event.n ?? 0, time: t)
            case .fix: out = c.chooseFix(reading: event.n ?? 0)
            case .cursor:
                out = c.cursorWillMove()
            case .notIt: c.beginCorrection()
            case .notItCancel: c.cancelCorrection(time: t)
            case .notItSave: out = c.saveCorrection(time: t)
            case .deleteWord: out = c.deleteWord(time: t)
            case .boost, .forget:
                if let word = Self.barWord(c.state.bar, event.n ?? 0) {
                    lastWordChange = (word, learned.entry(for: word))
                    if event.e == .boost { learned.teach(word, at: log.from) } else { learned.block(word, at: log.from) }
                    c.learned = learned
                    out = c.learnedDidChange(time: t)
                }
            case .wordUndo:
                if let (word, before) = lastWordChange, word == event.s {
                    lastWordChange = nil
                    learned.restore(word, to: before, at: log.from)
                    c.learned = learned
                    out = c.learnedDidChange(time: t)
                }
            case .tick: out = c.tick(time: t)
            case .hide: out = c.keyboardWillHide()
            case .language:
                let codes = (event.s ?? "").split(separator: "+").map(String.init)
                if let lang = language(codes) { out = c.setLanguage(lang, time: t) }
            default: break
            }
            composer = c
            if event.e == .searchOpen || event.e == .searchClose { applySettings() }
            field.apply(out)
            settle(out)
            composer?.setContext(before: field.text)
            let codes = TypingEvent.codes(of: out)
            effects[index] = codes
            pending = (index, codes)
        }
        closePending()
        return Result(text: field.text + field.marked, effects: effects, differences: differences, commits: commits)
    }

    static func barWord(_ bar: Composer.Bar, _ index: Int) -> String? {
        switch bar {
        case .guesses(let words, _), .fix(let words, _), .next(let words, _, _):
            words.indices.contains(index) ? words[index].lowercased() : nil
        case .idle, .correcting:
            nil
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
