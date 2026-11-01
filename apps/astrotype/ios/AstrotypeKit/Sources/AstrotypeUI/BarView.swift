#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// The bar above the keys, in its three states (DESIGN.md "The bar"): an idle note,
/// the guesses for the open word with the chosen one in a pill, or FIX with the other
/// readings of the word just written. Holding a guess and sliding up boosts it, down
/// forgets it (DESIGN.md "Learning").
///
///     bar.bar = model.state.bar
///     bar.onChoose = { index in model.choose(guess: index) }
///     bar.onBoost = { index in model.boost(guess: index) }
public final class BarView: UIView {
    public var onChoose: ((Int) -> Void)?
    public var onBoost: ((Int) -> Void)?
    public var onForget: ((Int) -> Void)?

    /// How far a held guess slides before it counts as a boost (up) or a forget (down).
    static let slideDistance: CGFloat = 22

    /// What the bar says when idle.
    public var note = "Both thumbs, one word" {
        didSet { if case .idle = bar { render() } }
    }

    public var bar: Composer.Bar = .idle {
        didSet { if bar != oldValue { render() } }
    }

    /// A line shown over whatever the bar has, for a moment (DESIGN.md "Free mode":
    /// "Two thumbs is in Astrotype Pro" for 1.6 s). Nothing shakes, nothing is lost.
    public func flash(_ text: String, for seconds: TimeInterval = 1.6) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private var notice: String? {
        didSet { if notice != oldValue { render() } }
    }
    private var noticeTask: Task<Void, Never>?

    private let label = UILabel()
    private let fixLabel = UILabel()
    private let stack = UIStackView()
    private var indices: [Int] = []
    private var holdStart: CGPoint?
    private var holdVerdict: Verdict?
    private let holdHaptic = UISelectionFeedbackGenerator()

    private enum Verdict { case boost, forget }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.ui(.kb)

        label.font = Theme.uiFont(size: 13, weight: .bold)
        label.textColor = Theme.ui(.muted)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        addSubview(label)

        fixLabel.font = Theme.uiFont(size: 11, weight: .black)
        fixLabel.textColor = Theme.ui(.accent)
        fixLabel.text = "FIX"
        fixLabel.accessibilityLabel = "Fix the last word"
        addSubview(fixLabel)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalCentering
        stack.spacing = Theme.Space.s
        stack.accessibilityLabel = "Suggestions"
        addSubview(stack)
        render()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let inset = bounds.insetBy(dx: Theme.Space.s, dy: 0)
        label.frame = inset
        if case .fix = bar {
            fixLabel.sizeToFit()
            fixLabel.frame = CGRect(x: inset.minX + Theme.Space.xs, y: 0, width: fixLabel.bounds.width, height: inset.height)
            let x = fixLabel.frame.maxX + Theme.Space.m
            stack.frame = CGRect(x: x, y: 0, width: inset.maxX - x, height: inset.height)
        } else {
            stack.frame = inset
        }
    }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        indices = []
        if let notice {
            label.text = notice
            label.isHidden = false
            fixLabel.isHidden = true
            stack.isHidden = true
            setNeedsLayout()
            return
        }
        switch bar {
        case .idle:
            label.text = note
            label.isHidden = false
            fixLabel.isHidden = true
            stack.isHidden = true
        case .guesses(let words, let chosen):
            label.isHidden = true
            fixLabel.isHidden = true
            stack.isHidden = false
            for (i, word) in words.enumerated() {
                add(word, index: i, chosen: i == chosen)
            }
        case .fix(let words, let chosen):
            label.isHidden = true
            fixLabel.isHidden = false
            stack.isHidden = false
            for (i, word) in words.enumerated() where i != chosen {
                add(word, index: i, chosen: false)
            }
        }
        setNeedsLayout()
    }

    private func add(_ word: String, index: Int, chosen: Bool) {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.m, bottom: 6, trailing: Theme.Space.m)
        config.background.cornerRadius = 16
        config.background.backgroundColor = chosen ? Theme.ui(.card) : .clear
        config.attributedTitle = AttributedString(word, attributes: AttributeContainer([
            .font: Theme.uiFont(size: 16, weight: chosen ? .bold : .semibold),
            .foregroundColor: Theme.ui(chosen ? .ink : .muted),
        ]))
        let button = UIButton(configuration: config)
        button.accessibilityLabel = word
        if chosen { button.accessibilityTraits.insert(.selected) }
        button.tag = indices.count
        indices.append(index)
        button.addAction(UIAction { [weak self] action in
            guard let self, let button = action.sender as? UIButton, self.indices.indices.contains(button.tag) else { return }
            self.onChoose?(self.indices[button.tag])
        }, for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.35
        hold.allowableMovement = 60
        button.addGestureRecognizer(hold)
        stack.addArrangedSubview(button)
    }

    // MARK: Hold and slide

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? UIButton, indices.indices.contains(button.tag) else { return }
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            holdStart = point
            holdVerdict = nil
            holdHaptic.prepare()
            holdHaptic.selectionChanged()
            paint(button, verdict: nil, held: true)
        case .changed:
            guard let start = holdStart else { return }
            let dy = point.y - start.y
            let verdict: Verdict? = dy <= -Self.slideDistance ? .boost : dy >= Self.slideDistance ? .forget : nil
            if verdict != holdVerdict {
                holdVerdict = verdict
                if verdict != nil { holdHaptic.selectionChanged() }
                paint(button, verdict: verdict, held: true)
            }
        case .ended:
            let index = indices[button.tag]
            let verdict = holdVerdict
            holdStart = nil
            holdVerdict = nil
            paint(button, verdict: nil, held: false)
            switch verdict {
            case .boost: onBoost?(index)
            case .forget: onForget?(index)
            case nil: break
            }
        default:
            holdStart = nil
            holdVerdict = nil
            paint(button, verdict: nil, held: false)
        }
    }

    /// A held guess shows what letting go would do: mint to keep it, coral to drop it.
    private func paint(_ button: UIButton, verdict: Verdict?, held: Bool) {
        guard var config = button.configuration else { return }
        let chosen = button.accessibilityTraits.contains(.selected)
        let background: UIColor
        let ink: UIColor
        switch verdict {
        case .boost:
            background = Theme.ui(.mint)
            ink = Theme.ui(.accentInk)
        case .forget:
            background = Theme.ui(.right)
            ink = Theme.ui(.accentInk)
        case nil:
            background = held ? Theme.ui(.ice) : (chosen ? Theme.ui(.card) : .clear)
            ink = Theme.ui(chosen ? .ink : .muted)
        }
        config.background.backgroundColor = background
        config.attributedTitle = AttributedString(button.accessibilityLabel ?? "", attributes: AttributeContainer([
            .font: Theme.uiFont(size: 16, weight: chosen ? .bold : .semibold),
            .foregroundColor: ink,
        ]))
        button.configuration = config
        button.transform = held ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
    }
}
#endif
