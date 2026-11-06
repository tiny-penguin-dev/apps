import Foundation

/// The field being typed in, as the app describes it, and what the keyboard makes of
/// it (features/field-types): which bottom row, what the return key says, whether taps
/// are typed exactly, whether words get a space after them, capitals, and whether the
/// keyboard may learn here. Pure: the extension reads UIKit's traits into the plain
/// values below (`KeyboardViewController.field`).
///
///     let field = Field(keyboard: .email, returnKey: .next)
///     field.kind                     // .email
///     field.bottomRow                // .email: space, @ and . before return
///     field.composerSettings(base)   // exact taps, no autospace, no capitals
public struct Field: Sendable, Equatable, Codable {
    /// What the keyboard turns into for the field.
    public enum Kind: String, Sendable, Equatable, Codable {
        case text, email, url, webSearch, social, numbers
    }

    /// The keyboard type the app asked for (UIKit's `UIKeyboardType`, read plainly).
    public enum KeyboardType: Sendable, Equatable {
        case `default`, email, url, webSearch, twitter, numbers, phone
    }

    /// What the field holds, when the app says (UIKit's `UITextContentType`, the ones
    /// that change anything here).
    public enum Content: Sendable, Equatable {
        case email, url, username, password
        /// A one-time code, a card number, a phone number or a postal code: typed
        /// exactly and never learned.
        case code
        case other
    }

    /// Capitals the field asks for (UIKit's `UITextAutocapitalizationType`).
    public enum Capitals: String, Sendable, Equatable, Codable {
        case none, words, sentences, all
    }

    /// What the return key says (UIKit's `UIReturnKeyType`).
    public enum ReturnKey: String, Sendable, Equatable, CaseIterable, Codable {
        case `return`, go, search, send, join, next, done, route, `continue`, emergencyCall

        /// The word on the key, lower case like Apple's; nil draws the return arrow.
        public var label: String? {
            switch self {
            case .return: nil
            case .go: "go"
            case .search: "search"
            case .send: "send"
            case .join: "join"
            case .next: "next"
            case .done: "done"
            case .route: "route"
            case .continue: "continue"
            case .emergencyCall: "emergency call"
            }
        }

        /// An action: drawn on blue, like Apple's. Next and the arrow stay grey.
        public var isAction: Bool { self != .return && self != .next }

        /// What VoiceOver says for the key.
        public var spokenName: String { label.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Return" }
    }

    public let kind: Kind
    public let returnKey: ReturnKey
    public let capitals: Capitals
    /// The field leaves corrections on. Off, taps are typed exactly.
    public let corrects: Bool
    /// The return key does nothing while the field is empty (the app's
    /// `enablesReturnKeyAutomatically`).
    public let returnNeedsText: Bool
    /// The keyboard may learn from what is typed here: never an address, a username,
    /// a password, a code or a number, nor a field that turned corrections off.
    public let learns: Bool
    /// Taps go in exactly as tapped (no guess replaces them): addresses, numbers,
    /// codes and fields without corrections.
    public let exactTaps: Bool

    /// A plain text field: everything as it always was.
    public static let text = Field()

    public init(keyboard: KeyboardType = .default, content: Content = .other, returnKey: ReturnKey = .return,
                capitals: Capitals = .sentences, corrects: Bool = true, returnNeedsText: Bool = false,
                secure: Bool = false, learns: Bool = true) {
        let kind: Kind = switch (keyboard, content) {
        case (.email, _), (_, .email), (_, .username): .email
        case (.url, _), (_, .url): .url
        case (.numbers, _), (.phone, _): .numbers
        case (.webSearch, _): .webSearch
        case (.twitter, _): .social
        default: .text
        }
        let code = content == .code || content == .password || secure
        self.kind = kind
        self.returnKey = returnKey
        // Addresses and numbers never start with a capital, whatever the field says.
        self.capitals = [.email, .url, .numbers].contains(kind) || code ? .none : capitals
        self.corrects = corrects
        self.returnNeedsText = returnNeedsText
        self.exactTaps = !corrects || code || [.email, .url, .numbers].contains(kind)
        self.learns = !exactTaps && learns
    }

    /// The emoji search field (features/emoji-search): words are guessed as anywhere,
    /// but nothing typed there is learned, capitalised or offered next words, and
    /// return says "done".
    public static let emojiSearch = Field(returnKey: .done, capitals: .none, learns: false)

    /// Words get a space after them (autospace, a guess from the bar, a double space
    /// for a period): not in an address or a number.
    public var spacesWords: Bool { ![.email, .url, .numbers].contains(kind) && !exactTapsOnlyBecauseCode }

    /// Autospace runs: where words get spaces, and not in a search, which is often one
    /// word and goes with return.
    public var autospaces: Bool { spacesWords && kind != .webSearch }

    /// The keys beside space on the letters page.
    public var bottomRow: Layout.BottomRow {
        switch kind {
        case .text, .numbers: .standard
        case .email: .email
        case .url: .url
        case .webSearch: .webSearch
        case .social: .social
        }
    }

    /// The page the keyboard opens on.
    public var startPage: Layout.Page { kind == .numbers ? .numbers : .letters }

    /// A code or password field in a plain keyboard: typed exactly and with no
    /// spaces after words, since a code is one word.
    private var exactTapsOnlyBecauseCode: Bool { exactTaps && corrects && kind == .text }

    /// The engine's settings for this field, on top of the person's (`base`, from
    /// `KeyboardSettings.composerSettings`): this only takes away, it never turns on
    /// what the person turned off.
    public func composerSettings(_ base: Composer.Settings) -> Composer.Settings {
        var out = base
        if !autospaces { out.autospaceDelay = nil }
        out.capitals = capitals
        out.exactTaps = exactTaps
        out.spacesWords = spacesWords
        return out
    }
}
