import Foundation

/// One text replacement the person made (features/text-replacements): type the
/// shortcut as a word and the keyboard writes the phrase in its place. The phrase may
/// hold variables (`{date}`, `{time}`, …) that fill in when it goes in.
///
///     TextReplacement(shortcut: "omw", phrase: "On my way!")
///     TextReplacement(shortcut: "today", phrase: "{day}, {date}")
public struct TextReplacement: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: UUID
    /// What is typed: one word of letters, kept lowercase (`TextReplacements.shortcut`).
    public var shortcut: String
    /// What goes in instead, variables and all.
    public var phrase: String

    public init(id: UUID = UUID(), shortcut: String, phrase: String) {
        self.id = id
        self.shortcut = shortcut
        self.phrase = phrase
    }
}

/// The text replacements the keyboard uses: the person's own, then the phone's
/// (Settings → General → Keyboard → Text Replacement), the person's winning on the same
/// shortcut. The composer looks each word up as it goes in.
///
///     let replacements = TextReplacements(own: settings.textReplacements, phone: fromIOS)
///     replacements.phrase(for: "OMW")                          // "On my way!"
///     TextReplacements.expand("{day}", at: now)                  // "Sunday"
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

    /// Every shortcut, lowercase: the matcher offers them like words, so a swipe can
    /// land on one.
    public var shortcuts: Set<String> { Set(phrases.keys) }

    /// The phrase (variables not filled in) for a word as written, any case; nil when
    /// the word is no shortcut.
    public func phrase(for word: String) -> String? {
        phrases[word.lowercased()]
    }

    /// What a shortcut must be: one word of 2 to 24 letters (the keys only type
    /// letters into a word), trimmed and lowercased; nil for anything else.
    public static func shortcut(_ text: String) -> String? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (2...24).contains(word.count), word.allSatisfy(\.isLetter) else { return nil }
        return word
    }

    // MARK: Variables

    /// A value a phrase can hold, written in braces: `{date}`.
    public struct Variable: Sendable, Equatable, Identifiable {
        /// The name inside the braces.
        public var name: String
        /// What it writes, for Settings ("Today's date").
        public var title: String
        public var id: String { name }
        /// How it is written in a phrase.
        public var token: String { "{\(name)}" }
    }

    /// The variables a phrase can hold, in the order Settings offers them.
    public static let variables: [Variable] = [
        Variable(name: "date", title: "Today's date"),
        Variable(name: "time", title: "The time now"),
        Variable(name: "day", title: "The day of the week"),
        Variable(name: "month", title: "This month"),
        Variable(name: "year", title: "This year"),
        Variable(name: "tomorrow", title: "Tomorrow's date"),
        Variable(name: "yesterday", title: "Yesterday's date"),
    ]

    /// `phrase` with its variables filled in for `date`, in the person's language and
    /// time zone. A name in braces that is no variable stays as written.
    public static func expand(_ phrase: String, at date: Date, locale: Locale = .current,
                              timeZone: TimeZone = .current) -> String {
        guard phrase.contains("{") else { return phrase }
        var out = ""
        var rest = Substring(phrase)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            let after = rest[rest.index(after: open)...]
            guard let close = after.firstIndex(of: "}"),
                  let value = value(of: after[..<close].lowercased().trimmingCharacters(in: .whitespaces),
                                    at: date, locale: locale, timeZone: timeZone) else {
                out.append("{")
                rest = after
                continue
            }
            out += value
            rest = after[after.index(after: close)...]
        }
        return out + rest
    }

    private static func value(of name: String, at date: Date, locale: Locale, timeZone: TimeZone) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = calendar
        func styled(_ day: Date) -> String {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: day)
        }
        func template(_ pattern: String) -> String {
            formatter.setLocalizedDateFormatFromTemplate(pattern)
            return formatter.string(from: date)
        }
        switch name {
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
        default: return nil
        }
    }

    /// A phrase on one line, for the bar and lists: line breaks become spaces.
    public static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
