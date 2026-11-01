import SwiftUI

/// Shakes side to side each time `count` changes.
struct Shake: GeometryEffect {
    var count: Int
    var animatableData: CGFloat

    init(count: Int) {
        self.count = count
        self.animatableData = CGFloat(count)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Fish confetti in the four ring colors, falling once across the whole view (DESIGN.md
/// "Success"). Draws nothing with Reduce Motion on.
struct FishConfetti: View {
    var count = 36
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fallen = false
    @State private var pieces: [Piece] = []

    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let delay: Double
        let duration: Double
        let spin: Double
        let size: CGFloat
        let color: Color
        let flipped: Bool
    }

    var body: some View {
        GeometryReader { geo in
            if !reduceMotion {
                ForEach(pieces) { piece in
                    Image(systemName: "fish.fill")
                        .font(.system(size: piece.size, weight: .bold))
                        .foregroundStyle(piece.color)
                        .scaleEffect(x: piece.flipped ? -1 : 1)
                        .rotationEffect(.degrees(fallen ? piece.spin : 0))
                        .position(x: piece.x * geo.size.width, y: fallen ? geo.size.height + 40 : -40)
                        .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: fallen)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            let colors = [Theme.accent, Theme.sun, Theme.coral, Theme.mint]
            pieces = (0..<count).map { i in
                Piece(
                    id: i, x: .random(in: 0.05...0.95), delay: .random(in: 0...0.8),
                    duration: .random(in: 1.6...2.8), spin: .random(in: -240...240),
                    size: .random(in: 14...26), color: colors[i % colors.count], flipped: Bool.random()
                )
            }
            // Next frame, so the fish start above the view and fall.
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                fallen = true
            }
        }
    }
}

extension View {
    /// A quick wobble each time `trigger` changes, like a toggle being flipped (DESIGN.md
    /// "Motion"). Does nothing with Reduce Motion on.
    func wobble<T: Equatable>(on trigger: T) -> some View {
        modifier(Wobble(trigger: trigger))
    }
}

private struct Wobble<T: Equatable>: ViewModifier {
    var trigger: T
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, angle in
                view.rotationEffect(.degrees(angle))
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(-7, duration: 0.08)
                    SpringKeyframe(5, duration: 0.1)
                    SpringKeyframe(-2, duration: 0.1)
                    SpringKeyframe(0, duration: 0.15)
                }
            }
        }
    }
}
