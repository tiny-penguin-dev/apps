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
    /// Keys the engine leaves to the host: the globe.
    public var onSystemKey: ((Key) -> Void)?
    /// Whether the bottom row has a globe key before the emoji key: the extension sets
    /// it from `needsInputModeSwitchKey` (true only where iOS draws no globe of its own).
    public var showsGlobe = false {
        didSet { if showsGlobe != oldValue { setNeedsLayout() } }
    }
    /// The keyboard's height changed with its width (a wide screen has taller keys).
    public var onHeightChange: ((CGFloat) -> Void)?

    public private(set) var page: Layout.Page = .letters {
        didSet { if page != oldValue { surface.layout = pageLayout(width: model.layout.width, height: keysHeight) } }
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
    private let keyHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let commitHaptic = UIImpactFeedbackGenerator(style: .light)

    public init(model: KeyboardModel) {
        self.model = model
        super.init(frame: CGRect(x: 0, y: 0, width: model.layout.width, height: Self.barHeight + model.layout.height))
        asked = height
        backgroundColor = Theme.ui(.kb)
        addSubview(bar)
        addSubview(surface)
        surface.delegate = self
        // Held keys offer the accents of the languages being typed (features/languages).
        surface.alternates = { [weak model] key in Accents.alternates(for: key, languages: model?.activeLanguages ?? []) }
        surface.layout = model.layout
        bar.onChoose = { [weak self] index in self?.model.choose(guess: index) }
        bar.onBoost = { [weak self] index in self?.model.boost(guess: index) }
        bar.onForget = { [weak self] index in self?.model.forget(guess: index) }
        model.onChange = { [weak self] in self?.render() }
        model.onHaptic = { [weak self] haptic in self?.play(haptic) }
        model.onNotice = { [weak self] notice in
            switch notice {
            case .twoThumbsIsPro: self?.bar.flash("Two thumbs is in Astrotype Pro")
            }
        }
        keyHaptic.prepare()
        render()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public var enableInputClicksWhenVisible: Bool { true }

    /// The height to ask the host for at a width: the keys where Apple's are (at the
    /// person's height), plus the bar when it sits on top.
    public func height(forWidth width: CGFloat) -> CGFloat {
        let keys = Layout.qwerty(width: width, split: model.splitOnWide, extraLetters: extraLetters, globe: showsGlobe, scale: scale)
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
        let natural = Layout.qwerty(width: width, split: split, extraLetters: extraLetters, globe: showsGlobe, scale: scale)
        let place = barPlace(for: natural)
        let barOnTop = place == .top
        let room = bounds.height - (barOnTop ? Self.barHeight : 0)
        let fill: CGFloat? = room > 0 ? min(room, natural.height) : nil
        if model.layout.width != width || model.layout.split != natural.split || model.layout.extraLetters != natural.extraLetters
            || model.layout.globe != showsGlobe || fill != keysHeight || place != self.place {
            keysHeight = fill
            self.place = place
            model.layout = Layout.qwerty(width: width, split: split, extraLetters: extraLetters, globe: showsGlobe, height: fill)
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
        if let emojiPage {
            // The bar's room and the keys', so the keyboard keeps its height.
            let top = place == .top ? bar.frame.minY : surface.frame.minY
            emojiPage.frame = CGRect(x: 0, y: top, width: width, height: surface.frame.maxY - top)
            bar.isHidden = true
            surface.isHidden = true
        } else {
            surface.isHidden = false
        }
        if let panel {
            // Over the keys and the guesses bar both: the bar has nothing to say while
            // the settings are open (Gabriel, 3 Nov 2026).
            bar.isHidden = true
            panel.frame = CGRect(x: 0, y: top, width: width, height: max(0, bounds.height - top))
            panel.granted = (bounds.height, wanted)
            bringSubviewToFront(panel)
        }
    }

    private func pageLayout(width: CGFloat, height: CGFloat?) -> Layout {
        Layout.qwerty(width: width, page: page, split: model.splitOnWide, extraLetters: extraLetters, globe: showsGlobe,
                      height: height)
    }

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

    private func render() {
        bar.bar = model.state.bar
        if usesDefaultNote {
            bar.note = model.entitlement.allows(.twoThumbs) ? "Both thumbs, one word" : "One finger at a time"
        }
        surface.shifted = model.state.isShifted
        surface.showsTrails = model.keyboardSettings.trails
        surface.showsFlashes = model.keyboardSettings.trails
        surface.spaceSlideEnabled = model.keyboardSettings.spaceSlide
        surface.backspaceSwipeEnabled = model.keyboardSettings.backspaceSwipe
        panel?.allowsSplit = model.entitlement.allows(.splitLayout)
        panel?.showsSplit = model.layout.isWide
        panel?.allowsTwoLanguages = model.entitlement.allows(.twoLanguages)
        if model.layout.split != (model.splitOnWide && model.layout.isWide)
            || model.layout.extraLetters != (model.layout.split && extraLetters) || barPlace(for: model.layout) != place
            || height != asked { setNeedsLayout() }
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
        panel.preferredLanguages = model.preferredLanguages
        panel.onChange = { [weak self] settings in self?.model.keyboardSettings = settings }
        panel.onDone = { [weak self] in self?.hideSettings() }
        panel.frame = surface.frame
        panel.granted = (bounds.height, height)
        panel.heightStory = heightStory
        addSubview(panel)
        self.panel = panel
        setNeedsLayout()
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
        addSubview(page)
        emojiPage = page
        hideSettings()
        setNeedsLayout()
        layoutIfNeeded()
        UIAccessibility.post(notification: .screenChanged, argument: page)
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
            showEmoji()
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
            // Like Apple's keyboard, a space on the numbers page goes back to the letters.
            page = .letters
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
        default: page = .letters
        }
    }

    public func keySurface(_ surface: KeySurfaceView, picked letter: Character, touch id: Int, time: TimeInterval) {
        model.pick(letter, touch: id, time: time)
    }
}
#endif
