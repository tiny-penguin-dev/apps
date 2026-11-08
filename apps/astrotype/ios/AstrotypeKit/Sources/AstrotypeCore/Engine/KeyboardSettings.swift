import Foundation

/// What the person can change about the keyboard from inside it (DESIGN.md: the
/// in-keyboard settings panel, for when Full Access is off). A small versioned
/// value, mirrored to the App Group and iCloud when Full Access allows (`Stores`, `CloudSync`).
///
///     var settings = KeyboardSettings()
///     settings.autospaceDelay = 1.2
///     composer.settings = settings.composerSettings(from: composer.settings)
public struct KeyboardSettings: Codable, Sendable, Equatable {
    public static let version = 1
    public static let delayRange: ClosedRange<TimeInterval> = 0.1...1.5
    /// How much taller or shorter than Apple's the keys can be made.
    public static let heightRange: ClosedRange<Double> = 0.8...1.2

    public var version = KeyboardSettings.version
    /// Write a swiped word after a pause with no finger down (never a pecked one).
    public var autospace = true
    /// How long that pause is, 0.1 to 1.5 s.
    public var autospaceDelay: TimeInterval = 0.9
    /// Effects on: key flashes, taps and trails, as `effects` says (features/customization;
    /// the setting was "Trails and flashes"). Off is the battery saver.
    public var trails = true
    /// A soft tap on each key and a firmer one on each word, where the host allows it
    /// (the extension needs Full Access for haptics).
    public var haptics = true
    /// A slide on the space bar moves the cursor.
    public var spaceSlide = true
    /// A swipe left on backspace deletes the last word.
    public var backspaceSwipe = true
    /// On a wide screen (the iPhone Duo open), pull the two halves apart to the edges.
    public var splitOnWide = false
    /// Show the guesses in a bar above the keys when there is no room beside them (a
    /// phone). Off gives the keys the bar's height. Where the keys leave room (split,
    /// or a wide screen) the guesses sit beside them either way (Gabriel, 2 Nov 2026).
    public var showsBar = true
    /// On the split keyboard, one more letter past the middle on each half (Y H B on the
    /// left, T F C on the right) for swiping across. Off is Apple's split.
    public var splitExtraLetters = false
    /// Learn the person's words, word pairs and where their thumbs land, on the device
    /// (features/smart-matching Phase B, "Learns from you").
    public var learnsFromYou = true
    /// The last "Forget everything": a keyboard whose personal model is older forgets
    /// it when these settings reach it (here, through the App Group or iCloud).
    public var forgetPersonalAt: Date?
    /// Keep the fixes made from the bar in other apps (the word and the guess, nothing
    /// around them) for the app to share with "Send practice sessions"
    /// (features/smart-matching Phase C). Off by default; needs Full Access.
    public var shareCorrections = false
    /// How sure the keyboard must be of a real word before it writes it in place of
    /// pecked letters that spell none, 0 to 1 (`Matcher.strictness`). At 1 it only
    /// ever writes real words.
    public var wordStrictness = 0.8
    /// How sure the keyboard must be that pecked letters are two words with the space
    /// missed ("textseparately") before it writes them split, 0 to 1
    /// (`Matcher.splitStrictness`), and that two words autospace wrote apart are one
    /// ("some thing", `Matcher.join`) before it joins them. At 0 it does neither.
    public var splitStrictness = 0.8
    /// How tall the keys are against Apple's, 0.8 to 1.2. At 1 every key sits where
    /// Apple's does; other heights move the top row and keep the bottom row in place.
    /// The guesses bar adds to the height either way (Gabriel, 3 Nov 2026).
    public var keyboardHeight = 1.0
    /// After each word, offer the likely next words on the bar; a tap writes one
    /// (features/next-word). On by default.
    public var nextWords = true
    /// The languages the person turned on, as codes ("en", "es"), in their order. Nil
    /// follows the phone (`phoneLanguages`): a Spanish phone types Spanish
    /// (features/languages). Two at once is Pro; `activeLanguages` says which apply.
    public var languages: [String]?
    /// With two languages on, guess from both for every word, for people who mix them
    /// in one sentence. Off by default: once a sentence shows its language, the rest of
    /// it keeps to that one (`Composer.Settings.mixesLanguages`, Gabriel 3 Nov 2026).
    public var mixesLanguages = false
    /// A tiny readout of the keyboard's memory in a corner of the keys, for watching it
    /// on a phone (Settings → Debug, Gabriel 3 Nov 2026). Off by default.
    public var showsStats = false
    /// Keep the last half hour of typing on the phone, to send from Settings → Debug
    /// when something goes wrong (`TypingRecorder`, Gabriel 6 Nov 2026). Off by default,
    /// only offered in TestFlight builds, and needs Full Access.
    public var recordsTyping = false
    /// The person's text replacements, newest first (features/text-replacements):
    /// a shortcut typed as a word goes in as its phrase.
    public var textReplacements: [TextReplacement] = []
    /// Also use the phone's own text replacements (Settings → General → Keyboard →
    /// Text Replacement), which the keyboard reads from iOS. On by default.
    public var usesPhoneReplacements = true
    /// What `{name}`, `{email}`, `{phone}` and `{address}` write in a replacement.
    public var personalDetails = PersonalDetails()

    /// The chosen theme's id: a built-in one (`KeyboardTheme.builtIn`) or one of
    /// `customThemes` (features/customization). Classic by default.
    public var themeID = KeyboardTheme.classic.id
    /// The themes the person made.
    public var customThemes: [KeyboardTheme] = []
    /// Which effects, when `trails` (the Effects switch) is on. Calm by default.
    public var effects = EffectsSettings.calm

    /// The chosen theme, Classic if it is gone.
    public var chosenTheme: KeyboardTheme {
        customThemes.first { $0.id == themeID } ?? KeyboardTheme.named(themeID) ?? .classic
    }

    /// The theme the keyboard draws: the chosen one, or Classic when it is Pro and Pro
    /// is off (the choice is kept for when Pro comes back).
    public func style(allows pro: Bool) -> KeyboardTheme {
        let theme = chosenTheme
        return pro || theme.isFree ? theme : .classic
    }

    /// The effects the keyboard draws: none with the switch off, Calm when the chosen
    /// ones need Pro and Pro is off.
    public func activeEffects(allows pro: Bool) -> EffectsSettings? {
        guard trails else { return nil }
        return pro || effects.isFree ? effects : .calm
    }

    /// A new theme of the person's from `base`, chosen and kept; returns its id.
    @discardableResult
    public mutating func addTheme(from base: KeyboardTheme, now: Date = Date()) -> String {
        let id = "custom-\(Int(now.timeIntervalSince1970 * 1000))"
        let mine = customThemes.count + 1
        customThemes.append(base.copy(id: id, name: mine == 1 ? "My theme" : "My theme \(mine)"))
        themeID = id
        return id
    }

    /// Delete one of the person's themes; the keyboard goes back to Classic if it was on.
    public mutating func removeTheme(id: String) {
        customThemes.removeAll { $0.id == id }
        if themeID == id { themeID = KeyboardTheme.classic.id }
    }

    /// Change one of the person's themes in place.
    public mutating func updateTheme(_ theme: KeyboardTheme) {
        guard let i = customThemes.firstIndex(where: { $0.id == theme.id }) else { return }
        customThemes[i] = theme
    }

    /// `keyboardHeight` kept in its range, for `Layout.qwerty(scale:)`.
    public var heightScale: CGFloat {
        CGFloat(min(max(keyboardHeight, Self.heightRange.lowerBound), Self.heightRange.upperBound))
    }

    public init() {}

    /// Reads older saved settings too: a key that is missing keeps its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.version
        autospace = try c.decodeIfPresent(Bool.self, forKey: .autospace) ?? true
        autospaceDelay = try c.decodeIfPresent(TimeInterval.self, forKey: .autospaceDelay) ?? 0.9
        trails = try c.decodeIfPresent(Bool.self, forKey: .trails) ?? true
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        spaceSlide = try c.decodeIfPresent(Bool.self, forKey: .spaceSlide) ?? true
        backspaceSwipe = try c.decodeIfPresent(Bool.self, forKey: .backspaceSwipe) ?? true
        splitOnWide = try c.decodeIfPresent(Bool.self, forKey: .splitOnWide) ?? false
        showsBar = try c.decodeIfPresent(Bool.self, forKey: .showsBar) ?? true
        splitExtraLetters = try c.decodeIfPresent(Bool.self, forKey: .splitExtraLetters) ?? false
        learnsFromYou = try c.decodeIfPresent(Bool.self, forKey: .learnsFromYou) ?? true
        forgetPersonalAt = try c.decodeIfPresent(Date.self, forKey: .forgetPersonalAt)
        shareCorrections = try c.decodeIfPresent(Bool.self, forKey: .shareCorrections) ?? false
        wordStrictness = try c.decodeIfPresent(Double.self, forKey: .wordStrictness) ?? 0.8
        splitStrictness = try c.decodeIfPresent(Double.self, forKey: .splitStrictness) ?? 0.8
        keyboardHeight = try c.decodeIfPresent(Double.self, forKey: .keyboardHeight) ?? 1.0
        nextWords = try c.decodeIfPresent(Bool.self, forKey: .nextWords) ?? true
        languages = try c.decodeIfPresent([String].self, forKey: .languages)
        mixesLanguages = try c.decodeIfPresent(Bool.self, forKey: .mixesLanguages) ?? false
        showsStats = try c.decodeIfPresent(Bool.self, forKey: .showsStats) ?? false
        recordsTyping = try c.decodeIfPresent(Bool.self, forKey: .recordsTyping) ?? false
        textReplacements = (try? c.decodeIfPresent([TextReplacement].self, forKey: .textReplacements)) ?? []
        usesPhoneReplacements = try c.decodeIfPresent(Bool.self, forKey: .usesPhoneReplacements) ?? true
        personalDetails = (try? c.decodeIfPresent(PersonalDetails.self, forKey: .personalDetails)) ?? PersonalDetails()
        themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? KeyboardTheme.classic.id
        customThemes = (try? c.decodeIfPresent([KeyboardTheme].self, forKey: .customThemes)) ?? []
        effects = (try? c.decodeIfPresent(EffectsSettings.self, forKey: .effects)) ?? .calm
    }

    /// The bundled languages among the phone's preferred ones (`Locale.preferredLanguages`,
    /// "es-MX" is "es"), in its order; English when it lists none of them.
    public static func phoneLanguages(_ preferred: [String]) -> [String] {
        var out: [String] = []
        for identifier in preferred {
            let code = String(identifier.lowercased().prefix { $0.isLetter })
            if Language.bundledCodes.contains(code), !out.contains(code) { out.append(code) }
        }
        return out.isEmpty ? ["en"] : out
    }

    /// The languages turned on (or the phone's), bundled ones only, never none.
    public func chosenLanguages(preferred: [String]) -> [String] {
        let chosen = (languages ?? Self.phoneLanguages(preferred)).filter { Language.bundledCodes.contains($0) }
        return chosen.isEmpty ? Self.phoneLanguages(preferred) : chosen
    }

    /// The languages the keyboard types in: the chosen ones, or with one allowed (the
    /// free keyboard), the chosen one the phone puts first. At most two.
    public func activeLanguages(preferred: [String], allowsTwo: Bool) -> [String] {
        let chosen = chosenLanguages(preferred: preferred)
        guard !allowsTwo, chosen.count > 1 else { return Array(chosen.prefix(2)) }
        let phone = Self.phoneLanguages(preferred)
        let first = chosen.min { (phone.firstIndex(of: $0) ?? .max) < (phone.firstIndex(of: $1) ?? .max) } ?? chosen[0]
        return [first]
    }

    /// Adds a replacement, or changes the one with the same id, keeping it first; one
    /// with the same shortcut as another goes in its place. Returns false when the
    /// shortcut or the phrase can't be used (`TextReplacements.shortcut`).
    @discardableResult
    public mutating func save(_ replacement: TextReplacement) -> Bool {
        guard let shortcut = TextReplacements.shortcut(replacement.shortcut), !replacement.phrase.isEmpty else { return false }
        var item = replacement
        item.shortcut = shortcut
        if let i = textReplacements.firstIndex(where: { $0.id == item.id }) {
            textReplacements[i] = item
            textReplacements.removeAll { $0.id != item.id && $0.shortcut == shortcut }
        } else {
            textReplacements.removeAll { $0.shortcut == shortcut }
            textReplacements.insert(item, at: 0)
        }
        return true
    }

    /// `base` with these settings applied; the rest of the engine's settings stay.
    public func composerSettings(from base: Composer.Settings = Composer.Settings()) -> Composer.Settings {
        var out = base
        out.autospaceDelay = autospace ? min(max(autospaceDelay, Self.delayRange.lowerBound), Self.delayRange.upperBound) : nil
        out.strictness = min(max(wordStrictness, 0), 1)
        out.splitStrictness = min(max(splitStrictness, 0), 1)
        out.nextWords = nextWords
        out.mixesLanguages = mixesLanguages
        out.replacements = TextReplacements(own: textReplacements)
        out.details = personalDetails
        return out
    }
}

/// Where the keyboard's settings are kept.
public protocol SettingsStore: Sendable {
    func load() -> KeyboardSettings?
    func save(_ settings: KeyboardSettings)
    /// When the saved settings last changed, for stores that keep track.
    func lastChanged() -> Date?
}

public extension SettingsStore {
    func lastChanged() -> Date? { nil }
}

/// Settings in `UserDefaults`: the extension's own, so they work without Full Access.
public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "keyboardSettings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> KeyboardSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyboardSettings.self, from: data)
    }

    public func save(_ settings: KeyboardSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
        defaults.set(Date().timeIntervalSinceReferenceDate, forKey: key + ".changed")
    }

    public func lastChanged() -> Date? {
        guard defaults.object(forKey: key + ".changed") != nil else { return nil }
        return Date(timeIntervalSinceReferenceDate: defaults.double(forKey: key + ".changed"))
    }
}

/// A store that keeps settings in memory, for tests and previews.
public final class MemorySettingsStore: SettingsStore, @unchecked Sendable {
    private var settings: KeyboardSettings?
    private let lock = NSLock()

    public init(_ settings: KeyboardSettings? = nil) {
        self.settings = settings
    }

    public func load() -> KeyboardSettings? {
        lock.lock(); defer { lock.unlock() }
        return settings
    }

    public func save(_ settings: KeyboardSettings) {
        lock.lock(); defer { lock.unlock() }
        self.settings = settings
    }
}
