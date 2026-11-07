#if canImport(UIKit)
import AstrotypeCore
import UIKit
/// Where flow stands: the level, the combo count the space bar shows, and progress
/// (features/customization "Flow").
/// (the space bar's combo count, features/customization "Flow").
public struct FlowState: Equatable, Sendable {
    /// Flow is on in the effects.
    public var isOn: Bool
    public var level: FlowLevel
    public var combo: Int
    /// How far toward the next level, 0 to 1.
    public var progress: Double
    /// The meter has anything in it.
    public var isActive: Bool
    /// The combo count shows (Waddle reached, with its switch on).
    public var showsCombo: Bool
    /// A new level was reached on this update.
    public var leveledUp: Bool

    public static let off = FlowState(isOn: false, level: .calm, combo: 0, progress: 0, isActive: false, showsCombo: false, leveledUp: false)
}

/// One swipe's trail as it draws.
@MainActor
final class TrailDrawing {
    let side: Side
    let kind: EffectsSettings.Trail
    let color: UIColor
    let container = CALayer()
    var shapes: [CAShapeLayer] = []
    var head: CALayer?
    var emitter: CAEmitterLayer?

    init(side: Side, kind: EffectsSettings.Trail, color: UIColor) {
        self.side = side
        self.kind = kind
        self.color = color
    }
}

/// Calls a closure from a display link (a display link needs an Objective-C target).
@MainActor
private final class LinkTarget: NSObject {
    let tick: @MainActor () -> Void
    init(_ tick: @escaping @MainActor () -> Void) { self.tick = tick }
    @objc func step() { tick() }
}

/// The small images particles are drawn with, made once.
@MainActor
enum Sprites {
    static let dot: CGImage? = render(CGSize(width: 16, height: 16)) { ctx, size in
        let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.35, 1]) else { return }
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width / 2, options: [])
    }
    static let star: CGImage? = render(CGSize(width: 24, height: 24)) { ctx, size in
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.addPath(starPath(in: CGRect(origin: .zero, size: size), inner: 0.45))
        ctx.fillPath()
    }
    static let twinkle: CGImage? = render(CGSize(width: 24, height: 24)) { ctx, size in
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.addPath(starPath(in: CGRect(origin: .zero, size: size), inner: 0.2, points: 4))
        ctx.fillPath()
    }
    static let confetti: CGImage? = render(CGSize(width: 10, height: 5)) { ctx, size in
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
    }
    /// A hard square, for 8-bit blasts.
    static let pixel: CGImage? = render(CGSize(width: 6, height: 6)) { ctx, size in
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
    }
    /// A thin bar of static.
    static let bar: CGImage? = render(CGSize(width: 36, height: 2)) { ctx, size in
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
    }
    static let heart: CGImage? = render(CGSize(width: 22, height: 20)) { ctx, size in
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.addPath(heartPath(in: CGRect(origin: .zero, size: size)))
        ctx.fillPath()
    }
    static let petal: CGImage? = render(CGSize(width: 20, height: 11)) { ctx, size in
        let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.55).cgColor] as CFArray
        ctx.addEllipse(in: CGRect(origin: .zero, size: size))
        ctx.clip()
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
    }

    private static func render(_ size: CGSize, _ draw: (CGContext, CGSize) -> Void) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext, size) }.cgImage
    }

    static func heartPath(in rect: CGRect) -> CGPath {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x + w / 2, y: y + h))
        path.addCurve(to: CGPoint(x: x, y: y + h * 0.3), control1: CGPoint(x: x + w * 0.2, y: y + h * 0.8),
                      control2: CGPoint(x: x, y: y + h * 0.55))
        path.addArc(center: CGPoint(x: x + w * 0.25, y: y + h * 0.27), radius: w * 0.25, startAngle: .pi, endAngle: 0, clockwise: false)
        path.addArc(center: CGPoint(x: x + w * 0.75, y: y + h * 0.27), radius: w * 0.25, startAngle: .pi, endAngle: 0, clockwise: false)
        path.addCurve(to: CGPoint(x: x + w / 2, y: y + h), control1: CGPoint(x: x + w, y: y + h * 0.55),
                      control2: CGPoint(x: x + w * 0.8, y: y + h * 0.8))
        path.closeSubpath()
        return path
    }

    static func starPath(in rect: CGRect, inner: CGFloat, points: Int = 5) -> CGPath {
        let path = CGMutablePath()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<(points * 2) {
            let radius = i % 2 == 0 ? r : r * inner
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let p = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// The colours the presets throw around.
@MainActor
enum Palette {
    static let neon = [UIColor(red: 1, green: 0.17, blue: 0.84, alpha: 1), UIColor(red: 0.13, green: 0.9, blue: 1, alpha: 1),
                       UIColor(red: 1, green: 0.9, blue: 0.2, alpha: 1), UIColor(red: 0.24, green: 1, blue: 0.43, alpha: 1)]
    static let glitch = [UIColor(red: 1, green: 0.12, blue: 0.31, alpha: 1), UIColor(red: 0.1, green: 0.9, blue: 1, alpha: 1), UIColor.white]
    static let rainbow = (0..<6).map { UIColor(hue: CGFloat($0) / 6, saturation: 0.85, brightness: 1, alpha: 1) }
    static let candy = [UIColor(red: 1, green: 0.31, blue: 0.64, alpha: 1), UIColor(red: 1, green: 0.54, blue: 0.78, alpha: 1),
                        UIColor(red: 0.77, green: 0.55, blue: 1, alpha: 1), UIColor(red: 1, green: 0.7, blue: 0.66, alpha: 1)]
    static let zen = [UIColor(red: 0.68, green: 0.92, blue: 0.85, alpha: 1), UIColor(red: 0.79, green: 0.72, blue: 1, alpha: 1),
                      UIColor(red: 1, green: 0.82, blue: 0.86, alpha: 1), UIColor(white: 1, alpha: 0.9)]
    static let space = [UIColor.white, UIColor(red: 0.7, green: 0.82, blue: 1, alpha: 1), UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 1)]

    /// A hue that moves round the rainbow over about a second.
    static func cycling(at time: TimeInterval) -> UIColor {
        UIColor(hue: CGFloat((time * 0.9).truncatingRemainder(dividingBy: 1)), saturation: 0.8, brightness: 1, alpha: 1)
    }
}

/// Everything the effects draw on the keys (features/customization "Effects"): taps,
/// trails, the letter effects, and flow with what it brings at each level (bigger taps,
/// comets and sparks, falling stars or snow and glowing keys, the sky). Core Animation
/// for all but the sky and the Metal letters (`MetalKeyboard`). Owned by the
/// `KeySurfaceView`, which tells it about touches. Nothing here moves a key or delays a
/// touch: it only draws.
@MainActor
final class KeyEffects {
    unowned let surface: KeySurfaceView
    var settings: EffectsSettings? = .calm {
        didSet { if settings != oldValue { settingsChanged() } }
    }
    var style = KeyStyle.classic {
        didSet { if style != oldValue { styleChanged() } }
    }
    var onFlow: ((FlowState) -> Void)?

    /// Taps, trails and particles, over the keys.
    let layer = CALayer()
    private weak var host: CALayer?
    private weak var effectsLayer: CALayer?
    private var flow = FlowMeter()
    private(set) var level = FlowLevel.calm
    private var lastState = FlowState.off
    private var link: CADisplayLink?
    private var linkTarget: LinkTarget?
    /// What flies across the keys at Blizzard: one emitter per side it comes from.
    private var falls: [(emitter: CAEmitterLayer, place: Place)] = []
    private var fallKind: EffectsSettings.Fall?
    /// When the keys next glitch (static at Blizzard, a torn row at the top).
    private var nextGlitch: TimeInterval = 0
    private var sky: SkyRenderer?
    private var skyGoneAt: TimeInterval?
    private var letters: LetterRenderer?
    private var lettersDirty = false
    private var bursts = 0
    private var bursting = false
    private var glowing = false

    init(surface: KeySurfaceView) {
        self.surface = surface
        layer.isOpaque = false
    }

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Low Power Mode or a hot phone: flow stops at Toboggan and letters don't use Metal.
    private var constrained: Bool {
        let info = ProcessInfo.processInfo
        return info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical
    }

    /// The highest level flow may reach now.
    private var cap: Int {
        guard let settings else { return 0 }
        return constrained ? min(settings.topLevel, FlowLevel.toboggan.rawValue) : settings.topLevel
    }

    /// Whether the settings and the phone's state call for the Metal letters now.
    private var wantsMetalLetters: Bool {
        guard let settings, settings.letters.usesMetal, !reduceMotion, !constrained else { return false }
        return true
    }

    /// Whether the settings and the phone's state call for the Metal key effects now.
    private var wantsMetalKeys: Bool {
        guard let settings, settings.keys != .none, !reduceMotion, !constrained else { return false }
        return true
    }

    /// The Metal layer over the keys is wanted for the letters, the key effects or both.
    private var wantsMetalLayer: Bool { wantsMetalLetters || wantsMetalKeys }

    /// Whether the Metal letters draw the letter keys' labels: wanted, and Metal is in
    /// (`MetalKeyboard.load`); until then the keys draw their own.
    var drawsLetters: Bool { !resting && wantsMetalLetters && MetalKeyboard.shared != nil }

    /// Called when Metal is in after an effect asked for it, so the keys' labels can
    /// move to the Metal letters (`KeySurfaceView.applyLetterMode`).
    var onMetalReady: (() -> Void)?

    /// Asks for Metal, off the main thread; the letters and the sky are made when it is in.
    private func requestMetal() {
        MetalKeyboard.load { [weak self] in
            guard let self else { return }
            onMetalReady?()
            applyLevel()
        }
    }

    private var now: TimeInterval { CACurrentMediaTime() }

    // MARK: Layers

    /// Put the layers in order on the key surface: the sky behind the keys, the Metal
    /// letters over them, then the replay's layer and the effects on top.
    func attach(to host: CALayer, effects: CALayer) {
        self.host = host
        effectsLayer = effects
        if let sky { host.insertSublayer(sky.layer, at: 0) }
        if let letters { host.addSublayer(letters.layer) }
        host.addSublayer(effects)
        host.addSublayer(layer)
        lettersDirty = true
        if letters != nil { ensureLink() }
    }

    func layout(_ bounds: CGRect) {
        guard layer.frame != bounds else { return }
        layer.frame = bounds
        sky?.layout(bounds, scale: surface.traitCollection.displayScale)
        letters?.layout(bounds, scale: surface.traitCollection.displayScale)
        layoutFall()
        lettersDirty = true
        if letters != nil { ensureLink() }
    }

    private func settingsChanged() {
        if settings?.flow != true { flow.reset() }
        updateLevel()
        if !falls.isEmpty, fallKind != settings?.fall { removeFall() }
        applyLevel()
    }

    private func styleChanged() {
        if !falls.isEmpty { removeFall(); applyLevel() }
        lettersChanged()
    }

    // MARK: Letters

    /// The letter or key effect, the theme or the keys changed: make, remake or drop the
    /// Metal layer over the keys (letters and key effects share it).
    func lettersChanged() {
        guard !resting, wantsMetalLayer, let metal = MetalKeyboard.shared, let host else {
            if !resting, wantsMetalLayer, MetalKeyboard.shared == nil { requestMetal() }
            letters?.layer.removeFromSuperlayer()
            letters = nil
            return
        }
        if letters == nil {
            let renderer = LetterRenderer(metal: metal)
            if let effectsLayer, effectsLayer.superlayer === host {
                host.insertSublayer(renderer.layer, below: effectsLayer)
            } else {
                host.addSublayer(renderer.layer)
            }
            renderer.layout(layer.bounds, scale: surface.traitCollection.displayScale)
            letters = renderer
        }
        letters?.keyMode = wantsMetalKeys ? settings?.keys ?? .none : .none
        if drawsLetters {
            letters?.mode = settings?.letters ?? .none
            letters?.prepare(letters: surface.lettersOnKeys(), font: style.letterFont(), scale: surface.traitCollection.displayScale)
        } else {
            letters?.mode = .none
            letters?.dropLetters()
        }
        lettersDirty = true
        ensureLink()
    }

    /// A key lit or went out: the Metal letters redraw in its new colour.
    func keysChanged() {
        guard letters != nil else { return }
        lettersDirty = true
        ensureLink()
    }

    /// A thumb hit a key: the key effect, and the letter effect when it is a letter.
    func keyHit(_ key: Key, at point: CGPoint) {
        guard let settings, !reduceMotion else { return }
        let isLetter = key.character != nil && settings.letters != .none
        if let letters, letters.keyMode != .none || (isLetter && drawsLetters) {
            letters.hit(key, at: point, time: now)
            ensureLink()
        }
        guard isLetter, !drawsLetters else { return }
        if settings.letters == .pop || settings.letters.usesMetal {
            // Pop, or a Metal effect when Metal can't run now.
            surface.popLetter(key, scale: 1.4 + 0.08 * CGFloat(level.rawValue))
        }
    }

    // MARK: Flow

    func word(at point: CGPoint, side: Side) {
        guard let settings, settings.flow else { return }
        flow.word(at: now)
        if settings.comets, level >= .toboggan, !reduceMotion {
            let look = particles(for: settings.tap, side: side)
            burst(at: point, look: look, count: 18 + 4 * level.rawValue, speed: 320, lifetime: 0.4, scale: look.scale * 1.1)
        }
        updateLevel()
        ensureLink()
    }

    func delete() {
        guard settings?.flow == true else { return }
        flow.delete(at: now)
        updateLevel()
        ensureLink()
    }

    func resetFlow() {
        flow.reset()
        updateLevel()
    }

    private func updateLevel() {
        guard let settings, settings.flow else {
            if level != .calm { level = .calm; applyLevel() }
            publish(leveledUp: false)
            return
        }
        flow.tick(now: now)
        let reached = flow.level(scale: settings.levelScale, cap: cap)
        let up = reached > level
        if reached != level {
            level = reached
            applyLevel()
        }
        if up { levelUp() }
        publish(leveledUp: up)
    }

    private func publish(leveledUp: Bool) {
        let settings = self.settings
        var state = FlowState.off
        if let settings, settings.flow {
            let progress = flow.progress(scale: settings.levelScale, cap: cap)
            state = FlowState(isOn: true, level: level, combo: flow.combo, progress: (progress * 50).rounded() / 50,
                              isActive: flow.score > 0, showsCombo: settings.combo && level >= .waddle, leveledUp: leveledUp)
        }
        guard state != lastState || leveledUp else { return }
        lastState = state
        onFlow?(state)
    }

    /// What each level brings, switched on or off as flow climbs or falls.
    private func applyLevel() {
        guard !resting else { return }
        let settings = self.settings
        let blizzard = settings?.flow == true && settings?.falling == true && level >= .blizzard && !reduceMotion
        if blizzard { startFall() } else { stopFall() }
        if blizzard, nextGlitch == 0 { nextGlitch = now + 0.3 }
        if blizzard != glowing {
            glowing = blizzard
            surface.setGlow(blizzard ? style.accent.withAlphaComponent(0.8) : nil)
        }
        let aurora = settings?.flow == true && settings?.skyOn == true && level >= .aurora && !reduceMotion
        if aurora { showSky() } else { hideSky() }
        for fall in falls { fall.emitter.birthRate = level >= .aurora ? 1.6 : 1 }
    }

    /// A new level: a blast from the middle of the keys in every direction.
    private func levelUp() {
        guard let settings, !reduceMotion, level >= .waddle else { return }
        let centre = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
        let look = particles(for: settings.tap, side: .left)
        burst(at: centre, look: look, count: 30 + 10 * level.rawValue, speed: 460, lifetime: 0.6, scale: look.scale * 1.3, force: true)
        if settings.tap == .glitch || settings.fall == .static {
            surface.glitchKeys(count: 6 + 3 * level.rawValue, strength: 10)
        }
    }

    /// Glitch flow: keys jolt now and then with static at Blizzard, and whole rows tear
    /// with the glitch sky at the top.
    private func glitchTick(_ time: TimeInterval) {
        guard let settings, settings.flow, !reduceMotion, level >= .blizzard, time >= nextGlitch else { return }
        let static_ = settings.falling && settings.fall == .static
        let torn = settings.skyOn && settings.sky == .glitch && level >= .aurora
        guard static_ || torn else { return }
        if static_ { surface.glitchKeys(count: level >= .aurora ? 5 : 3, strength: level >= .aurora ? 9 : 6) }
        if torn { surface.tearRow(strength: 12) }
        nextGlitch = time + Double.random(in: torn ? 0.18...0.6 : 0.3...0.9)
    }

    // MARK: Ticks

    private func ensureLink() {
        guard link == nil else { return }
        let target = LinkTarget { [weak self] in self?.step() }
        let link = CADisplayLink(target: target, selector: #selector(LinkTarget.step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
        linkTarget = target
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
        linkTarget = nil
    }

    private func step() {
        let time = now
        if flow.score > 0 { updateLevel() }
        glitchTick(time)
        var busy = flow.score > 0 || bursting
        if let letters {
            let moving = letters.isAnimating(time: time) || level >= .aurora
                || ((letters.mode == .disco || letters.keyMode != .none) && level >= .toboggan)
            if moving || lettersDirty {
                letters.render(keys: letters.mode != .none ? surface.letterKeys() : [],
                               frames: letters.keyMode != .none ? surface.keyFrames() : [],
                               time: time, level: level.rawValue, style: style)
                lettersDirty = false
            }
            busy = busy || moving
        }
        if let sky {
            sky.render(time: time, kind: settings?.sky ?? .aurora)
            busy = true
            if let gone = skyGoneAt, time >= gone {
                sky.layer.removeFromSuperlayer()
                self.sky = nil
                skyGoneAt = nil
            }
        }
        if !busy { stopLink() }
    }

    // MARK: Taps

    func tap(at point: CGPoint, side: Side) {
        guard let settings, settings.tap != .none else { return }
        let color = style.thumb(side)
        let grow = 1 + (settings.flow && settings.combo ? 0.15 * CGFloat(level.rawValue) : 0)
        if reduceMotion {
            let ring = makeRing(at: point, color: color, radius: 14)
            ring.transform = CATransform3DMakeScale(1.2, 1.2, 1)
            layer.addSublayer(ring)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Theme.Motion.tapRing))
                ring.removeFromSuperlayer()
            }
            return
        }
        switch settings.tap {
        case .none:
            break
        case .ring:
            ping(makeRing(at: point, color: color, radius: 14 * grow), delay: 0)
        case .ripple:
            for i in 0..<3 {
                let ring = makeRing(at: point, color: color, radius: (12 + CGFloat(i) * 7) * grow)
                ring.lineWidth = 2.5 - CGFloat(i) * 0.5
                ping(ring, delay: Double(i) * 0.06)
            }
        case .glitch:
            glitchTap(at: point, grow: grow)
            if let key = surface.key(at: point) { surface.glitchKey(key, strength: 5 * grow) }
        case .fireworks:
            ping(makeRing(at: point, color: Palette.cycling(at: now), radius: 12 * grow), delay: 0)
            fallthrough
        default:
            let look = particles(for: settings.tap, side: side)
            burst(at: point, look: look, count: look.count + look.perLevel * level.rawValue, speed: look.speed * grow,
                  lifetime: look.lifetime, scale: look.scale * grow)
        }
    }

    /// How each tap's particles look and move. Quick and in every direction (Gabriel,
    /// 7 Nov 2026); Petals stay soft and slow for Zen.
    private struct Look {
        var image: CGImage?
        var colors: [UIColor]
        var count = 12
        var perLevel = 2
        var speed: CGFloat = 260
        var lifetime: Float = 0.32
        var scale: CGFloat = 0.45
        var gravity: CGFloat = 0
        var spin: CGFloat = 0
    }

    private func particles(for tap: EffectsSettings.Tap, side: Side) -> Look {
        let color = style.thumb(side)
        switch tap {
        case .none, .ring, .ripple, .sparks:
            return Look(image: Sprites.dot, colors: [color, .white], count: 14, perLevel: 3)
        case .stars:
            return Look(image: Sprites.star, colors: [color, Theme.ui(.sun), .white], count: 8, speed: 220, lifetime: 0.45, scale: 0.4, spin: 5)
        case .snow:
            return Look(image: Sprites.dot, colors: [snowColor], count: 12, speed: 130, lifetime: 0.55, scale: 0.32, gravity: 140)
        case .pixels:
            return Look(image: Sprites.pixel, colors: Palette.neon, count: 18, perLevel: 3, speed: 250, lifetime: 0.38, scale: 0.75, gravity: 320)
        case .fireworks:
            return Look(image: Sprites.dot, colors: Palette.rainbow, count: 26, perLevel: 4, speed: 300, lifetime: 0.5, scale: 0.38, gravity: 260)
        case .glitch:
            return Look(image: Sprites.pixel, colors: Palette.glitch, count: 14, speed: 280, lifetime: 0.24, scale: 0.9)
        case .hearts:
            return Look(image: Sprites.heart, colors: Palette.candy + [.white], count: 10, perLevel: 3, speed: 240, lifetime: 0.5,
                        scale: 0.45, gravity: -90, spin: 2)
        case .petals:
            return Look(image: Sprites.petal, colors: Palette.zen, count: 9, perLevel: 1, speed: 95, lifetime: 0.95, scale: 0.55, spin: 1.6)
        }
    }

    /// Glitch: blocks of the touch's area break off in split red and cyan and jump
    /// about in every direction for a moment (Gabriel, 7 Nov 2026: not just lines).
    private func glitchTap(at point: CGPoint, grow: CGFloat) {
        let blocks = 6 + level.rawValue
        for i in 0..<blocks {
            let size = CGSize(width: CGFloat.random(in: 4...16) * grow, height: CGFloat.random(in: 4...14) * grow)
            let centre = CGPoint(x: point.x + CGFloat.random(in: -26...26) * grow, y: point.y + CGFloat.random(in: -22...22) * grow)
            let hops = (0..<5).map { _ in CGPoint(x: centre.x + CGFloat.random(in: -18...18) * grow, y: centre.y + CGFloat.random(in: -14...14) * grow) }
            // A red copy and a cyan copy a few points apart, and sometimes a white one.
            var copies: [(UIColor, CGFloat)] = [(Palette.glitch[0], -2.5), (Palette.glitch[1], 2.5)]
            if i % 3 == 0 { copies.append((.white, 0)) }
            for (color, shift) in copies {
                let block = CALayer()
                block.bounds = CGRect(origin: .zero, size: size)
                block.position = centre
                block.backgroundColor = color.cgColor
                block.opacity = 0
                block.compositingFilter = color == .white ? nil : "screenBlendMode"
                layer.addSublayer(block)
                let jump = CAKeyframeAnimation(keyPath: "position")
                jump.values = hops.map { NSValue(cgPoint: CGPoint(x: $0.x + shift, y: $0.y)) }
                jump.calculationMode = .discrete
                let flicker = CAKeyframeAnimation(keyPath: "opacity")
                flicker.values = [0.9, 0.2, 0.95, 0.5, 0.85, 0]
                flicker.calculationMode = .discrete
                let group = CAAnimationGroup()
                group.animations = [jump, flicker]
                group.duration = 0.26
                group.beginTime = block.convertTime(CACurrentMediaTime(), from: nil) + Double(i) * 0.01
                group.fillMode = .forwards
                group.isRemovedOnCompletion = false
                CATransaction.begin()
                CATransaction.setCompletionBlock { block.removeFromSuperlayer() }
                block.add(group, forKey: "glitch")
                CATransaction.commit()
            }
        }
    }

    private var snowColor: UIColor { style.backgroundIsDark ? .white : style.colors.left.uiColor }

    private func makeRing(at point: CGPoint, color: UIColor, radius: CGFloat) -> CAShapeLayer {
        let ring = CAShapeLayer()
        ring.bounds = CGRect(x: 0, y: 0, width: 2 * radius, height: 2 * radius)
        ring.position = point
        ring.path = UIBezierPath(ovalIn: ring.bounds).cgPath
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = 2
        return ring
    }

    /// The effects' ring is quicker than the keyboard's old one (Gabriel, 7 Nov 2026).
    private static let quickRing: TimeInterval = 0.4

    /// Today's tap ring: it grows from half size and fades.
    private func ping(_ ring: CAShapeLayer, delay: TimeInterval) {
        ring.opacity = 0
        layer.addSublayer(ring)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.5
        grow.toValue = 1.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = Self.quickRing
        group.beginTime = ring.convertTime(CACurrentMediaTime(), from: nil) + delay
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "ping")
        CATransaction.commit()
    }

    /// A short spray of particles from a point, in every direction.
    private func burst(at point: CGPoint, look: Look, count: Int, speed: CGFloat, lifetime: Float, scale: CGFloat, force: Bool = false) {
        guard let image = look.image, bursts < (force ? 24 : 18), !look.colors.isEmpty else { return }
        let emitter = CAEmitterLayer()
        emitter.frame = layer.bounds
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.renderMode = .unordered
        emitter.emitterCells = look.colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = image
            cell.color = color.cgColor
            cell.birthRate = Float(count) / Float(look.colors.count) / 0.05
            cell.lifetime = lifetime
            cell.lifetimeRange = lifetime * 0.3
            cell.velocity = speed
            cell.velocityRange = speed * 0.5
            cell.emissionRange = .pi * 2
            cell.yAcceleration = look.gravity
            cell.scale = scale
            cell.scaleRange = scale * 0.35
            cell.scaleSpeed = -scale * 0.6
            cell.alphaSpeed = -1 / lifetime
            cell.spin = look.spin
            cell.spinRange = look.spin * 2
            return cell
        }
        emitter.beginTime = CACurrentMediaTime()
        layer.addSublayer(emitter)
        bursts += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            emitter.birthRate = 0
            try? await Task.sleep(for: .seconds(Double(lifetime) * 1.4 + 0.1))
            emitter.removeFromSuperlayer()
            self?.bursts -= 1
        }
    }

    // MARK: Trails

    func beginTrail(side: Side, at point: CGPoint) -> TrailDrawing? {
        guard let settings, settings.trail != .none else { return nil }
        var kind = settings.trail
        // At Toboggan the plain trails become comets; the presets' own keep their look.
        if settings.flow, settings.comets, level >= .toboggan, kind == .line || kind == .glitter { kind = .comet }
        if reduceMotion { kind = .line }
        let trail = TrailDrawing(side: side, kind: kind, color: style.thumb(side))
        trail.container.frame = layer.bounds
        layer.addSublayer(trail.container)
        func shape(width: CGFloat, opacity: Float, color: UIColor) -> CAShapeLayer {
            let s = CAShapeLayer()
            s.frame = trail.container.bounds
            s.fillColor = nil
            s.strokeColor = color.cgColor
            s.lineWidth = width
            s.lineCap = .round
            s.lineJoin = .round
            s.opacity = opacity
            trail.container.addSublayer(s)
            trail.shapes.append(s)
            return s
        }
        switch kind {
        case .none:
            break
        case .line:
            _ = shape(width: 9, opacity: 0.85, color: trail.color)
        case .glitter:
            _ = shape(width: 3, opacity: 0.45, color: trail.color)
            trail.emitter = stream(at: point, image: Sprites.dot, colors: [trail.color, Theme.ui(.sun)], rate: 90, scale: 0.3, spread: 8)
        case .comet:
            _ = shape(width: 3, opacity: 0.3, color: trail.color)
            _ = shape(width: 7, opacity: 0.6, color: trail.color)
            _ = shape(width: 12, opacity: 0.95, color: trail.color)
            let head = CALayer()
            head.bounds = CGRect(x: 0, y: 0, width: 11, height: 11)
            head.cornerRadius = 5.5
            head.backgroundColor = UIColor.white.cgColor
            head.shadowColor = trail.color.cgColor
            head.shadowOpacity = 1
            head.shadowRadius = 8
            head.shadowOffset = .zero
            head.position = point
            trail.container.addSublayer(head)
            trail.head = head
            trail.emitter = stream(at: point, image: Sprites.dot, colors: [trail.color, .white], rate: 70, scale: 0.35, spread: 4)
        case .pixels:
            let dashes = shape(width: 7, opacity: 0.95, color: trail.color)
            dashes.lineCap = .butt
            dashes.lineJoin = .miter
            dashes.lineDashPattern = [7, 4]
            trail.emitter = stream(at: point, image: Sprites.pixel, colors: Palette.neon, rate: 60, scale: 0.6, spread: 6)
        case .glitch:
            _ = shape(width: 4, opacity: 0.85, color: Palette.glitch[0])
            _ = shape(width: 4, opacity: 0.85, color: Palette.glitch[1])
            _ = shape(width: 6, opacity: 0.95, color: trail.color)
            trail.emitter = stream(at: point, image: Sprites.pixel, colors: Palette.glitch, rate: 45, scale: 0.7, spread: 10)
        case .hearts:
            _ = shape(width: 5, opacity: 0.8, color: Palette.candy[0])
            trail.emitter = stream(at: point, image: Sprites.heart, colors: Palette.candy, rate: 45, scale: 0.35, spread: 6)
        case .silk:
            _ = shape(width: 20, opacity: 0.16, color: trail.color)
            _ = shape(width: 9, opacity: 0.32, color: trail.color)
            _ = shape(width: 2.5, opacity: 0.9, color: .white)
        case .rainbow:
            let gradient = CAGradientLayer()
            gradient.type = .conic
            gradient.frame = trail.container.bounds
            let w = max(gradient.bounds.width, 1), h = max(gradient.bounds.height, 1)
            gradient.startPoint = CGPoint(x: point.x / w, y: point.y / h)
            gradient.endPoint = CGPoint(x: point.x / w, y: point.y / h - 0.5)
            gradient.colors = (0...8).map { UIColor(hue: CGFloat($0) / 8, saturation: 0.85, brightness: 1, alpha: 1).cgColor }
            let mask = CAShapeLayer()
            mask.frame = gradient.bounds
            mask.fillColor = nil
            mask.strokeColor = UIColor.black.cgColor
            mask.lineWidth = 10
            mask.lineCap = .round
            mask.lineJoin = .round
            gradient.mask = mask
            trail.container.addSublayer(gradient)
            trail.shapes.append(mask)
        }
        return trail
    }

    /// Particles that keep coming from a point while a finger moves (glitter, comets).
    private func stream(at point: CGPoint, image: CGImage?, colors: [UIColor], rate: Float, scale: CGFloat, spread: CGFloat) -> CAEmitterLayer? {
        guard let image else { return nil }
        let emitter = CAEmitterLayer()
        emitter.frame = layer.bounds
        emitter.emitterPosition = point
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: spread, height: spread)
        emitter.renderMode = .unordered
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = image
            cell.color = color.cgColor
            cell.birthRate = rate / Float(colors.count)
            cell.lifetime = 0.45
            cell.lifetimeRange = 0.15
            cell.velocity = 45
            cell.velocityRange = 35
            cell.emissionRange = .pi * 2
            cell.scale = scale
            cell.scaleRange = scale * 0.5
            cell.scaleSpeed = -scale * 0.6
            cell.alphaSpeed = -1.5
            return cell
        }
        emitter.beginTime = CACurrentMediaTime()
        layer.addSublayer(emitter)
        return emitter
    }

    func moveTrail(_ trail: TrailDrawing, points: [CGPoint]) {
        guard let last = points.last else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch trail.kind {
        case .comet:
            let tails = [points.count, 28, 12]
            for (shape, count) in zip(trail.shapes, tails) {
                shape.path = Self.path(Array(points.suffix(count)))
            }
            trail.head?.position = last
        case .glitch:
            let path = Self.path(points)
            for (i, shape) in trail.shapes.enumerated() {
                shape.path = path
                // The red and cyan copies jump about beside the line.
                if i < 2 {
                    let side: CGFloat = i == 0 ? 1 : -1
                    shape.setAffineTransform(CGAffineTransform(translationX: side * CGFloat.random(in: 1...5), y: CGFloat.random(in: -2...2)))
                }
            }
        default:
            let path = Self.path(points)
            trail.shapes.forEach { $0.path = path }
        }
        trail.emitter?.emitterPosition = last
        CATransaction.commit()
    }

    private static func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    /// After lift the trail fades: today's line over `Theme.Motion.trailFade`, the
    /// others quicker. Under Reduce Motion it stays for the same time and then goes.
    func endTrail(_ trail: TrailDrawing) {
        trail.emitter?.birthRate = 0
        let container = trail.container
        let emitter = trail.emitter
        let seconds = switch trail.kind {
        case .line: Theme.Motion.trailFade
        case .silk: 1.0
        default: 0.4
        }
        if reduceMotion {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                container.removeFromSuperlayer()
            }
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = seconds
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            container.removeFromSuperlayer()
            emitter?.removeFromSuperlayer()
        }
        container.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    func cancelTrail(_ trail: TrailDrawing) {
        trail.container.removeFromSuperlayer()
        trail.emitter?.removeFromSuperlayer()
    }

    // MARK: Blizzard: things fall

    /// Where an emitter sits on the keys.
    private enum Place { case top, bottom, left, right, centre, area, bottomLeft, bottomRight }

    private func startFall() {
        guard let settings, falls.isEmpty else { return }
        let kind = settings.fall
        func cell(_ image: CGImage?, _ color: UIColor, _ setup: (CAEmitterCell) -> Void) -> CAEmitterCell {
            let cell = CAEmitterCell()
            cell.contents = image
            cell.color = color.cgColor
            setup(cell)
            return cell
        }
        func cells(_ image: CGImage?, _ colors: [UIColor], _ setup: @escaping (CAEmitterCell) -> Void) -> [CAEmitterCell] {
            colors.map { cell(image, $0, setup) }
        }
        /// A cannon from a bottom corner: up and in, then down again.
        func cannon(_ image: CGImage?, _ colors: [UIColor], left: Bool, rate: Float, spin: CGFloat) -> [CAEmitterCell] {
            cells(image, colors) { c in
                c.birthRate = rate
                c.lifetime = 2.2
                c.velocity = 430
                c.velocityRange = 120
                c.emissionLongitude = -.pi / 2 + (left ? 0.5 : -0.5)
                c.emissionRange = 0.4
                c.yAcceleration = 400
                c.scale = 0.7
                c.scaleRange = 0.3
                c.spin = spin
                c.spinRange = spin * 2
            }
        }
        var sources: [(Place, [CAEmitterCell])] = []
        switch kind {
        case .stars:
            let twinkles = cells(Sprites.twinkle, [UIColor(red: 1, green: 0.96, blue: 0.76, alpha: 1), style.thumb(.left)]) { c in
                c.birthRate = 7
                c.lifetime = 0.9
                c.lifetimeRange = 0.3
                c.scale = 0.25
                c.scaleRange = 0.15
                c.scaleSpeed = 0.3
                c.alphaSpeed = -1.1
                c.spin = 2
                c.spinRange = 3
            }
            let shooting = cells(Sprites.star, [.white, Theme.ui(.sun)]) { c in
                c.birthRate = 2.5
                c.lifetime = 1
                c.velocity = 260
                c.velocityRange = 80
                c.emissionRange = .pi * 2
                c.scale = 0.15
                c.scaleSpeed = 0.45
                c.spin = 3
            }
            sources = [(.area, twinkles), (.centre, shooting)]
        case .snow:
            let flake = snowColor.withAlphaComponent(0.9)
            let falling = cells(Sprites.dot, [flake]) { c in
                c.birthRate = 16
                c.lifetime = 3.5
                c.velocity = 90
                c.velocityRange = 40
                c.emissionLongitude = .pi / 2
                c.emissionRange = .pi / 8
                c.yAcceleration = 30
                c.xAcceleration = -25
                c.scale = 0.3
                c.scaleRange = 0.18
            }
            // A gust from the side.
            let gust = cells(Sprites.dot, [flake]) { c in
                c.birthRate = 9
                c.lifetime = 3
                c.velocity = 170
                c.velocityRange = 60
                c.emissionLongitude = 0.35
                c.emissionRange = 0.3
                c.scale = 0.26
                c.scaleRange = 0.15
            }
            sources = [(.top, falling), (.left, gust)]
        case .confetti:
            let colors = [Theme.ui(.right), Theme.ui(.sun), Theme.ui(.mint), Theme.ui(.left), UIColor(red: 0.48, green: 0.38, blue: 1, alpha: 1)]
            let rain = cells(Sprites.confetti, colors) { c in
                c.birthRate = 1.2
                c.lifetime = 3
                c.velocity = 110
                c.velocityRange = 40
                c.emissionLongitude = .pi / 2
                c.emissionRange = .pi / 6
                c.yAcceleration = 40
                c.scale = 0.7
                c.scaleRange = 0.3
                c.spin = 5
                c.spinRange = 6
            }
            sources = [(.bottomLeft, cannon(Sprites.confetti, colors, left: true, rate: 3, spin: 6)),
                       (.bottomRight, cannon(Sprites.confetti, colors, left: false, rate: 3, spin: 6)), (.top, rain)]
        case .pixels:
            let fountain = cells(Sprites.pixel, Palette.neon) { c in
                c.birthRate = 5
                c.lifetime = 1.6
                c.velocity = 400
                c.velocityRange = 110
                c.emissionLongitude = -.pi / 2
                c.emissionRange = 0.7
                c.yAcceleration = 440
                c.scale = 0.8
                c.scaleRange = 0.3
            }
            let rain = cells(Sprites.pixel, Palette.neon) { c in
                c.birthRate = 1.5
                c.lifetime = 2.5
                c.velocity = 140
                c.emissionLongitude = .pi / 2
                c.emissionRange = 0.1
                c.scale = 0.6
            }
            sources = [(.bottom, fountain), (.top, rain)]
        case .static:
            let bars = cells(Sprites.bar, Palette.glitch) { c in
                c.birthRate = 6
                c.lifetime = 0.12
                c.lifetimeRange = 0.08
                c.scale = 1
                c.scaleRange = 0.7
                c.alphaRange = 0.5
            }
            // Mostly blocks, a few thin bars: static, not just lines.
            let blocks = cells(Sprites.pixel, Palette.glitch) { c in
                c.birthRate = 12
                c.lifetime = 0.14
                c.lifetimeRange = 0.08
                c.scale = 1.1
                c.scaleRange = 0.8
                c.alphaRange = 0.5
            }
            sources = [(.area, bars + blocks)]
        case .warp:
            // Stars rush out from the middle and grow as they pass.
            let stars = cells(Sprites.dot, Palette.space.map { $0.withAlphaComponent(0.4) }) { c in
                c.birthRate = 14
                c.lifetime = 1.4
                c.velocity = 150
                c.velocityRange = 90
                c.emissionRange = .pi * 2
                c.scale = 0.06
                c.scaleSpeed = 0.5
                c.alphaSpeed = 0.6
            }
            sources = [(.centre, stars)]
        case .petals:
            func drift(_ left: Bool) -> [CAEmitterCell] {
                cells(Sprites.petal, Palette.zen) { c in
                    c.birthRate = 1.6
                    c.lifetime = 6
                    c.velocity = 75
                    c.velocityRange = 30
                    c.emissionLongitude = left ? 0.15 : .pi - 0.15
                    c.emissionRange = 0.45
                    c.yAcceleration = -4
                    c.scale = 0.55
                    c.scaleRange = 0.2
                    c.spin = 1.2
                    c.spinRange = 2
                }
            }
            sources = [(.left, drift(true)), (.right, drift(false))]
        case .hearts:
            let rising = cells(Sprites.heart, Palette.candy) { c in
                c.birthRate = 2.5
                c.lifetime = 3
                c.velocity = 120
                c.velocityRange = 60
                c.emissionLongitude = -.pi / 2
                c.emissionRange = 0.5
                c.scale = 0.45
                c.scaleRange = 0.2
                c.scaleSpeed = 0.1
                c.spin = 0.8
                c.spinRange = 1.6
            }
            sources = [(.bottom, rising), (.bottomLeft, cannon(Sprites.heart, Palette.candy, left: true, rate: 1.5, spin: 2)),
                       (.bottomRight, cannon(Sprites.heart, Palette.candy, left: false, rate: 1.5, spin: 2))]
        }
        let start = CACurrentMediaTime()
        for (place, cells) in sources {
            let emitter = CAEmitterLayer()
            emitter.renderMode = .unordered
            emitter.emitterCells = cells
            emitter.beginTime = start
            layer.insertSublayer(emitter, at: 0)
            falls.append((emitter, place))
        }
        fallKind = kind
        layoutFall()
    }

    private func layoutFall() {
        let b = layer.bounds
        for (emitter, place) in falls {
            emitter.frame = b
            let (position, size): (CGPoint, CGSize) = switch place {
            case .top: (CGPoint(x: b.midX, y: -6), CGSize(width: b.width, height: 1))
            case .bottom: (CGPoint(x: b.midX, y: b.maxY + 6), CGSize(width: b.width, height: 1))
            // The keyboard doesn't reach the screen's edges, so the sides start a little in.
            case .left: (CGPoint(x: 10, y: b.midY), CGSize(width: 1, height: b.height * 0.8))
            case .right: (CGPoint(x: b.maxX - 10, y: b.midY), CGSize(width: 1, height: b.height * 0.8))
            case .centre: (CGPoint(x: b.midX, y: b.midY), .zero)
            case .area: (CGPoint(x: b.midX, y: b.midY), CGSize(width: b.width - 24, height: b.height - 16))
            case .bottomLeft: (CGPoint(x: 16, y: b.maxY), .zero)
            case .bottomRight: (CGPoint(x: b.maxX - 16, y: b.maxY), .zero)
            }
            emitter.emitterShape = size == .zero ? .point : .rectangle
            emitter.emitterPosition = position
            emitter.emitterSize = size
        }
    }

    private func stopFall() {
        guard !falls.isEmpty else { return }
        let gone = falls.map(\.emitter)
        gone.forEach { $0.birthRate = 0 }
        falls = []
        fallKind = nil
        nextGlitch = 0
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            gone.forEach { $0.removeFromSuperlayer() }
        }
    }

    private func removeFall() {
        falls.forEach { $0.emitter.removeFromSuperlayer() }
        falls = []
        fallKind = nil
    }

    // MARK: Aurora: the sky

    private func showSky() {
        skyGoneAt = nil
        if sky == nil {
            guard let metal = MetalKeyboard.shared, let host else {
                if MetalKeyboard.shared == nil { requestMetal() }
                return
            }
            let renderer = SkyRenderer(metal: metal)
            renderer.layout(layer.bounds, scale: surface.traitCollection.displayScale)
            renderer.layer.opacity = 0
            host.insertSublayer(renderer.layer, at: 0)
            sky = renderer
        }
        guard let sky else { return }
        fade(sky.layer, to: 0.95, duration: 0.8)
        ensureLink()
    }

    private func hideSky() {
        guard let sky, skyGoneAt == nil else { return }
        fade(sky.layer, to: 0, duration: 1.2)
        skyGoneAt = now + 1.3
    }

    private func fade(_ layer: CALayer, to value: Float, duration: TimeInterval) {
        let from = layer.presentation()?.opacity ?? layer.opacity
        guard from != value || layer.opacity != value else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = value
        animation.duration = duration
        layer.opacity = value
        layer.add(animation, forKey: "fade")
    }

    // MARK: Play a burst

    private static let burstWords = ["the", "quick", "penguin", "slides", "over", "ice", "and", "types", "fast", "with", "both", "thumbs",
                                     "while", "friends", "cheer", "from", "the", "floe", "what", "a", "great", "day", "to", "glide", "home"]

    /// Swipe a fast run of words over the keys (nothing is typed), faster as it goes, so
    /// flow climbs and every level shows.
    func playBurst(completion: (@MainActor () -> Void)?) {
        guard !bursting else { return }
        bursting = true
        ensureLink()
        Task { @MainActor [weak self] in
            for i in 0..<60 {
                guard let self, self.bursting else { break }
                let word = Self.burstWords[i % Self.burstWords.count]
                let points = word.compactMap { self.surface.centre(of: $0) }
                guard let first = points.first else { continue }
                let side: Side = first.x < self.layer.bounds.midX ? .left : .right
                let steps = max(8, points.count * 4)
                let duration = max(0.14, 0.32 - Double(i) * 0.003)
                var drawn: [CGPoint] = [first]
                var lit: Key?
                let trail = self.beginTrail(side: side, at: first)
                for step in 0...steps {
                    let f = Double(step) / Double(steps) * Double(points.count - 1)
                    let a = points[Int(f)], b = points[min(points.count - 1, Int(f) + 1)]
                    let u = CGFloat(f - floor(f))
                    let p = CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
                    drawn.append(p)
                    if let trail { self.moveTrail(trail, points: drawn) }
                    let key = self.surface.key(at: p)
                    if key != lit {
                        if let lit { self.surface.unlight(lit) }
                        if let key { self.surface.light(key, side: side) }
                        lit = key
                    }
                    try? await Task.sleep(for: .seconds(duration / Double(steps)))
                }
                if let lit { self.surface.unlight(lit) }
                if let trail { self.endTrail(trail) }
                self.word(at: drawn.last ?? first, side: side)
                try? await Task.sleep(for: .seconds(max(0.06, 0.5 - Double(i) * 0.009)))
            }
            self?.bursting = false
            completion?()
        }
    }
}
#endif
