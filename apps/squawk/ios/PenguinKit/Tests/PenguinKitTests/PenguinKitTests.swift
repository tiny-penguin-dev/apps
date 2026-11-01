import SwiftUI
import Testing
@testable import PenguinKit

@Suite struct PenguinGeometryTests {
    let canvas = CGRect(x: 0, y: 0, width: 200, height: 200)

    @Test func bodyFitsTheCanvas() {
        let box = PenguinGeometry.body.boundingRect
        #expect(abs(box.minX - 50) < 0.5)
        #expect(abs(box.maxX - 150) < 0.5)
        #expect(abs(box.minY - 46) < 0.5)
        #expect(abs(box.maxY - 188) < 0.5)
    }

    @Test func bellyIsCenteredAndReachesTheBottom() {
        let box = PenguinGeometry.belly.boundingRect
        #expect(abs(box.midX - 100) < 0.5)
        #expect(abs(box.maxY - 188) < 0.5)
        #expect(abs(PenguinGeometry.legNotch.boundingRect.midX - 100) < 0.5)
    }

    @Test func flippersMirrorEachOther() {
        for up in [false, true] {
            let left = PenguinGeometry.leftFlipper(up: up).boundingRect
            let right = PenguinGeometry.rightFlipper(up: up).boundingRect
            #expect(abs(left.minX - (200 - right.maxX)) < 0.5)
            #expect(abs(left.minY - right.minY) < 0.5)
        }
    }

    @Test func liftedFlippersSitHigher() {
        let down = PenguinGeometry.leftFlipper(up: false).boundingRect
        let up = PenguinGeometry.leftFlipper(up: true).boundingRect
        #expect(up.maxY < down.maxY)
    }

    @Test func everyMoodDrawsInsideTheCanvas() {
        let parts: [Path] = [
            PenguinGeometry.beak, PenguinGeometry.mouth, PenguinGeometry.lowerBeak, PenguinGeometry.upperBeak,
            PenguinGeometry.sleepingEyes, PenguinGeometry.happyEyes, PenguinGeometry.faintEyes,
            PenguinGeometry.nightcap, PenguinGeometry.beanie, PenguinGeometry.partyHat, PenguinGeometry.scarf,
            PenguinGeometry.sunglasses, PenguinGeometry.feet, PenguinGeometry.shoutLines,
        ] + PenguinMood.allCases.map(PenguinGeometry.pupils(for:))
        for part in parts {
            #expect(!part.isEmpty)
            #expect(canvas.contains(part.boundingRect))
        }
    }

    @Test func beakIsCentered() {
        #expect(abs(PenguinGeometry.beak.boundingRect.midX - 100) < 0.5)
        #expect(abs(PenguinGeometry.lowerBeak.boundingRect.midX - 100) < 0.5)
    }

    @MainActor @Test func shapeScalesToItsFrame() {
        let shape = UnitShape(path: PenguinGeometry.body)
        let box = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).boundingRect
        #expect(abs(box.minX - 25) < 0.5)
        #expect(abs(box.maxX - 75) < 0.5)
    }
}

@Suite struct PenguinMoodTests {
    @Test func cheeksOnlyWhenProud() {
        #expect(PenguinMood.allCases.filter(\.showsCheeks) == [.proud])
    }

    @Test func beakOpensOnlyWhenSquawking() {
        #expect(PenguinMood.allCases.filter(\.beakOpen) == [.squawk])
    }

    @Test func flippersUpForBigMoments() {
        #expect(Set(PenguinMood.allCases.filter(\.flippersUp)) == [.proud, .squawk])
    }

    @Test func faintStaysStill() {
        #expect(PenguinMood.faint.motion == .still)
    }
}
