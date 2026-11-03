#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// The in-keyboard settings under a held "123" (features/settings/FEATURE.md): the core
/// few, so they can change without leaving the app being typed in, and so people
/// without Full Access (where the app's Settings can't reach the keyboard) can still
/// change them. Four quick tiles (autospace, the guesses bar, haptics, trails, and the
/// split on a wide screen) and four sliders (height, real words, split words, and
/// autospace's wait), and a Languages row that opens the list of languages
/// (features/languages: any one free, two at once Pro). The rest lives in the app.
///
/// Shown over the keys. The title and Done stay at the top; the tiles and sliders sit
/// below and scroll when the keys' space is shorter than them.
public final class SettingsPanelView: UIView {
    public var settings: KeyboardSettings {
        didSet { render() }
    }
    public var onChange: ((KeyboardSettings) -> Void)?
    public var onDone: (() -> Void)?
    /// Whether the split layout may be turned on (Pro). Off, the Split tile shows PRO
    /// and stays put; the app's Pro screen is where to go.
    public var allowsSplit = true {
        didSet { if allowsSplit != oldValue { render() } }
    }
    /// Whether the keyboard is on a wide screen, where the Split tile shows.
    public var showsSplit = false {
        didSet { if showsSplit != oldValue { layoutTiles(); render() } }
    }
    /// Whether two languages may be on at once (Pro). Off, turning one on turns the
    /// other off, and a line says Pro types in both.
    public var allowsTwoLanguages = true {
        didSet { if allowsTwoLanguages != oldValue { render() } }
    }
    /// The phone's languages, for the languages that follow it until chosen.
    public var preferredLanguages: [String] = Locale.preferredLanguages {
        didSet { render() }
    }
    /// The height iOS gave the keyboard and the height it asked for. When iOS gives
    /// less, the keys shrink to fit, and a note under the sliders says so.
    public var granted: (got: CGFloat, asked: CGFloat) = (0, 0) {
        didSet { if granted != oldValue { render() } }
    }
    /// How the keyboard's last opening went, when iOS first gave it a different height
    /// (from the host). Shown under the sliders while the opening height is being fixed.
    public var heightStory: String? {
        didSet { if heightStory != oldValue { render() } }
    }

    private static let headerHeight: CGFloat = 48

    private let title = UILabel()
    private let back = UIButton(configuration: .plain())
    private let done = UIButton(configuration: .filled())
    private let scroll = PanelScrollView()
    private let column = UIStackView()
    private let tileGrid = UIStackView()

    private let autospaceTile = QuickTile(title: "Autospace", symbol: "space")
    private let barTile = QuickTile(title: "Guesses bar", symbol: "rectangle.topthird.inset.filled")
    private let hapticsTile = QuickTile(title: "Haptics", symbol: "iphone.radiowaves.left.and.right")
    private let trailsTile = QuickTile(title: "Trails", symbol: "scribble")
    private let splitTile = QuickTile(title: "Split", symbol: "rectangle.split.2x1")
    private let nextTile = QuickTile(title: "Next word", symbol: "text.append")

    private let height = SliderRow(title: "Height", range: KeyboardSettings.heightRange, label: "Keyboard height")
    private let strict = SliderRow(title: "Real words", range: 0...1, label: "Real words")
    private let split = SliderRow(title: "Split words", range: 0...1, label: "Split words")
    private let wait = SliderRow(title: "Wait", range: KeyboardSettings.delayRange, label: "Autospace wait")
    private let note = UILabel()
    /// The Languages row: the ones on, and a chevron to the list.
    private let languagesLink = LinkRow(title: "Languages", symbol: "character.bubble")
    /// The list of languages, shown in place of the settings when the row is tapped.
    private let languageScroll = PanelScrollView()
    private let languageList = UIStackView()
    /// One row per bundled language, named in itself ("Español").
    private let languageRows: [(code: String, row: CheckRow)] = Language.bundledCodes.map {
        ($0, CheckRow(title: Language.names[$0] ?? $0, subtitle: Language.englishNames[$0]))
    }
    private let languageNote = UILabel()
    private var showingLanguages = false {
        didSet { if showingLanguages != oldValue { showPage() } }
    }
    private let more = UILabel()
    private var flashedIndicators = false

    public init(settings: KeyboardSettings) {
        self.settings = settings
        super.init(frame: .zero)
        backgroundColor = Theme.ui(.kb)

        title.text = "Keyboard settings"
        title.font = Theme.uiFont(size: 17, weight: .heavy)
        title.textColor = Theme.ui(.ink)
        title.accessibilityTraits = .header
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.8
        addSubview(title)

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = Theme.ui(.accent)
        config.baseForegroundColor = Theme.ui(.accentInk)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.l, bottom: 6, trailing: Theme.Space.l)
        config.attributedTitle = AttributedString("Done", attributes: AttributeContainer([.font: Theme.uiFont(size: 15, weight: .bold)]))
        done.configuration = config
        done.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
        addSubview(done)

        var backConfig = UIButton.Configuration.plain()
        backConfig.image = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold))
        backConfig.baseForegroundColor = Theme.ui(.accent)
        backConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 8)
        back.configuration = backConfig
        back.accessibilityLabel = "Back to keyboard settings"
        back.addAction(UIAction { [weak self] _ in self?.showingLanguages = false }, for: .touchUpInside)
        back.isHidden = true
        addSubview(back)

        wire(autospaceTile) { $0.autospace.toggle() }
        wire(barTile) { $0.showsBar.toggle() }
        wire(hapticsTile) { $0.haptics.toggle() }
        wire(trailsTile) { $0.trails.toggle() }
        wire(splitTile) { $0.splitOnWide.toggle() }
        wire(nextTile) { $0.nextWords.toggle() }
        nextTile.accessibilityHint = "Likely next words in the bar after each word"
        languagesLink.addAction(UIAction { [weak self] _ in self?.showingLanguages = true }, for: .touchUpInside)
        for (code, row) in languageRows {
            row.addAction(UIAction { [weak self] _ in self?.toggleLanguage(code) }, for: .touchUpInside)
        }

        height.onChange = { [weak self] value in
            // In 5% steps, so 100% (Apple's) is easy to land on.
            self?.update { $0.keyboardHeight = (value * 20).rounded() / 20 }
        }
        height.slider.accessibilityHint = "How tall the keys are. 100 percent puts every key where Apple's keyboard has it"
        strict.onChange = { [weak self] value in self?.update { $0.wordStrictness = (value * 100).rounded() / 100 } }
        strict.slider.accessibilityHint = "How sure the keyboard must be of a real word before it puts one in for letters you tapped"
        split.onChange = { [weak self] value in self?.update { $0.splitStrictness = (value * 100).rounded() / 100 } }
        split.slider.accessibilityHint = "How sure the keyboard must be before it puts a space into letters that read as two words. At 0 it never splits"
        wait.onChange = { [weak self] value in self?.update { $0.autospaceDelay = (value * 10).rounded() / 10 } }
        wait.slider.accessibilityHint = "How long autospace waits before it puts a swiped word in"

        note.font = Theme.uiFont(size: 13, weight: .regular, scaledWith: .footnote, upTo: 18)
        note.textColor = Theme.ui(.muted)
        note.adjustsFontForContentSizeCategory = true
        note.numberOfLines = 0
        languageNote.font = note.font
        languageNote.textColor = Theme.ui(.muted)
        languageNote.adjustsFontForContentSizeCategory = true
        languageNote.numberOfLines = 0
        languageNote.text = "One language at a time. Pro types in two at once."
        more.text = "More in the Astrotype app"
        more.font = Theme.uiFont(size: 13, weight: .semibold, scaledWith: .footnote, upTo: 18)
        more.textColor = Theme.ui(.muted)
        more.textAlignment = .center
        more.adjustsFontForContentSizeCategory = true
        more.numberOfLines = 0

        build()
        layoutTiles()
        render()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _: UITraitCollection) in
            self.layoutTiles()
        }
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func wire(_ tile: QuickTile, _ change: @escaping (inout KeyboardSettings) -> Void) {
        tile.addAction(UIAction { [weak self] _ in self?.update(change) }, for: .touchUpInside)
    }

    private func update(_ change: (inout KeyboardSettings) -> Void) {
        change(&settings)
        onChange?(settings)
    }

    // MARK: Building

    private func build() {
        tileGrid.axis = .vertical
        tileGrid.spacing = Theme.Space.s

        let sliders = UIStackView()
        sliders.axis = .vertical
        sliders.backgroundColor = Theme.ui(.key)
        sliders.layer.cornerRadius = Theme.Radius.sm
        sliders.layer.cornerCurve = .continuous
        sliders.isLayoutMarginsRelativeArrangement = true
        sliders.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: Theme.Space.m, bottom: 0, trailing: Theme.Space.m)
        for (index, row) in [height, strict, split, wait].enumerated() {
            if index > 0 {
                let line = UIView()
                line.backgroundColor = Theme.ui(.kb)
                line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                sliders.addArrangedSubview(line)
            }
            sliders.addArrangedSubview(row)
        }
        // The sliders start at the same place.
        for row in [strict, split, wait] {
            row.label.widthAnchor.constraint(equalTo: height.label.widthAnchor).isActive = true
        }

        column.axis = .vertical
        column.spacing = Theme.Space.s
        column.translatesAutoresizingMaskIntoConstraints = false
        let languagesCard = card([languagesLink])
        for view in [tileGrid, languagesCard, sliders, note, more] { column.addArrangedSubview(view) }

        // The languages page: a card of rows, the free note under it.
        languageList.axis = .vertical
        languageList.spacing = Theme.Space.s
        languageList.translatesAutoresizingMaskIntoConstraints = false
        languageList.addArrangedSubview(card(languageRows.map(\.row)))
        languageList.addArrangedSubview(languageNote)
        languageScroll.showsHorizontalScrollIndicator = false
        languageScroll.alwaysBounceVertical = true
        languageScroll.delaysContentTouches = false
        languageScroll.isHidden = true
        languageScroll.addSubview(languageList)
        addSubview(languageScroll)
        NSLayoutConstraint.activate([
            languageList.topAnchor.constraint(equalTo: languageScroll.contentLayoutGuide.topAnchor),
            languageList.bottomAnchor.constraint(equalTo: languageScroll.contentLayoutGuide.bottomAnchor, constant: -Theme.Space.m),
            languageList.leadingAnchor.constraint(equalTo: languageScroll.frameLayoutGuide.leadingAnchor, constant: Theme.Space.m),
            languageList.trailingAnchor.constraint(equalTo: languageScroll.frameLayoutGuide.trailingAnchor, constant: -Theme.Space.m),
        ])

        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        scroll.delaysContentTouches = false
        scroll.backgroundColor = .clear
        scroll.addSubview(column)
        addSubview(scroll)

        let content = scroll.contentLayoutGuide
        let frame = scroll.frameLayoutGuide
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: content.topAnchor),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Theme.Space.m),
            column.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: Theme.Space.m),
            column.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -Theme.Space.m),
        ])
    }

    /// Rows in a rounded `key` card, with a hairline between them.
    private func card(_ rows: [UIView]) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.backgroundColor = Theme.ui(.key)
        stack.layer.cornerRadius = Theme.Radius.sm
        stack.layer.cornerCurve = .continuous
        stack.clipsToBounds = true
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = UIView()
                line.backgroundColor = Theme.ui(.kb)
                line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                stack.addArrangedSubview(line)
            }
            stack.addArrangedSubview(row)
        }
        return stack
    }

    /// The settings, or the list of languages in their place.
    private func showPage() {
        scroll.isHidden = showingLanguages
        languageScroll.isHidden = !showingLanguages
        back.isHidden = !showingLanguages
        title.text = showingLanguages ? "Languages" : "Keyboard settings"
        setNeedsLayout()
        UIAccessibility.post(notification: .screenChanged, argument: title)
    }

    /// One row of tiles, or rows of two at the accessibility text sizes.
    private func layoutTiles() {
        for row in tileGrid.arrangedSubviews { row.removeFromSuperview() }
        let tiles = [autospaceTile, nextTile, barTile, hapticsTile, trailsTile] + (showsSplit ? [splitTile] : [])
        let perRow = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 2 : tiles.count
        for start in stride(from: 0, to: tiles.count, by: perRow) {
            let row = UIStackView(arrangedSubviews: Array(tiles[start..<min(start + perRow, tiles.count)]))
            row.axis = .horizontal
            row.spacing = Theme.Space.s
            row.distribution = .fillEqually
            tileGrid.addArrangedSubview(row)
        }
    }

    // MARK: State

    /// A language tapped: on, it goes off unless it is the last one; off, it joins the
    /// others (or, free, takes the place of the one that was on).
    private func toggleLanguage(_ code: String) {
        var chosen = settings.activeLanguages(preferred: preferredLanguages, allowsTwo: allowsTwoLanguages)
        if chosen.contains(code) {
            guard chosen.count > 1 else { return }
            chosen.removeAll { $0 == code }
        } else {
            chosen = allowsTwoLanguages ? chosen + [code] : [code]
        }
        update { $0.languages = chosen }
    }

    private func render() {
        let active = settings.activeLanguages(preferred: preferredLanguages, allowsTwo: allowsTwoLanguages)
        for (code, row) in languageRows {
            row.isOn = active.contains(code)
        }
        languagesLink.value = active.map { Language.names[$0] ?? $0 }.joined(separator: ", ")
        languageNote.isHidden = allowsTwoLanguages
        autospaceTile.isOn = settings.autospace
        barTile.isOn = settings.showsBar
        hapticsTile.isOn = settings.haptics
        trailsTile.isOn = settings.trails
        nextTile.isOn = settings.nextWords
        splitTile.isOn = settings.splitOnWide && allowsSplit
        splitTile.isEnabled = allowsSplit
        splitTile.subtitle = allowsSplit ? nil : "PRO"

        height.set(Double(settings.heightScale), text: percent(Double(settings.heightScale)))
        strict.set(settings.wordStrictness, text: percent(settings.wordStrictness))
        split.set(settings.splitStrictness, text: percent(settings.splitStrictness))
        wait.set(settings.autospaceDelay, text: "\(String(format: "%.1f", settings.autospaceDelay)) s",
                 spoken: "\(String(format: "%.1f", settings.autospaceDelay)) seconds")
        wait.slider.isEnabled = settings.autospace
        wait.alpha = settings.autospace ? 1 : 0.45

        let short = granted.got > 0 && granted.got < granted.asked - 0.5
        let lines = [short ? "iOS gave the keyboard \(Int(granted.got)) of the \(Int(granted.asked.rounded())) pt it asked for, so the keys are shorter." : nil,
                     heightStory].compactMap { $0 }
        note.text = lines.isEmpty ? nil : lines.joined(separator: " ")
        note.isHidden = lines.isEmpty
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    // MARK: Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        let side = Theme.Space.m
        let header = Self.headerHeight
        done.sizeToFit()
        let doneSize = CGSize(width: max(80, done.bounds.width), height: 34)
        done.frame = CGRect(x: bounds.maxX - side - doneSize.width, y: (header - doneSize.height) / 2,
                            width: doneSize.width, height: doneSize.height)
        back.sizeToFit()
        back.frame = CGRect(x: side - 4, y: (header - 44) / 2, width: max(44, back.bounds.width), height: 44)
        let titleX = showingLanguages ? back.frame.maxX : side + Theme.Space.xs
        title.frame = CGRect(x: titleX, y: 0, width: max(0, done.frame.minX - titleX - Theme.Space.s), height: header)
        let body = CGRect(x: 0, y: header, width: bounds.width, height: max(0, bounds.height - header))
        scroll.frame = body
        languageScroll.frame = body
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !flashedIndicators else { return }
        flashedIndicators = true
        // Shows there is more below when the list does not fit.
        Task { @MainActor [weak self] in self?.scroll.flashScrollIndicators() }
    }
}

/// A square switch, like Control Center's: a symbol over a name, `key` when off and
/// `accent` when on. VoiceOver reads it as a toggle button with its name.
final class QuickTile: UIControl {
    var isOn = false {
        didSet { if isOn != oldValue { restyle() } }
    }
    /// A second line under the name, like "PRO" when the tile can't turn on yet.
    var subtitle: String? {
        didSet { name.text = subtitle.map { "\(title) · \($0)" } ?? title; restyle() }
    }
    override var isEnabled: Bool {
        didSet { restyle() }
    }
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
                self.transform = self.isHighlighted && !UIAccessibility.isReduceMotionEnabled ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
            }
        }
    }

    private let title: String
    private let icon = UIImageView()
    private let name = UILabel()

    init(title: String, symbol: String) {
        self.title = title
        super.init(frame: .zero)
        layer.cornerRadius = Theme.Radius.sm
        layer.cornerCurve = .continuous
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold))
        icon.contentMode = .center
        name.text = title
        name.font = Theme.uiFont(size: 12, weight: .heavy, scaledWith: .caption1, upTo: 17)
        name.adjustsFontForContentSizeCategory = true
        name.textAlignment = .center
        // Two words may take two lines; one word stays on one line and shrinks a little
        // rather than breaking mid-word ("Autospa / ce").
        name.numberOfLines = title.contains(" ") ? 2 : 1
        name.lineBreakMode = .byWordWrapping
        name.adjustsFontSizeToFitWidth = true
        name.minimumScaleFactor = 0.7
        name.allowsDefaultTighteningForTruncation = true
        // Fill, not center: a centred multi-line label in a narrow tile gets squeezed to a
        // letter wide, so each letter went on its own line (Gabriel, 3 Nov 2026).
        let stack = UIStackView(arrangedSubviews: [icon, name])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
        isAccessibilityElement = true
        accessibilityTraits = [.button, .toggleButton]
        restyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func restyle() {
        backgroundColor = isOn ? Theme.ui(.accent) : Theme.ui(.key)
        let ink = isOn ? Theme.ui(.accentInk) : Theme.ui(.keyInk)
        icon.tintColor = ink.withAlphaComponent(isOn ? 1 : 0.65)
        name.textColor = ink
        alpha = isEnabled ? 1 : 0.5
        accessibilityLabel = subtitle.map { "\(title), \($0)" } ?? title
        accessibilityValue = isOn ? "On" : "Off"
        if isEnabled { accessibilityTraits.remove(.notEnabled) } else { accessibilityTraits.insert(.notEnabled) }
    }
}

/// A row that opens a page: a symbol, a name, the current value and a chevron.
private final class LinkRow: UIControl {
    var value: String? {
        didSet { detail.text = value; accessibilityValue = value }
    }
    private let name = UILabel()
    private let detail = UILabel()

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        let font = Theme.uiFont(size: 15, weight: .semibold, scaledWith: .body, upTo: 22)
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)))
        icon.tintColor = Theme.ui(.ink)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        name.text = title
        name.font = font
        name.textColor = Theme.ui(.ink)
        name.adjustsFontForContentSizeCategory = true
        name.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        name.setContentCompressionResistancePriority(.required, for: .horizontal)
        detail.font = font
        detail.textColor = Theme.ui(.muted)
        detail.textAlignment = .right
        detail.adjustsFontForContentSizeCategory = true
        detail.lineBreakMode = .byTruncatingTail
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
        chevron.tintColor = Theme.ui(.muted)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [icon, name, detail, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Theme.Space.s
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Space.xs),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Space.xs),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Space.m),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Space.m),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? Theme.ui(.keyPressed) : .clear }
    }
}

/// A row to pick: a name, a quieter second name, and a tick when it is on.
private final class CheckRow: UIControl {
    var isOn = false {
        didSet {
            tick.isHidden = !isOn
            accessibilityTraits = isOn ? [.button, .selected] : .button
        }
    }
    private let tick = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .black)))

    init(title: String, subtitle: String?) {
        super.init(frame: .zero)
        let name = UILabel()
        name.text = title
        name.font = Theme.uiFont(size: 15, weight: .semibold, scaledWith: .body, upTo: 22)
        name.textColor = Theme.ui(.ink)
        name.adjustsFontForContentSizeCategory = true
        let second = UILabel()
        second.text = subtitle
        second.font = Theme.uiFont(size: 13, weight: .regular, scaledWith: .footnote, upTo: 18)
        second.textColor = Theme.ui(.muted)
        second.adjustsFontForContentSizeCategory = true
        second.isHidden = subtitle == nil || subtitle == title
        let names = UIStackView(arrangedSubviews: [name, second])
        names.axis = .vertical
        names.spacing = 1
        tick.tintColor = Theme.ui(.accent)
        tick.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [names, tick])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Theme.Space.m
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Space.s),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Space.s),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Space.m),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Space.m),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityHint = subtitle
        accessibilityTraits = .button
        tick.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? Theme.ui(.keyPressed) : .clear }
    }
}

/// A name, a slider and its value at the end, at least 44 pt tall.
private final class SliderRow: UIStackView {
    let label = UILabel()
    let slider = UISlider()
    private let value = UILabel()
    var onChange: ((Double) -> Void)?

    init(title: String, range: ClosedRange<Double>, label accessibilityLabel: String) {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .center
        spacing = Theme.Space.m
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: Theme.Space.xs, leading: 0, bottom: Theme.Space.xs, trailing: 0)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        let font = Theme.uiFont(size: 15, weight: .semibold, scaledWith: .body, upTo: 22)
        label.text = title
        label.font = font
        label.textColor = Theme.ui(.ink)
        label.adjustsFontForContentSizeCategory = true
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.isAccessibilityElement = false
        value.font = font
        value.textColor = Theme.ui(.muted)
        value.textAlignment = .right
        value.adjustsFontForContentSizeCategory = true
        value.setContentHuggingPriority(.required, for: .horizontal)
        value.widthAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        value.isAccessibilityElement = false

        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.minimumTrackTintColor = Theme.ui(.accent)
        slider.accessibilityLabel = accessibilityLabel
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        slider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onChange?(Double(self.slider.value))
        }, for: .valueChanged)

        for view in [label, slider, value] { addArrangedSubview(view) }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func set(_ number: Double, text: String, spoken: String? = nil) {
        if !slider.isTracking { slider.value = Float(number) }
        value.text = text
        slider.accessibilityValue = spoken ?? text
    }
}

/// Lets a drag that starts on a tile scroll the list, while a drag on a slider still
/// moves the slider.
private final class PanelScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        !(view is UISlider)
    }
}
#endif
