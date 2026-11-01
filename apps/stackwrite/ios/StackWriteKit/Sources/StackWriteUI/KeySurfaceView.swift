#if canImport(UIKit)
import StackWriteCore
import UIKit

@MainActor
public protocol KeySurfaceDelegate: AnyObject {
    /// A finger landed on a letter key. `id` names the touch until it lifts.
    func keySurface(_ surface: KeySurfaceView, touchBegan id: Int, at point: CGPoint, time: TimeInterval)
    func keySurface(_ surface: KeySurfaceView, touchMoved id: Int, to point: CGPoint, time: TimeInterval)
    func keySurface(_ surface: KeySurfaceView, touchEnded id: Int, at point: CGPoint, time: TimeInterval)
    func keySurface(_ surface: KeySurfaceView, touchCancelled id: Int, time: TimeInterval)
    /// A finger tapped a key that is not a letter (landed and lifted on it). Backspace
    /// held down repeats this.
    func keySurface(_ surface: KeySurfaceView, didTap key: Key, side: Side)
    /// A finger slid along the space bar by `steps` more characters (negative is left).
    func keySurface(_ surface: KeySurfaceView, didSlideSpace steps: Int)
    /// A finger swiped left from backspace.
    func keySurfaceDidSwipeBackspace(_ surface: KeySurfaceView)
    /// A finger held the "123" key.
    func keySurfaceDidHoldNumbers(_ surface: KeySurfaceView)
}

/// The keys. One UIKit view that draws a `Layout` and reports touches, with multitouch
/// on so each thumb is its own touch. Letter keys stream their touches (down, moves,
/// up) so the engine can tell taps from swipes; the other keys report a tap, or one of
/// the keyboard's gestures (DESIGN.md "The keyboard"): a slide on space moves the
/// cursor, a swipe left from backspace deletes a word, backspace held repeats, "123"
/// held opens the settings. Keys flash in the thumb's colour (teal left, coral right),
/// taps leave a ring that pings out, swipes draw a trail that fades after lift.
///
///     let surface = KeySurfaceView()
///     surface.delegate = self
///     surface.layout = Layout.qwerty(width: view.bounds.width)
public final class KeySurfaceView: UIView {
    public weak var delegate: KeySurfaceDelegate?

    public var layout = Layout.qwerty(width: 390) {
        didSet { if layout != oldValue { rebuild() } }
    }

    /// Draw letters as capitals.
    public var shifted = false {
        didSet { keyViews.values.forEach { $0.shifted = shifted } }
    }

    /// What the space bar says when idle.
    public var spaceLabel = "StackWrite" {
        didSet { keyViews[.space]?.label.text = spaceLabel }
    }

    /// Draw swipe trails and tap rings.
    public var showsTrails = true

    /// How far a finger slides on space for one cursor step.
    public static let cursorStep: CGFloat = 12
    /// How far left of backspace a swipe has to travel to delete a word.
    public static let wordSwipe: CGFloat = 40
    static let holdDelay: TimeInterval = 0.45
    static let repeatInterval: TimeInterval = 0.09

    private struct Active {
        var id: Int
        var key: Key?
        let startKey: Key
        let startPoint: CGPoint
        var side: Side
        var isLetter: Bool
        var points: [CGPoint]
        var trail: CAShapeLayer?
        /// Cursor steps already reported for a slide on space.
        var slideSteps = 0
        /// A slide, a swipe or a hold took this touch: no tap when it lifts.
        var gestured = false
        var hold: Task<Void, Never>?
    }

    private var keyViews: [Key: KeyView] = [:]
    private var active: [ObjectIdentifier: Active] = [:]
    private var nextID = 1
    private let effects = CALayer()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = Theme.ui(.kb)
        rebuild()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: layout.height)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        effects.frame = bounds
    }

    private func rebuild() {
        keyViews.values.forEach { $0.removeFromSuperview() }
        keyViews = [:]
        for placement in layout.placements {
            let keyView = KeyView(key: placement.key, spaceLabel: spaceLabel)
            keyView.frame = placement.frame
            keyView.shifted = shifted
            addSubview(keyView)
            keyViews[placement.key] = keyView
        }
        effects.removeFromSuperlayer()
        effects.frame = bounds
        layer.addSublayer(effects)
        invalidateIntrinsicContentSize()
    }

    // MARK: Touches

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let key = layout.key(at: point) else { continue }
            let side = layout.side(at: point)
            let id = nextID
            nextID += 1
            let oid = ObjectIdentifier(touch)
            var touchState = Active(id: id, key: key, startKey: key, startPoint: point, side: side, isLetter: key.character != nil, points: [point], trail: nil)
            keyViews[key]?.flash(side: side)
            switch key {
            case .backspace:
                touchState.hold = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.holdDelay))
                    while !Task.isCancelled {
                        guard let self, self.active[oid] != nil else { return }
                        self.active[oid]?.gestured = true
                        self.delegate?.keySurface(self, didTap: .backspace, side: side)
                        try? await Task.sleep(for: .seconds(Self.repeatInterval))
                    }
                }
            case .numbers:
                touchState.hold = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.holdDelay))
                    guard !Task.isCancelled, let self, let state = self.active[oid], !state.gestured else { return }
                    self.active[oid]?.gestured = true
                    self.keyViews[.numbers]?.unflash()
                    self.delegate?.keySurfaceDidHoldNumbers(self)
                }
            default:
                break
            }
            active[oid] = touchState
            if key.character != nil {
                delegate?.keySurface(self, touchBegan: id, at: point, time: touch.timestamp)
            }
        }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let oid = ObjectIdentifier(touch)
            guard var touchState = active[oid] else { continue }
            let point = touch.location(in: self)
            if touchState.isLetter {
                let now = layout.key(at: point)
                if now != touchState.key {
                    if let was = touchState.key { keyViews[was]?.unflash() }
                    if let now { keyViews[now]?.flash(side: touchState.side) }
                    touchState.key = now
                }
                touchState.points.append(point)
                if showsTrails { drawTrail(&touchState) }
                active[oid] = touchState
                delegate?.keySurface(self, touchMoved: touchState.id, to: point, time: touch.timestamp)
                continue
            }
            switch touchState.startKey {
            case .space:
                let steps = Int((point.x - touchState.startPoint.x) / Self.cursorStep)
                if steps != touchState.slideSteps {
                    touchState.gestured = true
                    delegate?.keySurface(self, didSlideSpace: steps - touchState.slideSteps)
                    touchState.slideSteps = steps
                }
            case .backspace:
                if !touchState.gestured, touchState.startPoint.x - point.x >= Self.wordSwipe {
                    touchState.gestured = true
                    touchState.hold?.cancel()
                    delegate?.keySurfaceDidSwipeBackspace(self)
                }
            default:
                let now = layout.key(at: point)
                if now != touchState.key {
                    if let was = touchState.key { keyViews[was]?.unflash() }
                    if let now { keyViews[now]?.flash(side: touchState.side) }
                    touchState.key = now
                    if touchState.startKey == .numbers { touchState.hold?.cancel() }
                }
            }
            active[oid] = touchState
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let touchState = active.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            touchState.hold?.cancel()
            let point = touch.location(in: self)
            if let key = touchState.key { keyViews[key]?.unflash() }
            if touchState.isLetter {
                if showsTrails { finish(touchState, at: point) }
                delegate?.keySurface(self, touchEnded: touchState.id, at: point, time: touch.timestamp)
            } else if !touchState.gestured, let key = touchState.key {
                delegate?.keySurface(self, didTap: key, side: touchState.side)
            }
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let touchState = active.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            touchState.hold?.cancel()
            if let key = touchState.key { keyViews[key]?.unflash() }
            touchState.trail?.removeFromSuperlayer()
            if touchState.isLetter {
                delegate?.keySurface(self, touchCancelled: touchState.id, time: touch.timestamp)
            }
        }
    }

    // MARK: Trails and rings

    private func drawTrail(_ touchState: inout Active) {
        let path = UIBezierPath()
        path.move(to: touchState.points[0])
        for point in touchState.points.dropFirst() { path.addLine(to: point) }
        if touchState.trail == nil {
            let trail = CAShapeLayer()
            trail.fillColor = nil
            trail.strokeColor = Theme.ui(touchState.side == .left ? .left : .right).cgColor
            trail.lineWidth = 9
            trail.lineCap = .round
            trail.lineJoin = .round
            trail.opacity = 0.85
            effects.addSublayer(trail)
            touchState.trail = trail
        }
        touchState.trail?.path = path.cgPath
    }

    private func finish(_ touchState: Active, at point: CGPoint) {
        if let trail = touchState.trail {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.85
            fade.toValue = 0
            fade.duration = Theme.Motion.trailFade
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            CATransaction.begin()
            CATransaction.setCompletionBlock { trail.removeFromSuperlayer() }
            trail.add(fade, forKey: "fade")
            CATransaction.commit()
        } else {
            let ring = CAShapeLayer()
            let radius: CGFloat = 14
            ring.bounds = CGRect(x: 0, y: 0, width: 2 * radius, height: 2 * radius)
            ring.position = point
            ring.path = UIBezierPath(ovalIn: ring.bounds).cgPath
            ring.fillColor = nil
            ring.strokeColor = Theme.ui(touchState.side == .left ? .left : .right).cgColor
            ring.lineWidth = 2
            effects.addSublayer(ring)
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.5
            grow.toValue = 1.6
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [grow, fade]
            group.duration = Theme.Motion.tapRing
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            CATransaction.begin()
            CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
            ring.add(group, forKey: "ping")
            CATransaction.commit()
        }
    }
}

/// One key: a rounded face with a letter or a symbol.
final class KeyView: UIView {
    let key: Key
    let label = UILabel()
    var shifted = false { didSet { label.text = text } }

    private let spaceLabel: String

    init(key: Key, spaceLabel: String) {
        self.key = key
        self.spaceLabel = spaceLabel
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = Theme.Radius.key
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        backgroundColor = Theme.ui(key.isFunction ? .keyDark : .key)
        label.textAlignment = .center
        label.textColor = Theme.ui(key == .space ? .muted : .keyInk)
        label.font = Theme.uiFont(size: fontSize, weight: key == .space ? .heavy : key.isFunction ? .medium : .bold)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.text = text
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 0)
    }

    private var fontSize: CGFloat {
        switch key {
        case .letter, .symbol: 21
        case .space: 13
        case .shift, .backspace: 18
        default: 14
        }
    }

    private var text: String {
        switch key {
        case .letter(let c): shifted ? String(c).uppercased() : String(c)
        case .symbol(let c): String(c)
        case .shift: "⇧"
        case .backspace: "⌫"
        case .numbers: "123"
        case .symbols: "#+="
        case .letters: "ABC"
        case .globe: "🌐"
        case .space: spaceLabel
        case .returnKey: "return"
        }
    }

    func flash(side: Side) {
        backgroundColor = Theme.ui(side == .left ? .left : .right)
        label.textColor = .white
        UIView.animate(withDuration: Theme.Motion.keyHit, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) {
            self.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
        }
    }

    func unflash() {
        UIView.animate(withDuration: 0.25) {
            self.backgroundColor = Theme.ui(self.key.isFunction ? .keyDark : .key)
            self.label.textColor = Theme.ui(self.key == .space ? .muted : .keyInk)
            self.transform = .identity
        }
    }
}
#endif
