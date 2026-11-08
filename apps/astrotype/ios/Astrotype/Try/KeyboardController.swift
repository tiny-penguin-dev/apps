import Foundation
import Observation
import AstrotypeCore

/// The text the keyboard types into. Matches the parts of `UITextDocumentProxy`
/// the keyboard uses, so the keyboard extension can reuse this controller.
@MainActor
protocol TextTarget: AnyObject {
    var documentContextBeforeInput: String? { get }
    func insertText(_ text: String)
    func deleteBackward()
    /// Shows tentative text at the cursor as ordinary text, replacing the last.
    func setMarkedText(_ text: String)
    /// Keeps the tentative text as it is.
    func unmarkText()
}

/// Keyboard logic. Writing is continuous: strokes collect into a stretch of
/// writing that is read again after every stroke, and its words show as
/// tentative text that can still change. Older words lock in once two more
/// follow them; the rest lock in when the writer stops for a moment, picks a
/// suggestion, or taps space, return or punctuation.
@MainActor @Observable
final class KeyboardController {
    weak var target: TextTarget?
    private let recognition: RecognitionService

    /// Up to three readings of the tentative words, best first.
    private(set) var suggestions: [String] = []
    /// Which suggestion is in the text now.
    private(set) var chosen: Int?
    /// What the model read, for the debug line under the text.
    private(set) var lastReading: String?

    /// Strokes not locked in yet.
    private var recording = Recording()
    /// How the tentative words start: a space before them, a capital.
    private var lead = (space: "", capitalized: false)
    private var commitTask: Task<Void, Never>?
    /// The text the last locked-in words added, so a suggestion or delete can
    /// take it back out.
    private var lastInsert: (text: String, space: String, capitalized: Bool)?

    /// How long the writer can stop before the tentative words lock in.
    static let idleCommit: Duration = .seconds(2)

    init(recognition: RecognitionService) {
        self.recognition = recognition
    }

    var isWriting: Bool { !recording.isEmpty }

    func handleStroke(_ points: [StrokePoint]) {
        if recording.isEmpty {
            let before = target?.documentContextBeforeInput ?? ""
            lead = (Self.needsSpace(before) ? " " : "", Self.startsSentence(before))
            lastInsert = nil
        }
        recording.add(points)
        read()
        commitTask?.cancel()
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleCommit)
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    /// Reads the tentative strokes again and shows the best reading.
    private func read() {
        guard let result = recognition.recognize(recording.strokes, partial: true) else {
            lastReading = recognition.statusText
            return
        }
        lastReading = "letters “\(result.letters)” · model \(result.modelTime.milliseconds) · decoder \(result.decodeTime.milliseconds)"
        var texts = Array(result.texts.prefix(3))
        // Nothing in the dictionary fits: offer the raw letters so something still comes out.
        if texts.count < 3, !result.letters.isEmpty, !texts.contains(result.letters) {
            texts.append(result.letters)
        }
        guard let best = texts.first else { return }
        if lockOlderWords(best, result) { return read() }
        suggestions = texts
        chosen = 0
        target?.setMarkedText(format(best))
    }

    /// With four or more words, locks in all but the last two, if the model's
    /// own word breaks say which strokes they used.
    private func lockOlderWords(_ best: String, _ result: Recognizer.Result) -> Bool {
        let words = best.split(separator: " ")
        guard words.count >= 4, result.breakStrokes.count == words.count - 1 else { return false }
        let keep = 2
        let firstKept = result.breakStrokes[words.count - keep - 1]
        guard firstKept > 0, firstKept < recording.count else { return false }
        target?.setMarkedText(format(words.prefix(words.count - keep).joined(separator: " ")))
        target?.unmarkText()
        recording.removeFirst(firstKept)
        lead = (" ", false)
        return true
    }

    /// Locks in the tentative words as they are.
    private func commit() {
        commitTask?.cancel()
        guard !recording.isEmpty else { return }
        recognition.learnLifts(recording.lifts)
        recording.removeAll()
        if let chosen, suggestions.indices.contains(chosen) {
            lastInsert = (format(suggestions[chosen]), lead.space, lead.capitalized)
        }
        target?.unmarkText()
    }

    func pick(_ index: Int) {
        guard suggestions.indices.contains(index) else { return }
        if isWriting {
            chosen = index
            target?.setMarkedText(format(suggestions[index]))
            commit()
        } else if index != chosen, let last = lastInsert, removeLastInsert() {
            chosen = index
            lead = (last.space, last.capitalized)
            let text = format(suggestions[index])
            target?.insertText(text)
            lastInsert = (text, last.space, last.capitalized)
        }
    }

    /// While writing, takes back the last stroke. Otherwise deletes the words
    /// just written, or one character.
    func deleteTapped() {
        if isWriting {
            recording.removeLast()
            if recording.isEmpty {
                commitTask?.cancel()
                target?.setMarkedText("")
                target?.unmarkText()
                clearSuggestions()
            } else {
                read()
            }
            return
        }
        if !removeLastInsert() {
            target?.deleteBackward()
        }
        clearSuggestions()
    }

    func spaceTapped() { finish(then: " ") }
    func returnTapped() { finish(then: "\n") }
    func punctuationTapped(_ mark: String) { finish(then: mark) }

    private func finish(then text: String) {
        commit()
        target?.insertText(text)
        clearSuggestions()
    }

    private func clearSuggestions() {
        lastInsert = nil
        suggestions = []
        chosen = nil
    }

    /// "i" becomes "I", the first word gets a capital at a sentence start,
    /// and a space goes in front when the text before needs one.
    private func format(_ text: String) -> String {
        var words = text.split(separator: " ").map { $0 == "i" ? "I" : String($0) }
        if lead.capitalized, let first = words.first {
            words[0] = first.prefix(1).uppercased() + first.dropFirst()
        }
        return lead.space + words.joined(separator: " ")
    }

    /// Removes the last locked-in words if they're still right before the cursor.
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
