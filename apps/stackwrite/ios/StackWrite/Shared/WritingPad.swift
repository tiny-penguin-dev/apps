import StackWriteCore
import SwiftUI

/// A square pad that records finger strokes. Each stroke is reported when the
/// finger lifts, with `t` in seconds since the reference date, so callers can
/// measure the lifts between strokes. Ink fades shortly after each lift, so
/// a letter's earlier strokes stay visible while the next one is drawn.
struct WritingPad: View {
    /// Called when the finger lifts, with the stroke in box units and the pad size.
    var onStroke: ([StrokePoint], CGSize) -> Void

    private struct Ink {
        var points: [CGPoint] = []
        var times: [TimeInterval] = []
        var liftedAt: TimeInterval?
    }

    @State private var ink: [Ink] = []
    @State private var drawing = false

    private static let trail: TimeInterval = 1.2
    private static let fadeOut: TimeInterval = 0.6

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: ink.isEmpty)) { timeline in
                Canvas { context, size in
                    drawGuides(in: &context, size: size)
                    drawInk(in: &context, now: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let t = value.time.timeIntervalSinceReferenceDate
                        if !drawing {
                            drawing = true
                            ink.removeAll { $0.liftedAt.map { t - $0 > Self.fadeOut } ?? false }
                            ink.append(Ink())
                        }
                        ink[ink.count - 1].points.append(value.location)
                        ink[ink.count - 1].times.append(t)
                    }
                    .onEnded { value in
                        guard drawing, let last = ink.last else { return }
                        drawing = false
                        let stroke = zip(last.points, last.times).map {
                            StrokePoint(touch: $0.0, padSize: geo.size, t: $0.1)
                        }
                        let lifted = Date().timeIntervalSinceReferenceDate
                        ink[ink.count - 1].liftedAt = lifted
                        onStroke(stroke, geo.size)
                        Task {
                            try? await Task.sleep(for: .seconds(Self.fadeOut))
                            ink.removeAll { $0.liftedAt.map { $0 <= lifted } ?? false }
                        }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .background(.background.secondary, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator))
        .accessibilityLabel("Writing pad")
    }

    /// Faint lines where the model expects the letters: baseline and x-height.
    private func drawGuides(in context: inout GraphicsContext, size: CGSize) {
        for y in [0.3, 0.7] {
            var line = Path()
            let py = (1 - y) * size.height
            line.move(to: CGPoint(x: size.width * 0.08, y: py))
            line.addLine(to: CGPoint(x: size.width * 0.92, y: py))
            context.stroke(line, with: .color(.secondary.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
        }
    }

    private func drawInk(in context: inout GraphicsContext, now: TimeInterval) {
        let style = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        for stroke in ink {
            var fade = 1.0
            if let liftedAt = stroke.liftedAt {
                fade = max(0, 1 - (now - liftedAt) / Self.fadeOut)
            }
            guard fade > 0, let first = stroke.points.first else { continue }
            if stroke.points.count == 1 {
                // A tap: a dot.
                let dot = Path(ellipseIn: CGRect(x: first.x - 3, y: first.y - 3, width: 6, height: 6))
                context.fill(dot, with: .color(.accentColor.opacity(fade)))
                continue
            }
            for i in 1..<stroke.points.count {
                let age = now - stroke.times[i]
                let opacity = max(0.2, 1 - age / Self.trail) * fade
                var segment = Path()
                segment.move(to: stroke.points[i - 1])
                segment.addLine(to: stroke.points[i])
                context.stroke(segment, with: .color(.accentColor.opacity(opacity)), style: style)
            }
        }
    }
}
