#if canImport(CoreML)
import CoreML
import Foundation

/// Turns strokes into ranked phrases: featurize → Core ML model → decoder.
/// Load it once; reading a few words takes a few milliseconds.
public final class Recognizer: @unchecked Sendable {
    public struct Result: Sendable {
        public var candidates: [PhraseDecoder.Candidate]
        /// Best letters and spaces without the dictionary, for words it doesn't know.
        public var letters: String
        /// For each space in `letters`, the stroke the next word starts with.
        public var breakStrokes: [Int]
        public var modelTime: Duration
        public var decodeTime: Duration

        public var texts: [String] { candidates.map(\.text) }
    }

    private let model: MLModel
    public let decoder: PhraseDecoder

    /// `modelURL` is the compiled model (`.mlmodelc`).
    public init(modelURL: URL, lexicon: Lexicon, computeUnits: MLComputeUnits = .all) throws {
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        model = try MLModel(contentsOf: modelURL, configuration: config)
        decoder = PhraseDecoder(lexicon: lexicon)
    }

    /// `partial` allows an unfinished last word (live typing).
    public func recognize(_ strokes: [[StrokePoint]], liftScale: Double? = nil, partial: Bool = false) throws -> Result {
        let clock = ContinuousClock()
        let start = clock.now
        let features = Features.featurize(strokes, liftScale: liftScale)
        let (logprobs, frames) = try run(features: Features.padded(features.values))
        let modelDone = clock.now
        let candidates = decoder.decode(logprobs: logprobs, frames: frames, partial: partial)
        let (letters, spaceFrames) = PhraseDecoder.greedy(logprobs, frames: frames)
        return Result(
            candidates: candidates,
            letters: letters,
            breakStrokes: spaceFrames.map { PhraseDecoder.stroke(atRow: $0 * 4, starts: features.strokeStarts) },
            modelTime: modelDone - start,
            decodeTime: clock.now - modelDone
        )
    }

    /// Runs the model on flattened `[T, 9]` features. Returns `frames × 28` log-probs.
    public func run(features: [Float]) throws -> (logprobs: [Float], frames: Int) {
        let rows = features.count / Features.width
        let input = try MLMultiArray(shape: [1, NSNumber(value: rows), NSNumber(value: Features.width)], dataType: .float32)
        input.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, strides in
            for r in 0..<rows {
                for c in 0..<Features.width {
                    buffer[r * strides[1] + c * strides[2]] = features[r * Features.width + c]
                }
            }
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["strokes": MLFeatureValue(multiArray: input)])
        let output = try model.prediction(from: provider)
        guard let array = output.featureValue(for: "logprobs")?.multiArrayValue else {
            throw RecognizerError.missingOutput
        }
        let frames = array.shape[1].intValue
        let classes = array.shape[2].intValue
        let s1 = array.strides[1].intValue
        let s2 = array.strides[2].intValue
        var out = [Float](repeating: 0, count: frames * classes)
        switch array.dataType {
        case .float16:
            array.withUnsafeBufferPointer(ofType: Float16.self) { buffer in
                for t in 0..<frames { for k in 0..<classes { out[t * classes + k] = Float(buffer[t * s1 + k * s2]) } }
            }
        case .float32:
            array.withUnsafeBufferPointer(ofType: Float.self) { buffer in
                for t in 0..<frames { for k in 0..<classes { out[t * classes + k] = buffer[t * s1 + k * s2] } }
            }
        default:
            for t in 0..<frames {
                for k in 0..<classes {
                    out[t * classes + k] = array[[0, NSNumber(value: t), NSNumber(value: k)]].floatValue
                }
            }
        }
        return (out, frames)
    }
}

public enum RecognizerError: Error {
    case missingOutput
}
#endif
