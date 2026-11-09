#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// The mic at the bar's right end (features/dictation, DESIGN "Where the mic goes"). It
/// stays the same view while listening, so a finger holding it keeps its touch:
///
/// - off: the mic, dimmed like the bar's other buttons;
/// - ready: the same, with a small mint dot (the mic is on, a tap listens at once);
/// - starting or listening by a tap: a mint circle with ✓ (Done);
/// - held: a coral circle with the mic, pulsing ("Let go to stop").
///
/// A finger down sends `.down` at once (a hold hears from the start), and `.up` when it
/// lifts, wherever it is then.
public final class MicButton: UIControl {
    public var onAction: ((MicAction) -> Void)?

    public var status: MicStatus = .off {
        didSet { if status != oldValue { render() } }
    }
    /// The dimmed ink of the bar's other buttons.
    public var ink: UIColor = .gray {
        didSet { if ink != oldValue { render() } }
    }
    /// Small, as in the split's middle column.
    public var small = false {
        didSet { if small != oldValue { render() } }
    }

    private let icon = UIImageView()
    private let disc = UIView()
    private let dot = UIView()
    private var pulsing = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        disc.isUserInteractionEnabled = false
        addSubview(disc)
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        addSubview(icon)
        dot.backgroundColor = Theme.ui(.mint)
        dot.isUserInteractionEnabled = false
        addSubview(dot)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(down), for: .touchDown)
        addTarget(self, action: #selector(up), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        render()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func down() {
        pop()
        onAction?(.down)
    }

    @objc private func up() {
        onAction?(.up)
    }

    /// VoiceOver's double tap: down and up at once (a tap).
    public override func accessibilityActivate() -> Bool {
        onAction?(.down)
        onAction?(.up)
        return true
    }

    /// The mic pops when touched (a spring); not under Reduce Motion.
    private func pop() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.5,
                       options: [.allowUserInteraction]) {
            self.transform = .identity
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height, small ? 32 : 40)
        disc.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        disc.layer.cornerRadius = side / 2
        icon.frame = bounds
        let d: CGFloat = 8
        dot.frame = CGRect(x: bounds.midX + 5, y: bounds.midY - 13, width: d, height: d)
        dot.layer.cornerRadius = d / 2
    }

    private func render() {
        let size: CGFloat = small ? 15 : 17
        let symbol: String
        let tint: UIColor
        var discColor: UIColor = .clear
        var pulse = false
        switch status {
        case .hidden, .off, .ready:
            symbol = "mic"
            tint = ink
        case .starting, .listening(held: false):
            symbol = "checkmark"
            tint = .white
            discColor = Theme.ui(.mint)
        case .listening(held: true):
            symbol = "mic.fill"
            tint = .white
            discColor = Theme.ui(.right)
            pulse = true
        }
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .bold))
        icon.tintColor = tint
        disc.backgroundColor = discColor
        dot.isHidden = status != .ready
        setPulsing(pulse)
        switch status {
        case .hidden, .off:
            accessibilityLabel = "Dictate"
            accessibilityHint = "Double tap to start. Double tap and hold to talk."
        case .ready:
            accessibilityLabel = "Dictate, mic ready"
            accessibilityHint = "Double tap to start. Double tap and hold to talk."
        case .starting, .listening(held: false):
            accessibilityLabel = "Done"
            accessibilityHint = "Stops listening and keeps the words"
        case .listening(held: true):
            accessibilityLabel = "Let go to stop"
            accessibilityHint = nil
        }
        setNeedsLayout()
    }

    /// A soft coral ring breathing out while held; still under Reduce Motion.
    private func setPulsing(_ on: Bool) {
        guard on != pulsing else { return }
        pulsing = on
        disc.layer.removeAnimation(forKey: "pulse")
        disc.layer.borderWidth = on ? 4 : 0
        disc.layer.borderColor = Theme.ui(.right).withAlphaComponent(0.3).cgColor
        guard on, !UIAccessibility.isReduceMotionEnabled else { return }
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1
        pulse.toValue = 1.1
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        disc.layer.add(pulse, forKey: "pulse")
    }
}

/// The listening strip's wave (DESIGN "Listening state"): coral bars across the bar's
/// middle that follow the voice, newest on the right. Under Reduce Motion, one steady
/// bar whose length is the level.
public final class WaveView: UIView {
    /// How loud it is now, 0 to 1 (`DictationState.level`).
    public var level: Double = 0

    private var bars: [CALayer] = []
    private var history: [Double] = []
    private var link: CADisplayLink?
    private let steady = CALayer()
    private static let barWidth: CGFloat = 3
    private static let gap: CGFloat = 3

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = "Listening"
        steady.backgroundColor = Theme.ui(.right).cgColor
        steady.cornerRadius = 3
        layer.addSublayer(steady)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateLink()
    }

    public override var isHidden: Bool {
        didSet { updateLink() }
    }

    /// Runs only while on screen.
    private func updateLink() {
        let running = window != nil && !isHidden
        if running, link == nil {
            let link = CADisplayLink(target: WeakTarget(self), selector: #selector(WeakTarget.step))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 24)
            link.add(to: .main, forMode: .common)
            self.link = link
        } else if !running {
            link?.invalidate()
            link = nil
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let count = max(0, Int((bounds.width + Self.gap) / (Self.barWidth + Self.gap)))
        if bars.count != count {
            bars.forEach { $0.removeFromSuperlayer() }
            bars = (0..<count).map { _ in
                let bar = CALayer()
                bar.backgroundColor = Theme.ui(.right).cgColor
                bar.cornerRadius = Self.barWidth / 2
                layer.addSublayer(bar)
                return bar
            }
            history = Array(history.suffix(count))
        }
        draw()
    }

    fileprivate func step() {
        // Each frame the newest bar takes the level, a little uneven like a voice.
        let jitter = Double.random(in: 0.7...1.15)
        history.append(min(1, level * jitter))
        if history.count > bars.count { history.removeFirst(history.count - bars.count) }
        draw()
    }

    private func draw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let reduce = UIAccessibility.isReduceMotionEnabled
        steady.isHidden = !reduce
        let height = bounds.height
        if reduce {
            bars.forEach { $0.isHidden = true }
            let width = max(6, bounds.width * CGFloat(level))
            steady.frame = CGRect(x: bounds.midX - width / 2, y: bounds.midY - 3, width: width, height: 6)
        } else {
            let total = CGFloat(bars.count) * (Self.barWidth + Self.gap) - Self.gap
            var x = bounds.midX - total / 2
            let offset = bars.count - history.count
            for (i, bar) in bars.enumerated() {
                let value = i >= offset ? history[i - offset] : 0
                let h = min(height, 5 + CGFloat(value) * (height - 5))
                bar.isHidden = false
                bar.frame = CGRect(x: x, y: (height - h) / 2, width: Self.barWidth, height: h)
                x += Self.barWidth + Self.gap
            }
        }
        CATransaction.commit()
    }

    /// The display link holds its target strongly; this keeps the wave free to go.
    @MainActor
    private final class WeakTarget: NSObject {
        weak var wave: WaveView?
        init(_ wave: WaveView) { self.wave = wave }
        @objc func step() { wave?.step() }
    }
}
#endif
