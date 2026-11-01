#if canImport(UIKit)
import StackWriteCore
import UIKit

/// The bar above the keys, in its three states (DESIGN.md "The bar"): an idle note,
/// the guesses for the open word with the chosen one in a pill, or FIX with the other
/// readings of the word just written.
///
///     bar.bar = model.state.bar
///     bar.onChoose = { index in model.choose(guess: index) }
public final class BarView: UIView {
    public var onChoose: ((Int) -> Void)?

    /// What the bar says when idle.
    public var note = "Both thumbs, one word" {
        didSet { if case .idle = bar { render() } }
    }

    public var bar: Composer.Bar = .idle {
        didSet { if bar != oldValue { render() } }
    }

    private let label = UILabel()
    private let tag = UILabel()
    private let stack = UIStackView()
    private var indices: [Int] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.ui(.kb)

        label.font = Theme.uiFont(size: 13, weight: .bold)
        label.textColor = Theme.ui(.muted)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        addSubview(label)

        tag.font = Theme.uiFont(size: 11, weight: .black)
        tag.textColor = Theme.ui(.accent)
        tag.text = "FIX"
        tag.accessibilityLabel = "Fix the last word"
        addSubview(tag)

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
            tag.sizeToFit()
            tag.frame = CGRect(x: inset.minX + Theme.Space.xs, y: 0, width: tag.bounds.width, height: inset.height)
            let x = tag.frame.maxX + Theme.Space.m
            stack.frame = CGRect(x: x, y: 0, width: inset.maxX - x, height: inset.height)
        } else {
            stack.frame = inset
        }
    }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        indices = []
        switch bar {
        case .idle:
            label.text = note
            label.isHidden = false
            tag.isHidden = true
            stack.isHidden = true
        case .guesses(let words, let chosen):
            label.isHidden = true
            tag.isHidden = true
            stack.isHidden = false
            for (i, word) in words.enumerated() {
                add(word, index: i, chosen: i == chosen)
            }
        case .fix(let words, let chosen):
            label.isHidden = true
            tag.isHidden = false
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
        stack.addArrangedSubview(button)
    }
}
#endif
