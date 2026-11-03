import Foundation

/// The words before the cursor that the matcher may lean on: the last few words of
/// the sentence being written, lowercase, with `NgramModel.sentenceStart` standing in
/// where the sentence begins (features/smart-matching/FEATURE.md).
///
///     WordContext.words(before: "Hi! Going to the ", count: 2)   // ["to", "the"]
///     WordContext.words(before: "Hi! ", count: 2)                // ["<s>"]
///     WordContext.words(before: "Hi! Going ", count: 2)          // ["<s>", "going"]
public enum WordContext {
    /// Ends a sentence: the words before it say nothing about the next word.
    static let sentenceEnders: Set<Character> = [".", "!", "?", "\n"]
    /// Breaks a run of words without ending the sentence: no pair across it.
    static let breakers: Set<Character> = [",", ";", ":", "(", ")", "\"", "“", "”", "—", "–"]

    /// The last `count` words of the current sentence, oldest first, starting with
    /// `<s>` when the sentence has fewer. Empty when the cursor sits inside a word, or
    /// right after a comma or another break, where no pair applies.
    public static func words(before text: String, count: Int = 2) -> [String] {
        guard count > 0 else { return [] }
        // The current sentence: everything after the last ender.
        var sentence = Substring(text)
        // "¿" or "¡" just typed: a question or exclamation starts here, so the next
        // word starts a sentence ("Hola. ¿" reads as a sentence start).
        if let last = sentence.last, Accents.openers.contains(last) {
            while let last = sentence.last, Accents.openers.contains(last) { sentence = sentence.dropLast() }
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.last.map({ sentenceEnders.contains($0) }) == true {
                return [NgramModel.sentenceStart]
            }
            return words(before: String(sentence) + " ", count: count)
        }
        if let end = sentence.lastIndex(where: { sentenceEnders.contains($0) }) {
            sentence = sentence[sentence.index(after: end)...]
        }
        // Inside a word (no space after it) the next touch continues it, not a new word.
        if let last = sentence.last, !(last.isWhitespace || breakers.contains(last)) {
            return []
        }
        // The current run: everything after the last break.
        var run = sentence
        var broken = false
        if let brk = run.lastIndex(where: { breakers.contains($0) }) {
            run = run[run.index(after: brk)...]
            broken = true
        }
        var words = run.split(whereSeparator: { $0.isWhitespace })
            .map { normalize($0) }
            .filter { !$0.isEmpty }
        if words.isEmpty, broken { return [] }
        if words.count < count, !broken { words.insert(NgramModel.sentenceStart, at: 0) }
        return Array(words.suffix(count))
    }

    /// A token as the model knows it: lowercase letters with accents off (`Lexicon.fold`,
    /// "Mañana" → "manana"), apostrophes dropped ("Don't" → "dont"), anything else removed.
    static func normalize(_ token: Substring) -> String {
        String(Lexicon.fold(String(token)).unicodeScalars.filter { $0.value >= 97 && $0.value <= 122 }.map(Character.init))
    }
}
