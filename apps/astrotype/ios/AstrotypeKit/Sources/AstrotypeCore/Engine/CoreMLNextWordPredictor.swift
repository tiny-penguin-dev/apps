#if canImport(CoreML)
import CoreML
import Foundation

/// The next-word network run by Core ML on the Neural Engine (features/next-word-model).
/// `modelURL` is the compiled model (`.mlmodelc`) Xcode makes from
/// `NextWordEn.mlpackage` in the keyboard's bundle; loading it takes a moment the
/// first time (iOS compiles it for the Neural Engine and keeps that), so do it off
/// the main thread.
///
///     let predictor = try CoreMLNextWordPredictor(modelURL: url)
///     let model = NextWordModel(code: "en", vocabulary: words, predictor: predictor)
public final class CoreMLNextWordPredictor: NextWordPredicting, @unchecked Sendable {
    private let model: MLModel
    private let input: MLMultiArray
    private let lock = NSLock()

    public init(modelURL: URL, computeUnits: MLComputeUnits = .cpuAndNeuralEngine) throws {
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        model = try MLModel(contentsOf: modelURL, configuration: config)
        input = try MLMultiArray(shape: [1, NSNumber(value: NextWordModel.window)], dataType: .int32)
    }

    public func logProbabilities(_ ids: [Int32]) -> [Float]? {
        guard ids.count == NextWordModel.window else { return nil }
        lock.lock()
        defer { lock.unlock() }
        input.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, strides in
            for (i, id) in ids.enumerated() { buffer[i * strides[1]] = id }
        }
        guard let features = try? MLDictionaryFeatureProvider(dictionary: ["ids": MLFeatureValue(multiArray: input)]),
              let output = try? model.prediction(from: features),
              let scores = output.featureValue(for: "scores")?.multiArrayValue else { return nil }
        let count = scores.count
        var out = [Float](repeating: 0, count: count)
        switch scores.dataType {
        case .float16:
            scores.withUnsafeBufferPointer(ofType: Float16.self) { buffer in
                for i in 0..<count { out[i] = Float(buffer[i]) }
            }
        case .float32:
            scores.withUnsafeBufferPointer(ofType: Float.self) { buffer in
                for i in 0..<count { out[i] = buffer[i] }
            }
        default:
            for i in 0..<count { out[i] = scores[i].floatValue }
        }
        return out
    }
}
#endif
