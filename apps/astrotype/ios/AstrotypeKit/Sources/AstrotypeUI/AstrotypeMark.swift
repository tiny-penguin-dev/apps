#if canImport(UIKit)
import UIKit

/// The app icon's mark (design/icon: an "A" key with two orbits, each ending in a dot)
/// as one-colour art for small places, such as the keyboard's menu button in the
/// guesses bar. A template image, so it takes the tint it is shown in: the bar's grey,
/// like the pencil (Gabriel, 8 Nov 2026: "just in monochrome gray"). The key is filled
/// with the "A" cut out of it, the back halves of the orbits are faded behind the key,
/// and the front halves cross it with a thin gap cut around them. The orbits are a
/// little tighter than the icon's so the mark is less wide, and as thin as the icon's,
/// so the key leads (Gabriel, 9 Nov 2026: "less wide", the orbits "too thick").
///
///     button.configuration?.image = AstrotypeMark.image(width: 30)
@MainActor
public enum AstrotypeMark {
    /// The mark `width` points wide (and about two thirds as tall), drawn once per size.
    public static func image(width: CGFloat) -> UIImage {
        if let cached = cache[width] { return cached }
        let image = draw(width: width)
        cache[width] = image
        return image
    }

    private static var cache: [CGFloat: UIImage] = [:]

    /// In the icon's own 1024 box: the key and the "A" are the icon's; the orbits are
    /// 360 × 130 (the icon's 432 × 152) at the same ±28°, cropped to their ends.
    private static let box = CGRect(x: 140, y: 268, width: 744, height: 504)
    private static let center = CGPoint(x: 512, y: 520)
    private static let orbit = CGSize(width: 360, height: 130)
    private static let orbitWidth: CGFloat = 36
    private static let dotRadius: CGFloat = 44
    private static let gap: CGFloat = 18
    /// Each orbit's tilt and where its dot sits: just past the front half's end, on the
    /// left for the first and the right for the second, as on the icon.
    private static let orbits: [(tilt: CGFloat, dot: CGPoint)] = [
        (-28, CGPoint(x: -354.6, y: -22.4)),
        (28, CGPoint(x: 354.6, y: 22.4)),
    ]

    private static func draw(width: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let scale = width / box.width
        let size = CGSize(width: width, height: (box.height * scale).rounded(.up))
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: -box.minX, y: -box.minY)
            UIColor.black.setStroke()
            UIColor.black.setFill()

            // The back halves, faded, behind the key.
            for (tilt, _) in orbits {
                let back = half(tilt: tilt, front: false)
                back.lineWidth = orbitWidth
                back.lineCapStyle = .round
                back.stroke(with: .normal, alpha: 0.35)
            }

            // The key, with the "A" cut out (the icon's own strokes).
            UIBezierPath(roundedRect: CGRect(x: 292, y: 292, width: 440, height: 440), cornerRadius: 92).fill()
            let a = UIBezierPath()
            a.move(to: CGPoint(x: 412.16, y: 644))
            a.addLine(to: CGPoint(x: 512, y: 388))
            a.addLine(to: CGPoint(x: 611.84, y: 644))
            a.move(to: CGPoint(x: 452.1, y: 551.84))
            a.addLine(to: CGPoint(x: 571.9, y: 551.84))
            a.lineWidth = 66
            a.lineCapStyle = .round
            a.lineJoinStyle = .round
            a.stroke(with: .clear, alpha: 1)

            // The gaps around the front halves and their dots, then the halves and dots.
            for (tilt, dot) in orbits {
                let front = half(tilt: tilt, front: true)
                front.lineCapStyle = .round
                front.lineWidth = orbitWidth + 2 * gap
                front.stroke(with: .clear, alpha: 1)
                circle(at: dot, radius: dotRadius + gap, tilt: tilt).fill(with: .clear, alpha: 1)
            }
            for (tilt, dot) in orbits {
                let front = half(tilt: tilt, front: true)
                front.lineCapStyle = .round
                front.lineWidth = orbitWidth
                front.stroke()
                circle(at: dot, radius: dotRadius, tilt: tilt).fill()
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// Half an orbit: the front (lower) half crosses the key, the back goes behind it.
    private static func half(tilt: CGFloat, front: Bool) -> UIBezierPath {
        let path = UIBezierPath(arcCenter: .zero, radius: 1, startAngle: 0, endAngle: .pi, clockwise: front)
        path.apply(CGAffineTransform(scaleX: orbit.width, y: orbit.height).concatenating(place(tilt)))
        return path
    }

    /// A dot at `point` in the orbit's own (untilted) frame.
    private static func circle(at point: CGPoint, radius: CGFloat, tilt: CGFloat) -> UIBezierPath {
        let c = point.applying(place(tilt))
        return UIBezierPath(ovalIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))
    }

    /// From an orbit's frame to the icon's box: tilted, then moved to the centre.
    private static func place(_ tilt: CGFloat) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: tilt * .pi / 180).concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }
}
#endif
