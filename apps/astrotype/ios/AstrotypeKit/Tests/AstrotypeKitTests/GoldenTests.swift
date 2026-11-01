import Foundation
import Testing
@testable import AstrotypeCore

/// Replays `ml/export/golden.json`: the Python reference's features, model
/// output and decoded phrases for six synthetic recordings.
struct Golden: Decodable {
    struct Case: Decodable {
        var text: String
        var lift_scale: Double?
        var strokes: [[[Double]]]
        var cut_strokes: Int
        var features: [[Float]]
        var logprobs: [[Float]]
        var cut_logprobs: [[Float]]
        var expected_top: [[Score]]
        var expected_partial: [[Score]]
    }

    enum Score: Decodable {
        case text(String), score(Double)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .text(s) } else { self = .score(try c.decode(Double.self)) }
        }
        var text: String? { if case .text(let w) = self { w } else { nil } }
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
    var points: [[StrokePoint]] { strokes.map { $0.map { StrokePoint(x: $0[0], y: $0[1], t: $0[2]) } } }
    func expected(_ list: [[Golden.Score]]) -> [(String, Double)] {
        list.compactMap { pair in pair.first?.text.flatMap { t in pair.last?.score.map { (t, $0) } } }
    }
}

@Suite struct FeatureTests {
    @Test func matchesPython() {
        for c in Golden.shared.cases {
            let f = Features.featurize(c.points, liftScale: c.lift_scale)
            let expected = c.features.flatMap { $0 }
            #expect(f.values.count == expected.count, "\(c.text): \(f.rows) rows, expected \(c.features.count)")
            guard f.values.count == expected.count else { continue }
            // golden.json rounds features to 5 decimals.
            let diff = zip(f.values, expected).map { abs($0 - $1) }.max() ?? 0
            #expect(diff < 1e-4, "\(c.text): max diff \(diff)")
            #expect(f.strokeStarts.count == c.strokes.count)
        }
    }

    @Test func tapsAndLifts() {
        let tap = [StrokePoint(x: 0.5, y: 0.5, t: 1.0)]
        let line = [StrokePoint(x: 0.2, y: 0.5, t: 0), StrokePoint(x: 0.6, y: 0.5, t: 0.5)]
        let f = Features.featurize([line, tap], liftScale: 0.25)
        #expect(f.strokeStarts == [0, 10])
        #expect(f.rows == 11)
        let tapRow = Array(f.values[10 * 9..<11 * 9])
        #expect(tapRow[2] == 0 && tapRow[3] == 0)              // a tap has no direction
        #expect(tapRow[5] == 1)                                 // stroke start
        #expect(abs(tapRow[6] - Float(log1p(0.5 / 0.25))) < 1e-6)
        #expect(Features.padded(f.values).count == Features.minFrames * Features.width)
    }

    @Test func writerLiftScale() {
        #expect(Features.writerLiftScale([0.1, 0.2]) == 0.2)   // too few: the default
        #expect(Features.writerLiftScale([0.1, 0.12, 0.14, 0.16, 1.0, 2.0]) == 0.12)
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
        let decoder = PhraseDecoder(lexicon: Golden.lexicon)
        for c in Golden.shared.cases {
            check(decoder.decode(logprobs: c.logprobs.flatMap { $0 }, frames: c.logprobs.count),
                  c.expected(c.expected_top), c.text)
            check(decoder.decode(logprobs: c.cut_logprobs.flatMap { $0 }, frames: c.cut_logprobs.count, partial: true),
                  c.expected(c.expected_partial), c.text + " (partial)")
        }
    }

    private func check(_ out: [PhraseDecoder.Candidate], _ expected: [(String, Double)], _ name: String) {
        #expect(out.map(\.text) == expected.map(\.0), "\(name)")
        for (o, e) in zip(out, expected) {
            #expect(abs(o.score - e.1) < 0.01, "\(name): \(o.text) \(o.score) vs \(e.1)")
        }
    }

    @Test func greedyAndBreaks() {
        // Frames: h, blank, i, space, space, blank, y, o, space(trailing)
        let labels = [8, 0, 9, 27, 27, 0, 25, 15, 27]
        var lp = [Float](repeating: -10, count: labels.count * 28)
        for (t, k) in labels.enumerated() { lp[t * 28 + k] = 0 }
        let (text, spaces) = PhraseDecoder.greedy(lp, frames: labels.count)
        #expect(text == "hi yo")
        #expect(spaces == [3])
        #expect(PhraseDecoder.stroke(atRow: 12, starts: [0, 5, 13, 20]) == 2)
    }
}

@Suite struct SampleTests {
    @Test func roundTripsAsJSON() throws {
        let sample = StrokeSample(
            label: "hello there", labelSource: .prompt,
            strokes: [[StrokePoint(x: 0.123456789, y: 0.5, t: 0.0123456)], [StrokePoint(x: 0.5, y: 0.5, t: 0.4)]],
            padSize: CGSize(width: 320, height: 320),
            writer: "w", session: "s", device: "iPhone", system: "iOS 26", app: "0.1.0 (1)",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), prompt: "hello there", recognized: ["hello there"]
        )
        let data = try StrokeSample.encoder.encode(sample)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"strokes\":[[[0.12346,0.5,0.0123]],[[0.5,0.5,0.4]]]"))
        let back = try StrokeSample.decoder.decode(StrokeSample.self, from: data)
        #expect(back.label == "hello there" && back.createdAt == sample.createdAt && back.version == 2)
        #expect(back.strokes.count == 2)
    }

    @Test func readsVersionOne() throws {
        let json = """
        {"version":1,"id":"6F1C9A2E-0000-4000-8000-000000000000","label":"hi","labelSource":"prompt",
         "points":[[0.1,0.2,0],[0.3,0.4,0.01]],"padWidth":300,"padHeight":300,"writer":"w","session":"s",
         "device":"d","system":"s","app":"a","createdAt":"2026-10-30T04:00:00Z"}
        """
        let s = try StrokeSample.decoder.decode(StrokeSample.self, from: Data(json.utf8))
        #expect(s.version == 1 && s.strokes.count == 1 && s.strokes[0].count == 2)
        let again = String(decoding: try StrokeSample.encoder.encode(s), as: UTF8.self)
        #expect(again.contains("\"points\":[[0.1,0.2,0],[0.3,0.4,0.01]]"))
    }
}

#if canImport(CoreML)
import CoreML

@Suite struct ModelTests {
    @Test func matchesPython() async throws {
        let package = Golden.mlExport.appendingPathComponent("Astrotype.mlpackage")
        let compiled = try await MLModel.compileModel(at: package)
        let recognizer = try Recognizer(modelURL: compiled, lexicon: Golden.lexicon, computeUnits: .cpuOnly)
        for c in Golden.shared.cases {
            let (lp, frames) = try recognizer.run(features: c.features.flatMap { $0 })
            #expect(frames == c.logprobs.count)
            guard frames == c.logprobs.count else { continue }
            // fp16 model: compare where the reference is confident enough to matter.
            // Long phrases drift up to ~0.2; the decoded text below is what must match.
            let diff = zip(lp, c.logprobs.flatMap { $0 }).filter { $0.1 > -6 }.map { abs($0.0 - $0.1) }.max() ?? 0
            #expect(diff < 0.3, "\(c.text): max logprob diff \(diff)")
            let result = try recognizer.recognize(c.points, liftScale: c.lift_scale)
            #expect(result.texts.first == c.text, "\(c.text): got \(result.texts)")
        }
    }
}
#endif
