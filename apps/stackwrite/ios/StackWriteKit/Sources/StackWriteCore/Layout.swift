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
    /// The keyboard's height, keys and padding included (the bar is not part of it).
    public let height: CGFloat
    public let keyHeight: CGFloat
    public let gap: CGFloat
    public let placements: [Placement]

    private let top: CGFloat
    private let rowGap: CGFloat

    /// From what width on the screen counts as wide (the iPhone Duo's inner screen).
    public static let wideWidth: CGFloat = 700

    /// The standard layout for a width: 33 pt keys at 390 pt (an iPhone), wider on the
    /// iPhone Duo's screens, capped at 58 pt so a swipe keeps its shape on a wide
    /// screen (DESIGN.md "Sizes"). Every page has the same height. `split` pulls the
    /// two halves apart on a wide screen, each under a thumb, with the space bar in
    /// both. `maxHeight` shrinks the keys when the system grants less room than the
    /// layout wants, so the bar and every row stay on screen.
    public static func qwerty(width: CGFloat, page: Page = .letters, split: Bool = false, maxHeight: CGFloat? = nil) -> Layout {
        let margin: CGFloat = 3
        let gap = min(8, max(4, (6 * width / 390).rounded()))
        let unit = min(58, ((width - 2 * margin - 9 * gap) / 10).rounded(.down))
        let wide = width >= wideWidth
        var keyHeight: CGFloat = wide ? 54 : 44
        var rowGap: CGFloat = wide ? 10 : 9
        let top: CGFloat = 8
        let bottom: CGFloat = 5
        if let maxHeight, top + 4 * keyHeight + 3 * rowGap + bottom > maxHeight {
            let available = maxHeight - top - bottom
            rowGap = max(4, min(rowGap, ((available - 4 * 36) / 3).rounded(.down)))
            keyHeight = max(28, ((available - 3 * rowGap) / 4).rounded(.down))
        }
        let split = split && wide
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
            // Two blocks, five keys wide, at the screen's edges. Rows are laid from the
            // left edge on the left and end at the right edge on the right; the home row
            // sits half a key in, as it does whole.
            let edge: CGFloat = 12
            let half = 5 * unit + 4 * gap
            func leftRow(_ items: [(Key, CGFloat)], row: Int, inset: CGFloat = 0) {
                var x = edge + inset
                for (key, w) in items {
                    add(key, row: row, x: x, width: w)
                    x += w + gap
                }
            }
            func rightRow(_ items: [(Key, CGFloat)], row: Int, inset: CGFloat = 0) {
                let total = items.reduce(0) { $0 + $1.1 } + CGFloat(items.count - 1) * gap
                var x = width - edge - inset - total
                for (key, w) in items {
                    add(key, row: row, x: x, width: w)
                    x += w + gap
                }
            }
            func units(_ chars: ArraySlice<Character>, as make: (Character) -> Key) -> [(Key, CGFloat)] {
                chars.map { (make($0), unit) }
            }
            switch page {
            case .letters:
                leftRow(units(rows[0][0..<5], as: Key.letter), row: 0)
                rightRow(units(rows[0][5...], as: Key.letter), row: 0)
                leftRow(units(rows[1][0..<5], as: Key.letter), row: 1, inset: unit / 2)
                rightRow(units(rows[1][5...], as: Key.letter), row: 1, inset: unit / 2)
                leftRow([(.shift, wideKey)] + units(rows[2][0..<4], as: Key.letter), row: 2)
                rightRow(units(rows[2][4...], as: Key.letter) + [(.backspace, wideKey)], row: 2)
            case .numbers, .symbols:
                let table = page == .numbers ? numberRows : symbolRows
                leftRow(units(table[0][0..<5], as: Key.symbol), row: 0)
                rightRow(units(table[0][5...], as: Key.symbol), row: 0)
                leftRow(units(table[1][0..<5], as: Key.symbol), row: 1)
                rightRow(units(table[1][5...], as: Key.symbol), row: 1)
                leftRow([(page == .numbers ? .symbols : .numbers, wideKey)] + units(table[2][0..<3], as: Key.symbol), row: 2)
                rightRow(units(table[2][3...], as: Key.symbol) + [(.backspace, wideKey)], row: 2)
            }
            leftRow([(page == .letters ? .numbers : .letters, fnKey), (.globe, fnKey), (.space, half - 2 * fnKey - 2 * gap)], row: 3)
            rightRow([(.space, half - returnKey - gap), (.returnKey, returnKey)], row: 3)
            return Layout(width: width, page: page, split: true, height: top + 4 * keyHeight + 3 * rowGap + bottom,
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

        return Layout(width: width, page: page, split: false, height: top + 4 * keyHeight + 3 * rowGap + bottom,
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

    /// The key's frame; for a key that is placed twice (space on a split keyboard), the first.
    public func frame(of key: Key) -> CGRect? {
        placements.first { $0.key == key }?.frame
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
