import Foundation

/// The five words of the Try it screen (DESIGN.md screen 4), each with the thumb by
/// thumb way to type it. The hint is built from the strokes so the words and the
/// instructions cannot drift apart; "Show me" replays the same strokes on the keys.
public struct TryWord: Sendable, Equatable {
    /// One thumb's part: a tap (one letter) or a swipe (several).
    public struct Stroke: Sendable, Equatable {
        public var side: Side
        public var letters: String

        public var isTap: Bool { letters.count == 1 }

        public static func tap(_ letter: Character, _ side: Side) -> Stroke {
            Stroke(side: side, letters: String(letter))
        }

        public static func swipe(_ letters: String, _ side: Side) -> Stroke {
            Stroke(side: side, letters: letters)
        }
    }

    /// A run of the hint: plain words, a bold letter or path, or a thumb's name in its colour.
    public struct HintPart: Sendable, Equatable {
        public enum Role: Sendable { case plain, strong, left, right }
        public var text: String
        public var role: Role
    }

    public var word: String
    public var strokes: [Stroke]

    public init(_ word: String, _ strokes: [Stroke]) {
        self.word = word
        self.strokes = strokes
    }

    public static let all: [TryWord] = [
        TryWord("something", [.tap("s", .left), .swipe("om", .right), .tap("e", .left), .swipe("thing", .right)]),
        TryWord("with", [.tap("w", .left), .tap("i", .right), .tap("t", .left), .tap("h", .right)]),
        TryWord("great", [.swipe("great", .left)]),
        TryWord("morning", [.swipe("mo", .right), .tap("r", .left), .swipe("ning", .right)]),
        TryWord("think", [.tap("t", .left), .swipe("hink", .right)]),
    ]

    /// "Left thumb taps s and e. Right thumb swipes o→m, then t→h→i→n→g. Space when it
    /// says something." One sentence per thumb, the thumb that starts first.
    public var hint: [HintPart] {
        var parts: [HintPart] = []
        var sides: [Side] = []
        for stroke in strokes where !sides.contains(stroke.side) { sides.append(stroke.side) }
        for side in sides {
            let run = strokes.filter { $0.side == side }
            if !parts.isEmpty { parts.append(HintPart(text: " ", role: .plain)) }
            parts.append(HintPart(text: side == .left ? "Left thumb" : "Right thumb", role: side == .left ? .left : .right))
            let taps = run.filter(\.isTap)
            let swipes = run.filter { !$0.isTap }
            if !taps.isEmpty {
                parts.append(HintPart(text: " taps ", role: .plain))
                parts += Self.list(taps.map { HintPart(text: $0.letters, role: .strong) }, joiner: " and ")
            }
            if !swipes.isEmpty {
                parts.append(HintPart(text: taps.isEmpty ? " swipes " : ", then swipes ", role: .plain))
                parts += Self.list(swipes.map { HintPart(text: $0.letters.map(String.init).joined(separator: "→"), role: .strong) }, joiner: ", then ")
            }
            parts.append(HintPart(text: ".", role: .plain))
        }
        parts.append(HintPart(text: " Space when it says \(word).", role: .plain))
        return parts
    }

    /// The hint as one plain string, for accessibility and tests.
    public var hintText: String { hint.map(\.text).joined() }

    private static func list(_ items: [HintPart], joiner: String) -> [HintPart] {
        var out: [HintPart] = []
        for (i, item) in items.enumerated() {
            if i > 0 { out.append(HintPart(text: joiner, role: .plain)) }
            out.append(item)
        }
        return out
    }
}
