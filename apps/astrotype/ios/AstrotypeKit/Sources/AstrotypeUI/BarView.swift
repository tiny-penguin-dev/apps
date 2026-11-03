#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// The guesses, in their states (DESIGN.md "The bar"): an idle note, the guesses
/// for the open word with the chosen one in a pill, FIX with the other readings of
/// the word just written, the likely next words with the best other reading of the
/// last word as a FIX chip in front (features/next-word), or the "Not it?" field where
/// the word meant is typed (features/missed-words). After a swiped word a "Not it?"
/// button sits at the end. Holding a guess and sliding up boosts it, down forgets it
/// (DESIGN.md "Learning"). A bar above the keys (`axis` horizontal) or a column beside
/// them (vertical: the middle of a split keyboard, the side of a wide one); in a column,
/// touches between the guesses fall through to the keys under it.
///
///     bar.bar = model.state.bar
///     bar.onChoose = { index in model.choose(guess: index) }
///     bar.onChooseFix = { model.chooseFix() }
///     bar.onBoost = { index in model.boost(guess: index) }
///     bar.canCorrect = model.state.canCorrect
///     bar.onNotIt = { model.beginCorrection() }
public final class BarView: UIView {
    public var onChoose: ((Int) -> Void)?
    /// The FIX chip beside the next words was tapped.
    public var onChooseFix: (() -> Void)?
    /// "Not it?", and the field's ✕ and Save.
    public var onNotIt: (() -> Void)?
    public var onCancelCorrection: (() -> Void)?
    public var onSaveCorrection: (() -> Void)?

    /// Whether to offer "Not it?" (`Composer.State.canCorrect`).
    public var canCorrect = false {
        didSet { if canCorrect != oldValue { render() } }
    }
    public var onBoost: ((Int) -> Void)?
    public var onForget: ((Int) -> Void)?

    /// How far a held guess slides before it counts as a boost (up) or a forget (down).
    static let slideDistance: CGFloat = 22

    /// What the bar says when idle.
    public var note = "Both thumbs, one word" {
        didSet { if case .idle = bar { render() } }
    }

    /// Horizontal: a bar above the keys. Vertical: a column beside them.
    public var axis: NSLayoutConstraint.Axis = .horizontal {
        didSet {
            guard axis != oldValue else { return }
            stack.axis = axis
            stack.distribution = axis == .vertical ? .fill : .equalCentering
            stack.spacing = axis == .vertical ? Theme.Space.xs : Theme.Space.s
            label.numberOfLines = axis == .vertical ? 0 : 1
            setNeedsLayout()
        }
    }

    public var bar: Composer.Bar = .idle {
        didSet {
            guard bar != oldValue else { return }
            render()
            if case .next(let words, _, _) = bar, words != Self.nextWords(of: oldValue) { fadeIn() }
        }
    }

    private static func nextWords(of bar: Composer.Bar) -> [String] {
        if case .next(let words, _, _) = bar { return words }
        return []
    }

    /// New next words rise into place over 0.25 s; at once with Reduce Motion.
    private func fadeIn() {
        guard !UIAccessibility.isReduceMotionEnabled, window != nil else { return }
        stack.alpha = 0
        stack.transform = CGAffineTransform(translationX: 0, y: 4)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.stack.alpha = 1
            self.stack.transform = .identity
        }
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
    private let notItButton = UIButton(configuration: .plain())
    private let cancelButton = UIButton(configuration: .plain())
    private let saveButton = UIButton(configuration: .plain())
    private let fieldLabel = UILabel()
    private let stack = UIStackView()
    private var indices: [Int] = []
    private var holdStart: CGPoint?
    private var holdVerdict: Verdict?
    private let holdHaptic = UISelectionFeedbackGenerator()

    private enum Verdict { case boost, forget }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        // Clear: in a column it lies over the keys' open middle, where trails pass.
        backgroundColor = .clear

        // The bar's text scales one step with the person's text size (DESIGN.md
        // "Accessibility"); the keys do not.
        label.font = Theme.uiFont(size: 13, weight: .bold, scaledWith: .footnote, upTo: 15)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Theme.ui(.muted)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        addSubview(label)

        fixLabel.font = Theme.uiFont(size: 11, weight: .black, scaledWith: .caption2, upTo: 13)
        fixLabel.adjustsFontForContentSizeCategory = true
        fixLabel.textColor = Theme.ui(.accent)
        fixLabel.text = "FIX"
        fixLabel.accessibilityLabel = "Fix the last word"
        addSubview(fixLabel)

        var notIt = UIButton.Configuration.plain()
        notIt.image = UIImage(systemName: "pencil", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        notIt.imagePadding = Theme.Space.xs
        notIt.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.s, bottom: 6, trailing: Theme.Space.s)
        notIt.baseForegroundColor = Theme.ui(.muted)
        notIt.attributedTitle = AttributedString("Not it?", attributes: AttributeContainer([
            .font: Theme.uiFont(size: 13, weight: .bold, scaledWith: .footnote, upTo: 15),
        ]))
        notItButton.configuration = notIt
        notItButton.accessibilityLabel = "Not it? Type the word you meant"
        notItButton.addAction(UIAction { [weak self] _ in self?.onNotIt?() }, for: .touchUpInside)
        addSubview(notItButton)

        var cancel = UIButton.Configuration.plain()
        cancel.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        cancel.baseForegroundColor = Theme.ui(.muted)
        cancelButton.configuration = cancel
        cancelButton.accessibilityLabel = "Cancel"
        cancelButton.addAction(UIAction { [weak self] _ in self?.onCancelCorrection?() }, for: .touchUpInside)
        addSubview(cancelButton)

        saveButton.addAction(UIAction { [weak self] _ in self?.onSaveCorrection?() }, for: .touchUpInside)
        saveButton.accessibilityLabel = "Save"
        addSubview(saveButton)

        fieldLabel.adjustsFontForContentSizeCategory = true
        fieldLabel.lineBreakMode = .byTruncatingHead
        fieldLabel.textAlignment = .center
        fieldLabel.isAccessibilityElement = true
        fieldLabel.accessibilityTraits = .staticText
        addSubview(fieldLabel)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalCentering
        stack.spacing = Theme.Space.s
        stack.accessibilityLabel = "Suggestions"
        addSubview(stack)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: BarView, _: UITraitCollection) in
            self.render()
        }
        render()
    }

    private func guessFont(chosen: Bool) -> UIFont {
        Theme.uiFont(size: 16, weight: chosen ? .bold : .semibold, scaledWith: .body, upTo: 18)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Empty parts of the bar take no touches: in a column over the keys they belong
    /// to the keys.
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self || hit === stack ? nil : hit
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if axis == .vertical {
            layoutColumn()
            return
        }
        var inset = bounds.insetBy(dx: Theme.Space.s, dy: 0)
        if case .correcting = bar {
            let save = saveButton.sizeThatFits(inset.size)
            cancelButton.frame = CGRect(x: inset.minX, y: 0, width: 40, height: inset.height)
            saveButton.frame = CGRect(x: inset.maxX - save.width, y: (inset.height - save.height) / 2, width: save.width, height: save.height)
            fieldLabel.frame = CGRect(x: cancelButton.frame.maxX + Theme.Space.s, y: 0,
                                      width: saveButton.frame.minX - cancelButton.frame.maxX - Theme.Space.m, height: inset.height)
            return
        }
        if !notItButton.isHidden {
            let size = notItButton.sizeThatFits(inset.size)
            notItButton.frame = CGRect(x: inset.maxX - size.width, y: (inset.height - size.height) / 2, width: size.width, height: size.height)
            inset = inset.divided(atDistance: size.width + Theme.Space.xs, from: .maxXEdge).remainder
        }
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

    /// A column: FIX on top when fixing, the guesses stacked and centred under it.
    private func layoutColumn() {
        var area = bounds.insetBy(dx: Theme.Space.xs, dy: Theme.Space.s)
        if case .correcting = bar {
            // The word, then Save, then ✕, stacked in the middle of the column.
            let line = fieldLabel.sizeThatFits(area.size).height
            let save = saveButton.sizeThatFits(area.size)
            let total = line + Theme.Space.s + save.height + Theme.Space.s + 40
            var y = area.midY - total / 2
            fieldLabel.frame = CGRect(x: area.minX, y: y, width: area.width, height: line)
            y += line + Theme.Space.s
            saveButton.frame = CGRect(x: area.midX - save.width / 2, y: y, width: save.width, height: save.height)
            y += save.height + Theme.Space.s
            cancelButton.frame = CGRect(x: area.midX - 20, y: y, width: 40, height: 40)
            return
        }
        if !notItButton.isHidden {
            let size = notItButton.sizeThatFits(area.size)
            notItButton.frame = CGRect(x: area.midX - size.width / 2, y: area.maxY - size.height, width: size.width, height: size.height)
            area = area.divided(atDistance: size.height + Theme.Space.s, from: .maxYEdge).remainder
        }
        label.frame = area
        if case .fix = bar {
            fixLabel.sizeToFit()
            fixLabel.frame = CGRect(x: area.midX - fixLabel.bounds.width / 2, y: area.minY,
                                    width: fixLabel.bounds.width, height: fixLabel.bounds.height)
            area = area.divided(atDistance: fixLabel.bounds.height + Theme.Space.xs, from: .minYEdge).remainder
        }
        let fit = stack.systemLayoutSizeFitting(CGSize(width: area.width, height: UIView.layoutFittingCompressedSize.height),
                                                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let height = min(area.height, fit.height)
        stack.frame = CGRect(x: area.minX, y: area.midY - height / 2, width: area.width, height: height)
    }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        indices = []
        let correcting: String?
        if case .correcting(let typed) = bar { correcting = typed } else { correcting = nil }
        notItButton.isHidden = !canCorrect || notice != nil || correcting != nil
        cancelButton.isHidden = correcting == nil
        saveButton.isHidden = correcting == nil
        fieldLabel.isHidden = correcting == nil
        if let correcting, notice == nil {
            renderField(correcting)
            label.isHidden = true
            fixLabel.isHidden = true
            stack.isHidden = true
            setNeedsLayout()
            return
        }
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
        case .next(let words, _, _):
            label.isHidden = true
            fixLabel.isHidden = true
            stack.isHidden = false
            if let fix = bar.fixChoice {
                addFixChip(fix)
                if axis == .horizontal { addHairline() }
            }
            for (i, word) in words.enumerated() {
                add(word, index: i, chosen: false)
                stack.arrangedSubviews.last?.accessibilityHint = "Writes the next word"
            }
        case .correcting:
            break
        }
        setNeedsLayout()
    }

    /// The best other reading of the last word, in front of the next words: FIX and the
    /// word on the ice fill, at most 38% of the bar so a long word truncates here.
    private func addFixChip(_ word: String) {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.s, bottom: 6, trailing: Theme.Space.m)
        config.background.cornerRadius = 16
        config.background.backgroundColor = Theme.ui(.ice)
        config.titleLineBreakMode = .byTruncatingTail
        var title = AttributedString("FIX ", attributes: AttributeContainer([
            .font: Theme.uiFont(size: 11, weight: .black, scaledWith: .caption2, upTo: 13),
            .foregroundColor: Theme.ui(.accent),
        ]))
        title += AttributedString(word, attributes: AttributeContainer([
            .font: guessFont(chosen: true),
            .foregroundColor: Theme.ui(.ink),
        ]))
        config.attributedTitle = title
        let chip = UIButton(configuration: config)
        chip.accessibilityLabel = "Fix: \(word)"
        chip.addAction(UIAction { [weak self] _ in self?.onChooseFix?() }, for: .touchUpInside)
        stack.addArrangedSubview(chip)
        if axis == .horizontal {
            chip.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.38).isActive = true
        }
    }

    /// A hairline between the FIX chip and the next words.
    private func addHairline() {
        let line = UIView()
        line.backgroundColor = Theme.ui(.line)
        line.isAccessibilityElement = false
        line.isUserInteractionEnabled = false
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1 / max(1, traitCollection.displayScale)),
            line.heightAnchor.constraint(equalToConstant: 22),
        ])
        stack.addArrangedSubview(line)
    }

    /// The "Not it?" field: the word typed so far with a caret, or the question while
    /// empty, and Save, dimmed until there is a letter.
    private func renderField(_ typed: String) {
        let font = guessFont(chosen: true)
        if typed.isEmpty {
            fieldLabel.attributedText = NSAttributedString(string: "What did you mean?", attributes: [
                .font: Theme.uiFont(size: 15, weight: .semibold, scaledWith: .body, upTo: 17),
                .foregroundColor: Theme.ui(.muted),
            ])
        } else {
            let text = NSMutableAttributedString(string: typed, attributes: [.font: font, .foregroundColor: Theme.ui(.ink)])
            text.append(NSAttributedString(string: "|", attributes: [.font: font, .foregroundColor: Theme.ui(.accent)]))
            fieldLabel.attributedText = text
        }
        fieldLabel.accessibilityLabel = "What did you mean?"
        fieldLabel.accessibilityValue = typed
        var save = UIButton.Configuration.filled()
        save.cornerStyle = .capsule
        save.baseBackgroundColor = Theme.ui(.accent)
        save.baseForegroundColor = Theme.ui(.accentInk)
        save.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.l, bottom: 6, trailing: Theme.Space.l)
        save.attributedTitle = AttributedString("Save", attributes: AttributeContainer([.font: font]))
        saveButton.configuration = save
        saveButton.isEnabled = !typed.isEmpty
        saveButton.alpha = typed.isEmpty ? 0.45 : 1
    }

    private func add(_ word: String, index: Int, chosen: Bool) {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.m, bottom: 6, trailing: Theme.Space.m)
        config.background.cornerRadius = 16
        config.titleLineBreakMode = .byTruncatingTail
        config.background.backgroundColor = chosen ? Theme.ui(.card) : .clear
        config.attributedTitle = AttributedString(word, attributes: AttributeContainer([
            .font: guessFont(chosen: chosen),
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
            .font: guessFont(chosen: chosen),
            .foregroundColor: ink,
        ]))
        button.configuration = config
        button.transform = held ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
    }
}
#endif
