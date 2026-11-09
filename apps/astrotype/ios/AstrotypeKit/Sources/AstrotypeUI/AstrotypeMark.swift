#if canImport(UIKit)
import UIKit

/// The app icon's mark (design/icon: an "A" key with two orbits) as one-colour art for
/// small places, such as the keyboard's menu button in the guesses bar. A template
/// image, so it takes the tint it is shown in: the bar's grey, like the pencil
/// (Gabriel, 8 Nov 2026: "just in monochrome gray"). The key is filled with the "A"
/// cut out of it, the back halves of the orbits are faded behind the key, and the front
/// halves cross it with a thin gap. The icon's two dots are left out and the strokes
/// are thicker, so it still reads at 22 pt tall.
///
///     button.configuration?.image = AstrotypeMark.image(height: 22)
@MainActor
public enum AstrotypeMark {
    /// The mark `height` points tall (and half as wide again), drawn once per size.
    public static func image(height: CGFloat) -> UIImage {
        if let cached = cache[height] { return cached }
        let image = draw(height: height)
        cache[height] = image
        return image
    }

    private static var cache: [CGFloat: UIImage] = [:]

    /// The icon's own geometry (its 1024 box), cropped to the orbits.
    private static let box = CGRect(x: 90, y: 240, width: 844, height: 560)
    private static let center = CGPoint(x: 512, y: 520)
    private static let orbit = CGSize(width: 432, height: 152)
    private static let tilts: [CGFloat] = [-28, 28]
    private static let orbitWidth: CGFloat = 60
    private static let gap: CGFloat = 34

    private static func draw(height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let scale = height / box.height
        let size = CGSize(width: (box.width * scale).rounded(.up), height: height)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: -box.minX, y: -box.minY)
            UIColor.black.setStroke()
            UIColor.black.setFill()

            // The back halves, faded, behind the key.
            for tilt in tilts {
                let back = half(tilt: tilt, front: false)
                back.lineWidth = orbitWidth
                back.lineCapStyle = .round
                back.stroke(with: .normal, alpha: 0.45)
            }

            // The key, with the "A" cut out.
            let key = UIBezierPath(roundedRect: CGRect(x: 292, y: 292, width: 440, height: 440), cornerRadius: 92)
            key.fill()
            let a = UIBezierPath()
            a.move(to: CGPoint(x: 412.16, y: 644))
            a.addLine(to: CGPoint(x: 512, y: 388))
            a.addLine(to: CGPoint(x: 611.84, y: 644))
            a.move(to: CGPoint(x: 452.1, y: 551.84))
            a.addLine(to: CGPoint(x: 571.9, y: 551.84))
            a.lineWidth = 72
            a.lineCapStyle = .round
            a.lineJoinStyle = .round
            a.stroke(with: .clear, alpha: 1)

            // The front halves, each with a thin gap cut around it.
            for tilt in tilts {
                let front = half(tilt: tilt, front: true)
                front.lineCapStyle = .round
                front.lineWidth = orbitWidth + 2 * gap
                front.stroke(with: .clear, alpha: 1)
            }
            for tilt in tilts {
                let front = half(tilt: tilt, front: true)
                front.lineCapStyle = .round
                front.lineWidth = orbitWidth
                front.stroke()
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// Half an orbit: the front (lower) half crosses the key, the back goes behind it.
    private static func half(tilt: CGFloat, front: Bool) -> UIBezierPath {
        let path = UIBezierPath(arcCenter: .zero, radius: 1, startAngle: 0, endAngle: .pi, clockwise: front)
        path.apply(CGAffineTransform(scaleX: orbit.width, y: orbit.height)
            .concatenating(CGAffineTransform(rotationAngle: tilt * .pi / 180))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
        return path
    }
}
#endif
