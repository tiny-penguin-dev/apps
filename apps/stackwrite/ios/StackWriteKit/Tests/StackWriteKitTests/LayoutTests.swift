import Foundation
import Testing
@testable import StackWriteCore

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
}
