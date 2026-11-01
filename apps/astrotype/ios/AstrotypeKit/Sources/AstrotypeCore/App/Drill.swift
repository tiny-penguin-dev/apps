import Foundation

/// A drill (DESIGN.md screen 8): one habit, five words, the keys of the next word lit
/// in the thumb's colour. The words carry their strokes like the Try it words do, so
/// the hint, the key lights and the engine test all come from one place.
public struct Drill: Sendable, Equatable, Identifiable {
    public enum ID: String, CaseIterable, Codable, Sendable {
        case pairs, switching, doubles
    }

    /// A drill word: its strokes, and whether the tap lands inside the swipe (the
    /// doubled-letter gesture) rather than after it.
    public struct Word: Sendable, Equatable {
        public var word: TryWord
        public var tapInsideSwipe: Bool

        public init(_ word: String, _ strokes: [TryWord.Stroke], tapInsideSwipe: Bool = false) {
            self.word = TryWord(word, strokes)
            self.tapInsideSwipe = tapInsideSwipe
        }

        public var text: String { word.word }
        public var strokes: [TryWord.Stroke] { word.strokes }
    }

    public var id: ID
    public var number: Int
    public var title: String
    public var subtitle: String
    /// "Left swipes w→e, right swipes n→t. Keys light up to show which thumb."
    public var hint: [TryWord.HintPart]
    public var words: [Word]

    public static let all: [Drill] = [
        Drill(id: .pairs, number: 1, title: "Two-letter swipes", subtitle: "th, in, er, on",
              hint: [.plain("Short swipes, two letters at a time, with whichever thumb is closer. "),
                     .plain("Keys light up to show which thumb.")],
              words: [
                  Word("then", [.swipe("th", .left), .swipe("en", .right)]),
                  Word("into", [.swipe("in", .right), .swipe("to", .left)]),
                  Word("over", [.swipe("ov", .right), .swipe("er", .left)]),
                  Word("under", [.swipe("un", .right), .swipe("de", .left), .tap("r", .left)]),
                  Word("bring", [.swipe("br", .left), .swipe("in", .right), .tap("g", .left)]),
              ]),
        Drill(id: .switching, number: 2, title: "Switching thumbs", subtitle: "Start left, finish right",
              hint: [.left("Left"), .plain(" swipes "), .strong("w→e"), .plain(", "), .right("right"), .plain(" swipes "),
                     .strong("n→t"), .plain(". Keys light up to show which thumb.")],
              words: [
                  Word("went", [.swipe("we", .left), .swipe("nt", .right)]),
                  Word("stop", [.swipe("st", .left), .swipe("op", .right)]),
                  Word("drum", [.swipe("dr", .left), .swipe("um", .right)]),
                  Word("mouse", [.swipe("mou", .right), .swipe("se", .left)]),
                  Word("hunger", [.swipe("hun", .right), .swipe("ger", .left)]),
              ]),
        Drill(id: .doubles, number: 3, title: "Doubled letters", subtitle: "A tap inside a swipe",
              hint: [.plain("Swipe the word once, and while the swipe is on the doubled letter, "),
                     .plain("tap it with the other thumb.")],
              words: [
                  Word("hello", [.swipe("helo", .right), .tap("l", .left)], tapInsideSwipe: true),
                  Word("coffee", [.swipe("cofe", .left), .tap("f", .right)], tapInsideSwipe: true),
                  Word("little", [.swipe("litle", .right), .tap("t", .left)], tapInsideSwipe: true),
                  Word("happy", [.swipe("hapy", .right), .tap("p", .left)], tapInsideSwipe: true),
                  Word("better", [.swipe("beter", .left), .tap("t", .right)], tapInsideSwipe: true),
              ]),
    ]

    public static func named(_ id: ID) -> Drill {
        all.first { $0.id == id } ?? all[0]
    }

    /// The hint as one plain string, for accessibility and tests.
    public var hintText: String { hint.map(\.text).joined() }

    /// The letters of a word with the thumb that types each, for lighting the keys.
    public static func keys(for word: Word) -> [(letter: Character, side: Side)] {
        var out: [(Character, Side)] = []
        for stroke in word.strokes {
            for letter in stroke.letters where !out.contains(where: { $0.0 == letter }) {
                out.append((letter, stroke.side))
            }
        }
        return out
    }
}

public extension TryWord.HintPart {
    static func plain(_ text: String) -> TryWord.HintPart { TryWord.HintPart(text: text, role: .plain) }
    static func strong(_ text: String) -> TryWord.HintPart { TryWord.HintPart(text: text, role: .strong) }
    static func left(_ text: String) -> TryWord.HintPart { TryWord.HintPart(text: text, role: .left) }
    static func right(_ text: String) -> TryWord.HintPart { TryWord.HintPart(text: text, role: .right) }
}
