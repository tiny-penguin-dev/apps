#if canImport(UIKit)
import SwiftUI

/// The generic graphics (DESIGN.md "Graphics"): a keyboard with a teal and a coral
/// thumb trail. Drawn from the same key rectangles the keyboard uses, in a 200×200
/// box, so it scales and recolours with the theme. No mascot.
///
///     ThumbsArt().frame(width: 220, height: 220)
public struct ThumbsArt: View {
    /// Draw the trails when the view appears (off under Reduce Motion: shown finished).
    var animated: Bool
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(animated: Bool = true) { self.animated = animated }

    public var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height) / 200
            let progress: CGFloat = drawn || !animated || reduceMotion ? 1 : 0
            ZStack {
                KeyboardShape().fill(Theme.kb)
                KeysShape().fill(Theme.key)
                TrailShape(points: Self.leftTrail)
                    .trim(from: 0, to: progress)
                    .stroke(Theme.left, style: StrokeStyle(lineWidth: 10 * s, lineCap: .round, lineJoin: .round))
                Circle().fill(Theme.left)
                    .frame(width: 16 * s, height: 16 * s)
                    .position(x: Self.leftTrail.last!.x * s, y: Self.leftTrail.last!.y * s)
                    .scaleEffect(progress)
                TrailShape(points: Self.rightTrail)
                    .trim(from: 0, to: progress)
                    .stroke(Theme.right, style: StrokeStyle(lineWidth: 10 * s, lineCap: .round, lineJoin: .round))
                Circle().fill(Theme.right)
                    .frame(width: 16 * s, height: 16 * s)
                    .position(x: Self.rightTrail.last!.x * s, y: Self.rightTrail.last!.y * s)
                    .scaleEffect(progress)
            }
            .frame(width: 200 * s, height: 200 * s)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("A keyboard with two thumb trails")
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(.spring(duration: 1.4, bounce: 0.2).delay(0.2)) { drawn = true }
        }
    }

    static let leftTrail: [CGPoint] = [CGPoint(x: 44, y: 83), CGPoint(x: 56, y: 118), CGPoint(x: 74, y: 105)]
    static let rightTrail: [CGPoint] = [CGPoint(x: 160, y: 83), CGPoint(x: 132, y: 100), CGPoint(x: 136, y: 128), CGPoint(x: 118, y: 150)]

    /// The rounded key panel, in 200×200 units scaled to the rect.
    struct KeyboardShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 200
            return Path(roundedRect: CGRect(x: 18 * s, y: 66 * s, width: 164 * s, height: 100 * s), cornerRadius: 16 * s)
        }
    }

    /// Three rows of keys and a space bar.
    struct KeysShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 200
            var path = Path()
            let rows: [(y: CGFloat, count: Int)] = [(78, 8), (100, 7), (122, 6)]
            for row in rows {
                let w: CGFloat = 16, g: CGFloat = 5
                let start = 100 - (CGFloat(row.count) * w + CGFloat(row.count - 1) * g) / 2
                for i in 0..<row.count {
                    let x = start + CGFloat(i) * (w + g)
                    path.addRoundedRect(in: CGRect(x: x * s, y: row.y * s, width: w * s, height: w * s), cornerSize: CGSize(width: 4 * s, height: 4 * s))
                }
            }
            path.addRoundedRect(in: CGRect(x: 52 * s, y: 144 * s, width: 96 * s, height: 16 * s), cornerSize: CGSize(width: 5 * s, height: 5 * s))
            return path
        }
    }

    /// A smooth trail through a few points.
    struct TrailShape: Shape {
        var points: [CGPoint]

        func path(in rect: CGRect) -> Path {
            let s = rect.width / 200
            var path = Path()
            guard let first = points.first else { return path }
            path.move(to: CGPoint(x: first.x * s, y: first.y * s))
            for i in 1..<points.count {
                let p = CGPoint(x: points[i].x * s, y: points[i].y * s)
                let prev = CGPoint(x: points[i - 1].x * s, y: points[i - 1].y * s)
                let mid = CGPoint(x: (prev.x + p.x) / 2, y: (prev.y + p.y) / 2)
                path.addQuadCurve(to: p, control: CGPoint(x: mid.x + (p.y - prev.y) * 0.3, y: mid.y - (p.x - prev.x) * 0.3))
            }
            return path
        }
    }
}

#Preview {
    ThumbsArt().frame(width: 220, height: 220).padding().background(Theme.bg)
}
#endif
