import SwiftUI

/// Every part of the penguin as a path on a 200 × 200 canvas. The numbers match the
/// approved HTML mockup (`apps/squawk/design/mockups/penguins-front.html`, penguin 2),
/// so the app and the mockup draw the same penguin.
public enum PenguinGeometry {
    /// The size of the canvas every path is drawn on.
    public static let canvas: CGFloat = 200

    // MARK: Body

    /// Navy arch with rounded bottom corners.
    public static let body: Path = {
        var p = Path()
        p.move(to: pt(50, 96))
        p.addArc(tangent1End: pt(50, 46), tangent2End: pt(100, 46), radius: 50)
        p.addArc(tangent1End: pt(150, 46), tangent2End: pt(150, 96), radius: 50)
        p.addLine(to: pt(150, 170))
        p.addQuadCurve(to: pt(132, 188), control: pt(150, 188))
        p.addLine(to: pt(68, 188))
        p.addQuadCurve(to: pt(50, 170), control: pt(50, 188))
        p.closeSubpath()
        return p
    }()

    /// White belly window with straight sides and a square bottom.
    public static let belly: Path = archWindow(left: 70, right: 130, shoulder: 140, bottom: 188)

    /// The leg notch, running to the bottom edge like the Tiny Penguin logo.
    public static let legNotch: Path = archWindow(left: 90, right: 110, shoulder: 176, bottom: 188)

    /// Left flipper, attached to the side. `up` lifts it for big moments.
    public static func leftFlipper(up: Bool) -> Path {
        var p = Path()
        p.move(to: pt(57, 103))
        p.addCurve(to: pt(40, 161), control1: pt(42, 115), control2: pt(36, 140))
        p.addCurve(to: pt(60, 127), control1: pt(49, 156), control2: pt(56, 142))
        p.closeSubpath()
        return p.applying(rotation(degrees: up ? flipperLift : 0, around: pt(56, 106)))
    }

    /// Right flipper, the mirror of the left one. `wave` adds extra lift for waving.
    public static func rightFlipper(up: Bool, wave: Double = 0) -> Path {
        var p = Path()
        p.move(to: pt(143, 103))
        p.addCurve(to: pt(160, 161), control1: pt(158, 115), control2: pt(164, 140))
        p.addCurve(to: pt(140, 127), control1: pt(151, 156), control2: pt(144, 142))
        p.closeSubpath()
        let angle = -(up ? flipperLift : 0) - wave
        return p.applying(rotation(degrees: angle, around: pt(144, 106)))
    }

    /// How far flippers lift, in degrees.
    public static let flipperLift: Double = 30

    public static let feet: Path = {
        var p = Path()
        p.addEllipse(in: CGRect(x: 67, y: 184, width: 26, height: 10))
        p.addEllipse(in: CGRect(x: 107, y: 184, width: 26, height: 10))
        return p
    }()

    public static let cheeks: Path = {
        var p = Path()
        p.addEllipse(in: circle(66, 110, 6))
        p.addEllipse(in: circle(134, 110, 6))
        return p
    }()

    // MARK: Eyes (white eyes on the navy face)

    static let leftEyeX: CGFloat = 82, rightEyeX: CGFloat = 118, eyeY: CGFloat = 90

    /// Open eyes: white ball, navy pupil, little white glint.
    public static func eyeWhites(radius: CGFloat = 10) -> Path {
        var p = Path()
        p.addEllipse(in: circle(leftEyeX, eyeY, radius))
        p.addEllipse(in: circle(rightEyeX, eyeY, radius))
        return p
    }

    public static func pupils(for mood: PenguinMood) -> Path {
        var p = Path()
        switch mood {
        case .grumpy:
            p.addEllipse(in: circle(leftEyeX + 1, eyeY + 3, 4.5))
            p.addEllipse(in: circle(rightEyeX - 1, eyeY + 3, 4.5))
        case .squawk:
            p.addEllipse(in: circle(leftEyeX, eyeY, 3.5))
            p.addEllipse(in: circle(rightEyeX, eyeY, 3.5))
        default:
            p.addEllipse(in: circle(leftEyeX + 2, eyeY + 1, 5))
            p.addEllipse(in: circle(rightEyeX + 2, eyeY + 1, 5))
        }
        return p
    }

    public static let glints: Path = {
        var p = Path()
        p.addEllipse(in: circle(leftEyeX + 4, eyeY - 2, 1.8))
        p.addEllipse(in: circle(rightEyeX + 4, eyeY - 2, 1.8))
        return p
    }()

    /// Sleeping eyes: two little smiles (stroked, not filled).
    public static let sleepingEyes: Path = eyeArcs(lift: 0, dip: 7)

    /// Proud eyes: happy upside-down arcs (stroked).
    public static let happyEyes: Path = eyeArcs(lift: 3, dip: -10)

    /// Fainted eyes: two X's (stroked).
    public static let faintEyes: Path = {
        var p = Path()
        for x in [leftEyeX, rightEyeX] {
            p.move(to: pt(x - 6, eyeY - 6)); p.addLine(to: pt(x + 6, eyeY + 6))
            p.move(to: pt(x + 6, eyeY - 6)); p.addLine(to: pt(x - 6, eyeY + 6))
        }
        return p
    }()

    /// Grumpy brows: body-colored wedges that cut into the top of each eye.
    public static let grumpyBrows: Path = {
        var p = Path()
        p.move(to: pt(leftEyeX - 12, eyeY - 14))
        p.addLine(to: pt(leftEyeX + 12, eyeY - 4))
        p.addLine(to: pt(leftEyeX + 12, eyeY - 16))
        p.closeSubpath()
        p.move(to: pt(rightEyeX + 12, eyeY - 14))
        p.addLine(to: pt(rightEyeX - 12, eyeY - 4))
        p.addLine(to: pt(rightEyeX - 12, eyeY - 16))
        p.closeSubpath()
        return p
    }()

    // MARK: Beak

    static let beakTop: CGFloat = 104

    /// Closed beak: narrow, a bit long, with soft corners.
    public static let beak: Path = {
        let y = beakTop
        var p = Path()
        p.move(to: pt(91.5, y))
        p.addQuadCurve(to: pt(108.5, y), control: pt(100, y - 1.5))
        p.addLine(to: pt(101.6, y + 14.5))
        p.addQuadCurve(to: pt(98.4, y + 14.5), control: pt(100, y + 17))
        p.closeSubpath()
        return p
    }()

    /// The open mouth behind the beak when squawking.
    public static let mouth: Path = {
        let y = beakTop
        var p = Path()
        p.move(to: pt(89, y + 2))
        p.addQuadCurve(to: pt(111, y + 2), control: pt(100, y + 4))
        p.addQuadCurve(to: pt(100.8, y + 22), control: pt(108, y + 15))
        p.addQuadCurve(to: pt(99.2, y + 22), control: pt(100, y + 23))
        p.addQuadCurve(to: pt(89, y + 2), control: pt(92, y + 15))
        p.closeSubpath()
        return p
    }()

    public static let tongue: Path = Path(ellipseIn: CGRect(x: 95, y: beakTop + 12.5, width: 10, height: 6))

    /// Lower beak when squawking: a pointy V under the mouth.
    public static let lowerBeak: Path = {
        let y = beakTop
        var p = Path()
        p.move(to: pt(88, y + 3))
        p.addQuadCurve(to: pt(99, y + 27), control: pt(93, y + 17))
        p.addQuadCurve(to: pt(101, y + 27), control: pt(100, y + 28.5))
        p.addQuadCurve(to: pt(112, y + 3), control: pt(107, y + 17))
        p.addQuadCurve(to: pt(100, y + 21.5), control: pt(107, y + 14))
        p.addQuadCurve(to: pt(88, y + 3), control: pt(93, y + 14))
        p.closeSubpath()
        return p
    }()

    /// Upper beak when squawking: wider and pointing down.
    public static let upperBeak: Path = {
        let y = beakTop
        var p = Path()
        p.move(to: pt(88, y))
        p.addQuadCurve(to: pt(112, y), control: pt(100, y - 2))
        p.addLine(to: pt(101.6, y + 10.5))
        p.addQuadCurve(to: pt(98.4, y + 10.5), control: pt(100, y + 12.5))
        p.closeSubpath()
        return p
    }()

    /// Little shout lines above the head when squawking (stroked).
    public static let shoutLines: Path = {
        var p = Path()
        p.move(to: pt(162, 60)); p.addLine(to: pt(174, 50))
        p.move(to: pt(38, 60)); p.addLine(to: pt(26, 50))
        p.move(to: pt(100, 22)); p.addLine(to: pt(100, 8))
        return p
    }()

    // MARK: Outfits

    public static let nightcap: Path = {
        var p = Path()
        p.move(to: pt(64, 70))
        p.addQuadCurve(to: pt(140, 64), control: pt(100, 0))
        p.addQuadCurve(to: pt(64, 70), control: pt(100, 52))
        p.closeSubpath()
        return p
    }()

    public static let nightcapPompom = Path(ellipseIn: circle(146, 62, 9))

    public static let beanie: Path = {
        var p = Path()
        p.move(to: pt(52, 72))
        p.addCurve(to: pt(148, 72), control1: pt(52, 24), control2: pt(148, 24))
        p.closeSubpath()
        return p
    }()

    public static let beanieBand = Path(roundedRect: CGRect(x: 48, y: 66, width: 104, height: 13), cornerRadius: 6.5)
    public static let beaniePompom = Path(ellipseIn: circle(100, 34, 10))

    public static let partyHat: Path = {
        var p = Path()
        p.move(to: pt(82, 54)); p.addLine(to: pt(100, 6)); p.addLine(to: pt(118, 54))
        p.addQuadCurve(to: pt(82, 54), control: pt(100, 60))
        p.closeSubpath()
        return p
    }()

    public static let partyHatStripes: Path = {
        var p = Path()
        p.move(to: pt(89, 36)); p.addLine(to: pt(109, 26))
        p.move(to: pt(85, 50)); p.addLine(to: pt(114, 38))
        return p
    }()

    public static let partyHatPompom = Path(ellipseIn: circle(100, 7, 6))

    public static let scarf = Path(roundedRect: CGRect(x: 49, y: 112, width: 102, height: 14), cornerRadius: 7)

    public static let scarfTail: Path = {
        var p = Path()
        p.move(to: pt(116, 120)); p.addLine(to: pt(132, 120))
        p.addLine(to: pt(137, 152)); p.addLine(to: pt(121, 154))
        p.closeSubpath()
        return p
    }()

    public static let sunglasses: Path = {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 68, y: 80, width: 28, height: 19), cornerSize: CGSize(width: 9, height: 9))
        p.addRoundedRect(in: CGRect(x: 104, y: 80, width: 28, height: 19), cornerSize: CGSize(width: 9, height: 9))
        p.addRect(CGRect(x: 95, y: 85, width: 10, height: 3.5))
        return p
    }()

    public static let sunglassesShine: Path = {
        var p = Path()
        p.move(to: pt(74, 85)); p.addLine(to: pt(80, 85))
        p.move(to: pt(110, 85)); p.addLine(to: pt(116, 85))
        return p
    }()

    // MARK: Sleep z's

    /// Where the two floating z's start, and their sizes.
    public static let zs: [(point: CGPoint, size: CGFloat)] = [(pt(152, 40), 22), (pt(164, 28), 16)]

    // MARK: Helpers

    static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect {
        CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
    }

    /// A window with straight sides, a round top and a flat bottom.
    static func archWindow(left: CGFloat, right: CGFloat, shoulder: CGFloat, bottom: CGFloat) -> Path {
        let r = (right - left) / 2
        var p = Path()
        p.move(to: pt(left, bottom))
        p.addLine(to: pt(left, shoulder))
        p.addArc(tangent1End: pt(left, shoulder - r), tangent2End: pt(left + r, shoulder - r), radius: r)
        p.addArc(tangent1End: pt(right, shoulder - r), tangent2End: pt(right, shoulder), radius: r)
        p.addLine(to: pt(right, bottom))
        p.closeSubpath()
        return p
    }

    static func eyeArcs(lift: CGFloat, dip: CGFloat) -> Path {
        var p = Path()
        for x in [leftEyeX, rightEyeX] {
            p.move(to: pt(x - 9, eyeY + lift))
            p.addQuadCurve(to: pt(x + 9, eyeY + lift), control: pt(x, eyeY + lift + dip))
        }
        return p
    }

    /// Rotation around a point. Positive degrees turn clockwise on screen.
    static func rotation(degrees: Double, around c: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -c.x, y: -c.y)
    }
}
