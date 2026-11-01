#if canImport(UIKit)
import StackWriteCore
import UIKit

@MainActor
public protocol KeySurfaceDelegate: AnyObject {
    /// A finger tapped a key (landed and lifted on it). `side` is the thumb it came from.
    func keySurface(_ surface: KeySurfaceView, didTap key: Key, side: Side)
}

/// The keys. One UIKit view that draws a `Layout` and reports taps, with multitouch on
/// so each thumb is its own touch. Keys flash in the thumb's colour (teal left, coral
/// right). Swipes and trails come in Phase 2.
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

    private var keyViews: [Key: KeyView] = [:]
    private var touchKeys: [ObjectIdentifier: Key] = [:]

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
        invalidateIntrinsicContentSize()
    }

    // MARK: Touches

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let key = layout.key(at: point) else { continue }
            touchKeys[ObjectIdentifier(touch)] = key
            keyViews[key]?.flash(side: layout.side(at: point))
        }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let was = touchKeys[id] else { continue }
            let point = touch.location(in: self)
            let now = layout.key(at: point)
            if now != was {
                keyViews[was]?.unflash()
                if let now {
                    keyViews[now]?.flash(side: layout.side(at: point))
                }
                touchKeys[id] = now
            }
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let point = touch.location(in: self)
            if let key = touchKeys.removeValue(forKey: id) {
                keyViews[key]?.unflash()
                delegate?.keySurface(self, didTap: key, side: layout.side(at: point))
            }
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let key = touchKeys.removeValue(forKey: ObjectIdentifier(touch)) {
                keyViews[key]?.unflash()
            }
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
        backgroundColor = Theme.ui(key.character == nil && key != .space ? .keyDark : .key)
        label.textAlignment = .center
        label.textColor = Theme.ui(key == .space ? .muted : .keyInk)
        label.font = Theme.uiFont(size: fontSize, weight: key == .space ? .heavy : key.character == nil ? .medium : .bold)
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
        case .letter: 21
        case .space: 13
        case .shift, .backspace: 18
        default: 14
        }
    }

    private var text: String {
        switch key {
        case .letter(let c): shifted ? String(c).uppercased() : String(c)
        case .shift: "⇧"
        case .backspace: "⌫"
        case .numbers: "123"
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
            self.backgroundColor = Theme.ui(self.key.character == nil && self.key != .space ? .keyDark : .key)
            self.label.textColor = Theme.ui(self.key == .space ? .muted : .keyInk)
            self.transform = .identity
        }
    }
}
#endif
