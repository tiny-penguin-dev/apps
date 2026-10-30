import Foundation
import Observation
import StackWriteKit

/// Loads the model and dictionary once, off the main thread, and recognizes strokes.
@MainActor @Observable
final class RecognitionService {
    private(set) var recognizer: Recognizer?
    /// The dictionary, also used to pick training prompts.
    private(set) var entries: [Lexicon.Entry] = []
    private(set) var loadError: String?

    var statusText: String {
        if recognizer != nil { return "Ready" }
        if let loadError { return "Failed: \(loadError)" }
        return "Loading…"
    }

    func load() async {
        guard recognizer == nil else { return }
        do {
            let (recognizer, entries) = try await Task.detached(priority: .userInitiated) {
                guard let model = Bundle.main.url(forResource: "StrokeModel", withExtension: "mlmodelc"),
                      let lexicon = Bundle.main.url(forResource: "lexicon", withExtension: "tsv")
                else { throw CocoaError(.fileNoSuchFile) }
                let entries = try Lexicon.readEntries(from: lexicon)
                return (try Recognizer(modelURL: model, lexicon: Lexicon(entries: entries)), entries)
            }.value
            self.entries = entries
            self.recognizer = recognizer
        } catch {
            loadError = error.localizedDescription
        }
    }

    func recognize(_ points: [StrokePoint]) -> Recognizer.Result? {
        try? recognizer?.recognize(points)
    }
}

extension Duration {
    /// "3.2 ms"
    var milliseconds: String {
        let ms = Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
        return ms.formatted(.number.precision(.fractionLength(1))) + " ms"
    }
}
