import Foundation

/// A key on the keyboard.
public enum Key: Hashable, Sendable {
    case letter(Character)
    /// A digit or punctuation mark on the numbers and symbols pages; types itself.
    case symbol(Character)
    case shift
    case backspace
    /// Switch to the numbers page ("123").
    case numbers
    /// Switch to the symbols page ("#+=").
    case symbols
    /// Back to the letters ("ABC").
    case letters
    case globe
    case space
    case returnKey

    /// The letter, for letter keys.
    public var character: Character? {
        if case .letter(let c) = self { return c }
        return nil
    }

    /// The character a symbol key types.
    public var symbolCharacter: Character? {
        if case .symbol(let c) = self { return c }
        return nil
    }

    /// Shift, backspace, the page keys, the globe and return: drawn darker.
    public var isFunction: Bool {
        switch self {
        case .letter, .symbol, .space: false
        default: true
        }
    }
}

/// Which thumb a key belongs to: the left half of the keyboard or the right.
public enum Side: Sendable, Equatable {
    case left, right
}

/// Where the keys are, for a keyboard of a given width. Pure geometry, shared by the
/// key surface (to draw) and the matcher (to decode), so they always agree. Apple's
/// QWERTY proportions so muscle memory carries over (DESIGN.md "The keyboard").
///
///     let layout = Layout.qwerty(width: 390)
///     layout.key(at: CGPoint(x: 40, y: 30))   // .letter("w")
///     layout.frame(of: .space)
///     layout.side(of: .letter("h"))           // .right
///     Layout.qwerty(width: 390, page: .numbers).key(at: CGPoint(x: 40, y: 30))  // .symbol("2")
public struct Layout: Sendable, Equatable {
    public struct Placement: Sendable, Equatable {
        public let key: Key
        public let frame: CGRect
        public let row: Int
    }

    /// The keyboard's pages: letters, then "123" and "#+=" like Apple's.
    public enum Page: Sendable, Equatable {
        case letters, numbers, symbols
    }

    public static let rows: [[Character]] = [
        Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm"),
    ]
    static let numberRows: [[Character]] = [
        Array("1234567890"), Array("-/:;()$&@\""), Array(".,?!'"),
    ]
    static let symbolRows: [[Character]] = [
        Array("[]{}#%^*+="), Array("_\\|~<>€£¥•"), Array(".,?!'"),
    ]

    public let width: CGFloat
    public let page: Page
    /// The halves pulled apart to the screen's edges (wide screens only).
    public let split: Bool
    /// On a split keyboard, each half also has the next key past Apple's: Y H B on the
    /// left, T F C on the right (an option, Gabriel, 2 Nov 2026).
    public let extraLetters: Bool
    /// The keyboard's height: the keys fill it edge to edge, with no padding of their
    /// own (iOS pads the keyboard itself). The bar is not part of it.
    public let height: CGFloat
    public let keyHeight: CGFloat
    public let gap: CGFloat
    public let placements: [Placement]

    private let top: CGFloat
    private let rowGap: CGFloat

    /// From what width on the screen counts as wide (the iPhone Duo's inner screen).
    public static let wideWidth: CGFloat = 700
    /// The least room a split keyboard leaves between its halves, for the guesses.
    public static let splitMiddle: CGFloat = 120
    /// The space between keys, across and down: a thin line, so the keys get nearly
    /// all the room and taps rarely land in a gap (Gabriel, 2 Nov 2026).
    public static let keyGap: CGFloat = 2
    /// The widest a letter key gets, so a swipe keeps its shape on a wide screen.
    public static let maxKeyWidth: CGFloat = 64
    /// The tallest a key gets when the keyboard has more room than it needs.
    public static let maxKeyHeight: CGFloat = 64

    /// The standard layout for a width: 37 pt keys at 390 pt (an iPhone), wider on the
    /// iPhone Duo's screens, capped at 64 pt so a swipe keeps its shape on a wide
    /// screen (DESIGN.md "Sizes"). Keys are `keyGap` apart, across and down, and the
    /// keyboard is as tall as Apple's, so the keys are bigger than Apple's in both
    /// directions. Every page has the same height, and no page has any padding: the
    /// keys run to the edges and iOS adds its own margins around the keyboard
    /// (Gabriel, 2 Nov 2026).
    ///
    /// `split` pulls the two halves apart on a wide screen, each under a thumb, with the
    /// space bar in both and, like Apple's, G and V on both halves. `extraLetters`
    /// adds one more key past the middle to each half (Y H B left, T F C right). `height` makes the keys fill that
    /// height (the room the system granted): they shrink to fit or grow up to a limit,
    /// and past the limit they sit at the bottom.
    public static func qwerty(width: CGFloat, page: Page = .letters, split: Bool = false, extraLetters: Bool = false,
                              height fill: CGFloat? = nil) -> Layout {
        let gap = keyGap
        let wide = width >= wideWidth
        let split = split && wide
        let extra = split && extraLetters
        var unit = min(maxKeyWidth, ((width - 9 * gap) / 10).rounded(.down))
        if split {
            // Two halves of 5.5 keys (6.5 with the extra letters), the middle left over.
            unit = extraLetters
                ? min(unit, ((width - splitMiddle - 11 * gap) / 13).rounded(.down))
                : min(unit, ((width - splitMiddle - 9 * gap) / 11).rounded(.down))
        }

        // As tall as Apple's keyboard (42 pt keys 14 pt apart on a wide screen, 44 and
        // 11 on a phone), with the rows only `keyGap` apart, so the keys take the rest.
        let natural: CGFloat = wide ? 210 : 209
        let rowGap = gap
        var keyHeight = (natural - 3 * rowGap) / 4
        var top: CGFloat = 0
        var height = natural
        if let fill, fill > 0, fill != natural {
            keyHeight = min(maxKeyHeight, max(28, (fill - 3 * rowGap) / 4))
            let used = 4 * keyHeight + 3 * rowGap
            top = max(0, fill - used)
            height = max(fill, used)
        }

        let rowWidth = 10 * unit + 9 * gap
        let left = ((width - rowWidth) / 2).rounded()

        var placements: [Placement] = []
        func y(_ row: Int) -> CGFloat { top + CGFloat(row) * (keyHeight + rowGap) }
        func add(_ key: Key, row: Int, x: CGFloat, width w: CGFloat) {
            placements.append(Placement(key: key, frame: CGRect(x: x, y: y(row), width: w, height: keyHeight), row: row))
        }
        func keys(_ chars: [Character], as make: (Character) -> Key, row: Int, from x: CGFloat) -> CGFloat {
            var x = x
            for c in chars {
                add(make(c), row: row, x: x, width: unit)
                x += unit + gap
            }
            return x
        }

        let wideKey = (1.45 * unit).rounded()
        let fnKey = (1.33 * unit).rounded()
        let returnKey = (2.66 * unit).rounded()
        var x: CGFloat

        if split {
            // Apple's split: each half is a window on the whole keyboard, so a swipe has
            // the same shape as on one keyboard. The left half is Q to T, A to G and Z to
            // V; the right is Y to P, G to L and V to M, so G and V are on both (Gabriel,
            // 2 Nov 2026: exactly like Apple's). Each letter's own copy is placed first
            // (`frame(of:)` finds it), the right half's G and V after.
            let pitch = unit + gap
            let leftEnd = (extra ? 5.5 : 4.5) * pitch + unit
            let backspaceX = 8.5 * pitch
            let rightShift = width - max(9 * pitch + unit, backspaceX + wideKey)
            let rightStart = (extra ? 3.5 : 4.5) * pitch + rightShift
            switch page {
            case .letters:
                func letter(_ row: Int, _ column: Int, shift dx: CGFloat) {
                    let offset: CGFloat = [0, 0.5, 1.5][row]
                    add(.letter(rows[row][column]), row: row, x: (CGFloat(column) + offset) * pitch + dx, width: unit)
                }
                // Left half's own keys, then the right's, then the shared ones.
                for c in 0..<5 { letter(0, c, shift: 0) }
                for c in 0..<5 { letter(1, c, shift: 0) }
                add(.shift, row: 2, x: 1.5 * pitch - gap - wideKey, width: wideKey)
                for c in 0..<4 { letter(2, c, shift: 0) }
                for c in 5..<10 { letter(0, c, shift: rightShift) }
                for c in 5..<9 { letter(1, c, shift: rightShift) }
                for c in 4..<7 { letter(2, c, shift: rightShift) }
                add(.backspace, row: 2, x: backspaceX + rightShift, width: wideKey)
                letter(1, 4, shift: rightShift); letter(2, 3, shift: rightShift)
                if extra {
                    letter(0, 5, shift: 0); letter(1, 5, shift: 0); letter(2, 4, shift: 0)
                    letter(0, 4, shift: rightShift); letter(1, 3, shift: rightShift); letter(2, 2, shift: rightShift)
                }
            case .numbers, .symbols:
                let table = page == .numbers ? numberRows : symbolRows
                let half = 5 * unit + 4 * gap
                _ = keys(Array(table[0][0..<5]), as: Key.symbol, row: 0, from: 0)
                _ = keys(Array(table[0][5...]), as: Key.symbol, row: 0, from: width - half)
                _ = keys(Array(table[1][0..<5]), as: Key.symbol, row: 1, from: 0)
                _ = keys(Array(table[1][5...]), as: Key.symbol, row: 1, from: width - half)
                add(page == .numbers ? .symbols : .numbers, row: 2, x: 0, width: wideKey)
                _ = keys(Array(table[2][0..<3]), as: Key.symbol, row: 2, from: wideKey + gap)
                x = keys(Array(table[2][3...]), as: Key.symbol, row: 2, from: width - wideKey - 2 * unit - 2 * gap)
                add(.backspace, row: 2, x: x, width: wideKey)
            }
            add(page == .letters ? .numbers : .letters, row: 3, x: 0, width: fnKey)
            add(.globe, row: 3, x: fnKey + gap, width: fnKey)
            add(.space, row: 3, x: 2 * (fnKey + gap), width: leftEnd - 2 * (fnKey + gap))
            add(.space, row: 3, x: rightStart, width: width - rightStart - returnKey - gap)
            add(.returnKey, row: 3, x: width - returnKey, width: returnKey)
            return Layout(width: width, page: page, split: true, extraLetters: extra, height: height,
                          keyHeight: keyHeight, gap: gap, placements: placements, top: top, rowGap: rowGap)
        }

        switch page {
        case .letters:
            _ = keys(rows[0], as: Key.letter, row: 0, from: left)
            _ = keys(rows[1], as: Key.letter, row: 1, from: left + (unit + gap) / 2)
            let row2Width = 2 * wideKey + 7 * unit + 8 * gap
            x = ((width - row2Width) / 2).rounded()
            add(.shift, row: 2, x: x, width: wideKey)
            x = keys(rows[2], as: Key.letter, row: 2, from: x + wideKey + gap)
            add(.backspace, row: 2, x: x, width: wideKey)
        case .numbers, .symbols:
            let table = page == .numbers ? numberRows : symbolRows
            _ = keys(table[0], as: Key.symbol, row: 0, from: left)
            _ = keys(table[1], as: Key.symbol, row: 1, from: left)
            let row2Width = 2 * wideKey + 5 * unit + 6 * gap
            x = ((width - row2Width) / 2).rounded()
            add(page == .numbers ? .symbols : .numbers, row: 2, x: x, width: wideKey)
            x = keys(table[2], as: Key.symbol, row: 2, from: x + wideKey + gap)
            add(.backspace, row: 2, x: x, width: wideKey)
        }

        let space = rowWidth - 2 * fnKey - returnKey - 3 * gap
        x = left
        add(page == .letters ? .numbers : .letters, row: 3, x: x, width: fnKey); x += fnKey + gap
        add(.globe, row: 3, x: x, width: fnKey); x += fnKey + gap
        add(.space, row: 3, x: x, width: space); x += space + gap
        add(.returnKey, row: 3, x: x, width: returnKey)

        return Layout(width: width, page: page, split: false, extraLetters: false, height: height,
                      keyHeight: keyHeight, gap: gap, placements: placements, top: top, rowGap: rowGap)
    }

    /// The key under a point. Forgiving like Apple's keyboard: the gaps between keys
    /// and the edges of a row count for the nearest key. Nil above or below the keys.
    public func key(at point: CGPoint) -> Key? {
        guard point.y >= 0, point.y <= height else { return nil }
        let rowIndex = min(3, max(0, Int((point.y - top + rowGap / 2) / (keyHeight + rowGap))))
        let row = placements.filter { $0.row == rowIndex }
        guard let nearest = row.min(by: { abs($0.frame.midX - point.x) < abs($1.frame.midX - point.x) }) else { return nil }
        return nearest.key
    }

    /// The key's frame; for a key that is placed twice (space, and the middle letters
    /// on a split keyboard), its own copy: the one on the half it belongs to.
    public func frame(of key: Key) -> CGRect? {
        placements.first { $0.key == key }?.frame
    }

    /// The key's frame on one half: for a middle letter on a split keyboard, the copy
    /// under that thumb ("t" on the right is the T beside Y there). Any copy when the
    /// key is only on the other half.
    ///
    ///     layout.frame(of: .letter("t"), on: .right)   // the right half's T
    public func frame(of key: Key, on side: Side) -> CGRect? {
        let copies = placements.filter { $0.key == key }
        return (copies.first { self.side(at: CGPoint(x: $0.frame.midX, y: 0)) == side } ?? copies.first)?.frame
    }

    /// The stretches of the width that no key in any row covers and that are at least
    /// `minWidth` wide, left to right: the middle of a split keyboard, the sides of a
    /// wide one. The keyboard puts its guesses there instead of in a bar on top.
    public func openColumns(atLeast minWidth: CGFloat) -> [ClosedRange<CGFloat>] {
        var out: [ClosedRange<CGFloat>] = []
        var x: CGFloat = 0
        for frame in placements.map(\.frame).sorted(by: { $0.minX < $1.minX }) {
            if frame.minX - x >= minWidth { out.append(x...frame.minX) }
            x = max(x, frame.maxX)
        }
        if width - x >= minWidth { out.append(x...width) }
        return out
    }

    /// The length the matcher measures distances in. Its weights were tuned on
    /// Apple's phone keys (33 pt wide, 6 pt apart, so 39 pt from centre to centre), so
    /// this is that key width scaled to this layout's key spacing: 33 pt on a phone
    /// whatever the gap. Measuring in the key's own width instead made the keys look
    /// closer together once they grew into the gaps, and "helo" came out "help".
    public var distanceUnit: CGFloat {
        guard let q = frame(of: .letter("q")) else { return 33 }
        return (q.width + gap) * 33 / 39
    }

    /// Whether this width counts as wide (the iPhone Duo's inner screen).
    public var isWide: Bool { width >= Self.wideWidth }

    /// The thumb a key belongs to, by which half of the keyboard it sits in.
    public func side(of key: Key) -> Side {
        guard let frame = frame(of: key) else { return .left }
        return frame.midX < width / 2 ? .left : .right
    }

    /// The thumb a touch belongs to, by which half of the keyboard it landed in.
    public func side(at point: CGPoint) -> Side {
        point.x < width / 2 ? .left : .right
    }
}
