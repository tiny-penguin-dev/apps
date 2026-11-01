import Foundation
import Observation
import StackWriteCore

/// Loads the model and dictionary once, off the main thread, and reads strokes.
/// Also keeps the writer's recent lifts between letters, so a slow writer's
/// pauses are judged against their own pace.
@MainActor @Observable
final class RecognitionService {
    private(set) var recognizer: Recognizer?
    /// The dictionary, also used to pick training prompts.
    private(set) var entries: [Lexicon.Entry] = []
    private(set) var loadError: String?

    private static let liftsKey = "recentLifts"
    private var recentLifts: [Double] = UserDefaults.standard.array(forKey: liftsKey) as? [Double] ?? []

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

    /// `partial` allows an unfinished last word, for reading while the writer
    /// is still going.
    func recognize(_ strokes: [[StrokePoint]], partial: Bool = false) -> Recognizer.Result? {
        guard !strokes.isEmpty else { return nil }
        return try? recognizer?.recognize(strokes, liftScale: liftScale, partial: partial)
    }

    /// The writer's usual lift, once there are enough to tell; until then the
    /// model measures it from the strokes it's reading.
    var liftScale: Double? {
        recentLifts.count >= 8 ? Features.writerLiftScale(recentLifts) : nil
    }

    /// Remembers the lifts of finished writing (the last 100).
    func learnLifts(_ lifts: [Double]) {
        recentLifts = Array((recentLifts + lifts.filter { $0 > 0 && $0 < 5 }).suffix(100))
        UserDefaults.standard.set(recentLifts, forKey: Self.liftsKey)
    }
}

extension Duration {
    /// "3.2 ms"
    var milliseconds: String {
        let ms = Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
        return ms.formatted(.number.precision(.fractionLength(1))) + " ms"
    }
}
