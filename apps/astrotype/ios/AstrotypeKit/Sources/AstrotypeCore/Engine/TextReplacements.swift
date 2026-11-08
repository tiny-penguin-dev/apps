import Foundation

/// One text replacement the person made (features/text-replacements): type the
/// shortcut and the keyboard writes the phrase in its place. The phrase may hold
/// variables (`{date}`, `{cursor}`, `{?name}`, …) that fill in when it goes in.
///
///     TextReplacement(shortcut: "omw", phrase: "On my way!")
///     TextReplacement(shortcut: ";sig", phrase: "{name}\n{phone}")
public struct TextReplacement: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: UUID
    /// What is typed: one word with no spaces, kept lowercase (`TextReplacements.shortcut`).
    public var shortcut: String
    /// What goes in instead, variables and all.
    public var phrase: String

    public init(id: UUID = UUID(), shortcut: String, phrase: String) {
        self.id = id
        self.shortcut = shortcut
        self.phrase = phrase
    }
}

/// What `{name}`, `{email}`, `{phone}` and `{address}` write: the person's own
/// details, from Settings → Text replacements → Your details.
public struct PersonalDetails: Codable, Sendable, Equatable, Hashable {
    public var name = ""
    public var email = ""
    public var phone = ""
    public var address = ""

    public init(name: String = "", email: String = "", phone: String = "", address: String = "") {
        self.name = name
        self.email = email
        self.phone = phone
        self.address = address
    }

    public var isEmpty: Bool { name.isEmpty && email.isEmpty && phone.isEmpty && address.isEmpty }

    /// Older saved settings may miss any of them.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
    }
}

/// The text replacements the keyboard uses: the person's own, then the phone's
/// (Settings → General → Keyboard → Text Replacement), the person's winning on the same
/// shortcut. The composer looks each word up as it goes in.
///
///     let replacements = TextReplacements(own: settings.textReplacements, phone: fromIOS)
///     replacements.phrase(for: "OMW")                                   // "On my way!"
///     TextReplacements.expand("{day}{cursor}!", in: context)          // ("Sunday!", cursor: 1)
public struct TextReplacements: Sendable, Equatable {
    /// Phrases by shortcut, lowercase.
    public private(set) var phrases: [String: String] = [:]

    public init(own: [TextReplacement] = [], phone: [TextReplacement] = []) {
        for item in phone + own {
            guard let key = Self.shortcut(item.shortcut), !item.phrase.isEmpty else { continue }
            phrases[key] = item.phrase
        }
    }

    public var isEmpty: Bool { phrases.isEmpty }

    /// The shortcuts made only of letters, lowercase: the matcher offers them like
    /// words, so a swipe can land on one. Others (";addr") are matched on the text.
    public var shortcuts: Set<String> { Set(phrases.keys.filter(Self.isWord)) }

    /// The phrase (variables not filled in) for a word as written, any case; nil when
    /// the word is no shortcut.
    public func phrase(for word: String) -> String? {
        phrases[word.lowercased()]
    }

    /// The first shortcut that `typed` begins and is longer than, for the bar to offer
    /// while the shortcut is being typed (features/text-replacements: suggest as you
    /// type). Needs two letters; the shortest such shortcut wins, then the first.
    public func completion(of typed: String) -> String? {
        let start = typed.lowercased()
        guard start.count >= 2 else { return nil }
        return phrases.keys.filter { $0.count > start.count && $0.hasPrefix(start) }
            .min { ($0.count, $0) < ($1.count, $1) }
    }

    /// What a shortcut must be: 2 to 24 characters with no spaces, at least one of them
    /// a letter or a symbol (not only digits), trimmed and lowercased; nil otherwise.
    public static func shortcut(_ text: String) -> String? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (2...24).contains(word.count), !word.contains(where: { $0.isWhitespace || $0.isNewline }),
              !word.allSatisfy(\.isNumber) else { return nil }
        return word
    }

    /// A shortcut of letters only, which the keys type as a word.
    public static func isWord(_ shortcut: String) -> Bool {
        shortcut.allSatisfy(\.isLetter)
    }

    // MARK: Variables

    /// A value a phrase can hold, written in braces: `{date}`.
    public struct Variable: Sendable, Equatable, Identifiable {
        /// What goes in the phrase.
        public var token: String
        /// What it writes, for Settings ("Today's date").
        public var title: String
        public var id: String { token }
    }

    /// The variables a phrase can hold, in the order Settings offers them.
    public static let variables: [Variable] = [
        Variable(token: "{date}", title: "Today's date"),
        Variable(token: "{time}", title: "The time now"),
        Variable(token: "{day}", title: "The day of the week"),
        Variable(token: "{month}", title: "This month"),
        Variable(token: "{year}", title: "This year"),
        Variable(token: "{tomorrow}", title: "Tomorrow's date"),
        Variable(token: "{yesterday}", title: "Yesterday's date"),
        Variable(token: "{date+7}", title: "The date a week from now (any number of days, + or -)"),
        Variable(token: "{next friday}", title: "The date next Friday (any day)"),
        Variable(token: "{cursor}", title: "Where the cursor goes after"),
        Variable(token: "{clipboard}", title: "What you copied (needs Full Access)"),
        Variable(token: "{?name}", title: "Asks for a word as it goes in"),
        Variable(token: "{pick:thanks|cheers}", title: "One of these at random"),
        Variable(token: "{name}", title: "Your name"),
        Variable(token: "{email}", title: "Your email"),
        Variable(token: "{phone}", title: "Your phone number"),
        Variable(token: "{address}", title: "Your address"),
    ]

    /// What the variables fill in from. The keyboard makes one as the phrase goes in.
    public struct Context: Sendable {
        public var date: Date
        public var locale: Locale
        public var timeZone: TimeZone
        /// What was copied; read only when a phrase asks for it.
        public var clipboard: @Sendable () -> String?
        public var details: PersonalDetails
        /// A number below the one given, for `{pick:…}`.
        public var random: @Sendable (Int) -> Int
        /// The words typed for the `{?blanks}`, by name.
        public var filled: [String: String]

        public init(date: Date = Date(), locale: Locale = .current, timeZone: TimeZone = .current,
                    clipboard: @escaping @Sendable () -> String? = { nil }, details: PersonalDetails = PersonalDetails(),
                    random: @escaping @Sendable (Int) -> Int = { Int.random(in: 0..<max(1, $0)) },
                    filled: [String: String] = [:]) {
            self.date = date
            self.locale = locale
            self.timeZone = timeZone
            self.clipboard = clipboard
            self.details = details
            self.random = random
            self.filled = filled
        }
    }

    /// A phrase filled in: the text, and how many characters before its end the cursor
    /// goes (`{cursor}`), nil for the end.
    public struct Expansion: Sendable, Equatable {
        public var text: String
        public var cursorFromEnd: Int?
    }

    /// The `{?blanks}` in a phrase, by name, in order, each once: the keyboard asks for
    /// these before it writes the phrase.
    public static func blanks(in phrase: String) -> [String] {
        var out: [String] = []
        for name in tokens(in: phrase) where name.hasPrefix("?") {
            let blank = String(name.dropFirst()).trimmingCharacters(in: .whitespaces)
            if !blank.isEmpty, !out.contains(blank) { out.append(blank) }
        }
        return out
    }

    /// `phrase` with its variables filled in. A name in braces that is no variable
    /// stays as written; a blank not yet filled shows as its name in brackets.
    public static func expand(_ phrase: String, in context: Context) -> Expansion {
        guard phrase.contains("{") else { return Expansion(text: phrase, cursorFromEnd: nil) }
        var out = ""
        var cursorAt: Int?
        var rest = Substring(phrase)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            let after = rest[rest.index(after: open)...]
            guard let close = after.firstIndex(of: "}") else {
                out.append("{")
                rest = after
                continue
            }
            let name = String(after[..<close])
            let key = name.lowercased().trimmingCharacters(in: .whitespaces)
            if key == "cursor" {
                if cursorAt == nil { cursorAt = out.count }
            } else if let value = value(of: name, key: key, in: context) {
                out += value
            } else {
                out.append("{")
                rest = after
                continue
            }
            rest = after[after.index(after: close)...]
        }
        out += rest
        return Expansion(text: out, cursorFromEnd: cursorAt.map { out.count - $0 })
    }

    /// `phrase` filled in for `date` and nothing else, as plain text.
    public static func expand(_ phrase: String, at date: Date, locale: Locale = .current,
                              timeZone: TimeZone = .current) -> String {
        expand(phrase, in: Context(date: date, locale: locale, timeZone: timeZone)).text
    }

    /// The names inside braces, in order.
    private static func tokens(in phrase: String) -> [String] {
        var out: [String] = []
        var rest = Substring(phrase)
        while let open = rest.firstIndex(of: "{") {
            let after = rest[rest.index(after: open)...]
            guard let close = after.firstIndex(of: "}") else { break }
            out.append(String(after[..<close]))
            rest = after[after.index(after: close)...]
        }
        return out
    }

    private static func value(of name: String, key: String, in context: Context) -> String? {
        if name.hasPrefix("?") {
            let blank = String(name.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard !blank.isEmpty else { return nil }
            return context.filled[blank] ?? "[\(blank)]"
        }
        if key.hasPrefix("pick:") {
            let options = name.drop { $0 != ":" }.dropFirst().split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard !options.isEmpty else { return nil }
            return options[min(options.count - 1, max(0, context.random(options.count)))]
        }
        switch key {
        case "clipboard": return context.clipboard() ?? ""
        case "name": return context.details.name
        case "email": return context.details.email
        case "phone": return context.details.phone
        case "address": return context.details.address
        default: return dateValue(of: key, in: context)
        }
    }

    private static func dateValue(of key: String, in context: Context) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = context.locale
        calendar.timeZone = context.timeZone
        let formatter = DateFormatter()
        formatter.locale = context.locale
        formatter.timeZone = context.timeZone
        formatter.calendar = calendar
        let date = context.date
        func styled(_ day: Date) -> String {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: day)
        }
        func template(_ pattern: String) -> String {
            formatter.setLocalizedDateFormatFromTemplate(pattern)
            return formatter.string(from: date)
        }
        switch key {
        case "date": return styled(date)
        case "time":
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: date)
        case "day": return template("EEEE")
        case "month": return template("MMMM")
        case "year": return template("y")
        case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: date).map(styled)
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: date).map(styled)
        default: break
        }
        // {date+7}, {date-1}: days from today.
        if key.hasPrefix("date"), let sign = key.dropFirst(4).first, sign == "+" || sign == "-",
           let days = Int(key.dropFirst(5).trimmingCharacters(in: .whitespaces)) {
            return calendar.date(byAdding: .day, value: sign == "+" ? days : -days, to: date).map(styled)
        }
        // {next friday}: the next one after today, in English or the phone's language.
        if key.hasPrefix("next ") {
            let dayName = key.dropFirst(5).trimmingCharacters(in: .whitespaces)
            var english = Calendar(identifier: .gregorian)
            english.locale = Locale(identifier: "en_US_POSIX")
            let names = [english.weekdaySymbols, calendar.weekdaySymbols].map { $0.map { $0.lowercased() } }
            guard let index = names.lazy.compactMap({ $0.firstIndex(of: dayName) }).first else { return nil }
            let today = calendar.component(.weekday, from: date)
            var ahead = (index + 1 - today + 7) % 7
            if ahead == 0 { ahead = 7 }
            return calendar.date(byAdding: .day, value: ahead, to: date).map(styled)
        }
        return nil
    }

    /// A phrase on one line, for the bar and lists: line breaks become spaces.
    public static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
