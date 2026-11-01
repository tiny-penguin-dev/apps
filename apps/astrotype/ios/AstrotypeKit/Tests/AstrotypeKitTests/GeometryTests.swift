import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct GeometryTests {
    @Test func resampleSpreadsPointsEvenly() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 20)]
        let out = Geometry.resample(line, count: 7)
        #expect(out.count == 7)
        #expect(out.first == CGPoint(x: 0, y: 0))
        #expect(out.last == CGPoint(x: 10, y: 20))
        #expect(out[2] == CGPoint(x: 10, y: 0))
        #expect(Geometry.resample([CGPoint(x: 3, y: 4)], count: 3) == Array(repeating: CGPoint(x: 3, y: 4), count: 3))
        #expect(Geometry.resample([], count: 3).isEmpty)
    }

    @Test func dtwIsZeroForTheSamePathAndGrowsWithDistance() {
        let a = Geometry.resample([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], count: 16)
        let b = Geometry.resample([CGPoint(x: 0, y: 10), CGPoint(x: 100, y: 10)], count: 16)
        let c = Geometry.resample([CGPoint(x: 0, y: 40), CGPoint(x: 100, y: 40)], count: 16)
        #expect(Geometry.dtw(a, a) == 0)
        #expect(abs(Geometry.dtw(a, b) - 10) < 0.01)
        #expect(Geometry.dtw(a, c) > Geometry.dtw(a, b))
    }

    @Test func walkAndLength() {
        let points = Geometry.walk([CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0)], step: 10)
        #expect(points.count == 4)
        #expect(Geometry.length(points) == 30)
        #expect(Geometry.length([CGPoint(x: 1, y: 1)]) == 0)
    }
}
