import Foundation

/// Where the cursor sits in a word written earlier, read from the text around it
/// (features/fix-earlier-word): the cursor in the word or right after it, or just that
/// word selected. A bar can then show the word with its other readings and swap one in.
///
///     let spot = EarlierSpot.find(before: "at the ca", after: "ge tomorrow ", selected: nil, typedAfter: "")
///     spot?.word     // "cage"
///     spot?.offset   // 2: the cursor is after "ca"
///     spot?.rest     // 10: " tomorrow " lies between the word and where typing was
public struct EarlierSpot: Sendable, Equatable {
    /// The word as it stands in the field.
    public var word: String
    /// How many of its characters are before the cursor (0 when it is selected).
    public var offset: Int
    /// The word is selected: what is typed goes over it.
    public var selected: Bool
    /// How far past the word's end the person was typing before they moved the cursor,
    /// so a fix can put the cursor back there; 0 leaves it after the word.
    public var rest: Int

    public init(word: String, offset: Int, selected: Bool = false, rest: Int = 0) {
        self.word = word
        self.offset = offset
        self.selected = selected
        self.rest = rest
    }

    /// The longest word looked at; anything longer is not a word to fix.
    static let longest = 40

    /// The spot for the text around the cursor, or nil when the cursor is not in or
    /// right after one word. `selected` is the selected text, if any; `typedAfter` is
    /// what was after the cursor when the keyboard last typed (empty when typing at
    /// the end), so the fix can go back there.
    public static func find(before: String, after: String, selected: String?, typedAfter: String?) -> EarlierSpot? {
        if let selected, !selected.isEmpty {
            guard isWord(selected) else { return nil }
            return EarlierSpot(word: selected, offset: 0, selected: true, rest: rest(after: Substring(after), typedAfter: typedAfter))
        }
        let head = before.reversed().prefix { isWordCharacter($0) }.reversed()
        let tail = after.prefix { isWordCharacter($0) }
        guard !head.isEmpty else { return nil }
        let word = String(head) + tail
        guard isWord(word) else { return nil }
        return EarlierSpot(word: word, offset: head.count, selected: false,
                           rest: rest(after: after.dropFirst(tail.count), typedAfter: typedAfter))
    }

    /// Letters, with apostrophes or hyphens only inside ("don't", "e-mail").
    static func isWord(_ text: String) -> Bool {
        guard text.count <= longest, let first = text.first, let last = text.last,
              first.isLetter, last.isLetter else { return false }
        return text.allSatisfy(isWordCharacter)
    }

    static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c == "'" || c == "’" || c == "-"
    }

    /// The characters from the word's end to where typing was: the text after the word
    /// must end with what was after the cursor then.
    private static func rest(after remaining: Substring, typedAfter: String?) -> Int {
        guard let typedAfter, remaining.hasSuffix(typedAfter) else { return 0 }
        return remaining.count - typedAfter.count
    }

    /// Whether a change the field reported was the person moving the cursor (or
    /// selecting), rather than text going in or out at the cursor. Another app's
    /// dictation, a paste or autocorrect changes the text before the cursor and leaves
    /// the text after it as it was; a tap somewhere else changes what's after it.
    /// `lastAfter` is the text after the cursor when the keyboard last looked (nil:
    /// it hasn't yet, so it can't tell).
    public static func cursorMoved(lastAfter: String?, after: String, selected: String?) -> Bool {
        if let selected, !selected.isEmpty { return true }
        guard let lastAfter else { return false }
        return after != lastAfter
    }
}
