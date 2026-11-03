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
    /// Draw swipe trails, tap rings and key flashes. Off is the battery saver.
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
    /// In other apps, show the word being typed underlined (as marked text) instead of
    /// as plain text. Off by default: marked text put spaces before words (Gabriel kept
    /// it as a choice, 2 Nov 2026). The app's own fields always underline.
    public var underlinesWord = false
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
    /// How tall the keys are against Apple's, 0.8 to 1.2. At 1 every key sits where
    /// Apple's does; other heights move the top row and keep the bottom row in place.
    /// The guesses bar adds to the height either way (Gabriel, 3 Nov 2026).
    public var keyboardHeight = 1.0

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
        underlinesWord = try c.decodeIfPresent(Bool.self, forKey: .underlinesWord) ?? false
        learnsFromYou = try c.decodeIfPresent(Bool.self, forKey: .learnsFromYou) ?? true
        forgetPersonalAt = try c.decodeIfPresent(Date.self, forKey: .forgetPersonalAt)
        shareCorrections = try c.decodeIfPresent(Bool.self, forKey: .shareCorrections) ?? false
        wordStrictness = try c.decodeIfPresent(Double.self, forKey: .wordStrictness) ?? 0.8
        keyboardHeight = try c.decodeIfPresent(Double.self, forKey: .keyboardHeight) ?? 1.0
    }

    /// `base` with these settings applied; the rest of the engine's settings stay.
    public func composerSettings(from base: Composer.Settings = Composer.Settings()) -> Composer.Settings {
        var out = base
        out.autospaceDelay = autospace ? min(max(autospaceDelay, Self.delayRange.lowerBound), Self.delayRange.upperBound) : nil
        out.strictness = min(max(wordStrictness, 0), 1)
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
