import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// The go-back screen (features/dictation, DESIGN "Go back"): the keyboard's mic opened
/// the app to turn the mic on; this says so and shows how to get back to where the
/// person was typing. A teal trail slides along the real bottom edge, where the swipe
/// goes, with a thumb dot riding it; on phones that show "◀ App" at the top left, a
/// bubble points at it too. The first time, it asks for the mic first.
struct GoBackView: View {
    var model: DictationModel
    /// Opens the app's page in iOS Settings (the mic was turned off there).
    var openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: Theme.Space.l) {
                Spacer(minLength: 0)
                icon
                Text(title)
                    .font(.sw(.title))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(line)
                    .font(.sw(.body))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                actions
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.screen == .micOn {
                SwipeHint(reduceMotion: reduceMotion)
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityHidden(true)
                if !DeviceInfo.hidesBackButton {
                    BackBubble()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, Theme.Space.l)
                        .padding(.top, Theme.Space.xs)
                        .accessibilityHidden(true)
                }
            }
        }
        .foregroundStyle(Theme.ink)
    }

    private var title: String {
        switch model.screen {
        case .askMic: "Dictate with Astrotype"
        case .micDenied: "The mic is off"
        case .preparing: "Getting ready…"
        case .failed(.noSpeech): "Dictation isn't available"
        case .failed: "Dictation didn't start"
        case .micOn, nil: "Mic's on"
        }
    }

    private var line: String {
        switch model.screen {
        case .askMic: "Astrotype needs the mic to hear you. It listens only while you dictate, on your phone."
        case .micDenied: "Turn on the microphone for Astrotype in Settings, then tap the mic on the keyboard again."
        case .preparing: "Getting speech to text ready on your phone. The first time can take a moment."
        case .failed(.noSpeech): "Speech to text isn't available on this iPhone or in this language yet."
        case .failed: "Something went wrong with the mic. Go back and tap the mic to try again."
        case .micOn, nil: "Swipe right along the bottom edge to go back and talk."
        }
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            Circle().fill(model.screen == .micDenied || isFailed ? Theme.muted.opacity(0.25) : Theme.mint)
            if model.screen == .preparing {
                ProgressView().tint(.white).controlSize(.large)
            } else {
                Image(systemName: model.screen == .micDenied ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(model.screen == .micDenied || isFailed ? Theme.muted : .white)
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
    }

    private var isFailed: Bool {
        if case .failed = model.screen { true } else { false }
    }

    @ViewBuilder
    private var actions: some View {
        switch model.screen {
        case .askMic:
            Button("Allow the mic") { Task { await model.allowMic() } }
                .buttonStyle(.primary)
            notNow
        case .micDenied:
            Button("Open Settings", action: openSettings)
                .buttonStyle(.primary)
            notNow
        case .preparing, .micOn, nil:
            notNow
        case .failed:
            Button("Close") { model.notNow() }
                .buttonStyle(.ghost)
        }
    }

    private var notNow: some View {
        Button("Not now") { model.notNow() }
            .font(.sw(.heading))
            .foregroundStyle(Theme.accent)
            .padding(.top, Theme.Space.s)
    }
}

/// The swipe that goes back: a teal trail (the keyboard's own trail) sliding right
/// along the bottom edge, over and over, with a thumb dot riding its head. Every 1.6 s;
/// a still arrow under Reduce Motion.
struct SwipeHint: View {
    var reduceMotion: Bool
    static let loop: Double = 1.6

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Spacer()
            Text("Swipe right here")
                .font(.sw(.heading))
                .foregroundStyle(Theme.accent)
            if reduceMotion {
                Image(systemName: "arrow.right")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.bottom, Theme.Space.l)
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop) / Self.loop
                    Canvas { canvas, size in
                        draw(in: &canvas, size: size, progress: t)
                    }
                }
                .frame(height: 44)
            }
        }
    }

    /// The trail runs across the middle third of the edge, where the home indicator is.
    private func draw(in canvas: inout GraphicsContext, size: CGSize, progress t: Double) {
        let ease = 1 - pow(1 - min(1, t / 0.8), 3)
        let fade = t > 0.8 ? 1 - (t - 0.8) / 0.2 : 1
        let start = size.width * 0.3
        let end = size.width * 0.62
        let head = start + (end - start) * ease
        let y = size.height - 14
        let tail = max(start, head - size.width * 0.22)
        var path = Path()
        path.addRoundedRect(in: CGRect(x: tail, y: y - 5, width: head - tail, height: 10), cornerSize: CGSize(width: 5, height: 5))
        let gradient = Gradient(colors: [Theme.accent.opacity(0), Theme.accent.opacity(0.85 * fade)])
        canvas.fill(path, with: .linearGradient(gradient, startPoint: CGPoint(x: tail, y: y), endPoint: CGPoint(x: head, y: y)))
        let dot = CGRect(x: head - 16, y: y - 16, width: 32, height: 32)
        canvas.fill(Path(ellipseIn: dot), with: .color(Theme.accent.opacity(0.3 * fade)))
        canvas.stroke(Path(ellipseIn: dot), with: .color(Theme.accent.opacity(fade)), lineWidth: 2.5)
    }
}

/// "or tap here", pointing up at iOS's "◀ App" at the top left.
struct BackBubble: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Triangle()
                .fill(Theme.ink)
                .frame(width: 14, height: 8)
                .padding(.leading, Theme.Space.xl)
            Text("or tap here")
                .font(.sw(.small).weight(.heavy))
                .foregroundStyle(Theme.bg)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
                .background(Theme.ink, in: Capsule())
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}
