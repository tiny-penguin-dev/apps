import Foundation

/// A key on the keyboard.
public enum Key: Hashable, Sendable {
    case letter(Character)
    case shift
    case backspace
    case numbers
    case globe
    case space
    case returnKey

    /// The letter, for letter keys.
    public var character: Character? {
        if case .letter(let c) = self { return c }
        return nil
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
public struct Layout: Sendable, Equatable {
    public struct Placement: Sendable, Equatable {
        public let key: Key
        public let frame: CGRect
        public let row: Int
    }

    public static let rows: [[Character]] = [
        Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm"),
    ]

    public let width: CGFloat
    /// The keyboard's height, keys and padding included (the bar is not part of it).
    public let height: CGFloat
    public let keyHeight: CGFloat
    public let gap: CGFloat
    public let placements: [Placement]

    private let top: CGFloat
    private let rowGap: CGFloat

    /// The standard layout for a width: 33 pt keys at 390 pt (an iPhone), wider on the
    /// iPhone Duo's screens, capped at 58 pt so a swipe keeps its shape on a wide
    /// screen (DESIGN.md "Sizes").
    public static func qwerty(width: CGFloat) -> Layout {
        let margin: CGFloat = 3
        let gap = min(8, max(4, (6 * width / 390).rounded()))
        let unit = min(58, ((width - 2 * margin - 9 * gap) / 10).rounded(.down))
        let wide = width >= 700
        let keyHeight: CGFloat = wide ? 54 : 44
        let rowGap: CGFloat = wide ? 10 : 9
        let top: CGFloat = 8
        let bottom: CGFloat = 5
        let rowWidth = 10 * unit + 9 * gap
        let left = ((width - rowWidth) / 2).rounded()

        var placements: [Placement] = []
        func y(_ row: Int) -> CGFloat { top + CGFloat(row) * (keyHeight + rowGap) }
        func add(_ key: Key, row: Int, x: CGFloat, width w: CGFloat) {
            placements.append(Placement(key: key, frame: CGRect(x: x, y: y(row), width: w, height: keyHeight), row: row))
        }
        func letters(_ chars: [Character], row: Int, from x: CGFloat) -> CGFloat {
            var x = x
            for c in chars {
                add(.letter(c), row: row, x: x, width: unit)
                x += unit + gap
            }
            return x
        }

        _ = letters(rows[0], row: 0, from: left)
        _ = letters(rows[1], row: 1, from: left + (unit + gap) / 2)

        let wideKey = (1.45 * unit).rounded()
        let row2Width = 2 * wideKey + 7 * unit + 8 * gap
        var x = ((width - row2Width) / 2).rounded()
        add(.shift, row: 2, x: x, width: wideKey)
        x = letters(rows[2], row: 2, from: x + wideKey + gap)
        add(.backspace, row: 2, x: x, width: wideKey)

        let fnKey = (1.33 * unit).rounded()
        let returnKey = (2.66 * unit).rounded()
        let space = rowWidth - 2 * fnKey - returnKey - 3 * gap
        x = left
        add(.numbers, row: 3, x: x, width: fnKey); x += fnKey + gap
        add(.globe, row: 3, x: x, width: fnKey); x += fnKey + gap
        add(.space, row: 3, x: x, width: space); x += space + gap
        add(.returnKey, row: 3, x: x, width: returnKey)

        return Layout(width: width, height: top + 4 * keyHeight + 3 * rowGap + bottom,
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

    public func frame(of key: Key) -> CGRect? {
        placements.first { $0.key == key }?.frame
    }

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
