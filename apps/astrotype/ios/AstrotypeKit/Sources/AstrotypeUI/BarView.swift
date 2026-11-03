#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// The guesses, in three parts that never move (DESIGN.md "The bar",
/// features/guesses-bar): a key at the left end (`leadingKey`, the globe where our
/// keyboard draws one), the words in the middle, packed together and centred on the bar,
/// and the pencil ("Not it?") at the right end. The middle shows one kind of thing at a
/// time: an idle note, the guesses for the open word with the chosen one in a pill in
/// the centre, the readings of the word just written with it in the pill (FIX, when
/// there are no next words), or the likely next words. With next words, the other
/// readings of the last word wait behind the pencil: tapped, the bar becomes the fix
/// row (✕, the readings, "Type it"). "Type it", or the pencil when there is nothing to
/// pick, opens the "Not it?" field where the word meant is typed (features/missed-words).
/// Holding a guess and sliding up boosts it, down forgets it (DESIGN.md "Learning").
/// A bar above the keys (`axis` horizontal) or a column beside them (vertical: the
/// middle of a split keyboard, the side of a wide one); in a column, touches between
/// the guesses fall through to the keys under it, and there is no `leadingKey`.
///
///     bar.bar = model.state.bar
///     bar.onChoose = { index in model.choose(guess: index) }
///     bar.onChooseFix = { reading in model.chooseFix(reading: reading) }
///     bar.onBoost = { index in model.boost(guess: index) }
///     bar.canCorrect = model.state.canCorrect
///     bar.onNotIt = { model.beginCorrection() }
///     bar.leadingKey = globe
public final class BarView: UIView {
    public var onChoose: ((Int) -> Void)?
    /// A reading of the last word picked from the fix row: an index into `Bar.next`'s `fix`.
    public var onChooseFix: ((Int) -> Void)?
    /// "Type it" (or the pencil with nothing to pick), and the field's ✕ and Save.
    public var onNotIt: (() -> Void)?
    public var onCancelCorrection: (() -> Void)?
    public var onSaveCorrection: (() -> Void)?

    /// Whether to offer "Not it?" (`Composer.State.canCorrect`).
    public var canCorrect = false {
        didSet { if canCorrect != oldValue { render() } }
    }
    public var onBoost: ((Int) -> Void)?
    public var onForget: ((Int) -> Void)?

    /// A key for the bar's left end, 44 pt wide: the globe, set by the keyboard when it
    /// draws one (features/space-bar). Hidden while the left end shows ✕, and in a column.
    public var leadingKey: UIView? {
        didSet {
            guard leadingKey !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let leadingKey { addSubview(leadingKey) }
            render()
        }
    }

    /// How far a held guess slides before it counts as a boost (up) or a forget (down).
    static let slideDistance: CGFloat = 22
    /// The width of each end of the bar: one 44 pt button.
    static let endWidth: CGFloat = 44
    /// The narrowest a word on the bar is, so "I" or "a" is still easy to hit
    /// (Gabriel, 3 Nov 2026); the word sits centred in it.
    static let guessWidth: CGFloat = 64

    /// What the bar says when idle.
    public var note = "Both thumbs, one word" {
        didSet { if case .idle = bar { render() } }
    }

    /// Horizontal: a bar above the keys. Vertical: a column beside them.
    public var axis: NSLayoutConstraint.Axis = .horizontal {
        didSet {
            guard axis != oldValue else { return }
            stack.axis = axis
            stack.spacing = axis == .vertical ? Theme.Space.xs : Theme.Space.xs + 2
            label.numberOfLines = axis == .vertical ? 0 : 1
            render()
        }
    }

    public var bar: Composer.Bar = .idle {
        didSet {
            guard bar != oldValue else { return }
            showsFixes = false
            render()
            if case .next(let words, _, _) = bar, words != Self.nextWords(of: oldValue) { fadeIn() }
        }
    }

    /// The fix row is open: the pencil was tapped while next words showed.
    private var showsFixes = false

    private static func nextWords(of bar: Composer.Bar) -> [String] {
        if case .next(let words, _, _) = bar { return words }
        return []
    }

    /// The other readings of the last word behind the pencil, with their indices in `fix`.
    private var readings: [(index: Int, word: String)] {
        guard case .next(_, let fix, let chosen) = bar else { return [] }
        return fix.enumerated().filter { $0.offset != chosen }.map { ($0.offset, $0.element) }
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
    private let pencilButton = UIButton(configuration: .plain())
    private let closeButton = UIButton(configuration: .plain())
    private let saveButton = UIButton(configuration: .plain())
    private let fieldLabel = UILabel()
    private let stack = UIStackView()
    /// The word that must stay when the middle is too narrow for all of them.
    private weak var keptView: UIView?
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

        pencilButton.configuration = Self.iconConfiguration("pencil")
        pencilButton.accessibilityLabel = "Not it? Fix the last word"
        pencilButton.addAction(UIAction { [weak self] _ in self?.tappedPencil() }, for: .touchUpInside)
        addSubview(pencilButton)

        closeButton.configuration = Self.iconConfiguration("xmark")
        closeButton.addAction(UIAction { [weak self] _ in self?.tappedClose() }, for: .touchUpInside)
        addSubview(closeButton)

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
        stack.distribution = .fill
        stack.spacing = Theme.Space.xs + 2
        stack.accessibilityLabel = "Suggestions"
        addSubview(stack)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: BarView, _: UITraitCollection) in
            self.render()
        }
        render()
    }

    /// A bar button at one of the ends: a muted symbol on a 44 pt target.
    private static func iconConfiguration(_ symbol: String) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        config.baseForegroundColor = Theme.ui(.muted)
        config.contentInsets = .zero
        config.background.cornerRadius = 12
        return config
    }

    private func guessFont(chosen: Bool) -> UIFont {
        Theme.uiFont(size: 16, weight: chosen ? .bold : .semibold, scaledWith: .body, upTo: 18)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func tappedPencil() {
        if readings.isEmpty {
            onNotIt?()
        } else {
            showsFixes = true
            render()
        }
    }

    private func tappedClose() {
        if case .correcting = bar {
            onCancelCorrection?()
        } else {
            showsFixes = false
            render()
        }
    }

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
        let inset = bounds.insetBy(dx: Theme.Space.xs, dy: 0)
        let end = Self.endWidth
        if case .correcting = bar {
            // ✕ and Save at the ends, both ends as wide as Save so the word stays centred.
            let save = saveButton.sizeThatFits(inset.size)
            let side = max(end, save.width)
            closeButton.frame = CGRect(x: inset.minX, y: 0, width: end, height: inset.height)
            saveButton.frame = CGRect(x: inset.maxX - save.width, y: (inset.height - save.height) / 2, width: save.width, height: save.height)
            fieldLabel.frame = inset.insetBy(dx: side + Theme.Space.s, dy: 0)
            return
        }
        let left = CGRect(x: inset.minX, y: 0, width: end, height: inset.height)
        closeButton.frame = left
        leadingKey?.frame = left
        pencilButton.frame = CGRect(x: inset.maxX - end, y: 0, width: end, height: inset.height)
        let middle = inset.insetBy(dx: end + Theme.Space.xs, dy: 0)
        label.frame = middle
        fitMiddle(width: middle.width)
        let fit = stack.systemLayoutSizeFitting(CGSize(width: middle.width, height: middle.height),
                                                withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .required)
        let width = min(middle.width, fit.width)
        stack.frame = CGRect(x: bounds.midX - width / 2, y: 0, width: width, height: inset.height)
    }

    /// Drops the outer words, never the kept one, until the rest fit whole in `width`.
    private func fitMiddle(width: CGFloat) {
        let views = stack.arrangedSubviews
        views.forEach { if $0.isHidden { $0.isHidden = false } }
        func needed() -> CGFloat {
            let shown = views.filter { !$0.isHidden }
            return shown.reduce(0) { $0 + max($1.intrinsicContentSize.width, $1 is GuessButton ? Self.guessWidth : 0) } + CGFloat(max(0, shown.count - 1)) * stack.spacing
        }
        while needed() > width {
            let shown = views.filter { !$0.isHidden && $0 !== keptView }
            guard views.filter({ !$0.isHidden }).count > 1, let drop = shown.last ?? shown.first else { break }
            drop.isHidden = true
        }
    }

    /// A column: the words stacked and centred, the pencil (or ✕ in the fix row) under them.
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
            closeButton.frame = CGRect(x: area.midX - 20, y: y, width: 40, height: 40)
            return
        }
        let end = Self.endWidth
        let bottom = CGRect(x: area.midX - end / 2, y: area.maxY - end, width: end, height: end)
        pencilButton.frame = bottom
        closeButton.frame = bottom
        if !pencilButton.isHidden || !closeButton.isHidden {
            area = area.divided(atDistance: end + Theme.Space.s, from: .maxYEdge).remainder
        }
        label.frame = area
        stack.arrangedSubviews.forEach { if $0.isHidden { $0.isHidden = false } }
        let fit = stack.systemLayoutSizeFitting(CGSize(width: area.width, height: UIView.layoutFittingCompressedSize.height),
                                                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let height = min(area.height, fit.height)
        stack.frame = CGRect(x: area.minX, y: area.midY - height / 2, width: area.width, height: height)
    }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        indices = []
        keptView = nil
        let correcting: String?
        if case .correcting(let typed) = bar { correcting = typed } else { correcting = nil }
        if !readings.isEmpty, case .next = bar {} else { showsFixes = false }
        let fixing = showsFixes && correcting == nil && notice == nil
        pencilButton.isHidden = !(canCorrect || !readings.isEmpty) || notice != nil || correcting != nil || fixing
        closeButton.isHidden = correcting == nil && !fixing
        closeButton.accessibilityLabel = correcting != nil ? "Cancel" : "Back to the next words"
        leadingKey?.isHidden = axis == .vertical || !closeButton.isHidden
        saveButton.isHidden = correcting == nil
        fieldLabel.isHidden = correcting == nil
        if let correcting, notice == nil {
            renderField(correcting)
            label.isHidden = true
            stack.isHidden = true
            setNeedsLayout()
            return
        }
        if let notice {
            label.text = notice
            label.isHidden = false
            stack.isHidden = true
            setNeedsLayout()
            return
        }
        label.isHidden = true
        stack.isHidden = false
        if fixing {
            for reading in readings {
                addReading(reading.word, index: reading.index)
            }
            if canCorrect { addTypeIt() }
            setNeedsLayout()
            return
        }
        switch bar {
        case .idle:
            label.text = note
            label.isHidden = false
            stack.isHidden = true
        case .guesses(let words, let chosen):
            for i in middleFirst(words.count, chosen: chosen) {
                add(words[i], index: i, chosen: i == chosen)
            }
        case .fix(let words, let chosen):
            // The word just written in the pill, its other readings either side.
            for i in middleFirst(words.count, chosen: chosen) {
                add(words[i], index: i, chosen: i == chosen)
            }
        case .next(let words, _, _):
            for (i, word) in words.enumerated() {
                add(word, index: i, chosen: false)
                stack.arrangedSubviews.last?.accessibilityHint = "Writes the next word"
            }
            keptView = stack.arrangedSubviews.first
        case .correcting:
            break
        }
        setNeedsLayout()
    }

    /// The order the words sit in, left to right: the chosen one in the middle of
    /// three (in a column, on top), the rest in their order.
    private func middleFirst(_ count: Int, chosen: Int) -> [Int] {
        let others = (0..<count).filter { $0 != chosen }
        guard (0..<count).contains(chosen) else { return Array(0..<count) }
        if axis == .vertical || others.count < 2 { return [chosen] + others }
        return [others[0], chosen] + others.dropFirst()
    }

    /// A reading of the last word in the fix row: tapped, it replaces the word.
    private func addReading(_ word: String, index: Int) {
        let button = GuessButton(configuration: guessConfiguration(word, chosen: false, ink: .ink))
        button.accessibilityLabel = word
        button.accessibilityHint = "Replaces the last word"
        button.addAction(UIAction { [weak self] _ in self?.onChooseFix?(index) }, for: .touchUpInside)
        stack.addArrangedSubview(button)
        if keptView == nil { keptView = button }
    }

    /// "Type it", last in the fix row: opens the "Not it?" field.
    private func addTypeIt() {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "pencil", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        config.imagePadding = Theme.Space.xs
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.s, bottom: 6, trailing: Theme.Space.m)
        config.baseForegroundColor = Theme.ui(.muted)
        config.background.cornerRadius = 16
        config.background.strokeColor = Theme.ui(.line)
        config.background.strokeWidth = 1.5
        config.attributedTitle = AttributedString("Type it", attributes: AttributeContainer([
            .font: Theme.uiFont(size: 14, weight: .bold, scaledWith: .footnote, upTo: 16),
        ]))
        let button = UIButton(configuration: config)
        button.accessibilityLabel = "Type it"
        button.accessibilityHint = "Type the word you meant"
        button.addAction(UIAction { [weak self] _ in self?.onNotIt?() }, for: .touchUpInside)
        stack.addArrangedSubview(button)
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

    /// A word on the bar: the chosen one bold on the white pill, the rest plain.
    private func guessConfiguration(_ word: String, chosen: Bool, ink: Theme.Tone? = nil) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.m, bottom: 6, trailing: Theme.Space.m)
        config.background.cornerRadius = 16
        config.titleLineBreakMode = .byTruncatingTail
        config.background.backgroundColor = chosen ? Theme.ui(.card) : .clear
        config.attributedTitle = AttributedString(word, attributes: AttributeContainer([
            .font: guessFont(chosen: chosen),
            .foregroundColor: Theme.ui(ink ?? (chosen ? .ink : .muted)),
        ]))
        return config
    }

    private func add(_ word: String, index: Int, chosen: Bool) {
        let button = GuessButton(configuration: guessConfiguration(word, chosen: chosen))
        button.accessibilityLabel = word
        if chosen {
            button.accessibilityTraits.insert(.selected)
            keptView = button
        }
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
/// A word on the bar: at least `BarView.guessWidth` wide, and it takes touches over the
/// bar's whole height and halfway into the gap beside it, not only on its pill.
private final class GuessButton: UIButton {
    convenience init(configuration: UIButton.Configuration) {
        self.init(frame: .zero)
        self.configuration = configuration
        translatesAutoresizingMaskIntoConstraints = false
        let minimum = widthAnchor.constraint(greaterThanOrEqualToConstant: BarView.guessWidth)
        minimum.priority = .defaultHigh
        minimum.isActive = true
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let tall = max(0, (BarView.endWidth - bounds.height) / 2)
        return bounds.insetBy(dx: -3, dy: -tall).contains(point)
    }
}
#endif
