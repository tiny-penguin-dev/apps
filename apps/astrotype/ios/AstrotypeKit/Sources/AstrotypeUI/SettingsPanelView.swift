#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// The in-keyboard settings behind the guesses bar's Astrotype button (or a held "123"
/// where that button has no place; features/settings/FEATURE.md): the core
/// few, so they can change without leaving the app being typed in, and so people
/// without Full Access (where the app's Settings can't reach the keyboard) can still
/// change them. Quick tiles (autospace, next word, the guesses bar, haptics, effects,
/// and the split on a wide screen), the height slider, Autocorrect's four levels with the
/// Fix missed spaces switch (Gabriel, 13 Nov 2026: in place of two sliders), autospace's
/// wait, a Languages row that opens the list of languages
/// (features/languages: any one free, two at once Pro), and a Theme row that opens the
/// themes (features/customization: Classic free, the rest Pro). The rest lives in the app.
/// Above them, "Switch keyboard" (iOS's own: a tap goes to the next keyboard, a hold
/// shows the list) and "Open Astrotype", which opens the app for the rest (Gabriel,
/// 8 Nov 2026: the globe moved in here).
///
/// Shown over the keys, on the keyboard's own backdrop (glass on iOS 26). The title and
/// Done head the tiles and sliders and scroll away with them when the keys' space is
/// shorter than them (Gabriel, 3 Nov 2026).
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
    /// Whether themes other than Classic may be chosen (Pro). Off, they show PRO and stay
    /// put.
    public var allowsStyles = true {
        didSet { if allowsStyles != oldValue { render() } }
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
    /// Whether the typing recorder is on (Settings → Debug → "Keep recording"): a
    /// Mark row shows, to note the moment something went wrong.
    public var isRecording = false {
        didSet { if isRecording != oldValue { render() } }
    }
    /// Mark tapped.
    public var onMark: (() -> Void)?
    /// Every touch on "Switch keyboard" with its event, for iOS's
    /// `handleInputModeList(from:with:)` (`KeyboardView.onGlobeTouch`). Nil, the row
    /// doesn't show.
    public var onSwitchTouch: ((UIView, UIEvent) -> Void)? {
        didSet { if (onSwitchTouch == nil) != (oldValue == nil) { render() } }
    }
    /// A finger lifted on "Switch keyboard".
    public var onSwitched: (() -> Void)?
    /// Whether "Open Astrotype" shows (the keyboard extension can open its app).
    public var canOpenApp = false {
        didSet { if canOpenApp != oldValue { render() } }
    }
    /// "Open Astrotype" tapped.
    public var onOpenApp: (() -> Void)?
    /// Whether "Text replacements" shows (the person has some, and they apply here).
    public var offersSnippets = false {
        didSet { if offersSnippets != oldValue { render() } }
    }
    /// "Text replacements" tapped: the keyboard shows them in place of the keys.
    public var onSnippets: (() -> Void)?

    private static let headerHeight: CGFloat = 48

    /// The title, Done and the back chevron. It rides at the top of whichever page is
    /// showing, inside its scroll view, so it scrolls with the content.
    private let header = UIView()
    private let title = UILabel()
    private let back = UIButton(configuration: .plain())
    private let done = UIButton(configuration: .filled())
    private let scroll = PanelScrollView()
    private let column = UIStackView()
    private let tileGrid = UIStackView()

    private let autospaceTile = QuickTile(title: "Autospace", symbol: "space")
    private let barTile = QuickTile(title: "Top bar", symbol: "rectangle.topthird.inset.filled")
    private let hapticsTile = QuickTile(title: "Haptics", symbol: "iphone.radiowaves.left.and.right")
    private let trailsTile = QuickTile(title: "Effects", symbol: "sparkles")
    private let splitTile = QuickTile(title: "Split", symbol: "rectangle.split.2x1")
    private let nextTile = QuickTile(title: "Predictions", symbol: "text.append")

    // Each slider has an ⓘ at its right end that shows what it does under it (Gabriel,
    // 9 Nov 2026: the sliders weren't clear, "what is it waiting for?").
    private let height = SliderRow(title: "Height", range: KeyboardSettings.heightRange, label: "Keyboard height",
                                   info: "How tall the keys are. At 100% every key sits right where Apple's keyboard puts it.")
    private let strict = ChoiceRow(title: "Autocorrect", choices: KeyboardSettings.Autocorrect.allCases.map(\.shortTitle),
                                   info: "When letters you tap don't spell a word, how readily it swaps in a real word. It holds back on its own: slow taps only get a one-letter slip fixed, and letters right after @ or # stay as you tap them.")
    private let split = SwitchRow(title: "Fix missed spaces",
                                  info: "Adds a space you missed (\u{201C}textseparately\u{201D} becomes \u{201C}text separately\u{201D}) or takes out one autospace put inside a word, as readily as Autocorrect says.")
    private let wait = SliderRow(title: "Autospace wait", range: KeyboardSettings.delayRange, label: "Autospace wait",
                                 info: "After you swipe a word and lift your finger, how long autospace waits before it writes the word and a space. Shorter is faster, but a pause mid-word can cut it in two.")
    private let note = UILabel()
    /// The Languages row: the ones on, and a chevron to the list.
    private let languagesLink = LinkRow(title: "Languages", symbol: "character.bubble")
    /// "Mark this moment", while recording.
    private let markRow = LinkRow(title: "Mark this moment", symbol: "record.circle", chevron: false)
    private lazy var markCard = card([markRow])
    /// "Switch keyboard" and "Open Astrotype", at the top.
    private let switchRow = LinkRow(title: "Switch keyboard", symbol: "globe", chevron: false)
    private let openRow = LinkRow(title: "Open Astrotype", symbol: "arrow.up.forward.app", chevron: false)
    /// The text replacements, to write one (features/text-replacements). They were a
    /// button on the bar until 9 Nov 2026.
    private let snippetsRow = LinkRow(title: "Text replacements", symbol: "text.insert", chevron: false)
    private lazy var actionsCard = card([switchRow, snippetsRow, openRow])
    private var markedAt: Date?
    /// The list of languages, shown in place of the settings when the row is tapped.
    private let languageScroll = PanelScrollView()
    private let languageList = UIStackView()
    /// One row per bundled language, named in itself ("Español").
    private let languageRows: [(code: String, row: CheckRow)] = Language.bundledCodes.map {
        ($0, CheckRow(title: Language.names[$0] ?? $0, subtitle: Language.englishNames[$0]))
    }
    private let languageNote = UILabel()
    /// The Theme row, and the themes' page.
    private let themeLink = LinkRow(title: "Theme", symbol: "paintpalette")
    private let themeScroll = PanelScrollView()
    private let themeList = UIStackView()
    private let themeNote = UILabel()
    /// The themes the rows were made for, to remake them when the person's change.
    private var themeRows: [(id: String, row: CheckRow)] = []

    private enum Page { case main, languages, themes }
    private var page = Page.main {
        didSet { if page != oldValue { showPage() } }
    }
    private let more = UILabel()
    private var flashedIndicators = false

    public init(settings: KeyboardSettings) {
        self.settings = settings
        super.init(frame: .zero)
        // Not `.clear`: iOS drops touches on fully clear pixels in a keyboard.
        backgroundColor = Theme.seeThrough

        title.text = "Keyboard settings"
        title.font = Theme.uiFont(size: 17, weight: .heavy)
        title.textColor = Theme.ui(.ink)
        title.accessibilityTraits = .header
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.8
        header.addSubview(title)

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = Theme.ui(.accent)
        config.baseForegroundColor = Theme.ui(.accentInk)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: Theme.Space.l, bottom: 6, trailing: Theme.Space.l)
        config.attributedTitle = AttributedString("Done", attributes: AttributeContainer([.font: Theme.uiFont(size: 15, weight: .bold)]))
        done.configuration = config
        done.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
        header.addSubview(done)

        var backConfig = UIButton.Configuration.plain()
        backConfig.image = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold))
        backConfig.baseForegroundColor = Theme.ui(.accent)
        backConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 8)
        back.configuration = backConfig
        back.accessibilityLabel = "Back to keyboard settings"
        back.addAction(UIAction { [weak self] _ in self?.page = .main }, for: .touchUpInside)
        back.isHidden = true
        header.addSubview(back)

        wire(autospaceTile) { $0.autospace.toggle() }
        wire(barTile) { $0.showsBar.toggle() }
        wire(hapticsTile) { $0.haptics.toggle() }
        wire(trailsTile) { $0.trails.toggle() }
        wire(splitTile) { $0.splitOnWide.toggle() }
        wire(nextTile) { $0.nextWords.toggle() }
        nextTile.accessibilityHint = "Likely next words in the top bar after each word"
        languagesLink.addAction(UIAction { [weak self] _ in self?.page = .languages }, for: .touchUpInside)
        themeLink.addAction(UIAction { [weak self] _ in self?.page = .themes }, for: .touchUpInside)
        switchRow.accessibilityHint = "Goes to the next keyboard. Touch and hold for the list"
        switchRow.addTarget(self, action: #selector(switchTouched(_:with:)), for: .allTouchEvents)
        switchRow.addAction(UIAction { [weak self] _ in self?.onSwitched?() }, for: .touchUpInside)
        openRow.accessibilityHint = "Opens the Astrotype app, for the rest of the settings"
        openRow.addAction(UIAction { [weak self] _ in self?.onOpenApp?() }, for: .touchUpInside)
        snippetsRow.accessibilityHint = "Shows your replacements to write one"
        snippetsRow.addAction(UIAction { [weak self] _ in self?.onSnippets?() }, for: .touchUpInside)
        markRow.accessibilityHint = "Notes that something went wrong just now, to send from the app's Debug page"
        markRow.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onMark?()
            self.markedAt = Date()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.render()
        }, for: .touchUpInside)
        for (code, row) in languageRows {
            row.addAction(UIAction { [weak self] _ in self?.toggleLanguage(code) }, for: .touchUpInside)
        }

        height.onChange = { [weak self] value in
            // In 5% steps, so 100% (Apple's) is easy to land on.
            self?.update { $0.keyboardHeight = (value * 20).rounded() / 20 }
        }
        strict.onChange = { [weak self] index in self?.update { $0.autocorrect = KeyboardSettings.Autocorrect.allCases[index] } }
        split.onChange = { [weak self] isOn in self?.update { $0.fixesSpaces = isOn } }
        wait.onChange = { [weak self] value in self?.update { $0.autospaceDelay = (value * 10).rounded() / 10 } }

        note.font = Theme.uiFont(size: 13, weight: .regular, scaledWith: .footnote, upTo: 18)
        note.textColor = Theme.ui(.muted)
        note.adjustsFontForContentSizeCategory = true
        note.numberOfLines = 0
        languageNote.font = note.font
        languageNote.textColor = Theme.ui(.muted)
        languageNote.adjustsFontForContentSizeCategory = true
        languageNote.numberOfLines = 0
        languageNote.text = "One language at a time. Pro types in two at once."
        themeNote.font = note.font
        themeNote.textColor = Theme.ui(.muted)
        themeNote.adjustsFontForContentSizeCategory = true
        themeNote.numberOfLines = 0
        themeNote.text = "Classic is free. Pro has every theme, and you can make your own in the app."
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

    @objc private func switchTouched(_ sender: UIView, with event: UIEvent) {
        onSwitchTouch?(sender, event)
    }

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
        for (index, row) in ([height, strict, split, wait] as [UIStackView]).enumerated() {
            if index > 0 {
                let line = UIView()
                line.backgroundColor = Theme.ui(.kb)
                line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                sliders.addArrangedSubview(line)
            }
            sliders.addArrangedSubview(row)
        }
        // The sliders start at the same place.
        wait.label.widthAnchor.constraint(equalTo: height.label.widthAnchor).isActive = true

        column.axis = .vertical
        column.spacing = Theme.Space.s
        column.translatesAutoresizingMaskIntoConstraints = false
        let languagesCard = card([languagesLink, themeLink])
        for view in [tileGrid, actionsCard, languagesCard, sliders, note, markCard, more] { column.addArrangedSubview(view) }

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

        // The themes page: a card of rows, the Pro note under it.
        themeList.axis = .vertical
        themeList.spacing = Theme.Space.s
        themeList.translatesAutoresizingMaskIntoConstraints = false
        themeScroll.showsHorizontalScrollIndicator = false
        themeScroll.alwaysBounceVertical = true
        themeScroll.delaysContentTouches = false
        themeScroll.isHidden = true
        themeScroll.addSubview(themeList)
        addSubview(themeScroll)
        NSLayoutConstraint.activate([
            themeList.topAnchor.constraint(equalTo: themeScroll.contentLayoutGuide.topAnchor),
            themeList.bottomAnchor.constraint(equalTo: themeScroll.contentLayoutGuide.bottomAnchor, constant: -Theme.Space.m),
            themeList.leadingAnchor.constraint(equalTo: themeScroll.frameLayoutGuide.leadingAnchor, constant: Theme.Space.m),
            themeList.trailingAnchor.constraint(equalTo: themeScroll.frameLayoutGuide.trailingAnchor, constant: -Theme.Space.m),
        ])

        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        scroll.delaysContentTouches = false
        scroll.backgroundColor = .clear
        scroll.addSubview(column)
        addSubview(scroll)

        // Both pages leave room at the top for the header, which sits in that room.
        for page in [scroll, languageScroll, themeScroll] {
            page.contentInsetAdjustmentBehavior = .never
            page.contentInset.top = Self.headerHeight
            page.verticalScrollIndicatorInsets.top = Self.headerHeight
            page.contentOffset = CGPoint(x: 0, y: -Self.headerHeight)
        }
        scroll.addSubview(header)

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
        scroll.isHidden = page != .main
        languageScroll.isHidden = page != .languages
        themeScroll.isHidden = page != .themes
        back.isHidden = page == .main
        let view: UIScrollView
        switch page {
        case .main: title.text = "Keyboard settings"; view = scroll
        case .languages: title.text = "Languages"; view = languageScroll
        case .themes: title.text = "Theme"; view = themeScroll
        }
        view.addSubview(header)
        view.contentOffset = CGPoint(x: 0, y: -Self.headerHeight)
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
        renderThemes()
        autospaceTile.isOn = settings.autospace
        barTile.isOn = settings.showsBar
        hapticsTile.isOn = settings.haptics
        trailsTile.isOn = settings.trails
        nextTile.isOn = settings.nextWords
        // Predictions show in the top bar, or in the column beside the keys on a wide
        // screen; with the bar off on a phone there is nowhere for them.
        nextTile.isEnabled = settings.showsBar || showsSplit
        splitTile.isOn = settings.splitOnWide && allowsSplit
        splitTile.isEnabled = allowsSplit
        splitTile.subtitle = allowsSplit ? nil : "PRO"

        height.set(Double(settings.heightScale), text: percent(Double(settings.heightScale)))
        strict.set(KeyboardSettings.Autocorrect.allCases.firstIndex(of: settings.autocorrect) ?? 1)
        split.set(settings.fixesSpaces)
        split.isEnabled = settings.autocorrect != .never
        wait.set(settings.autospaceDelay, text: "\(String(format: "%.1f", settings.autospaceDelay)) s",
                 spoken: "\(String(format: "%.1f", settings.autospaceDelay)) seconds")
        wait.slider.isEnabled = settings.autospace
        wait.alpha = settings.autospace ? 1 : 0.45

        let short = granted.got > 0 && granted.got < granted.asked - 0.5
        let lines = [short ? "iOS gave the keyboard \(Int(granted.got)) of the \(Int(granted.asked.rounded())) pt it asked for, so the keys are shorter." : nil,
                     heightStory].compactMap { $0 }
        note.text = lines.isEmpty ? nil : lines.joined(separator: " ")
        note.isHidden = lines.isEmpty

        markCard.isHidden = !isRecording
        switchRow.isHidden = onSwitchTouch == nil
        openRow.isHidden = !canOpenApp
        snippetsRow.isHidden = !offersSnippets
        // A hairline only between two rows that show.
        if let stack = actionsCard as? UIStackView {
            var rowAbove = false
            for (index, view) in stack.arrangedSubviews.enumerated() where index % 2 == 1 {
                rowAbove = rowAbove || !stack.arrangedSubviews[index - 1].isHidden
                view.isHidden = !rowAbove || stack.arrangedSubviews[index + 1].isHidden
            }
        }
        actionsCard.isHidden = switchRow.isHidden && snippetsRow.isHidden && openRow.isHidden
        // "Open Astrotype" says it already.
        more.isHidden = canOpenApp
        markRow.value = markedAt.map { "Marked \($0.formatted(date: .omitted, time: .shortened))" } ?? "Recording"
    }

    /// The themes page: every built-in theme and the person's own, the one in use ticked.
    private func renderThemes() {
        let themes = KeyboardTheme.builtIn + settings.customThemes
        let ids = themes.map(\.id)
        if themeRows.map(\.id) != ids {
            for view in themeList.arrangedSubviews { view.removeFromSuperview() }
            themeRows = themes.map { theme in
                let row = CheckRow(title: theme.name, subtitle: nil)
                row.addAction(UIAction { [weak self] _ in self?.chooseTheme(theme.id) }, for: .touchUpInside)
                return (theme.id, row)
            }
            themeList.addArrangedSubview(card(themeRows.map(\.row)))
            themeList.addArrangedSubview(themeNote)
        }
        let shown = settings.style(allows: allowsStyles)
        for (theme, (_, row)) in zip(themes, themeRows) {
            row.isOn = theme.id == shown.id
            row.subtitle = allowsStyles || theme.isFree ? nil : "PRO"
            row.alpha = allowsStyles || theme.isFree ? 1 : 0.5
        }
        themeNote.isHidden = allowsStyles
        themeLink.value = shown.name
    }

    private func chooseTheme(_ id: String) {
        guard allowsStyles || id == KeyboardTheme.classic.id else { return }
        update { $0.themeID = id }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    // MARK: Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        let side = Theme.Space.m
        let headerHeight = Self.headerHeight
        scroll.frame = bounds
        languageScroll.frame = bounds
        themeScroll.frame = bounds
        self.header.frame = CGRect(x: 0, y: -headerHeight, width: bounds.width, height: headerHeight)
        done.sizeToFit()
        let doneSize = CGSize(width: max(80, done.bounds.width), height: 34)
        done.frame = CGRect(x: bounds.maxX - side - doneSize.width, y: (headerHeight - doneSize.height) / 2,
                            width: doneSize.width, height: doneSize.height)
        back.sizeToFit()
        back.frame = CGRect(x: side - 4, y: (headerHeight - 44) / 2, width: max(44, back.bounds.width), height: 44)
        let titleX = page != .main ? back.frame.maxX : side + Theme.Space.xs
        title.frame = CGRect(x: titleX, y: 0, width: max(0, done.frame.minX - titleX - Theme.Space.s), height: headerHeight)
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
        // The icon sits at the same height in every tile, and the name is centred in
        // the room under it, so a one-line name and a two-line one still line up across
        // the row (tiles in a row share a height). The label spans the tile's width: a
        // narrow multi-line label gets squeezed a letter wide (Gabriel, 3 Nov 2026).
        for view in [icon, name] {
            view.isUserInteractionEnabled = false
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            icon.heightAnchor.constraint(equalToConstant: 24),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor),
            icon.trailingAnchor.constraint(equalTo: trailingAnchor),
            name.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 4),
            name.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
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

    init(title: String, symbol: String, chevron showsChevron: Bool = true) {
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
        chevron.isHidden = !showsChevron
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
        didSet {
            // Rounded like the card, which no longer clips its rows.
            layer.cornerRadius = Theme.Radius.sm
            layer.cornerCurve = .continuous
            backgroundColor = isHighlighted ? Theme.ui(.keyPressed) : .clear
        }
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
    private let second = UILabel()
    private let title: String
    /// The quieter second line, like "PRO".
    var subtitle: String? {
        didSet {
            second.text = subtitle
            second.isHidden = subtitle == nil || subtitle == title
            accessibilityHint = subtitle
        }
    }

    init(title: String, subtitle: String?) {
        self.title = title
        super.init(frame: .zero)
        let name = UILabel()
        name.text = title
        name.font = Theme.uiFont(size: 15, weight: .semibold, scaledWith: .body, upTo: 22)
        name.textColor = Theme.ui(.ink)
        name.adjustsFontForContentSizeCategory = true
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
        didSet {
            // Rounded like the card, which no longer clips its rows.
            layer.cornerRadius = Theme.Radius.sm
            layer.cornerCurve = .continuous
            backgroundColor = isHighlighted ? Theme.ui(.keyPressed) : .clear
        }
    }
}

/// A name, a slider and its value at the end, at least 44 pt tall.
private final class SliderRow: UIStackView {
    let label = UILabel()
    let slider = UISlider()
    private let value = UILabel()
    /// What the slider does, under it, shown and hidden by the ⓘ at the row's end.
    private let detail = UILabel()
    private let infoButton = UIButton(configuration: .plain())
    var onChange: ((Double) -> Void)?

    init(title: String, range: ClosedRange<Double>, label accessibilityLabel: String, info: String) {
        super.init(frame: .zero)
        axis = .vertical
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: Theme.Space.xs, leading: 0, bottom: Theme.Space.xs, trailing: 0)

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
        slider.accessibilityHint = info
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        slider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onChange?(Double(self.slider.value))
        }, for: .valueChanged)

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "info.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        config.baseForegroundColor = Theme.ui(.muted)
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 0)
        infoButton.configuration = config
        infoButton.setContentHuggingPriority(.required, for: .horizontal)
        infoButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        infoButton.accessibilityLabel = "About \(accessibilityLabel)"
        infoButton.addAction(UIAction { [weak self] _ in self?.toggleDetail() }, for: .touchUpInside)

        detail.text = info
        detail.font = Theme.uiFont(size: 13, weight: .regular, scaledWith: .footnote, upTo: 18)
        detail.textColor = Theme.ui(.muted)
        detail.adjustsFontForContentSizeCategory = true
        detail.numberOfLines = 0
        detail.isHidden = true

        let row = UIStackView(arrangedSubviews: [label, slider, value, infoButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Theme.Space.m
        row.setCustomSpacing(Theme.Space.xs, after: value)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        addArrangedSubview(row)
        addArrangedSubview(detail)
        setCustomSpacing(Theme.Space.xs, after: row)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func toggleDetail() {
        let show = detail.isHidden
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2) {
            self.detail.isHidden = !show
            self.detail.alpha = show ? 1 : 0
            self.superview?.layoutIfNeeded()
        }
        infoButton.configuration?.image = UIImage(systemName: show ? "info.circle.fill" : "info.circle",
                                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        if show { UIAccessibility.post(notification: .announcement, argument: detail.text) }
    }

    func set(_ number: Double, text: String, spoken: String? = nil) {
        if !slider.isTracking { slider.value = Float(number) }
        value.text = text
        slider.accessibilityValue = spoken ?? text
    }
}

/// The ⓘ at a row's end and the note it shows under the row.
@MainActor
private func infoParts(label: String, info: String, onTap: @escaping () -> Void) -> (UIButton, UILabel) {
    let button = UIButton(configuration: .plain())
    var config = UIButton.Configuration.plain()
    config.image = UIImage(systemName: "info.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
    config.baseForegroundColor = Theme.ui(.muted)
    config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 0)
    button.configuration = config
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    button.accessibilityLabel = "About \(label)"
    button.addAction(UIAction { _ in onTap() }, for: .touchUpInside)
    let detail = UILabel()
    detail.text = info
    detail.font = Theme.uiFont(size: 13, weight: .regular, scaledWith: .footnote, upTo: 18)
    detail.textColor = Theme.ui(.muted)
    detail.adjustsFontForContentSizeCategory = true
    detail.numberOfLines = 0
    detail.isHidden = true
    return (button, detail)
}

@MainActor
private func toggle(_ detail: UILabel, button: UIButton, in view: UIView) {
    let show = detail.isHidden
    UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2) {
        detail.isHidden = !show
        detail.alpha = show ? 1 : 0
        view.superview?.layoutIfNeeded()
    }
    button.configuration?.image = UIImage(systemName: show ? "info.circle.fill" : "info.circle",
                                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
    if show { UIAccessibility.post(notification: .announcement, argument: detail.text) }
}

private func rowLabel(_ title: String) -> UILabel {
    let label = UILabel()
    label.text = title
    label.font = Theme.uiFont(size: 15, weight: .semibold, scaledWith: .body, upTo: 22)
    label.textColor = Theme.ui(.ink)
    label.adjustsFontForContentSizeCategory = true
    label.numberOfLines = 0
    label.isAccessibilityElement = false
    return label
}

/// A few choices in a segmented control under the row's title, with an ⓘ.
private final class ChoiceRow: UIStackView {
    let control: UISegmentedControl
    private var detail = UILabel()
    private var infoButton = UIButton()
    var onChange: ((Int) -> Void)?

    init(title: String, choices: [String], info: String) {
        control = UISegmentedControl(items: choices)
        super.init(frame: .zero)
        axis = .vertical
        spacing = Theme.Space.xs
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: Theme.Space.xs, leading: 0, bottom: Theme.Space.s, trailing: 0)
        (infoButton, detail) = infoParts(label: title, info: info) { [weak self] in
            guard let self else { return }
            toggle(self.detail, button: self.infoButton, in: self)
        }
        let label = rowLabel(title)
        let header = UIStackView(arrangedSubviews: [label, UIView(), infoButton])
        header.axis = .horizontal
        header.alignment = .center
        header.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        control.accessibilityLabel = title
        control.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onChange?(self.control.selectedSegmentIndex)
        }, for: .valueChanged)
        addArrangedSubview(header)
        addArrangedSubview(control)
        addArrangedSubview(detail)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func set(_ index: Int) {
        if control.selectedSegmentIndex != index { control.selectedSegmentIndex = index }
    }
}

/// A title and a switch, with an ⓘ.
private final class SwitchRow: UIStackView {
    let toggleSwitch = UISwitch()
    private var detail = UILabel()
    private var infoButton = UIButton()
    var onChange: ((Bool) -> Void)?
    var isEnabled = true {
        didSet {
            toggleSwitch.isEnabled = isEnabled
            alpha = isEnabled ? 1 : 0.45
        }
    }

    init(title: String, info: String) {
        super.init(frame: .zero)
        axis = .vertical
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: Theme.Space.xs, leading: 0, bottom: Theme.Space.xs, trailing: 0)
        (infoButton, detail) = infoParts(label: title, info: info) { [weak self] in
            guard let self else { return }
            toggle(self.detail, button: self.infoButton, in: self)
        }
        let label = rowLabel(title)
        toggleSwitch.onTintColor = Theme.ui(.accent)
        toggleSwitch.accessibilityLabel = title
        toggleSwitch.accessibilityHint = info
        toggleSwitch.setContentHuggingPriority(.required, for: .horizontal)
        toggleSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onChange?(self.toggleSwitch.isOn)
        }, for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [label, UIView(), toggleSwitch, infoButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Theme.Space.s
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        addArrangedSubview(row)
        addArrangedSubview(detail)
        setCustomSpacing(Theme.Space.xs, after: row)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func set(_ isOn: Bool) {
        if toggleSwitch.isOn != isOn { toggleSwitch.setOn(isOn, animated: false) }
    }
}

/// Lets a drag that starts on a tile scroll the list, while a drag on a slider still
/// moves the slider. The content fades out at the top and bottom where there is more.
private final class PanelScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        !(view is UISlider)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fadeEdges(.vertical, length: 24)
    }
}
#endif
