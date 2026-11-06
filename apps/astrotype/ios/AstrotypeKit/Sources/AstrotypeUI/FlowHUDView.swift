#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// What flow shows over the keyboard (features/customization "Motion"): the meter, a
/// 3 pt line along the top of the keys; the combo count (×12) at the bar's trailing end
/// from Waddle; and each new level's name popping on the bar. Takes no touches.
///
///     hud.style = surface.style
///     surface.onFlow = { hud.state = $0 }
public final class FlowHUDView: UIView {
    public var state = FlowState.off {
        didSet { if state != oldValue { update(from: oldValue) } }
    }
    public var style = KeyStyle.classic {
        didSet { if style != oldValue { recolour() } }
    }
    /// Where the keys start, from the view's top: the meter runs along it and the bar
    /// is above it.
    public var keysTop: CGFloat = 44 {
        didSet { if keysTop != oldValue { setNeedsLayout() } }
    }

    private let track = CALayer()
    private let meter = CAGradientLayer()
    private let combo = UILabel()
    private let comboPill = UIView()
    private let pop = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(track)
        meter.startPoint = CGPoint(x: 0, y: 0.5)
        meter.endPoint = CGPoint(x: 1, y: 0.5)
        meter.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer.addSublayer(meter)
        comboPill.layer.cornerRadius = 9
        comboPill.alpha = 0
        combo.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        combo.textAlignment = .center
        comboPill.addSubview(combo)
        addSubview(comboPill)
        pop.font = Theme.uiFont(size: 22, weight: .heavy)
        pop.textAlignment = .center
        pop.alpha = 0
        pop.layer.shadowOpacity = 0.5
        pop.layer.shadowRadius = 6
        pop.layer.shadowOffset = .zero
        addSubview(pop)
        track.opacity = 0
        meter.opacity = 0
        recolour()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = CGRect(x: 0, y: keysTop - 1.5, width: bounds.width, height: 3)
        meter.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: 3)
        meter.position = CGPoint(x: 0, y: keysTop)
        CATransaction.commit()
        let text = combo.text ?? ""
        let width = max(34, (text as NSString).size(withAttributes: [.font: combo.font!]).width + 14)
        comboPill.frame = CGRect(x: bounds.width - width - 8, y: max(0, keysTop - 26), width: width, height: 18)
        combo.frame = comboPill.bounds
        pop.frame = CGRect(x: 0, y: max(0, keysTop - 40), width: bounds.width, height: 36)
    }

    /// The colour of a level: the meter fills toward it and its name pops in it.
    func colour(of level: FlowLevel) -> UIColor {
        switch level {
        case .calm: style.thumb(.left)
        case .waddle: style.thumb(.right)
        case .toboggan: style.accent
        case .blizzard: UIColor(red: 0.56, green: 0.89, blue: 1, alpha: 1)
        case .aurora: UIColor(red: 0.49, green: 0.95, blue: 0.69, alpha: 1)
        }
    }

    private func recolour() {
        let next = FlowLevel(rawValue: min(state.level.rawValue + 1, 4)) ?? .aurora
        meter.colors = [style.thumb(.left).cgColor, colour(of: next).cgColor]
        track.backgroundColor = UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: style.interfaceStyle))
            .withAlphaComponent(0.1).cgColor
        comboPill.backgroundColor = colour(of: state.level).withAlphaComponent(0.9)
        combo.textColor = colour(of: state.level).isLight ? .black : .white
    }

    private func update(from old: FlowState) {
        recolour()
        let showsMeter = state.isOn && state.isActive
        fade(track, to: showsMeter ? 1 : 0)
        fade(meter, to: showsMeter ? 1 : 0)
        let fill = state.level == .aurora && state.progress >= 1 ? 1 : state.progress
        let animation = CABasicAnimation(keyPath: "transform.scale.x")
        animation.fromValue = meter.presentation()?.value(forKeyPath: "transform.scale.x") ?? meter.value(forKeyPath: "transform.scale.x")
        animation.toValue = fill
        animation.duration = 0.25
        meter.setValue(max(0.0001, fill), forKeyPath: "transform.scale.x")
        meter.add(animation, forKey: "fill")

        if state.showsCombo {
            combo.text = "×\(state.combo)"
            setNeedsLayout()
            if !old.showsCombo {
                comboPill.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8) {
                    self.comboPill.alpha = 1
                    self.comboPill.transform = .identity
                }
            }
        } else if old.showsCombo {
            UIView.animate(withDuration: 0.25) { self.comboPill.alpha = 0 }
        }

        if state.leveledUp, state.level != .calm, !UIAccessibility.isReduceMotionEnabled {
            popLevel(state.level)
        }
    }

    /// The level's name pops with a spring, holds, then floats up and fades (1.1 s).
    private func popLevel(_ level: FlowLevel) {
        pop.layer.removeAllAnimations()
        pop.text = "\(level.name)!"
        pop.textColor = colour(of: level)
        pop.layer.shadowColor = colour(of: level).cgColor
        pop.alpha = 0
        pop.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 1) {
            self.pop.alpha = 1
            self.pop.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.5, delay: 0.25, options: [.curveEaseIn]) {
                self.pop.alpha = 0
                self.pop.transform = CGAffineTransform(translationX: 0, y: -18)
            }
        }
    }

    private func fade(_ layer: CALayer, to value: Float) {
        guard layer.opacity != value else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = value
        animation.duration = 0.3
        layer.opacity = value
        layer.add(animation, forKey: "fade")
    }
}

private extension UIColor {
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.6
    }
}
#endif
