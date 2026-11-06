#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// Where flow stands, for the meter, the combo badge and the level pop
/// (`FlowHUDView`, features/customization "Flow").
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

    private static func render(_ size: CGSize, _ draw: (CGContext, CGSize) -> Void) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext, size) }.cgImage
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
    private var fall: CAEmitterLayer?
    private var fallKind: EffectsSettings.Fall?
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

    /// Whether the Metal letters draw the letter keys' labels.
    var drawsLetters: Bool {
        guard let settings, settings.letters.usesMetal, !reduceMotion, !constrained else { return false }
        return MetalKeyboard.shared != nil
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
        if fall != nil, fallKind != settings?.fall { removeFall() }
        applyLevel()
    }

    private func styleChanged() {
        if fall != nil { removeFall(); applyLevel() }
        lettersChanged()
    }

    // MARK: Letters

    /// The letter effect, the theme or the keys changed: make, remake or drop the Metal
    /// letters.
    func lettersChanged() {
        guard drawsLetters, let metal = MetalKeyboard.shared, let host else {
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
        letters?.mode = settings?.letters ?? .none
        letters?.prepare(letters: surface.lettersOnKeys(), font: style.letterFont(), scale: surface.traitCollection.displayScale)
        lettersDirty = true
        ensureLink()
    }

    /// A key lit or went out: the Metal letters redraw in its new colour.
    func keysChanged() {
        guard letters != nil else { return }
        lettersDirty = true
        ensureLink()
    }

    /// A thumb hit a letter.
    func letterHit(_ key: Key, at point: CGPoint) {
        guard let settings, settings.letters != .none, !reduceMotion else { return }
        if let letters {
            letters.hit(key, at: point, time: now)
            ensureLink()
        } else if settings.letters == .pop || settings.letters.usesMetal {
            // Pop, or a Metal effect when Metal can't run now.
            surface.popLetter(key, scale: 1.4 + 0.08 * CGFloat(level.rawValue))
        }
    }

    // MARK: Flow

    func word(at point: CGPoint, side: Side) {
        guard let settings, settings.flow else { return }
        flow.word(at: now)
        if settings.comets, level >= .toboggan, !reduceMotion {
            burst(at: point, image: Sprites.dot, colors: [style.thumb(side), .white], count: 14, speed: 150, lifetime: 0.45, scale: 0.5)
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
        let settings = self.settings
        let blizzard = settings?.flow == true && settings?.falling == true && level >= .blizzard && !reduceMotion
        if blizzard { startFall() } else { stopFall() }
        if blizzard != glowing {
            glowing = blizzard
            surface.setGlow(blizzard ? style.accent.withAlphaComponent(0.8) : nil)
        }
        let aurora = settings?.flow == true && settings?.skyOn == true && level >= .aurora && !reduceMotion
        if aurora { showSky() } else { hideSky() }
        fall?.birthRate = level >= .aurora ? 1.6 : 1
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
        var busy = flow.score > 0 || bursting
        if let letters {
            let moving = letters.isAnimating(time: time) || level >= .aurora
            if moving || lettersDirty {
                letters.render(keys: surface.letterKeys(), time: time, level: level.rawValue, style: style)
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
                ping(ring, delay: Double(i) * 0.08)
            }
        case .sparks:
            burst(at: point, image: Sprites.dot, colors: [color, .white], count: 10 + 2 * level.rawValue, speed: 130 * grow,
                  lifetime: 0.35, scale: 0.45 * grow)
        case .stars:
            burst(at: point, image: Sprites.star, colors: [color, Theme.ui(.sun)], count: 3 + level.rawValue, speed: 70 * grow,
                  lifetime: 0.7, scale: 0.45 * grow, upward: true, spin: 3)
        case .snow:
            burst(at: point, image: Sprites.dot, colors: [snowColor], count: 6 + 2 * level.rawValue, speed: 45 * grow,
                  lifetime: 0.9, scale: 0.35 * grow, gravity: 70)
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
        group.duration = Theme.Motion.tapRing
        group.beginTime = ring.convertTime(CACurrentMediaTime(), from: nil) + delay
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "ping")
        CATransaction.commit()
    }

    /// A short spray of particles from a point.
    private func burst(at point: CGPoint, image: CGImage?, colors: [UIColor], count: Int, speed: CGFloat, lifetime: Float,
                       scale: CGFloat, gravity: CGFloat = 0, upward: Bool = false, spin: CGFloat = 0) {
        guard let image, bursts < 14, !colors.isEmpty else { return }
        let emitter = CAEmitterLayer()
        emitter.frame = layer.bounds
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.renderMode = .unordered
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = image
            cell.color = color.cgColor
            cell.birthRate = Float(count) / Float(colors.count) / 0.06
            cell.lifetime = lifetime
            cell.lifetimeRange = lifetime * 0.3
            cell.velocity = speed
            cell.velocityRange = speed * 0.45
            cell.emissionLongitude = upward ? -.pi / 2 : 0
            cell.emissionRange = upward ? .pi / 2.5 : .pi * 2
            cell.yAcceleration = gravity
            cell.scale = scale
            cell.scaleRange = scale * 0.35
            cell.scaleSpeed = -scale * 0.5
            cell.alphaSpeed = -1 / lifetime
            cell.spin = spin
            cell.spinRange = spin * 2
            return cell
        }
        emitter.beginTime = CACurrentMediaTime()
        layer.addSublayer(emitter)
        bursts += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
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
        if settings.flow, settings.comets, level >= .toboggan, kind != .rainbow { kind = .comet }
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
            trail.emitter = stream(at: point, image: Sprites.dot, colors: [trail.color, Theme.ui(.sun)], rate: 70, scale: 0.3, spread: 8)
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
            trail.emitter = stream(at: point, image: Sprites.dot, colors: [trail.color, .white], rate: 50, scale: 0.35, spread: 4)
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
            cell.lifetime = 0.6
            cell.lifetimeRange = 0.2
            cell.velocity = 18
            cell.velocityRange = 14
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
        let seconds = trail.kind == .line ? Theme.Motion.trailFade : 0.55
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

    private func startFall() {
        guard let settings else { return }
        if fall != nil { return }
        let emitter = CAEmitterLayer()
        emitter.renderMode = .unordered
        let kind = settings.fall
        func cell(_ image: CGImage?, _ color: UIColor) -> CAEmitterCell {
            let cell = CAEmitterCell()
            cell.contents = image
            cell.color = color.cgColor
            return cell
        }
        switch kind {
        case .stars:
            emitter.emitterShape = .rectangle
            emitter.emitterCells = [UIColor(red: 1, green: 0.96, blue: 0.76, alpha: 1), style.thumb(.left)].map { color in
                let c = cell(Sprites.twinkle, color)
                c.birthRate = 4
                c.lifetime = 1.4
                c.lifetimeRange = 0.5
                c.scale = 0.25
                c.scaleRange = 0.15
                c.scaleSpeed = 0.15
                c.alphaSpeed = -0.7
                c.spin = 1
                c.spinRange = 2
                return c
            }
        case .snow:
            emitter.emitterShape = .line
            let c = cell(Sprites.dot, snowColor.withAlphaComponent(0.9))
            c.birthRate = 9
            c.lifetime = 6
            c.velocity = 26
            c.velocityRange = 14
            c.emissionLongitude = .pi / 2
            c.emissionRange = .pi / 8
            c.yAcceleration = 4
            c.xAcceleration = -2
            c.scale = 0.3
            c.scaleRange = 0.18
            emitter.emitterCells = [c]
        case .confetti:
            emitter.emitterShape = .line
            emitter.emitterCells = [Theme.ui(.right), Theme.ui(.sun), Theme.ui(.mint), Theme.ui(.left), UIColor(red: 0.48, green: 0.38, blue: 1, alpha: 1)].map { color in
                let c = cell(Sprites.confetti, color)
                c.birthRate = 1.8
                c.lifetime = 5
                c.velocity = 50
                c.velocityRange = 25
                c.emissionLongitude = .pi / 2
                c.emissionRange = .pi / 6
                c.yAcceleration = 18
                c.scale = 0.7
                c.scaleRange = 0.3
                c.spin = 3
                c.spinRange = 4
                return c
            }
        }
        emitter.beginTime = CACurrentMediaTime()
        fall = emitter
        fallKind = kind
        layer.insertSublayer(emitter, at: 0)
        layoutFall()
    }

    private func layoutFall() {
        guard let fall else { return }
        let bounds = layer.bounds
        fall.frame = bounds
        if fallKind == .stars {
            fall.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
            fall.emitterSize = bounds.size
        } else {
            fall.emitterPosition = CGPoint(x: bounds.midX, y: -6)
            fall.emitterSize = CGSize(width: bounds.width, height: 1)
        }
    }

    private func stopFall() {
        guard let fall else { return }
        fall.birthRate = 0
        self.fall = nil
        fallKind = nil
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            fall.removeFromSuperlayer()
        }
    }

    private func removeFall() {
        fall?.removeFromSuperlayer()
        fall = nil
        fallKind = nil
    }

    // MARK: Aurora: the sky

    private func showSky() {
        skyGoneAt = nil
        if sky == nil {
            guard let metal = MetalKeyboard.shared, let host else { return }
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
