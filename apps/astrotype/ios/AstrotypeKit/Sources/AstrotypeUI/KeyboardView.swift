#if canImport(UIKit)
import AstrotypeCore
import UIKit

/// The whole keyboard: the bar and the key surface, driven by a `KeyboardModel`. The
/// extension puts it in its input view; the app's practice field uses it as the input
/// view of a text view, so both run the same engine and the same views. Switches
/// between the letters, numbers and symbols pages and the emoji page (which takes the
/// bar's room too, features/emoji), and shows the settings panel.
///
/// The keys sit where Apple's do, at the person's keyboard height
/// (`KeyboardSettings.keyboardHeight`), at the bottom of the room they are given, with
/// no padding at the sides or the top (iOS pads the keyboard). The guesses sit beside
/// the keys where the layout leaves a column for them (the middle of a split keyboard,
/// the sides of a wide one), else in a bar on top that adds to the height, which the
/// person can turn off (`KeyboardSettings.showsBar`).
///
///     let keyboard = KeyboardView(model: model)
///     keyboard.onSystemKey = { key in if key == .globe { advanceToNextInputMode() } }
public final class KeyboardView: UIView, KeySurfaceDelegate, UIInputViewAudioFeedback {
    public static let barHeight: CGFloat = 44
    /// The narrowest open column beside the keys that takes the guesses.
    public static let columnWidth: CGFloat = 96

    public let model: KeyboardModel
    public let bar = BarView()
    public let surface = KeySurfaceView()
    /// The tiny memory readout in the keys' top corner, while
    /// `KeyboardSettings.showsStats` is on (Settings → Debug): one line below the keys.
    public let stats = StatsOverlayView()
    /// A small red dot in the keys' top left corner while the typing recorder is on
    /// (Settings → Debug → "Keep recording"), so it is never on unnoticed.
    public let recordingDot = UIView()
    /// The host draws the keyboard's backdrop (the extension: the system's glass), so
    /// the view stays clear. Themes never paint a background (Gabriel, 6 Nov 2026).
    public var usesSystemBackdrop = false {
        didSet { if usesSystemBackdrop != oldValue { applyBackdrop() } }
    }
    /// Keys the engine leaves to the host: the globe.
    public var onSystemKey: ((Key) -> Void)?
    /// Whether the keyboard has our globe key: the extension sets it from
    /// `needsInputModeSwitchKey` (true only where iOS draws no globe of its own). It
    /// sits at the bar's leading end when the bar is on top, else on the bottom row
    /// before the emoji key (features/space-bar).
    public var showsGlobe = false {
        didSet { if showsGlobe != oldValue { setNeedsLayout() } }
    }
    /// The keyboard's height changed with its width (a wide screen has taller keys).
    public var onHeightChange: ((CGFloat) -> Void)?
    /// The settings panel, the emoji page or emoji search opened, for the keyboard's
    /// memory readings (`KeyboardHealth.Part`).
    public var onPart: ((KeyboardHealth.Part) -> Void)?
    /// Whether the Metal effects are loaded in this process (then they stay).
    public static var metalLoaded: Bool { MetalKeyboard.loaded }
    /// How long the Metal shaders took to compile, ms; 0 until they have.
    public static var metalLoadMillis: Int { MetalKeyboard.loadMillis }

    public private(set) var page: Layout.Page = .letters {
        didSet {
            guard page != oldValue else { return }
            surface.layout = pageLayout(width: model.layout.width, height: keysHeight)
            model.pageChanged(page)
        }
    }

    /// The height the keys fill: what they want, or less when the view is shorter.
    private var keysHeight: CGFloat?
    /// Where the guesses are now.
    private var place: BarPlace = .top
    /// The height last asked of the host, to tell it when that changes.
    private var asked: CGFloat = 0

    /// Where the guesses go.
    enum BarPlace: Equatable {
        /// A bar above the keys.
        case top
        /// A column beside the keys, over this stretch of the width.
        case column(ClosedRange<CGFloat>)
        /// Nowhere: no room beside the keys and the bar is off.
        case hidden
    }

    private var panel: SettingsPanelView?
    /// Whether the host can play haptics at all: the extension only with Full Access
    /// (DESIGN.md "Motion"), the app always. With the haptics setting, decides `play`.
    public var hapticsAvailable = true {
        didSet { if hapticsAvailable && !oldValue { keyHaptic.prepare() } }
    }
    /// Our globe in the bar's left slot (features/space-bar): SF Symbol `globe` in
    /// the bar's `dimInk`, like the pencil at the other end, no key background; the bar gives it
    /// its 44 pt slot.
    private lazy var globeKey: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        config.baseForegroundColor = Theme.ui(.muted)
        let button = UIButton(configuration: config)
        button.accessibilityLabel = "Next keyboard"
        button.addAction(UIAction { [weak self] _ in self?.onSystemKey?(.globe) }, for: .touchUpInside)
        return button
    }()
    private let keyHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let commitHaptic = UIImpactFeedbackGenerator(style: .light)

    public init(model: KeyboardModel) {
        self.model = model
        LiveCount.keyboardViews.add(1, ordering: .relaxed)
        super.init(frame: CGRect(x: 0, y: 0, width: model.layout.width, height: Self.barHeight + model.layout.height))
        asked = height
        backgroundColor = Theme.ui(.kb)
        addSubview(bar)
        addSubview(surface)
        addSubview(stats)
        recordingDot.backgroundColor = .systemRed
        recordingDot.layer.cornerRadius = 3
        recordingDot.isUserInteractionEnabled = false
        recordingDot.isHidden = true
        recordingDot.accessibilityLabel = "Recording typing"
        addSubview(recordingDot)
        surface.delegate = self
        surface.onFlow = { [weak self] state in self?.flowChanged(state) }
        surface.onOtherTouch = { [weak model] phase, id, point, time, key in
            model?.otherTouch(phase, id: id, at: point, time: time, key: key)
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: KeyboardView, _: UITraitCollection) in
            self.applyBackdrop()
        }
        // Held keys offer the accents of the languages being typed (features/languages).
        surface.alternates = { [weak model] key in Accents.alternates(for: key, languages: model?.activeLanguages ?? []) }
        surface.layout = model.layout
        bar.onChoose = { [weak self] index in self?.model.choose(guess: index) }
        bar.onChooseFix = { [weak self] reading in self?.model.chooseFix(reading: reading) }
        bar.onBoost = { [weak self] index, how in self?.model.boost(guess: index, how: how) }
        bar.onForget = { [weak self] index, how in self?.model.forget(guess: index, how: how) }
        bar.onUndo = { [weak self] in self?.model.undoWordChange() }
        bar.onMenu = { [weak self] in self?.model.wordMenuOpened() }
        bar.knows = { [weak self] index in self?.model.knows(guess: index) ?? true }
        bar.onNotIt = { [weak self] in self?.model.beginCorrection() }
        bar.onCancelCorrection = { [weak self] in self?.model.cancelCorrection() }
        bar.onSaveCorrection = { [weak self] in self?.model.saveCorrection() }
        attachToModel()
        keyHaptic.prepare()
    }

    /// Makes this view the one the model draws to (its changes, haptics and notices),
    /// and draws it now. Called when it shows again, since several keyboard views can
    /// share one model (the extension keeps one per process).
    public func attachToModel() {
        model.onChange = { [weak self] in self?.render() }
        model.onHaptic = { [weak self] haptic in self?.play(haptic) }
        model.onNotice = { [weak self] notice in
            switch notice {
            case .twoThumbsIsPro: self?.bar.flash("Two thumbs is in Astrotype Pro")
            }
        }
        render()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        LiveCount.keyboardViews.subtract(1, ordering: .relaxed)
    }

    /// Off screen: drops the drawing surfaces the effects hold (`KeySurfaceView.rest`),
    /// so a hidden keyboard costs little. `wake` before it shows again.
    public func rest() { surface.rest() }
    public func wake() { surface.wake() }

    public var enableInputClicksWhenVisible: Bool { true }

    /// The height to ask the host for at a width: the keys where Apple's are (at the
    /// person's height), plus the bar when it sits on top.
    public func height(forWidth width: CGFloat) -> CGFloat {
        let keys = Layout.qwerty(width: width, split: model.splitOnWide, extraLetters: extraLetters, globe: showsGlobe, scale: scale,
                                 bottom: model.field.bottomRow)
        if searchView != nil { return EmojiSearchView.height + keys.height }
        return barPlace(for: keys) == .top ? Self.barHeight + keys.height : keys.height
    }

    /// The person's keyboard height against Apple's.
    private var scale: CGFloat { model.keyboardSettings.heightScale }

    /// The height to ask for at the current width.
    public var height: CGFloat { height(forWidth: model.layout.width) }

    /// The widest column the keys leave open, else the bar on top if it is on.
    func barPlace(for layout: Layout) -> BarPlace {
        let columns = layout.openColumns(atLeast: Self.columnWidth)
        if let column = columns.max(by: { $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound }) {
            return .column(column)
        }
        return model.keyboardSettings.showsBar ? .top : .hidden
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    /// Lays the guesses and the keys out for the view's size: the keys take the height
    /// they want at the bottom (so they line up with Apple's), or shrink when the host
    /// granted less, with the bar right above them when it is on top. `height` stays the
    /// height to ask for, which hosts pass to the system.
    public override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0 else { return }
        let split = model.splitOnWide
        let bottom = model.field.bottomRow
        let natural = Layout.qwerty(width: width, split: split, extraLetters: extraLetters, globe: showsGlobe, scale: scale,
                                    bottom: bottom)
        let place = barPlace(for: natural)
        let barOnTop = place == .top
        // Emoji search puts its field and results over the keys instead of the bar.
        let above = searchView != nil ? EmojiSearchView.height : barOnTop ? Self.barHeight : 0
        let room = bounds.height - above
        let fill: CGFloat? = room > 0 ? min(room, natural.height) : nil
        if model.layout.width != width || model.layout.split != natural.split || model.layout.extraLetters != natural.extraLetters
            || model.layout.globe != rowGlobe(place) || model.layout.bottomRow != bottom || fill != keysHeight || place != self.place {
            keysHeight = fill
            self.place = place
            model.layout = Layout.qwerty(width: width, split: split, extraLetters: extraLetters, globe: rowGlobe(place), height: fill,
                                         bottom: bottom)
            surface.layout = pageLayout(width: width, height: fill)
        }
        let wanted = height
        if wanted != asked {
            asked = wanted
            invalidateIntrinsicContentSize()
            onHeightChange?(wanted)
        }
        let keys = model.layout.height
        let top = max(0, bounds.height - keys - (barOnTop ? Self.barHeight : 0))
        bar.leadingKey = showsGlobe && place == .top ? globeKey : nil
        switch place {
        case .top:
            bar.isHidden = false
            bar.axis = .horizontal
            bar.frame = CGRect(x: 0, y: top, width: width, height: Self.barHeight)
            surface.frame = CGRect(x: 0, y: top + Self.barHeight, width: width, height: keys)
        case .column(let column):
            surface.frame = CGRect(x: 0, y: top, width: width, height: keys)
            bar.isHidden = false
            bar.axis = .vertical
            bar.frame = CGRect(x: column.lowerBound, y: top, width: column.upperBound - column.lowerBound, height: keys)
            // Over the keys' open column; touches between the guesses fall through.
            bringSubviewToFront(bar)
        case .hidden:
            bar.isHidden = true
            surface.frame = CGRect(x: 0, y: top, width: width, height: keys)
        }
        if let searchView {
            // One row taller than the bar (features/emoji-search), wherever the guesses
            // usually go.
            bar.isHidden = true
            surface.frame = CGRect(x: 0, y: bounds.height - keys, width: width, height: keys)
            searchView.frame = CGRect(x: 0, y: max(0, surface.frame.minY - EmojiSearchView.height), width: width,
                                      height: EmojiSearchView.height)
            bringSubviewToFront(searchView)
        }
        if let emojiPage {
            // The bar's room and the keys', so the keyboard keeps its height.
            let top = place == .top ? bar.frame.minY : surface.frame.minY
            emojiPage.frame = CGRect(x: 0, y: top, width: width, height: surface.frame.maxY - top)
            bar.isHidden = true
            surface.isHidden = true
        } else {
            surface.isHidden = false
        }
        // The stats sit centred in the strip below the keys (iOS gives it no touches
        // anyway), under the panel and the emoji page (Gabriel, 7 Nov 2026: small, one
        // line, at the very bottom).
        if stats.isRunning {
            let size = stats.sizeThatFits(CGSize(width: width - 8, height: .greatestFiniteMagnitude))
            let w = min(ceil(size.width) + 4, width - 8), h = ceil(size.height)
            stats.frame = CGRect(x: ((width - w) / 2).rounded(), y: bounds.height - h - 1, width: w, height: h)
            stats.isHidden = emojiPage != nil || panel != nil
            bringSubviewToFront(stats)
        }
        // The recording dot sits in the bottom-left corner of the page key ("123" or
        // "ABC"), out of the way of the letters (Gabriel, 7 Nov 2026).
        recordingDot.isHidden = model.recorder == nil || emojiPage != nil || panel != nil
        if !recordingDot.isHidden {
            let corner = surface.pageKeyFrame.map { convert($0, from: surface) }
                ?? CGRect(x: surface.frame.minX, y: surface.frame.maxY - 8, width: 8, height: 8)
            recordingDot.frame = CGRect(x: corner.minX + 4, y: corner.maxY - 10, width: 6, height: 6)
            bringSubviewToFront(recordingDot)
        }
        if let panel {
            // Over the keys and the guesses bar both: the bar has nothing to say while
            // the settings are open (Gabriel, 3 Nov 2026). The keys hide too: the panel
            // is see-through so the glass shows, and the letters showed through with it
            // (Gabriel, 4 Nov 2026).
            bar.isHidden = true
            surface.isHidden = true
            panel.frame = CGRect(x: 0, y: top, width: width, height: max(0, bounds.height - top))
            panel.granted = (bounds.height, wanted)
            bringSubviewToFront(panel)
        }
    }

    private func pageLayout(width: CGFloat, height: CGFloat?) -> Layout {
        Layout.qwerty(width: width, page: page, split: model.splitOnWide, extraLetters: extraLetters, globe: rowGlobe(place),
                      height: height, bottom: model.field.bottomRow)
    }

    /// Whether our globe goes on the bottom row: only when there's no bar on top to
    /// hold it (the bar is off, or the guesses are a column).
    private func rowGlobe(_ place: BarPlace) -> Bool { showsGlobe && place != .top }

    /// The split's extra letters, as set.
    private var extraLetters: Bool { model.keyboardSettings.splitExtraLetters
    }

    /// What the bar says when idle, unless the host set its own note.
    public var usesDefaultNote = true

    /// How the last opening went when iOS did not give the height asked for at first,
    /// from the host, for the settings panel to show. Nil when it did.
    public var heightStory: String? {
        didSet { panel?.heightStory = heightStory }
    }

    /// The field the keys were last set up for: a new one opens on its page.
    private var shownField: Field?

    private func render() {
        let wasCorrecting = { if case .correcting = self.bar.bar { true } else { false } }()
        bar.canCorrect = model.state.canCorrect
        if shownField != model.field {
            shownField = model.field
            page = model.field.startPage
            setNeedsLayout()
        }
        surface.returnKey = model.field.returnKey
        surface.returnEnabled = model.returnEnabled
        bar.bar = model.state.bar
        // Saved from "Not it?": the commit squeeze (DESIGN.md "Commit").
        if wasCorrecting, case .idle = model.state.bar, !model.state.canCorrect {
            UIView.animate(withDuration: 0.12, animations: { self.bar.transform = CGAffineTransform(scaleX: 0.97, y: 0.97) }) { _ in
                UIView.animate(withDuration: 0.15) { self.bar.transform = .identity }
            }
        }
        if usesDefaultNote {
            bar.note = model.entitlement.allows(.twoThumbs) ? "Both thumbs, one word" : "One finger at a time"
        }
        if let searchView { showSearchResults(in: searchView) }
        surface.shifted = model.state.isShifted
        // Themes and effects are Pro, except Classic and Calm (features/customization).
        surface.theme = model.keyboardSettings.style(allows: model.entitlement.allows(.styles))
        surface.keyAppearance = model.keyboardSettings.keyAppearance
        bar.keyTheme = surface.theme
        bar.keyAppearance = surface.keyAppearance
        globeKey.configuration?.baseForegroundColor = bar.dimInk
        surface.effects = model.keyboardSettings.activeEffects(allows: model.entitlement.allows(.effects))
        applyBackdrop()
        surface.spaceSlideEnabled = model.keyboardSettings.spaceSlide
        surface.backspaceSwipeEnabled = model.keyboardSettings.backspaceSwipe
        if recordingDot.isHidden != (model.recorder == nil || emojiPage != nil || panel != nil) { setNeedsLayout() }
        panel?.isRecording = model.recorder != nil
        if stats.isRunning != model.keyboardSettings.showsStats {
            stats.isRunning = model.keyboardSettings.showsStats
            setNeedsLayout()
        }
        panel?.allowsSplit = model.entitlement.allows(.splitLayout)
        panel?.showsSplit = model.layout.isWide
        panel?.allowsTwoLanguages = model.entitlement.allows(.twoLanguages)
        panel?.allowsStyles = model.entitlement.allows(.styles)
        if model.layout.split != (model.splitOnWide && model.layout.isWide)
            || model.layout.extraLetters != (model.layout.split && extraLetters) || barPlace(for: model.layout) != place
            || model.layout.bottomRow != model.field.bottomRow
            || height != asked { setNeedsLayout() }
    }

    // MARK: Look and flow

    /// The backdrop stays the host's whatever the theme: the system's glass in the
    /// extension, `kb` in the app. The keys' surface stays see-through over it.
    private func applyBackdrop() {
        if !usesSystemBackdrop { surface.backgroundColor = .clear }
        backgroundColor = usesSystemBackdrop ? .clear : Theme.ui(.kb)
    }

    private func flowChanged(_ state: FlowState) {
        if state.leveledUp, hapticsAvailable, model.keyboardSettings.haptics { commitHaptic.impactOccurred(intensity: 0.8) }
    }

    private func play(_ haptic: Composer.Haptic) {
        if haptic == .key { UIDevice.current.playInputClick() }
        guard hapticsAvailable, model.keyboardSettings.haptics else { return }
        switch haptic {
        case .key: keyHaptic.impactOccurred()
        case .commit: commitHaptic.impactOccurred()
        }
    }

    // MARK: Settings panel

    /// Show the in-keyboard settings over the keys.
    public func showSettings() {
        guard panel == nil else { return }
        let panel = SettingsPanelView(settings: model.keyboardSettings)
        panel.allowsSplit = model.entitlement.allows(.splitLayout)
        panel.showsSplit = model.layout.isWide
        panel.allowsTwoLanguages = model.entitlement.allows(.twoLanguages)
        panel.allowsStyles = model.entitlement.allows(.styles)
        panel.preferredLanguages = model.preferredLanguages
        panel.onChange = { [weak self] settings in self?.model.keyboardSettings = settings }
        panel.onDone = { [weak self] in self?.hideSettings() }
        panel.isRecording = model.recorder != nil
        panel.onMark = { [weak self] in self?.model.markMoment() }
        panel.frame = surface.frame
        panel.granted = (bounds.height, height)
        panel.heightStory = heightStory
        addSubview(panel)
        self.panel = panel
        setNeedsLayout()
        onPart?(.settings)
    }

    public func hideSettings() {
        panel?.removeFromSuperview()
        panel = nil
        setNeedsLayout()
    }

    // MARK: Emoji page

    private var emojiPage: EmojiPageView?
    /// Read when the page first opens, then kept: the list is the same all session.
    private var emojiCatalog: EmojiCatalog?

    /// Whether the emoji page is showing.
    public var showsEmoji: Bool { emojiPage != nil }

    /// Show the emoji page in place of the bar and the keys.
    public func showEmoji() {
        guard emojiPage == nil else { return }
        if emojiCatalog == nil {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            emojiCatalog = (try? EmojiCatalog.bundled(upTo: EmojiCatalog.version(forOS: os.majorVersion, os.minorVersion)))
                ?? EmojiCatalog(sections: [])
        }
        let page = EmojiPageView(catalog: emojiCatalog!)
        page.tone = { [weak self] base in self?.model.emojiHistory.tone(for: base) ?? base }
        page.frequent = model.emojiHistory.frequent(now: Date())
        page.onEmoji = { [weak self] form, base in self?.model.type(emoji: form, base: base) }
        page.onTone = { [weak self] form, base in self?.model.setTone(form, for: base) }
        page.onDelete = { [weak self] in self?.model.press(.backspace) }
        page.onABC = { [weak self] in self?.hideEmoji() }
        page.onSearch = { [weak self] in self?.startEmojiSearch() }
        addSubview(page)
        emojiPage = page
        hideSettings()
        setNeedsLayout()
        layoutIfNeeded()
        UIAccessibility.post(notification: .screenChanged, argument: page)
        onPart?(.emoji)
    }

    /// Back to the letters.
    public func hideEmoji() {
        guard let emojiPage else { return }
        emojiPage.removeFromSuperview()
        self.emojiPage = nil
        page = .letters
        setNeedsLayout()
        layoutIfNeeded()
        UIAccessibility.post(notification: .screenChanged, argument: surface)
    }

    // MARK: Emoji search

    private var searchView: EmojiSearchView?
    /// Built when search first opens, for the languages then: names load only if used.
    private var emojiSearch: (languages: [String], search: EmojiSearch)?

    /// Whether emoji search is open.
    public var showsEmojiSearch: Bool { searchView != nil }

    /// "Search emoji" on the emoji page: the letters come back with the search field
    /// and a row of results above them, and the keys type into the field.
    public func startEmojiSearch() {
        guard searchView == nil else { return }
        emojiPage?.removeFromSuperview()
        emojiPage = nil
        model.beginEmojiSearch()
        let view = EmojiSearchView()
        view.onEmoji = { [weak self] form, base in self?.model.typeFromSearch(emoji: form, base: base) }
        view.onClear = { [weak self] in self?.model.clearSearch() }
        addSubview(view)
        searchView = view
        page = .letters
        showSearchResults(in: view, force: true)
        setNeedsLayout()
        layoutIfNeeded()
        UIAccessibility.post(notification: .screenChanged, argument: view.field)
        onPart?(.emojiSearch)
    }

    /// Search closes: back to the emoji page (the smiley key, done), or to the letters.
    public func endEmojiSearch(toEmojiPage: Bool) {
        guard let searchView else { return }
        searchView.removeFromSuperview()
        self.searchView = nil
        model.endEmojiSearch()
        if toEmojiPage {
            showEmoji()
        } else {
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    /// The search last shown, so a render that changed nothing (a finger moving) doesn't
    /// search again.
    private var shownSearch: String?

    private func showSearchResults(in view: EmojiSearchView, force: Bool = false) {
        let query = model.searchQuery
        guard force || query != shownSearch else { return }
        shownSearch = query
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            let frequent = model.emojiHistory.frequent(now: Date())
            view.show(query: query, results: frequent.map { (form: $0, base: emojiCatalog?.emoji(for: $0)?.text ?? $0) })
            return
        }
        let languages = model.activeLanguages
        if emojiSearch?.languages != languages, let catalog = emojiCatalog {
            emojiSearch = (languages, EmojiSearch(catalog: catalog, names: languages.compactMap(EmojiNames.bundled)))
        }
        let history = model.emojiHistory
        let found = emojiSearch?.search.results(for: query, history: history) ?? []
        view.show(query: query, results: found.map { (form: $0.hasTones ? history.tone(for: $0.text) : $0.text, base: $0.text) })
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        // The keyboard went away mid-search: it comes back typing into the app.
        if window == nil {
            endEmojiSearch(toEmojiPage: false)
            surface.resetFlow()
        }
    }

    // MARK: KeySurfaceDelegate

    public func keySurface(_ surface: KeySurfaceView, touchBegan id: Int, at point: CGPoint, time: TimeInterval) {
        model.touchBegan(id: id, at: point, time: time)
    }

    public func keySurface(_ surface: KeySurfaceView, touchMoved id: Int, to point: CGPoint, time: TimeInterval) {
        model.touchMoved(id: id, to: point, time: time)
    }

    public func keySurface(_ surface: KeySurfaceView, touchEnded id: Int, at point: CGPoint, time: TimeInterval) {
        model.touchEnded(id: id, at: point, time: time)
    }

    public func keySurface(_ surface: KeySurfaceView, touchCancelled id: Int, time: TimeInterval) {
        model.touchCancelled(id: id, time: time)
    }

    public func keySurface(_ surface: KeySurfaceView, didTap key: Key, side: Side) {
        switch key {
        case .globe:
            onSystemKey?(key)
        case .emoji:
            if searchView != nil { endEmojiSearch(toEmojiPage: true) } else { showEmoji() }
        case .numbers:
            page = .numbers
        case .symbols:
            page = .symbols
        case .letters:
            page = .letters
        case .symbol(let c):
            model.press(character: c)
        case .space:
            model.press(.space)
            // Like Apple's keyboard, a space on the numbers page goes back to the
            // letters, except in a number field, which lives on the numbers page.
            if model.field.startPage == .letters { page = .letters }
        case .returnKey where searchView != nil:
            // "done" closes the search, back to the page.
            endEmojiSearch(toEmojiPage: true)
        case .returnKey:
            // A return key that waits for text does nothing until there is some.
            if model.returnEnabled { model.press(.returnKey) }
        default:
            model.press(key)
        }
    }

    public func keySurface(_ surface: KeySurfaceView, didSlideSpace steps: Int) {
        model.moveCursor(by: steps)
    }

    public func keySurfaceDidSwipeBackspace(_ surface: KeySurfaceView) {
        model.deleteWord()
    }

    public func keySurfaceDidHoldNumbers(_ surface: KeySurfaceView) {
        showSettings()
    }

    public func keySurfaceDidSlideOffNumbers(_ surface: KeySurfaceView) {
        page = .numbers
    }

    public func keySurface(_ surface: KeySurfaceView, didEndNumbersSlideOn key: Key?) {
        // Lifting on "#+=" or "ABC" keeps the page that key chose; anything else
        // (a number, a symbol, space, return, backspace, off the keys) goes back.
        switch key {
        case .symbols, .letters, .numbers: break
        default: page = model.field.startPage
        }
    }

    public func keySurface(_ surface: KeySurfaceView, picked letter: Character, touch id: Int, time: TimeInterval) {
        model.pick(letter, touch: id, time: time)
    }
}
#endif
