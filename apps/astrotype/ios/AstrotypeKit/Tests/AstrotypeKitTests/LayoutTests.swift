import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct LayoutTests {
    @Test func phoneHasApplesProportions() {
        let layout = Layout.qwerty(width: 390)
        let q = layout.frame(of: .letter("q"))!
        #expect(q.width == 37)
        #expect(q.height == 50.75)
        #expect(layout.gap == 2)
        #expect(layout.height == 209)
        // No padding of our own: the keys reach the top and the bottom.
        #expect(q.minY == 0)
        #expect(layout.frame(of: .space)!.maxY == layout.height)
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
        #expect(layout.keyHeight == 51)
        #expect(layout.height == 210)
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

    @Test func splitPullsTheHalvesApart() {
        let layout = Layout.qwerty(width: 1000, split: true)
        #expect(layout.split)
        #expect(layout.isWide)
        #expect(layout.height == Layout.qwerty(width: 1000).height)
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
            #expect(split.placements.count == Layout.qwerty(width: 1000, page: page).placements.count + 1)
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

    @Test func aWideKeyboardLeavesItsSidesOpen() {
        let full = Layout.qwerty(width: 1000)
        let sides = full.openColumns(atLeast: 96)
        #expect(sides.count == 2)
        #expect(sides[0].lowerBound == 0 && sides[1].upperBound == 1000)
        #expect(Layout.qwerty(width: 390).openColumns(atLeast: 96).isEmpty)
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
        #expect(shorter.frame(of: .space)!.maxY == 180)
        #expect(shorter.frame(of: .letter("q"))!.width == natural.frame(of: .letter("q"))!.width)
        let taller = Layout.qwerty(width: 390, height: 240)
        #expect(taller.height == 240)
        #expect(taller.keyHeight > Layout.qwerty(width: 390).keyHeight)
        #expect(taller.frame(of: .letter("q"))!.minY == 0)
        #expect(abs(taller.frame(of: .space)!.maxY - 240) < 0.001)
        // Far more room than keys want: they stop growing and sit at the bottom.
        let huge = Layout.qwerty(width: 390, height: 600)
        #expect(huge.keyHeight == 64)
        #expect(abs(huge.frame(of: .space)!.maxY - 600) < 0.001)
        // Very little room still keeps four rows.
        let tiny = Layout.qwerty(width: 390, height: 140)
        #expect(tiny.keyHeight >= 28)
        #expect(tiny.placements.filter { $0.row == 3 }.count == 4)
        // The natural height changes nothing.
        #expect(Layout.qwerty(width: 1000, height: natural.height) == natural)
    }
}
