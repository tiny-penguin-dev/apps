import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct LayoutTests {
    @Test func phoneHasApplesProportions() {
        let layout = Layout.qwerty(width: 390)
        let q = layout.frame(of: .letter("q"))!
        #expect(q.width == 33)
        #expect(q.height == 44)
        #expect(layout.gap == 6)
        #expect(layout.height == 216)
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
        #expect(unit <= 58)
        #expect(layout.frame(of: .space)!.width > 3 * unit)
    }

    @Test func wideKeysAreCapped() {
        let layout = Layout.qwerty(width: 744)
        #expect(layout.frame(of: .letter("q"))!.width == 58)
        #expect(layout.keyHeight == 54)
    }

    @Test func hitTestingIsForgiving() {
        let layout = Layout.qwerty(width: 390)
        let h = layout.frame(of: .letter("h"))!
        #expect(layout.key(at: CGPoint(x: h.midX, y: h.midY)) == .letter("h"))
        // In the gap just right of h, still h.
        #expect(layout.key(at: CGPoint(x: h.maxX + 2, y: h.midY)) == .letter("h"))
        // Off the left edge of a row, the first key.
        #expect(layout.key(at: CGPoint(x: 1, y: h.midY)) == .letter("a"))
        // Between two rows, the nearer one.
        #expect(layout.key(at: CGPoint(x: h.midX, y: h.minY - 3)) == .letter("h"))
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
        #expect(layout.placements.filter { $0.key == .letter("g") }.count == 1)
        #expect(layout.frame(of: .letter("q"))!.minX == 12)
        #expect(layout.frame(of: .letter("p"))!.maxX == 988)
        for placement in layout.placements {
            #expect(placement.frame.minX >= 0 && placement.frame.maxX <= 1000)
        }
        // The middle of the gap still finds the nearest key in the row.
        #expect(layout.key(at: CGPoint(x: 480, y: layout.frame(of: .letter("t"))!.midY)) == .letter("t"))
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

    @Test func splitIsIgnoredOnAPhone() {
        let layout = Layout.qwerty(width: 390, split: true)
        #expect(!layout.split)
        #expect(layout == Layout.qwerty(width: 390))
    }

    @Test func aShorterKeyboardShrinksItsKeys() {
        let natural = Layout.qwerty(width: 1000)
        #expect(natural.height == 259)
        let fitted = Layout.qwerty(width: 1000, maxHeight: 227)
        #expect(fitted.height <= 227)
        #expect(fitted.keyHeight < natural.keyHeight)
        #expect(fitted.keyHeight >= 36)
        #expect(fitted.frame(of: .letter("q"))!.width == natural.frame(of: .letter("q"))!.width)
        #expect(fitted.placements.allSatisfy { $0.frame.maxY <= fitted.height })
        // Room to spare changes nothing.
        #expect(Layout.qwerty(width: 1000, maxHeight: 400) == natural)
        // Very little room still keeps four rows.
        let tiny = Layout.qwerty(width: 390, maxHeight: 140)
        #expect(tiny.keyHeight >= 28)
        #expect(tiny.placements.filter { $0.row == 3 }.count == 4)
    }
}
