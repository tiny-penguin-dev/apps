import Foundation
import Testing
@testable import StackWriteKit

/// Replays `ml/export/golden.json`: the Python reference's features, model
/// output and decoded words for six synthetic strokes.
struct Golden: Decodable {
    struct Case: Decodable {
        var word: String
        var raw_path_box_units_y_up: [[Double]]
        var features: [[Float]]
        var logprobs: [[Float]]
        var expected_top_words: [[Score]]
    }

    enum Score: Decodable {
        case word(String), score(Double)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .word(s) } else { self = .score(try c.decode(Double.self)) }
        }
        var word: String? { if case .word(let w) = self { w } else { nil } }
        var score: Double? { if case .score(let s) = self { s } else { nil } }
    }

    var cases: [Case]

    static let mlExport = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../../../../ml/export").standardized

    static let shared: Golden = {
        let data = try! Data(contentsOf: mlExport.appendingPathComponent("golden.json"))
        return try! JSONDecoder().decode(Golden.self, from: data)
    }()

    static let lexicon = try! Lexicon(contentsOf: mlExport.appendingPathComponent("lexicon.tsv"))
}

extension Golden.Case {
    var points: [StrokePoint] { raw_path_box_units_y_up.map { StrokePoint(x: $0[0], y: $0[1], t: 0) } }
    var flatLogprobs: [Float] { logprobs.flatMap { $0 } }
    var expectedWords: [String] { expected_top_words.compactMap { $0.first?.word } }
}

@Suite struct FeatureTests {
    @Test func matchesPython() {
        for c in Golden.shared.cases {
            let f = Features.featurize(c.points)
            let expected = c.features.flatMap { $0 }
            #expect(f.count == expected.count, "\(c.word): \(f.count / 5) frames, expected \(c.features.count)")
            guard f.count == expected.count else { continue }
            let diff = zip(f, expected).map { abs($0 - $1) }.max() ?? 0
            // golden.json rounds the raw path to 5 decimals, which moves the
            // direction features by up to ~4e-3 (Python shows the same diffs).
            #expect(diff < 5e-3, "\(c.word): max diff \(diff)")
        }
    }

    @Test func shortStrokesArePadded() {
        // Python: a path shorter than one step keeps [first, last], then gets two extra points.
        let f = Features.featurize([StrokePoint(x: 0.5, y: 0.5, t: 0)])
        #expect(f.count == 4 * Features.width)
        #expect(Features.padded(f).count == Features.minFrames * Features.width)
    }

    @Test func touchToBoxUnits() {
        let p = StrokePoint(touch: CGPoint(x: 150, y: 0), padSize: CGSize(width: 300, height: 300), t: 0)
        #expect(p.x == 0.5 && p.y == 1)
        let wide = StrokePoint(touch: CGPoint(x: 50, y: 200), padSize: CGSize(width: 300, height: 200), t: 0)
        #expect(wide.x == 0 && wide.y == 0)
    }
}

@Suite struct DecoderTests {
    @Test func lexiconRoundTrips() {
        let lex = Golden.lexicon
        #expect(lex.contains("hello"))
        #expect(!lex.contains("hellz"))
        #expect(lex.word(at: lex.node(for: "keyboard")!) == "keyboard")
    }

    @Test func matchesPython() {
        let decoder = WordDecoder(lexicon: Golden.lexicon)
        for c in Golden.shared.cases {
            let out = decoder.decode(logprobs: c.flatLogprobs, frames: c.logprobs.count)
            #expect(out.map(\.word) == c.expectedWords, "\(c.word)")
            if let top = out.first, let expected = c.expected_top_words.first?.last?.score {
                #expect(abs(top.score - expected) < 0.01, "\(c.word): \(top.score) vs \(expected)")
            }
        }
    }
}

@Suite struct SampleTests {
    @Test func roundTripsAsJSON() throws {
        let sample = StrokeSample(
            label: "hello", labelSource: .prompt,
            points: [StrokePoint(x: 0.123456789, y: 0.5, t: 0.0123456)],
            padSize: CGSize(width: 320, height: 320),
            writer: "w", session: "s", device: "iPhone", system: "iOS 26", app: "0.1.0 (1)",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), prompt: "say hello", recognized: ["hello"]
        )
        let data = try StrokeSample.encoder.encode(sample)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"points\":[[0.12346,0.5,0.0123]]"))
        let back = try StrokeSample.decoder.decode(StrokeSample.self, from: data)
        #expect(back.label == "hello" && back.createdAt == sample.createdAt && back.version == 1)
    }
}

#if canImport(CoreML)
import CoreML

@Suite struct ModelTests {
    @Test func matchesPython() async throws {
        let package = Golden.mlExport.appendingPathComponent("StackWrite.mlpackage")
        let compiled = try await MLModel.compileModel(at: package)
        let recognizer = try Recognizer(modelURL: compiled, lexicon: Golden.lexicon, computeUnits: .cpuOnly)
        for c in Golden.shared.cases {
            let (lp, frames) = try recognizer.run(features: c.features.flatMap { $0 })
            #expect(frames == c.logprobs.count)
            guard frames == c.logprobs.count else { continue }
            // fp16 model: compare where the reference is confident enough to matter.
            let diff = zip(lp, c.flatLogprobs).filter { $0.1 > -6 }.map { abs($0.0 - $0.1) }.max() ?? 0
            #expect(diff < 0.15, "\(c.word): max logprob diff \(diff)")
            let result = try recognizer.recognize(c.points)
            #expect(result.words.first == c.word, "\(c.word): got \(result.words)")
        }
    }
}
#endif
