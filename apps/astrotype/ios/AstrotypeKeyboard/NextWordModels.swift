import AstrotypeCore
import CoreML
import Foundation

/// The next-word models in the keyboard's bundle (features/next-word-model):
/// `NextWord<Code>.mlpackage`, which Xcode compiles to `.mlmodelc`, and
/// `NextWord<Code>-vocab.txt` beside it. Loaded once per process and shared, since iOS
/// can keep more than one keyboard controller alive (astrotype memory work, PR #139).
/// A language without the files keeps the word pairs.
enum NextWordModels {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var loaded: [String: NextWordModel] = [:]

    /// `code` is "en" or "es"; nil when the bundle has no model for it or it fails to load.
    @Sendable static func load(_ code: String) -> NextWordModel? {
        lock.lock()
        defer { lock.unlock() }
        if let model = loaded[code] { return model }
        let name = "NextWord" + code.prefix(1).uppercased() + code.dropFirst()
        guard let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
              let vocabURL = Bundle.main.url(forResource: name + "-vocab", withExtension: "txt"),
              let vocabulary = try? NextWordModel.vocabulary(contentsOf: vocabURL),
              let predictor = try? CoreMLNextWordPredictor(modelURL: modelURL) else { return nil }
        let model = NextWordModel(code: code, vocabulary: vocabulary, predictor: predictor)
        loaded[code] = model
        return model
    }

    /// Frees them, for a memory warning.
    static func drop() {
        lock.lock()
        loaded = [:]
        lock.unlock()
    }
}
