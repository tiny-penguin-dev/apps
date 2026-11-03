import Foundation

/// The letters a held key offers (features/languages/FEATURE.md "Typing accents by
/// hand"): á on a, ñ on n, ¿ on ?, as each language that is on uses them. The plain
/// key itself is not in the list; the callout puts it first.
///
///     Accents.alternates(for: "n", languages: ["en", "es"])   // ["ñ"]
///     Accents.alternates(for: "n", languages: ["en"])         // []
public enum Accents {
    /// Per language, per key: its other letters, most used first.
    static let table: [String: [Character: [Character]]] = [
        "es": [
            "a": ["á"], "e": ["é"], "i": ["í"], "o": ["ó"], "u": ["ú", "ü"], "n": ["ñ"],
            "?": ["¿"], "!": ["¡"],
        ],
    ]

    /// What holding `key` offers with these languages on, in order, without repeats.
    public static func alternates(for key: Character, languages: [String]) -> [Character] {
        let lower = Character(key.lowercased())
        var out: [Character] = []
        for code in languages {
            for c in table[code]?[lower] ?? [] where !out.contains(c) { out.append(c) }
        }
        return out
    }

    /// Opens a question or an exclamation (Spanish): the sentence starts after it.
    public static let openers: Set<Character> = ["¿", "¡"]
}
