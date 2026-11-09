import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct LayoutTests {
    /// Gabriel's iPhone Duo, split (8 Nov 2026): iOS put every backspace tap's down on
    /// M at x 678 and its first move on backspace 8 ms later. The keyboard starts such
    /// a touch again where it really is, so it is a backspace tap, not an M swipe.
    @Test func misplacedDownIsSpotted() {
        let layout = Layout.qwerty(width: 801, split: true, extraLetters: true, globe: true, height: 216)
        let down = CGPoint(x: 678, y: 131)
        #expect(layout.key(at: down) == .letter("m"))
        for x in [747.0, 764.0, 770.0, 785.0] as [CGFloat] {
            let next = CGPoint(x: x, y: 132)
            #expect(Layout.downWasMisplaced(down, next: next))
            #expect(layout.key(at: next) == .backspace)
        }
        // A real swipe's first move is a few points: still a swipe.
        #expect(!Layout.downWasMisplaced(down, next: CGPoint(x: 690, y: 128)))
        #expect(!Layout.downWasMisplaced(down, next: down))
    }

    @Test func phoneHasApplesProportions() {
        let layout = Layout.qwerty(width: 390)
        let q = layout.frame(of: .letter("q"))!
        #expect(q.width == 37)
        #expect(q.height == 51.75)
        #expect(layout.gap == 2)
        // Apple's rows span 213 pt, and Apple's bottom row sits 7 pt higher than ours would.
        #expect(layout.height == 220)
        #expect(layout.bottomInset == 7)
        // No padding of our own at the top: the top row starts where Apple's does.
        #expect(q.minY == 0)
        #expect(layout.frame(of: .space)!.maxY == 213)
        #expect(layout.placements.filter { $0.row == 0 }.count == 10)
        #expect(layout.placements.filter { $0.row == 1 }.count == 9)
        #expect(layout.placements.filter { $0.row == 2 }.count == 9)
        #expect(layout.placements.filter { $0.row == 3 }.count == 4)
    }

    @Test(arguments: [320.0, 390.0, 420.0, 744.0] as [CGFloat])
    func keysFitEverySize(width: CGFloat) {
        let layout = Layout.qwerty(width: width)
        for placement in layout.placements {
            #expect(placement.frame.minX >= 0)
            #expect(placement.frame.maxX <= width)
            #expect(placement.frame.maxY <= layout.height)
        }
        let unit = layout.frame(of: .letter("q"))!.width
        #expect(unit <= Layout.maxKeyWidth)
        #expect(layout.frame(of: .space)!.width > 3 * unit)
    }

    @Test func wideKeysAreCapped() {
        let layout = Layout.qwerty(width: 744)
        #expect(layout.frame(of: .letter("q"))!.width == 64)
        #expect(layout.keyHeight == 50.5)
        #expect(layout.height == 212)
    }

    @Test func hitTestingIsForgiving() {
        let layout = Layout.qwerty(width: 390)
        let h = layout.frame(of: .letter("h"))!
        #expect(layout.key(at: CGPoint(x: h.midX, y: h.midY)) == .letter("h"))
        // In the gap just right of h, still h.
        #expect(layout.key(at: CGPoint(x: h.maxX + 0.5, y: h.midY)) == .letter("h"))
        // Off the left edge of a row, the first key.
        #expect(layout.key(at: CGPoint(x: 1, y: h.midY)) == .letter("a"))
        // Between two rows, the nearer one.
        #expect(layout.key(at: CGPoint(x: h.midX, y: h.minY - 0.5)) == .letter("h"))
        #expect(layout.key(at: CGPoint(x: 100, y: -1)) == nil)
        #expect(layout.key(at: CGPoint(x: 100, y: layout.height + 1)) == nil)
        #expect(layout.key(at: CGPoint(x: 195, y: layout.height - 20)) == .space)
        // Under the bottom row, still the bottom row.
        #expect(layout.key(at: CGPoint(x: 195, y: layout.height - 1)) == .space)
    }

    @Test func wideKeysGetAllOfTheirOwnRoom() {
        // Nearest by edge, not by middle: the ends of a wide key are that key.
        let layout = Layout.qwerty(width: 390)
        for key in [Key.space, .shift, .backspace, .emoji] {  // return: spaceReachesIntoReturn
            let f = layout.frame(of: key)!
            #expect(layout.key(at: CGPoint(x: f.minX + 1, y: f.midY)) == key, "\(key)")
            #expect(layout.key(at: CGPoint(x: f.maxX - 1, y: f.midY)) == key, "\(key)")
        }
    }

    @Test func spaceReachesIntoReturn() {
        let layouts = [
            Layout.qwerty(width: 390), Layout.qwerty(width: 430, globe: true),
            Layout.qwerty(width: 390, page: .numbers),
            Layout.qwerty(width: 951), Layout.qwerty(width: 951, split: true),
        ]
        for layout in layouts {
            let enter = layout.frame(of: .returnKey)!
            let y = enter.midY
            // A tap that just catches return's left edge is a space...
            #expect(layout.key(at: CGPoint(x: enter.minX + Layout.spaceReach - layout.gap - 1, y: y)) == .space)
            // ...but return's own middle and right are still return, and look the same.
            #expect(layout.key(at: CGPoint(x: enter.minX + Layout.spaceReach + 1, y: y)) == .returnKey)
            #expect(layout.key(at: CGPoint(x: enter.midX, y: y)) == .returnKey)
            #expect(layout.key(at: CGPoint(x: enter.maxX - 1, y: y)) == .returnKey)
        }
        // Where space isn't beside return (a web address, a search's "."), return keeps its edge.
        for bottom in [Layout.BottomRow.url, .webSearch] {
            let layout = Layout.qwerty(width: 390, bottom: bottom)
            let enter = layout.frame(of: .returnKey)!
            #expect(layout.key(at: CGPoint(x: enter.minX + 1, y: enter.midY)) == .returnKey, "\(bottom)")
        }
    }

    @Test func theKeyboardHeightMovesTheTopRowOnly() {
        let apple = Layout.qwerty(width: 390)
        let taller = Layout.qwerty(width: 390, scale: 1.2)
        let shorter = Layout.qwerty(width: 390, scale: 0.8)
        #expect(taller.keyHeight > apple.keyHeight)
        #expect(shorter.keyHeight < apple.keyHeight)
        #expect(abs(taller.height - 263) < 0.001)
        #expect(abs(shorter.height - 177) < 0.001)
        // Measured from the bottom, the bottom row stays put.
        for layout in [taller, shorter] {
            #expect(abs(layout.height - layout.frame(of: .space)!.maxY - 7) < 0.001)
            #expect(layout.frame(of: .letter("q"))!.minY == 0)
        }
    }

    @Test func theSplitSitsWhereApplesDoes() {
        let full = Layout.qwerty(width: 1000)
        let split = Layout.qwerty(width: 1000, split: true)
        #expect(full.bottomInset == 4)
        #expect(split.bottomInset == 8)
        #expect(split.keyHeight == full.keyHeight)
        #expect(abs(split.height - full.height - 4) < 0.001)
    }

    @Test func sidesFollowTheHalves() {
        let layout = Layout.qwerty(width: 390)
        #expect(layout.side(of: .letter("s")) == .left)
        #expect(layout.side(of: .letter("h")) == .right)
        #expect(layout.side(of: .letter("t")) == .left)
        #expect(layout.side(of: .letter("y")) == .right)
        #expect(layout.side(at: CGPoint(x: 10, y: 10)) == .left)
    }

    // MARK: Pages (Phase 3)

    @Test func numbersPageHasApplesRows() {
        let layout = Layout.qwerty(width: 390, page: .numbers)
        #expect(layout.page == .numbers)
        #expect(layout.height == Layout.qwerty(width: 390).height)
        #expect(layout.placements.filter { $0.row == 0 }.count == 10)
        #expect(layout.placements.filter { $0.row == 1 }.count == 10)
        #expect(layout.placements.filter { $0.row == 2 }.count == 7)
        #expect(layout.placements.filter { $0.row == 3 }.count == 4)
        #expect(layout.frame(of: .symbol("1")) != nil)
        #expect(layout.frame(of: .symbol("@")) != nil)
        #expect(layout.frame(of: .symbols) != nil)
        #expect(layout.frame(of: .letters) != nil)
        #expect(layout.frame(of: .numbers) == nil)
        #expect(layout.frame(of: .letter("q")) == nil)
        let one = layout.frame(of: .symbol("1"))!
        #expect(layout.key(at: CGPoint(x: one.midX, y: one.midY)) == .symbol("1"))
        #expect(layout.frame(of: .symbol("1"))!.width == Layout.qwerty(width: 390).frame(of: .letter("q"))!.width)
    }

    @Test func symbolsPageGoesBackToNumbers() {
        let layout = Layout.qwerty(width: 390, page: .symbols)
        #expect(layout.frame(of: .symbol("[")) != nil)
        #expect(layout.frame(of: .symbol("€")) != nil)
        #expect(layout.frame(of: .numbers) != nil)
        #expect(layout.frame(of: .symbols) == nil)
        #expect(layout.frame(of: .letters) != nil)
        #expect(layout.placements.filter { $0.row == 2 }.count == 7)
    }

    @Test func numbersThirdRowFillsTheRow() {
        let layout = Layout.qwerty(width: 390, page: .numbers)
        let q = Layout.qwerty(width: 390).frame(of: .letter("q"))!
        let p = Layout.qwerty(width: 390).frame(of: .letter("p"))!
        // The page key and backspace at the row's ends, under 1 and 0, as wide as ABC.
        #expect(layout.frame(of: .symbols)!.minX == q.minX)
        #expect(abs(layout.frame(of: .backspace)!.maxX - p.maxX) < 0.001)
        let abc = layout.frame(of: .letters)!.width
        #expect(layout.frame(of: .symbols)!.width == abc)
        #expect(layout.frame(of: .backspace)!.width == abc)
        // The five marks are wider than a letter and keep clear of each other.
        let marks = layout.placements.filter { $0.row == 2 && $0.key.symbolCharacter != nil }.map(\.frame)
        #expect(marks.count == 5)
        for (a, b) in zip(marks, marks.dropFirst()) {
            #expect(a.width > q.width)
            #expect(b.minX > a.maxX)
        }
        // No extra room between them: every key is `keyGap` from the next.
        let row = layout.placements.filter { $0.row == 2 }.map(\.frame).sorted { $0.minX < $1.minX }
        for (a, b) in zip(row, row.dropFirst()) {
            #expect(abs(b.minX - a.maxX - layout.gap) < 0.001)
        }
        // The middle mark is in the middle, like Apple's "?".
        #expect(abs(marks[2].midX - 195) < 2)
    }

    @Test(arguments: [320.0, 390.0, 744.0] as [CGFloat])
    func everyPageFits(width: CGFloat) {
        for page in [Layout.Page.numbers, .symbols] {
            let layout = Layout.qwerty(width: width, page: page)
            for placement in layout.placements {
                #expect(placement.frame.minX >= 0)
                #expect(placement.frame.maxX <= width)
                #expect(placement.frame.maxY <= layout.height)
            }
        }
    }

    /// Shift (or the page key) and backspace reach the row's outer edges, in line
    /// with Q and P above them, on every page, whole or split (Gabriel, 8 Nov 2026).
    @Test(arguments: [320.0, 390.0, 744.0, 1000.0] as [CGFloat])
    func shiftAndBackspaceReachTheEdges(width: CGFloat) {
        for page in [Layout.Page.letters, .numbers, .symbols] {
            for (split, extra) in [(false, false), (true, false), (true, true)] {
                let layout = Layout.qwerty(width: width, page: page, split: split, extraLetters: extra)
                func row(_ i: Int) -> [CGRect] {
                    layout.placements.filter { $0.row == i }.map(\.frame).sorted { $0.minX < $1.minX }
                }
                let label = "\(page) split \(split) extra \(extra)"
                #expect(abs(row(2).first!.minX - row(0).first!.minX) < 0.001, "\(label)")
                #expect(abs(row(2).last!.maxX - row(0).last!.maxX) < 0.001, "\(label)")
                #expect(layout.placements.first { $0.row == 2 && $0.frame == row(2).last! }!.key == .backspace, "\(label)")
                for (a, b) in zip(row(2), row(2).dropFirst()) where a.maxX <= b.minX {
                    #expect(b.minX - a.maxX >= layout.gap - 0.001, "\(label)")
                }
            }
        }
    }

    @Test func functionKeysAreDrawnDarker() {
        #expect(Key.shift.isFunction)
        #expect(Key.letters.isFunction)
        #expect(Key.globe.isFunction)
        #expect(!Key.letter("a").isFunction)
        #expect(!Key.symbol("1").isFunction)
        #expect(!Key.space.isFunction)
        #expect(Key.symbol("?").symbolCharacter == "?")
        #expect(Key.symbol("?").character == nil)
    }

    // MARK: Wide screens

    @Test func rowSpansMatchTheKeys() {
        let layout = Layout.qwerty(width: 1000, split: true)
        for (row, letter) in zip(0..<3, ["q", "a", "z"] as [Character]) {
            let frame = layout.frame(of: .letter(letter))!
            #expect(layout.rowSpan(row) == frame.minY...frame.maxY)
        }
        let space = layout.frame(of: .space)!
        #expect(layout.rowSpan(3) == space.minY...space.maxY)
    }

    @Test func splitPullsTheHalvesApart() {
        let layout = Layout.qwerty(width: 1000, split: true)
        #expect(layout.split)
        #expect(layout.isWide)
        #expect(layout.keyHeight == Layout.qwerty(width: 1000).keyHeight)
        for letter in "qwertasdfgzxcv" {
            #expect(layout.frame(of: .letter(letter))!.maxX < 500, "\(letter)")
        }
        for letter in "yuiophjklbnm" {
            #expect(layout.frame(of: .letter(letter))!.minX > 500, "\(letter)")
        }
        #expect(layout.placements.filter { $0.key == .space }.count == 2)
        // The halves run to the edges: iOS adds the margins.
        #expect(layout.placements.map(\.frame.minX).min() == 0)
        #expect(layout.frame(of: .letter("p"))!.maxX == 1000)
        for placement in layout.placements {
            #expect(placement.frame.minX >= 0 && placement.frame.maxX <= 1000)
        }
        #expect(layout.side(of: .letter("t")) == .left)
        #expect(layout.side(of: .letter("y")) == .right)
        for page in [Layout.Page.numbers, .symbols] {
            let split = Layout.qwerty(width: 1000, page: page, split: true)
            // A second space, and "?" on both halves.
            #expect(split.placements.count == Layout.qwerty(width: 1000, page: page).placements.count + 2)
            for placement in split.placements {
                #expect(placement.frame.minX >= 0 && placement.frame.maxX <= 1000)
            }
        }
    }

    @Test(arguments: [744.0, 951.0, 1000.0] as [CGFloat])
    func splitIsApplesWithGAndVOnBothHalves(width: CGFloat) {
        let layout = Layout.qwerty(width: width, split: true)
        for letter in "gv" {
            let copies = layout.placements.filter { $0.key == .letter(letter) }
            #expect(copies.count == 2, "\(letter)")
            let left = layout.frame(of: .letter(letter), on: .left)!
            let right = layout.frame(of: .letter(letter), on: .right)!
            #expect(left.maxX < width / 2 && right.minX > width / 2, "\(letter)")
            #expect(layout.key(at: CGPoint(x: left.midX, y: left.midY)) == .letter(letter))
            #expect(layout.key(at: CGPoint(x: right.midX, y: right.midY)) == .letter(letter))
        }
        for letter in "qwertyuiopasdfhjklzxcbnm" {
            #expect(layout.placements.filter { $0.key == .letter(letter) }.count == 1, "\(letter)")
        }
        // Rows as Apple's: QWERT | YUIOP, ASDFG | GHJKL, ZXCV | VBNM.
        func half(_ row: Int, _ side: Side) -> String {
            String(layout.placements.filter { $0.row == row && layout.side(at: CGPoint(x: $0.frame.midX, y: 0)) == side }
                .sorted { $0.frame.minX < $1.frame.minX }.compactMap(\.key.character))
        }
        #expect(half(0, .left) == "qwert" && half(0, .right) == "yuiop")
        #expect(half(1, .left) == "asdfg" && half(1, .right) == "ghjkl")
        #expect(half(2, .left) == "zxcv" && half(2, .right) == "vbnm")
        // Each half keeps the whole keyboard's stagger: the right G sits under Y's left edge.
        let y = layout.frame(of: .letter("y"))!, g = layout.frame(of: .letter("g"), on: .right)!
        #expect(g.minX < y.minX && g.maxX > y.minX)
        let columns = layout.openColumns(atLeast: Layout.splitMiddle)
        #expect(columns.count == 1)
        #expect(columns[0].lowerBound > width * 0.3 && columns[0].upperBound < width * 0.7)
    }

    @Test(arguments: [744.0, 951.0, 1000.0] as [CGFloat])
    func extraLettersAddOneMorePastTheMiddle(width: CGFloat) {
        let layout = Layout.qwerty(width: width, split: true, extraLetters: true)
        #expect(layout.extraLetters)
        func half(_ row: Int, _ side: Side) -> String {
            String(layout.placements.filter { $0.row == row && layout.side(at: CGPoint(x: $0.frame.midX, y: 0)) == side }
                .sorted { $0.frame.minX < $1.frame.minX }.compactMap(\.key.character))
        }
        #expect(half(0, .left) == "qwerty" && half(0, .right) == "tyuiop")
        #expect(half(1, .left) == "asdfgh" && half(1, .right) == "fghjkl")
        #expect(half(2, .left) == "zxcvb" && half(2, .right) == "cvbnm")
        for placement in layout.placements {
            #expect(placement.frame.minX >= 0 && placement.frame.maxX <= width)
        }
        #expect(layout.openColumns(atLeast: Layout.splitMiddle).count == 1)
        // Only with the split.
        #expect(!Layout.qwerty(width: width, extraLetters: true).extraLetters)
    }

    @Test(arguments: [744.0, 951.0, 1000.0] as [CGFloat])
    func splitSymbolsFollowTheLettersRules(width: CGFloat) {
        let cases: [(Layout.Page, Bool, [(String, String)])] = [
            (.numbers, false, [("12345", "67890"), ("-/:;(", ")$&@\""), (".,?", "?!'")]),
            (.numbers, true, [("123456", "567890"), ("-/:;()", "()$&@\""), (".,?!", ",?!'")]),
            (.symbols, false, [("[]{}#", "%^*+="), ("_\\|~<", ">€£¥•"), (".,?", "?!'")]),
            (.symbols, true, [("[]{}#%", "#%^*+="), ("_\\|~<>", "<>€£¥•"), (".,?!", ",?!'")]),
        ]
        for (page, extraLetters, rows) in cases {
            let layout = Layout.qwerty(width: width, page: page, split: true, extraLetters: extraLetters)
            func half(_ row: Int, _ side: Side) -> String {
                String(layout.placements.filter { $0.row == row && layout.side(at: CGPoint(x: $0.frame.midX, y: 0)) == side }
                    .sorted { $0.frame.minX < $1.frame.minX }.compactMap(\.key.symbolCharacter))
            }
            for (row, expected) in rows.enumerated() {
                #expect(half(row, .left) == expected.0 && half(row, .right) == expected.1, "\(page) \(extraLetters) row \(row)")
            }
            // "?" sits over V on both halves, and the marks are wider than a key.
            let letters = Layout.qwerty(width: width, split: true, extraLetters: extraLetters)
            for side in [Side.left, .right] {
                let mark = layout.frame(of: .symbol("?"), on: side)!
                let v = letters.frame(of: .letter("v"), on: side)!
                #expect(mark.minX <= v.midX && v.midX <= mark.maxX, "\(page) \(extraLetters) \(side)")
                #expect(mark.width > v.width)
            }
            // The page key and backspace are as wide as ABC.
            let abc = layout.frame(of: .letters)!.width
            #expect(layout.frame(of: .backspace)!.width == abc)
            #expect(layout.frame(of: page == .numbers ? .symbols : .numbers)!.width == abc)
            let q = layout.frame(of: .symbol("?"), on: .right)!
            #expect(layout.key(at: CGPoint(x: q.midX, y: q.midY)) == .symbol("?"))
            for placement in layout.placements {
                #expect(placement.frame.minX >= 0 && placement.frame.maxX <= width)
            }
            #expect(layout.frame(of: .backspace)!.maxX == width)
            #expect(layout.openColumns(atLeast: Layout.splitMiddle).count == 1)
        }
    }

    @Test func aWideKeyboardLeavesItsSidesOpen() {
        let full = Layout.qwerty(width: 1000)
        let sides = full.openColumns(atLeast: 96)
        #expect(sides.count == 2)
        #expect(sides[0].lowerBound == 0 && sides[1].upperBound == 1000)
        #expect(Layout.qwerty(width: 390).openColumns(atLeast: 96).isEmpty)
    }

    @Test func splitBottomRowGivesSpaceMoreRoom() {
        for globe in [false, true] {
            let full = Layout.qwerty(width: 1000, globe: globe)
            let split = Layout.qwerty(width: 1000, split: true, globe: globe)
            let fullFn = full.frame(of: .numbers)!.width
            let fn = split.frame(of: .numbers)!.width
            // A fifth narrower than on a whole keyboard, every key beside space alike.
            #expect(abs(fn - 0.8 * fullFn) <= 1)
            #expect(split.frame(of: .emoji)!.width == fn)
            if globe { #expect(split.frame(of: .globe)!.width == fn) }
            // Return is exactly two of them, gap included.
            #expect(split.frame(of: .returnKey)!.width == 2 * fn + split.gap)
            #expect(split.frame(of: .returnKey)!.maxX == 1000)
            // The whole keyboard keeps Apple's widths.
            #expect(full.frame(of: .returnKey)!.width == (2.66 * full.frame(of: .letter("q"))!.width).rounded())
        }
    }

    @Test func splitIsIgnoredOnAPhone() {
        let layout = Layout.qwerty(width: 390, split: true)
        #expect(!layout.split)
        #expect(layout == Layout.qwerty(width: 390))
    }

    @Test func theKeysFillTheHeightTheyAreGiven() {
        let natural = Layout.qwerty(width: 1000)
        let shorter = Layout.qwerty(width: 1000, height: 180)
        #expect(shorter.height == 180)
        #expect(shorter.keyHeight < natural.keyHeight)
        #expect(shorter.frame(of: .letter("q"))!.minY == 0)
        #expect(abs(shorter.frame(of: .space)!.maxY - 176) < 0.001)
        #expect(shorter.frame(of: .letter("q"))!.width == natural.frame(of: .letter("q"))!.width)
        let taller = Layout.qwerty(width: 390, height: 240)
        #expect(taller.height == 240)
        #expect(taller.keyHeight > Layout.qwerty(width: 390).keyHeight)
        #expect(taller.frame(of: .letter("q"))!.minY == 0)
        #expect(abs(taller.frame(of: .space)!.maxY - 233) < 0.001)
        // Far more room than keys want: they stop growing and sit at the bottom.
        let huge = Layout.qwerty(width: 390, height: 600)
        #expect(huge.keyHeight == 64)
        #expect(abs(huge.frame(of: .space)!.maxY - 593) < 0.001)
        // Very little room still keeps four rows.
        let tiny = Layout.qwerty(width: 390, height: 140)
        #expect(tiny.keyHeight >= 28)
        #expect(tiny.placements.filter { $0.row == 3 }.count == 4)
        // The natural height changes nothing.
        #expect(Layout.qwerty(width: 1000, height: natural.height) == natural)
    }
}
