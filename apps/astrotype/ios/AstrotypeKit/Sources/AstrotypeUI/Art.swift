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

/// A sun-yellow key tile with a star, a trail curling at two corners (DESIGN.md
/// "Graphics": Pro). In a 200×200 box like the others.
///
///     StarTileArt().frame(width: 140, height: 140)
public struct StarTileArt: View {
    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height) / 200
            ZStack {
                RoundedRectangle(cornerRadius: 26 * s, style: .continuous)
                    .fill(Theme.sun)
                    .frame(width: 120 * s, height: 120 * s)
                    .shadow(color: Theme.sunInk.opacity(0.25), radius: 0, y: 6 * s)
                StarShape()
                    .fill(Theme.sunInk)
                    .frame(width: 78 * s, height: 78 * s)
                ThumbsArt.TrailShape(points: [CGPoint(x: 22, y: 60), CGPoint(x: 36, y: 34), CGPoint(x: 62, y: 26)])
                    .stroke(Theme.left, style: StrokeStyle(lineWidth: 8 * s, lineCap: .round, lineJoin: .round))
                Circle().fill(Theme.left).frame(width: 13 * s, height: 13 * s).position(x: 62 * s, y: 26 * s)
                ThumbsArt.TrailShape(points: [CGPoint(x: 178, y: 140), CGPoint(x: 164, y: 166), CGPoint(x: 138, y: 174)])
                    .stroke(Theme.right, style: StrokeStyle(lineWidth: 8 * s, lineCap: .round, lineJoin: .round))
                Circle().fill(Theme.right).frame(width: 13 * s, height: 13 * s).position(x: 138 * s, y: 174 * s)
            }
            .frame(width: 200 * s, height: 200 * s)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("A gold star tile")
    }

    /// A five-point star filling the rect.
    struct StarShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let outer = rect.width / 2
            let inner = outer * 0.42
            for i in 0..<10 {
                let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let r = i.isMultiple(of: 2) ? outer : inner
                let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
    }
}

/// The keyboard faded to half, two z's floating up (DESIGN.md "Graphics": Trial over,
/// an empty history). The z's drift under motion; under Reduce Motion they sit still.
///
///     RestingKeyboardArt().frame(width: 180, height: 180)
public struct RestingKeyboardArt: View {
    @State private var drifting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height) / 200
            let lift: CGFloat = drifting && !reduceMotion ? -10 * s : 0
            ZStack {
                ThumbsArt.KeyboardShape().fill(Theme.kb)
                ThumbsArt.KeysShape().fill(Theme.key)
                Text("z")
                    .font(.system(size: 26 * s, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .position(x: 128 * s, y: 52 * s + lift)
                Text("z")
                    .font(.system(size: 18 * s, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .position(x: 148 * s, y: 30 * s + lift * 1.4)
            }
            .frame(width: 200 * s, height: 200 * s)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .opacity(0.5)
        .accessibilityLabel("A keyboard resting")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { drifting = true }
        }
    }
}

/// A cloud above a phone and a laptop, a teal and a coral line joining them
/// (the Keep your words everywhere screen). Floats gently unless Reduce Motion is on.
public struct CloudArt: View {
    @State private var floating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height) / 200
            ZStack {
                CloudShape().fill(Theme.card)
                CloudShape().stroke(Theme.line, lineWidth: 4 * s)
                Path { path in
                    path.move(to: CGPoint(x: 80 * s, y: 118 * s))
                    path.addLine(to: CGPoint(x: 70 * s, y: 150 * s))
                }
                .stroke(Theme.left, style: StrokeStyle(lineWidth: 8 * s, lineCap: .round))
                Path { path in
                    path.move(to: CGPoint(x: 124 * s, y: 118 * s))
                    path.addLine(to: CGPoint(x: 136 * s, y: 150 * s))
                }
                .stroke(Theme.right, style: StrokeStyle(lineWidth: 8 * s, lineCap: .round))
                RoundedRectangle(cornerRadius: 6 * s).fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 6 * s).stroke(Theme.line, lineWidth: 4 * s))
                    .frame(width: 26 * s, height: 44 * s).position(x: 62 * s, y: 170 * s)
                RoundedRectangle(cornerRadius: 6 * s).fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 6 * s).stroke(Theme.line, lineWidth: 4 * s))
                    .frame(width: 60 * s, height: 36 * s).position(x: 142 * s, y: 174 * s)
            }
            .frame(width: 200 * s, height: 200 * s)
            .offset(y: floating ? -4 * s : 4 * s)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("A cloud linked to a phone and a laptop")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { floating = true }
        }
    }

    struct CloudShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 200
            var path = Path()
            path.addEllipse(in: CGRect(x: 40 * s, y: 60 * s, width: 70 * s, height: 60 * s))
            path.addEllipse(in: CGRect(x: 80 * s, y: 40 * s, width: 80 * s, height: 70 * s))
            path.addEllipse(in: CGRect(x: 110 * s, y: 70 * s, width: 56 * s, height: 50 * s))
            path.addRoundedRect(in: CGRect(x: 48 * s, y: 90 * s, width: 112 * s, height: 30 * s), cornerSize: CGSize(width: 15 * s, height: 15 * s))
            return path
        }
    }
}

#Preview {
    VStack {
        ThumbsArt().frame(width: 220, height: 220)
        CloudArt().frame(width: 200, height: 200)
    }
    .padding().background(Theme.bg)
}
#endif
