import Foundation
import Observation
import StackWriteKit

/// The text the keyboard types into. Matches the parts of `UITextDocumentProxy`
/// the keyboard uses, so the keyboard extension can reuse this controller.
@MainActor
protocol TextTarget: AnyObject {
    var documentContextBeforeInput: String? { get }
    func insertText(_ text: String)
    func deleteBackward()
}

/// Keyboard logic: turns strokes into words, adds spaces and capitals, and
/// lets a suggestion replace the word just written.
@MainActor @Observable
final class KeyboardController {
    weak var target: TextTarget?
    private let recognition: RecognitionService

    /// Up to three words for the suggestion bar, best first.
    private(set) var suggestions: [String] = []
    /// Which suggestion is in the text now.
    private(set) var chosen: Int?
    /// What the model read, for the debug line under the text.
    private(set) var lastReading: String?

    /// The text the last word added (with its leading space), so a suggestion
    /// or delete can take it back out.
    private var lastInsert: (text: String, space: String, capitalized: Bool)?

    init(recognition: RecognitionService) {
        self.recognition = recognition
    }

    func handleStroke(_ points: [StrokePoint]) {
        // A tap or a tiny scribble isn't a word.
        guard Features.length(points) > 0.05 else { return }
        guard let result = recognition.recognize(points) else {
            lastReading = recognition.statusText
            return
        }
        var words = Array(result.words.prefix(3))
        // Not a dictionary word: offer the raw letters so something still comes out.
        if words.count < 3, !result.letters.isEmpty, !words.contains(result.letters) {
            words.append(result.letters)
        }
        lastReading = "letters “\(result.letters)” · model \(result.modelTime.milliseconds) · decoder \(result.decodeTime.milliseconds)"
        guard let first = words.first else {
            suggestions = []
            chosen = nil
            return
        }
        insertWord(first)
        suggestions = words
        chosen = 0
    }

    func pick(_ index: Int) {
        guard suggestions.indices.contains(index), index != chosen else { return }
        if let last = lastInsert, removeLastInsert() {
            insert(suggestions[index], space: last.space, capitalized: last.capitalized)
        } else {
            insertWord(suggestions[index])
        }
        chosen = index
    }

    /// Deletes the whole word just written, or one character otherwise.
    func deleteTapped() {
        if !removeLastInsert() {
            target?.deleteBackward()
        }
        reset()
    }

    func spaceTapped() {
        target?.insertText(" ")
        reset()
    }

    func returnTapped() {
        target?.insertText("\n")
        reset()
    }

    func punctuationTapped(_ mark: String) {
        target?.insertText(mark)
        reset()
    }

    private func reset() {
        lastInsert = nil
        suggestions = []
        chosen = nil
    }

    private func insertWord(_ word: String) {
        let before = target?.documentContextBeforeInput ?? ""
        insert(word, space: Self.needsSpace(before) ? " " : "", capitalized: Self.startsSentence(before))
    }

    private func insert(_ word: String, space: String, capitalized: Bool) {
        var text = word
        if word == "i" {
            text = "I"
        } else if capitalized {
            text = word.prefix(1).uppercased() + word.dropFirst()
        }
        target?.insertText(space + text)
        lastInsert = (space + text, space, capitalized)
    }

    /// Removes the last inserted word if it's still right before the cursor.
    private func removeLastInsert() -> Bool {
        guard let last = lastInsert, let target,
              (target.documentContextBeforeInput ?? "").hasSuffix(last.text)
        else { return false }
        for _ in 0..<last.text.count { target.deleteBackward() }
        lastInsert = nil
        return true
    }

    static func needsSpace(_ before: String) -> Bool {
        guard let c = before.last else { return false }
        return !c.isWhitespace && !"'’-(\"/".contains(c)
    }

    static func startsSentence(_ before: String) -> Bool {
        if before.last?.isNewline == true { return true }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        guard let c = trimmed.last else { return true }
        return ".!?".contains(c)
    }
}
