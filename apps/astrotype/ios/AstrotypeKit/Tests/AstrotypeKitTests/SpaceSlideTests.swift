import Foundation
import Testing
@testable import AstrotypeCore

/// A quick tap on space that drifts a little is a space, not a cursor move (Gabriel,
/// 6 Nov 2026: spaces missed when typing fast).
@Suite struct SpaceSlideTests {
    let start = CGPoint(x: 200, y: 180)

    func at(_ dx: CGFloat) -> CGPoint { CGPoint(x: start.x + dx, y: start.y) }

    @Test func aQuickTapThatDriftsIsATap() {
        var slide = SpaceSlide(at: start, time: 0)
        // A fast thumb: 30 pt sideways within a tenth of a second.
        #expect(slide.move(to: at(14), time: 0.05) == 0)
        #expect(slide.move(to: at(30), time: 0.09) == 0)
        #expect(!slide.isSliding)
    }

    @Test func aHeldFingerThatBarelyMovesIsATap() {
        var slide = SpaceSlide(at: start, time: 0)
        #expect(slide.move(to: at(15), time: 0.4) == 0)
        #expect(!slide.isSliding)
    }

    @Test func aHoldThenASlideMovesTheCursor() {
        var slide = SpaceSlide(at: start, time: 0)
        #expect(slide.move(to: at(10), time: 0.1) == 0)
        // Held long enough and far enough: the first step comes at once.
        #expect(slide.move(to: at(SpaceSlide.startDistance), time: 0.2) == 1)
        #expect(slide.isSliding)
        #expect(slide.move(to: at(SpaceSlide.startDistance + SpaceSlide.step), time: 0.25) == 1)
        #expect(slide.move(to: at(SpaceSlide.startDistance + 3 * SpaceSlide.step), time: 0.3) == 2)
        // Back the other way, past the start: steps to the left.
        #expect(slide.move(to: at(-SpaceSlide.startDistance), time: 0.4) == -5)
        // Once sliding, near the start is no steps at all, and still a slide.
        #expect(slide.move(to: at(0), time: 0.5) == 1)
        #expect(slide.isSliding)
    }

    @Test func aFastSlideStartsOnceTheHoldIsDone() {
        var slide = SpaceSlide(at: start, time: 0)
        #expect(slide.move(to: at(-40), time: 0.08) == 0)
        #expect(slide.move(to: at(-40), time: 0.16) == -2)
    }
}
