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
/// Holding a guess and letting go opens the word menu (features/word-control): the
/// word in the middle, "Never suggest" on its left, "Suggest more" (or "Learn it" for
/// letters it does not know) on its right; the word itself, a key or a few seconds
/// close it. Then "Won't suggest “end”" with Undo for a moment. Sliding up or down
/// while holding still boosts or blocks at once (DESIGN.md "Learning").
/// With the cursor in a word written earlier (features/fix-earlier-word) the bar is the
/// FIX layout for that word, its pill tagged "Fixing"; a reading tapped swaps it in, and
/// the bar says so with Undo (`say(_:undo:)`).
/// A bar above the keys (`axis` horizontal) or a column beside them (vertical: the
/// middle of a split keyboard, the side of a wide one); in a column, the guesses start
/// at the top, touches between them fall through to the keys under it, and
/// `leadingKey` sits faded at the bottom, centred (Gabriel, 8 Nov 2026).
///
///     bar.bar = model.state.bar
///     bar.onChoose = { index in model.choose(guess: index) }
///     bar.onChooseFix = { reading in model.chooseFix(reading: reading) }
///     bar.onBoost = { index, how in model.boost(guess: index, how: how) }
///     bar.knows = { index in model.knows(guess: index) }
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
    /// What space writes when the open word is a text replacement's shortcut
    /// (`Composer.State.replacement`): shown in the chosen word's pill.
    public var replacement: String? {
        didSet { if replacement != oldValue { render() } }
    }
    /// The phrase of every guess that is a shortcut (`Composer.State.previews`): each
    /// shows its phrase in its place, so a shortcut being typed can be tapped.
    public var previews: [String: String] = [:] {
        didSet { if previews != oldValue { render() } }
    }
    /// A replacement is asking for a blank (`Composer.State.fillPrompt`): the field asks
    /// for it by name instead of "What did you mean?", and Save works while it's empty.
    public var fillPrompt: String? {
        didSet { if fillPrompt != oldValue { render() } }
    }
    /// Whether to offer the snippet page (the person has text replacements), in the
    /// pencil's place when there is nothing to fix (features/text-replacements).
    public var offersSnippets = false {
        didSet { if offersSnippets != oldValue { render() } }
    }
    public var onSnippets: (() -> Void)?
    /// The person's details on offer (`Composer.State.autofill`, features/autofill): in
    /// place of the next words when nothing is typed, or on the left of the guesses
    /// while one is being typed. Each has a person icon, so it reads as yours.
    public var autofill: [Autofill.Offer] = [] {
        didSet { if autofill != oldValue { render() } }
    }
    /// A detail tapped: its index in `autofill`.
    public var onAutofill: ((Int) -> Void)?
    /// A guess boosted or blocked, and how: "menu" or "slide".
    public var onBoost: ((Int, String) -> Void)?
    public var onForget: ((Int, String) -> Void)?
    /// Undo on the bar after a boost or a block.
    public var onUndo: (() -> Void)?
    /// The word menu opened (counted only).
    public var onMenu: (() -> Void)?
    /// Whether the guess at an index is a word the keyboard knows: "Suggest more" for
    /// one, "Learn it" for letters it does not.
    public var knows: ((Int) -> Bool)?

    /// How long the word menu waits for a tap, and the undo note shows.
    static let menuTimeout: TimeInterval = 4

    /// A key for the bar's left end, 44 pt wide: the globe, set by the keyboard when it
    /// draws one (features/space-bar). Hidden while the left end shows ✕. In a column
    /// it sits at the bottom, centred, under the pencil.
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
    /// The widest a detail on the bar is (features/autofill); a long address is cut short.
    static let autofillWidth: CGFloat = 220
    private static let autofillID = "autofill"

    /// The keyboard's theme and look: the chosen word's pill takes the colour of shift,
    /// delete and return (with their see-through) and the letters' colour (Gabriel,
    /// 8 Nov 2026).
    public var keyTheme: KeyboardTheme = .classic {
        didSet { if keyTheme != oldValue { render() } }
    }
    public var keyAppearance: KeyAppearance = .system {
        didSet { if keyAppearance != oldValue { render() } }
    }
    private var keyStyle: KeyStyle { KeyStyle(theme: keyTheme, appearance: keyAppearance, traits: traitCollection) }
    private var keyColors: KeyColors { keyStyle.colors }
    private var pillColor: UIColor {
        let colors = keyColors
        return colors.functionKey.uiColor.withAlphaComponent(CGFloat(colors.functionKey.alpha * colors.keyOpacity))
    }
    /// Bar text is never fully solid and never a gray of its own: a pure colour at 80%
    /// where it stands out, 60% otherwise (Gabriel, 8 Nov 2026).
    /// The chosen word, on its pill: the letters' colour at 80%.
    private var pillInk: UIColor { keyColors.letters.uiColor.withAlphaComponent(0.8) }
    /// Text with no key behind it sits on the system backdrop, so it follows the look,
    /// not the theme's letters: white in dark, black in light.
    private var backdrop: UIColor { keyStyle.backgroundIsDark ? .white : .black }
    /// Readings and typed text: `backdrop` at 80%.
    private var backdropInk: UIColor { backdrop.withAlphaComponent(0.8) }
    /// The other guesses, notes, the pencil, ✕ and the globe: `backdrop` at 60%.
    public var dimInk: UIColor { backdrop.withAlphaComponent(0.6) }

    public override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.userInterfaceStyle != previous?.userInterfaceStyle { render() }
    }

    /// What the bar says when idle.
    public var note = "" {
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
            menu = nil
            // Typing on: the undo note has had its moment.
            if case .guesses = bar { undo = nil }
            render()
            if case .next(let words, _, _) = bar, words != Self.nextWords(of: oldValue) { fadeIn() }
        }
    }

    /// The fix row is open: the pencil was tapped while next words showed.
    private var showsFixes = false

    /// The word menu is open on this guess (features/word-control).
    private var menu: (index: Int, word: String, knows: Bool)? {
        didSet { menuShort = false; restartTimer() }
    }
    /// The menu's actions show their short labels ("Never", "More"): the long ones
    /// did not fit around the word.
    private var menuShort = false
    /// What the bar says after a boost or a block, with Undo beside it.
    private var undo: String? {
        didSet {
            if undo == nil { undoAction = nil }
            restartTimer()
        }
    }
    /// What Undo does when it is not `onUndo` (a swap of a word written earlier).
    private var undoAction: (() -> Void)?

    /// Says `text` with Undo beside it for a moment; Undo calls `undo`.
    public func say(_ text: String, undo action: @escaping () -> Void) {
        menu = nil
        undo = text
        undoAction = action
        render()
    }
    private var menuTask: Task<Void, Never>?

    /// The menu and the undo note go after `menuTimeout` with nothing touched.
    private func restartTimer() {
        menuTask?.cancel()
        guard menu != nil || undo != nil else { return }
        menuTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.menuTimeout))
            guard !Task.isCancelled, let self else { return }
            self.menu = nil
            self.undo = nil
            self.render()
        }
    }

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
    private let snippetButton = UIButton(configuration: .plain())
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
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        addSubview(label)

        pencilButton.configuration = Self.iconConfiguration("pencil")
        pencilButton.accessibilityLabel = "Not it? Fix the last word"
        pencilButton.addAction(UIAction { [weak self] _ in self?.tappedPencil() }, for: .touchUpInside)
        addSubview(pencilButton)

        snippetButton.configuration = Self.iconConfiguration("text.insert")
        snippetButton.accessibilityLabel = "Text replacements"
        snippetButton.accessibilityHint = "Shows your replacements to write one"
        snippetButton.addAction(UIAction { [weak self] _ in self?.onSnippets?() }, for: .touchUpInside)
        addSubview(snippetButton)

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

    /// A bar button at one of the ends: a dimmed symbol on a 44 pt target.
    private static func iconConfiguration(_ symbol: String) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
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
        snippetButton.frame = pencilButton.frame
        if menu != nil || undo != nil {
            // The whole bar, the ends included; the word (or the note) dead centre.
            let fit = stack.systemLayoutSizeFitting(CGSize(width: inset.width, height: inset.height),
                                                    withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .required)
            if menu != nil, !menuShort, fit.width > inset.width {
                menuShort = true
                render()
                return
            }
            let width = min(inset.width, fit.width)
            stack.frame = CGRect(x: bounds.midX - width / 2, y: 0, width: width, height: inset.height)
            return
        }
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
            return shown.reduce(0) { total, view in
                var w = max(view.intrinsicContentSize.width, view is GuessButton ? Self.guessWidth : 0)
                if view.accessibilityIdentifier == Self.autofillID { w = min(w, Self.autofillWidth) }
                return total + w
            } + CGFloat(max(0, shown.count - 1)) * stack.spacing
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
        let end = Self.endWidth
        if let leadingKey, !leadingKey.isHidden {
            // The globe at the bottom, centred, where iOS draws its own under a keyboard.
            leadingKey.frame = CGRect(x: area.midX - end / 2, y: area.maxY - end, width: end, height: end)
            area = area.divided(atDistance: end + Theme.Space.xs, from: .maxYEdge).remainder
        }
        if case .correcting = bar {
            // The word, then Save, then ✕, stacked from the top of the column.
            let line = fieldLabel.sizeThatFits(area.size).height
            let save = saveButton.sizeThatFits(area.size)
            var y = area.minY
            fieldLabel.frame = CGRect(x: area.minX, y: y, width: area.width, height: line)
            y += line + Theme.Space.s
            saveButton.frame = CGRect(x: area.midX - save.width / 2, y: y, width: save.width, height: save.height)
            y += save.height + Theme.Space.s
            closeButton.frame = CGRect(x: area.midX - 20, y: y, width: 40, height: 40)
            return
        }
        let bottom = CGRect(x: area.midX - end / 2, y: area.maxY - end, width: end, height: end)
        pencilButton.frame = bottom
        closeButton.frame = bottom
        snippetButton.frame = bottom
        if !pencilButton.isHidden || !closeButton.isHidden || !snippetButton.isHidden {
            area = area.divided(atDistance: end + Theme.Space.s, from: .maxYEdge).remainder
        }
        // The note and the guesses start at the top of the column (Gabriel, 8 Nov 2026).
        let note = min(area.height, ceil(label.sizeThatFits(area.size).height))
        label.frame = CGRect(x: area.minX, y: area.minY, width: area.width, height: note)
        stack.arrangedSubviews.forEach { if $0.isHidden { $0.isHidden = false } }
        let fit = stack.systemLayoutSizeFitting(CGSize(width: area.width, height: UIView.layoutFittingCompressedSize.height),
                                                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let height = min(area.height, fit.height)
        stack.frame = CGRect(x: area.minX, y: area.minY, width: area.width, height: height)
    }

    private func render() {
        let dim = dimInk
        label.textColor = dim
        pencilButton.configuration?.baseForegroundColor = dim
        closeButton.configuration?.baseForegroundColor = dim
        snippetButton.configuration?.baseForegroundColor = dim
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        indices = []
        keptView = nil
        let correcting: String?
        if case .correcting(let typed) = bar { correcting = typed } else { correcting = nil }
        if !readings.isEmpty, case .next = bar {} else { showsFixes = false }
        if correcting != nil || axis == .vertical { menu = nil; undo = nil }
        let fixing = showsFixes && correcting == nil && notice == nil
        let wordBar = (menu != nil || undo != nil) && notice == nil
        pencilButton.isHidden = !(canCorrect || !readings.isEmpty) || notice != nil || correcting != nil || fixing || wordBar
        closeButton.isHidden = (correcting == nil && !fixing) || wordBar
        snippetButton.isHidden = !offersSnippets || !pencilButton.isHidden || !closeButton.isHidden
            || correcting != nil || notice != nil || wordBar
        closeButton.accessibilityLabel = correcting != nil ? "Cancel" : "Back to the next words"
        leadingKey?.isHidden = axis == .vertical ? false : !closeButton.isHidden || wordBar
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
        if let menu, notice == nil {
            renderMenu(menu)
            setNeedsLayout()
            return
        }
        if let undo, notice == nil {
            renderUndo(undo)
            setNeedsLayout()
            return
        }
        if fixing {
            for reading in readings {
                addReading(reading.word, index: reading.index)
            }
            if canCorrect { addTypeIt() }
            setNeedsLayout()
            return
        }
        if !autofill.isEmpty {
            switch bar {
            case .idle, .next, .fix:
                // Nothing typed: the details take the middle, the first one kept.
                for i in autofill.indices { addAutofill(i) }
                keptView = stack.arrangedSubviews.first
                setNeedsLayout()
                return
            default: break
            }
        }
        switch bar {
        case .idle:
            label.text = note
            label.isHidden = false
            stack.isHidden = true
        case .guesses(let words, let chosen):
            // A detail being typed takes the place of the last guess, on the left so it
            // is dropped last when the bar is narrow.
            var order = middleFirst(words.count, chosen: chosen)
            if !autofill.isEmpty {
                if words.count > 2, let last = order.last(where: { $0 != chosen }) { order.removeAll { $0 == last } }
                addAutofill(0)
            }
            for i in order {
                add(words[i], index: i, chosen: i == chosen, shown: previews[words[i]] ?? (i == chosen ? replacement : nil))
            }
        case .fix(let words, let chosen):
            // The word just written in the pill, its other readings either side.
            for i in middleFirst(words.count, chosen: chosen) {
                add(words[i], index: i, chosen: i == chosen)
            }
        case .earlier(let words, let chosen):
            // The word the cursor is in, in the pill tagged "Fixing", its readings
            // either side (features/fix-earlier-word).
            for i in middleFirst(words.count, chosen: chosen) {
                add(words[i], index: i, chosen: i == chosen)
                guard let button = stack.arrangedSubviews.last else { continue }
                if i == chosen {
                    addFixingTag(to: button)
                    button.accessibilityValue = "Fixing"
                } else {
                    button.accessibilityHint = "Replaces \(words[chosen])"
                }
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

    /// One of the person's details: a person icon and the detail, cut short when long.
    private func addAutofill(_ index: Int) {
        let offer = autofill[index]
        var config = guessConfiguration(offer.text, chosen: false, ink: backdropInk)
        config.image = UIImage(systemName: "person.crop.circle.fill",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        config.imagePadding = Theme.Space.xs
        config.imageColorTransformer = UIConfigurationColorTransformer { [weak self] _ in self?.dimInk ?? .gray }
        let button = GuessButton(configuration: config)
        let widest = button.widthAnchor.constraint(lessThanOrEqualToConstant: Self.autofillWidth)
        widest.priority = .required - 1
        widest.isActive = true
        button.accessibilityIdentifier = Self.autofillID
        button.accessibilityLabel = TextReplacements.oneLine(offer.text)
        button.accessibilityHint = offer.replacing.isEmpty ? "Fills in your detail" : "Finishes it with your detail"
        button.addAction(UIAction { [weak self] _ in self?.onAutofill?(index) }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }

    /// The small "Fixing" tag over the pill of a word written earlier: the bar is about
    /// that word, not one being typed.
    private func addFixingTag(to button: UIView) {
        let tag = PaddedLabel()
        tag.text = "FIXING"
        tag.font = Theme.uiFont(size: 9, weight: .heavy, scaledWith: .caption2, upTo: 10)
        tag.textColor = Theme.ui(.accentInk)
        tag.backgroundColor = Theme.ui(.accent)
        tag.layer.cornerRadius = 6
        tag.layer.masksToBounds = true
        tag.isAccessibilityElement = false
        tag.isUserInteractionEnabled = false
        tag.translatesAutoresizingMaskIntoConstraints = false
        button.clipsToBounds = false
        button.addSubview(tag)
        NSLayoutConstraint.activate([
            tag.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            tag.centerYAnchor.constraint(equalTo: button.topAnchor, constant: 1),
        ])
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
        let button = GuessButton(configuration: guessConfiguration(word, chosen: false, ink: backdropInk))
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
        config.baseForegroundColor = dimInk
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
        let question = fillPrompt.map { "\($0.prefix(1).uppercased() + $0.dropFirst())?" } ?? "What did you mean?"
        if typed.isEmpty {
            fieldLabel.attributedText = NSAttributedString(string: question, attributes: [
                .font: Theme.uiFont(size: 15, weight: .semibold, scaledWith: .body, upTo: 17),
                .foregroundColor: dimInk,
            ])
        } else {
            let text = NSMutableAttributedString(string: typed, attributes: [.font: font, .foregroundColor: backdropInk])
            text.append(NSAttributedString(string: "|", attributes: [.font: font, .foregroundColor: Theme.ui(.accent)]))
            fieldLabel.attributedText = text
        }
        fieldLabel.accessibilityLabel = question
        fieldLabel.accessibilityValue = typed
        var save = UIButton.Configuration.filled()
        save.cornerStyle = .capsule
        save.baseBackgroundColor = Theme.ui(.accent)
        save.baseForegroundColor = Theme.ui(.accentInk)
        save.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.l, bottom: 6, trailing: Theme.Space.l)
        save.attributedTitle = AttributedString("Save", attributes: AttributeContainer([.font: font]))
        saveButton.configuration = save
        // A blank may be left empty.
        let ready = !typed.isEmpty || fillPrompt != nil
        saveButton.isEnabled = ready
        saveButton.alpha = ready ? 1 : 0.45
    }

    /// A word on the bar: the chosen one bold on the theme's pill, the rest plain.
    private func guessConfiguration(_ word: String, chosen: Bool, ink: UIColor? = nil) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.m, bottom: 6, trailing: Theme.Space.m)
        config.background.cornerRadius = 16
        config.titleLineBreakMode = .byTruncatingTail
        config.background.backgroundColor = chosen ? pillColor : .clear
        config.attributedTitle = AttributedString(TextReplacements.oneLine(word), attributes: AttributeContainer([
            .font: guessFont(chosen: chosen),
            .foregroundColor: ink ?? (chosen ? pillInk : dimInk),
        ]))
        return config
    }

    /// `shown`, when set, is what the word writes (a replacement's phrase), drawn in
    /// its place.
    private func add(_ word: String, index: Int, chosen: Bool, shown: String? = nil) {
        let button = GuessButton(configuration: guessConfiguration(shown ?? word, chosen: chosen))
        button.accessibilityLabel = shown.map { "\(word), writes \(TextReplacements.oneLine($0))" } ?? word
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
        // VoiceOver can't hold and slide: the menu's two actions, without the menu.
        button.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Never suggest") { [weak self] _ in
                self?.act(.forget, index: index, word: word, knows: true, how: "voiceover"); return true
            },
            UIAccessibilityCustomAction(name: "Suggest more") { [weak self] _ in
                self?.act(.boost, index: index, word: word, knows: true, how: "voiceover"); return true
            },
        ]
        stack.addArrangedSubview(button)
    }

    // MARK: Word menu

    /// Never suggest · the word · Suggest more (or Learn it), the word dead centre: the
    /// two actions are made the same width.
    private func renderMenu(_ menu: (index: Int, word: String, knows: Bool)) {
        let never = menuAction(menuShort ? "Never" : "Never suggest", symbol: "nosign", tone: .right) { [weak self] in
            self?.act(.forget, index: menu.index, word: menu.word, knows: menu.knows, how: "menu")
        }
        never.accessibilityLabel = "Never suggest \(menu.word)"
        let more = menu.knows
            ? menuAction(menuShort ? "More" : "Suggest more", symbol: "arrow.up", tone: .mint) { [weak self] in
                self?.act(.boost, index: menu.index, word: menu.word, knows: true, how: "menu")
            }
            : menuAction(menuShort ? "Learn" : "Learn it", symbol: "checkmark", tone: .mint) { [weak self] in
                self?.act(.boost, index: menu.index, word: menu.word, knows: false, how: "menu")
            }
        more.accessibilityLabel = menu.knows ? "Suggest \(menu.word) more" : "Learn \(menu.word)"
        let word = UIButton(configuration: guessConfiguration(menu.word, chosen: true))
        word.accessibilityLabel = menu.word
        word.accessibilityHint = "Closes the menu"
        word.addAction(UIAction { [weak self] _ in
            self?.menu = nil
            self?.render()
        }, for: .touchUpInside)
        word.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [never, word, more] { stack.addArrangedSubview(view) }
        never.widthAnchor.constraint(equalTo: more.widthAnchor).isActive = true
        UIAccessibility.post(notification: .layoutChanged, argument: never)
    }

    private func menuAction(_ title: String, symbol: String, tone: Theme.Tone, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = Theme.ui(tone)
        config.baseForegroundColor = Theme.ui(.accentInk)
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        config.imagePadding = Theme.Space.xs
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: Theme.Space.m, bottom: 7, trailing: Theme.Space.m)
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: Theme.uiFont(size: 14, weight: .bold, scaledWith: .footnote, upTo: 16),
        ]))
        let button = UIButton(configuration: config)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    /// "Won't suggest “end”" and Undo.
    private func renderUndo(_ text: String) {
        let note = UILabel()
        note.text = text
        note.font = Theme.uiFont(size: 14, weight: .bold, scaledWith: .footnote, upTo: 16)
        note.textColor = dimInk
        note.lineBreakMode = .byTruncatingMiddle
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = Theme.ui(.ice)
        config.baseForegroundColor = Theme.ui(.accent)
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.m, bottom: 6, trailing: Theme.Space.m)
        config.attributedTitle = AttributedString("Undo", attributes: AttributeContainer([
            .font: Theme.uiFont(size: 14, weight: .bold, scaledWith: .footnote, upTo: 16),
        ]))
        let button = UIButton(configuration: config)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let action = self.undoAction
            self.undo = nil
            if let action { action() } else { self.onUndo?() }
            self.render()
        }, for: .touchUpInside)
        stack.addArrangedSubview(note)
        stack.addArrangedSubview(button)
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    /// Boost or block a guess, then say so with Undo.
    private func act(_ verdict: Verdict, index: Int, word: String, knows: Bool, how: String) {
        menu = nil
        undoAction = nil
        let shown = "\u{201C}\(word)\u{201D}"
        switch verdict {
        case .forget:
            onForget?(index, how)
            undo = "Won't suggest \(shown)"
        case .boost:
            onBoost?(index, how)
            undo = knows ? "Will suggest \(shown) more" : "Learned \(shown)"
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        render()
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
            let word = button.accessibilityLabel ?? ""
            holdStart = nil
            holdVerdict = nil
            paint(button, verdict: nil, held: false)
            let knows = knows?(index) ?? true
            if let verdict {
                act(verdict, index: index, word: word, knows: knows, how: "slide")
            } else if axis == .horizontal {
                menu = (index, word, knows)
                onMenu?()
                render()
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
            background = held ? Theme.ui(.ice) : (chosen ? pillColor : .clear)
            ink = held ? Theme.ui(chosen ? .ink : .muted) : (chosen ? pillInk : dimInk)
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

/// A label with room around its text, for the "Fixing" tag.
private final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 1, left: 5, bottom: 1, right: 5)

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
#endif
