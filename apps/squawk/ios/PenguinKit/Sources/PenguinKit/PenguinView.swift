import SwiftUI

/// The penguin. Give it a mood, and optionally a style, an outfit or a wave.
///
/// ```swift
/// PenguinView(mood: .asleep, accessory: .nightcap)
///     .frame(width: 150, height: 150)
/// ```
///
/// It fills the space it's given (keeping a square shape) and loops the mood's motion.
/// With Reduce Motion on it keeps the pose and drops the movement.
public struct PenguinView: View {
    public var mood: PenguinMood
    public var style: PenguinStyle
    public var accessory: PenguinAccessory?
    /// Waves the right flipper (used when saying hi).
    public var waving: Bool
    /// Set to false for still images such as icons and screenshots.
    public var animated: Bool

    public init(
        mood: PenguinMood,
        style: PenguinStyle = .squawk,
        accessory: PenguinAccessory? = nil,
        waving: Bool = false,
        animated: Bool = true
    ) {
        self.mood = mood
        self.style = style
        self.accessory = accessory
        self.waving = waving
        self.animated = animated
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            AnimatedPenguin(
                mood: mood, style: style, accessory: accessory,
                waving: waving, moving: animated && !reduceMotion, scale: side / PenguinGeometry.canvas
            )
            .id(mood)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("Squawk the penguin, \(mood.displayName.lowercased())"))
        .accessibilityAddTraits(.isImage)
    }
}

/// Runs the looping motion. Recreated for each mood so the loop starts fresh.
private struct AnimatedPenguin: View {
    let mood: PenguinMood
    let style: PenguinStyle
    let accessory: PenguinAccessory?
    let waving: Bool
    let moving: Bool
    let scale: CGFloat

    @State private var phase = false
    @State private var wavePhase = false

    var body: some View {
        let motion = moving ? mood.motion : .still
        ZStack {
            PenguinFigure(
                mood: mood, style: style, accessory: accessory,
                wave: waving ? (wavePhase ? 45 : 10) : 0, scale: scale
            )
            .scaleEffect(
                x: motion.isBreathe && phase ? 1.03 : 1,
                y: motion.isBreathe && phase ? 0.97 : 1,
                anchor: UnitPoint(x: 0.5, y: 0.94)
            )
            .scaleEffect(motion == .shake && phase ? 1.03 : 1, anchor: UnitPoint(x: 0.5, y: 0.94))
            .rotationEffect(.degrees(motion == .shake && phase ? -4 : 0), anchor: UnitPoint(x: 0.5, y: 0.94))
            .offset(y: motion == .hop && phase ? -10 * scale : 0)
            .rotationEffect(.degrees(mood == .faint ? -80 : 0), anchor: UnitPoint(x: 0.3, y: 0.94))

            if mood == .asleep {
                SleepZs(moving: moving, scale: scale)
            }
        }
        .onAppear {
            guard moving else { return }
            if motion != .still {
                let base: Animation = motion == .hop
                    ? .spring(duration: motion.halfCycle * 2, bounce: 0.5)
                    : .easeInOut(duration: motion.halfCycle)
                withAnimation(base.repeatForever(autoreverses: true)) { phase = true }
            }
            if waving {
                withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) { wavePhase = true }
            }
        }
    }
}

private extension PenguinMotion {
    var isBreathe: Bool {
        switch self {
        case .breathe: true
        default: false
        }
    }
}

/// Two z's that float up and fade, over and over.
private struct SleepZs: View {
    let moving: Bool
    let scale: CGFloat
    @State private var rise = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(PenguinGeometry.zs.enumerated()), id: \.offset) { index, z in
                Text("z")
                    .font(.system(size: z.size * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                    .position(x: z.point.x * scale, y: z.point.y * scale)
                    .offset(x: rise ? 14 * scale : 0, y: rise ? -30 * scale : 0)
                    .opacity(moving ? (rise ? 0 : 1) : 1)
                    .animation(
                        moving ? .easeIn(duration: 2.6).repeatForever(autoreverses: false).delay(Double(index) * 1.3) : nil,
                        value: rise
                    )
            }
        }
        .frame(width: PenguinGeometry.canvas * scale, height: PenguinGeometry.canvas * scale)
        .accessibilityHidden(true)
        .onAppear { if moving { rise = true } }
    }
}

/// The still drawing: every shape stacked in order, back to front.
struct PenguinFigure: View {
    let mood: PenguinMood
    let style: PenguinStyle
    let accessory: PenguinAccessory?
    /// Extra right flipper lift in degrees, for waving.
    let wave: Double
    let scale: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let bodyColor = style.body(in: scheme)
        let G = PenguinGeometry.self
        ZStack {
            UnitShape(path: G.leftFlipper(up: mood.flippersUp)).fill(bodyColor)
            UnitShape(path: G.rightFlipper(up: mood.flippersUp, wave: wave)).fill(bodyColor)
            UnitShape(path: G.body).fill(bodyColor)
            UnitShape(path: G.belly).fill(style.belly)
            UnitShape(path: G.legNotch).fill(bodyColor)
            if accessory == .scarf {
                UnitShape(path: G.scarfTail).fill(style.outfitTrim)
                UnitShape(path: G.scarf).fill(style.outfit)
            }
            eyes(body: bodyColor)
            beak
            if mood.showsCheeks {
                UnitShape(path: G.cheeks).fill(style.cheek.opacity(0.85))
            }
            UnitShape(path: G.feet).fill(style.beak)
            outfit
            if mood == .squawk {
                UnitShape(path: G.shoutLines).stroke(style.beak, style: stroke(5))
            }
        }
        .frame(width: G.canvas * scale, height: G.canvas * scale)
    }

    @ViewBuilder private func eyes(body: Color) -> some View {
        let G = PenguinGeometry.self
        switch mood {
        case .asleep:
            UnitShape(path: G.sleepingEyes).stroke(style.belly, style: stroke(5))
        case .proud:
            UnitShape(path: G.happyEyes).stroke(style.belly, style: stroke(5))
        case .faint:
            UnitShape(path: G.faintEyes).stroke(style.belly, style: stroke(4.5))
        case .awake, .grumpy, .squawk:
            UnitShape(path: G.eyeWhites(radius: mood == .squawk ? 11 : 10)).fill(style.belly)
            UnitShape(path: G.pupils(for: mood)).fill(body)
            if mood == .awake {
                UnitShape(path: G.glints).fill(style.belly)
            }
            if mood == .grumpy {
                UnitShape(path: G.grumpyBrows).fill(body)
            }
        }
    }

    @ViewBuilder private var beak: some View {
        let G = PenguinGeometry.self
        if mood.beakOpen {
            UnitShape(path: G.mouth).fill(style.mouth)
            UnitShape(path: G.tongue).fill(style.tongue)
            UnitShape(path: G.lowerBeak).fill(style.beak)
            UnitShape(path: G.upperBeak).fill(style.beak)
        } else {
            UnitShape(path: G.beak).fill(style.beak)
        }
    }

    @ViewBuilder private var outfit: some View {
        let G = PenguinGeometry.self
        switch accessory {
        case .nightcap:
            UnitShape(path: G.nightcap).fill(style.outfit)
            UnitShape(path: G.nightcapPompom).fill(style.outfitTrim)
        case .beanie:
            UnitShape(path: G.beanie).fill(style.outfit)
            UnitShape(path: G.beanieBand).fill(style.outfitTrim)
            UnitShape(path: G.beaniePompom).fill(style.outfitTrim)
        case .partyHat:
            UnitShape(path: G.partyHat).fill(style.outfit)
            UnitShape(path: G.partyHatStripes).stroke(style.outfitTrim, style: stroke(4))
            UnitShape(path: G.partyHatPompom).fill(style.outfitTrim)
        case .sunglasses:
            UnitShape(path: G.sunglasses).fill(Color(hex: 0x0B0F1A))
            UnitShape(path: G.sunglassesShine).stroke(Color.white.opacity(0.7), style: stroke(2.5))
        case .scarf, nil:
            EmptyView()
        }
    }

    private func stroke(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round)
    }
}

/// Draws a canvas path scaled to fit its frame, centered.
struct UnitShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let s = side / PenguinGeometry.canvas
        return path
            .applying(CGAffineTransform(scaleX: s, y: s))
            .offsetBy(dx: rect.minX + (rect.width - side) / 2, dy: rect.minY + (rect.height - side) / 2)
    }
}

#Preview("Moods") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) {
            ForEach(PenguinMood.allCases) { mood in
                PenguinView(mood: mood, accessory: mood == .asleep ? .nightcap : nil)
                    .frame(height: 140)
            }
        }
        .padding()
    }
}
