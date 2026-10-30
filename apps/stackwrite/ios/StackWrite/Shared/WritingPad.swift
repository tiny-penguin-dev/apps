import StackWriteKit
import SwiftUI

/// A square pad that records one finger stroke at a time. The live path is
/// drawn with a fading trail, and fades out after the finger lifts.
struct WritingPad: View {
    /// Called when the finger lifts, with the stroke in box units and the pad size.
    var onStroke: ([StrokePoint], CGSize) -> Void

    @State private var points: [CGPoint] = []
    @State private var times: [TimeInterval] = []
    @State private var start: Date?
    @State private var liftedAt: Date?

    private static let trail: TimeInterval = 1.2
    private static let fadeOut: TimeInterval = 0.45

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: points.isEmpty)) { timeline in
                Canvas { context, size in
                    drawGuides(in: &context, size: size)
                    drawInk(in: &context, now: timeline.date)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if start == nil {
                            start = value.time
                            liftedAt = nil
                            points = []
                            times = []
                        }
                        points.append(value.location)
                        times.append(value.time.timeIntervalSince(start ?? value.time))
                    }
                    .onEnded { value in
                        guard start != nil else { return }
                        let stroke = zip(points, times).map {
                            StrokePoint(touch: $0.0, padSize: geo.size, t: $0.1)
                        }
                        start = nil
                        let lifted = Date()
                        liftedAt = lifted
                        onStroke(stroke, geo.size)
                        Task {
                            try? await Task.sleep(for: .seconds(Self.fadeOut))
                            if liftedAt == lifted {
                                points = []
                                times = []
                                liftedAt = nil
                            }
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

    private func drawInk(in context: inout GraphicsContext, now: Date) {
        guard points.count > 1, let first = times.first else { return }
        let strokeStart = start ?? liftedAt.map { $0.addingTimeInterval(-(times.last ?? 0) + first) } ?? now
        var fade = 1.0
        if let liftedAt {
            fade = max(0, 1 - now.timeIntervalSince(liftedAt) / Self.fadeOut)
        }
        let style = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        for i in 1..<points.count {
            let age = now.timeIntervalSince(strokeStart) - times[i]
            let opacity = max(0.2, 1 - age / Self.trail) * fade
            var segment = Path()
            segment.move(to: points[i - 1])
            segment.addLine(to: points[i])
            context.stroke(segment, with: .color(.accentColor.opacity(opacity)), style: style)
        }
    }
}
