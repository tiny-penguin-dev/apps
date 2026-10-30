#if canImport(CoreML)
import CoreML
import Foundation

/// Turns one stroke into ranked words: featurize → Core ML model → decoder.
/// Load it once; recognizing a word takes a few milliseconds.
public final class Recognizer: @unchecked Sendable {
    public struct Result: Sendable {
        public var candidates: [WordDecoder.Candidate]
        /// Best letters without the dictionary, for words it doesn't know.
        public var letters: String
        public var modelTime: Duration
        public var decodeTime: Duration

        public var words: [String] { candidates.map(\.word) }
    }

    private let model: MLModel
    public let decoder: WordDecoder

    /// `modelURL` is the compiled model (`.mlmodelc`).
    public init(modelURL: URL, lexicon: Lexicon, computeUnits: MLComputeUnits = .all) throws {
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        model = try MLModel(contentsOf: modelURL, configuration: config)
        decoder = WordDecoder(lexicon: lexicon)
    }

    public func recognize(_ points: [StrokePoint]) throws -> Result {
        let clock = ContinuousClock()
        let start = clock.now
        let features = Features.padded(Features.featurize(points))
        let (logprobs, frames) = try run(features: features)
        let modelDone = clock.now
        let candidates = decoder.decode(logprobs: logprobs, frames: frames)
        return Result(
            candidates: candidates,
            letters: Self.greedy(logprobs, frames: frames),
            modelTime: modelDone - start,
            decodeTime: clock.now - modelDone
        )
    }

    /// Runs the model on flattened `[T, 5]` features. Returns `frames × 27` log-probs.
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

    static func greedy(_ logprobs: [Float], frames: Int) -> String {
        var letters = [UInt8]()
        var previous = 0
        for t in 0..<frames {
            let row = logprobs[(t * 27)..<(t * 27 + 27)]
            let best = row.indices.max { row[$0] < row[$1] }! - t * 27
            if best != 0 && best != previous { letters.append(UInt8(96 + best)) }
            previous = best
        }
        return String(decoding: letters, as: UTF8.self)
    }
}

public enum RecognizerError: Error {
    case missingOutput
}
#endif
