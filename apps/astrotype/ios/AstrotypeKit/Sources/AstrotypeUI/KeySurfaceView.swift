#if canImport(UIKit)
import AstrotypeCore
import UIKit

@MainActor
public protocol KeySurfaceDelegate: AnyObject {
    /// A finger landed on a letter key. `id` names the touch until it lifts.
    func keySurface(_ surface: KeySurfaceView, touchBegan id: Int, at point: CGPoint, time: TimeInterval)
    func keySurface(_ surface: KeySurfaceView, touchMoved id: Int, to point: CGPoint, time: TimeInterval)
    func keySurface(_ surface: KeySurfaceView, touchEnded id: Int, at point: CGPoint, time: TimeInterval)
    func keySurface(_ surface: KeySurfaceView, touchCancelled id: Int, time: TimeInterval)
    /// A finger tapped a key that is not a letter (landed and lifted on it). Backspace
    /// held down repeats this.
    func keySurface(_ surface: KeySurfaceView, didTap key: Key, side: Side)
    /// A finger slid along the space bar by `steps` more characters (negative is left).
    func keySurface(_ surface: KeySurfaceView, didSlideSpace steps: Int)
    /// A finger swiped left from backspace.
    func keySurfaceDidSwipeBackspace(_ surface: KeySurfaceView)
    /// A finger held the "123" key.
    func keySurfaceDidHoldNumbers(_ surface: KeySurfaceView)
    /// A finger on "123" slid off it before the hold: show the numbers page under the
    /// finger, so it can lift on a number or symbol (Apple's slide from 123).
    func keySurfaceDidSlideOffNumbers(_ surface: KeySurfaceView)
    /// That finger lifted, on `key` (nil off the keys), after its tap went out:
    /// go back to the letters unless it lifted on a page key.
    func keySurface(_ surface: KeySurfaceView, didEndNumbersSlideOn key: Key?)
    /// A finger held a letter and lifted on another letter from its callout ("ñ" from
    /// n): the touch `id` types that letter instead (features/languages).
    func keySurface(_ surface: KeySurfaceView, picked letter: Character, touch id: Int, time: TimeInterval)
}

/// The keys. One UIKit view that draws a `Layout` and reports touches, with multitouch
/// on so each thumb is its own touch. Letter keys stream their touches (down, moves,
/// up) so the engine can tell taps from swipes; the other keys report a tap, or one of
/// the keyboard's gestures (DESIGN.md "The keyboard"): a slide on space moves the
/// cursor, a swipe left from backspace deletes a word, backspace held repeats, "123"
/// held opens the settings, and a slide off "123" shows the numbers page until the
/// finger lifts, types the key it lifts on and goes back to the letters, like Apple's.
/// Keys flash in the thumb's colour (teal left, coral right), taps leave a ring that
/// pings out, swipes draw a trail that fades after lift.
///
///     let surface = KeySurfaceView()
///     surface.delegate = self
///     surface.layout = Layout.qwerty(width: view.bounds.width)
public final class KeySurfaceView: UIView {
    public weak var delegate: KeySurfaceDelegate?

    public var layout = Layout.qwerty(width: 390) {
        didSet { if layout != oldValue { rebuild() } }
    }

    /// Draw letters as capitals.
    public var shifted = false {
        didSet {
            keyViews.values.forEach { $0.forEach { $0.shifted = shifted } }
            refreshAccessibilityLabels()
        }
    }

    /// What the return key says for the field (features/field-types): the arrow, or
    /// the app's word on grey, or on blue for an action.
    public var returnKey: Field.ReturnKey = .return {
        didSet {
            guard returnKey != oldValue else { return }
            keyViews[.returnKey]?.forEach { $0.returnKey = returnKey }
            refreshAccessibilityLabels()
        }
    }

    /// Whether return does anything now: a field that waits for text has it dimmed
    /// until there is some, and touches on it do nothing.
    public var returnEnabled = true {
        didSet {
            guard returnEnabled != oldValue else { return }
            keyViews[.returnKey]?.forEach { $0.enabled = returnEnabled }
            refreshAccessibilityLabels()
        }
    }

    /// What the space bar says when idle.
    public var spaceLabel = "Astrotype" {
        didSet { keyViews[.space]?.forEach { $0.label.text = spaceLabel } }
    }

    /// The theme the keys are drawn in (features/customization).
    public var theme: KeyboardTheme = .classic {
        didSet { if theme != oldValue { restyle() } }
    }
    /// Light or dark: like the phone, or always one.
    public var keyAppearance: KeyAppearance = .system {
        didSet { if keyAppearance != oldValue { restyle() } }
    }
    /// The effects: flashes, taps, trails, letters and flow. Nil is Effects off (the
    /// battery saver, DESIGN.md "Motion"): a hit key just darkens, like Apple's.
    public var effects: EffectsSettings? = .calm {
        didSet { if effects != oldValue { fx.settings = effects; applyLetterMode() } }
    }
    /// The theme as drawn now, in its light or dark look.
    public private(set) var style = KeyStyle.classic
    /// Flow changed: its level, the combo and how far to the next level.
    public var onFlow: ((FlowState) -> Void)? {
        get { fx.onFlow }
        set { fx.onFlow = newValue }
    }
    /// Keys outlined in a thumb's colour (a drill's next word, DESIGN.md screen 8).
    public var hints: [Key: Side] = [:] {
        didSet { applyHints() }
    }
    /// The other letters a held key offers (`Accents.alternates`), none to hold nothing.
    public var alternates: (Character) -> [Character] = { _ in [] }
    /// How long a finger rests on a key before its accents show.
    static let accentDelay: TimeInterval = 0.35

    /// Settings: a slide on space moves the cursor; a swipe left on backspace deletes a word.
    public var spaceSlideEnabled = true
    public var backspaceSwipeEnabled = true

    /// How far left of backspace a swipe has to travel to delete a word.
    public static let wordSwipe: CGFloat = 40
    /// How far a finger travels from "123" before the numbers page comes up under it.
    public static let numbersSlide: CGFloat = 12
    static let holdDelay: TimeInterval = 0.45
    static let repeatInterval: TimeInterval = 0.09

    private struct Active {
        var id: Int
        var key: Key?
        let startKey: Key
        let startPoint: CGPoint
        var side: Side
        var isLetter: Bool
        var points: [CGPoint]
        var trail: TrailDrawing?
        /// A finger on space: a tap, or a slide once it holds and travels (`SpaceSlide`).
        var slide: SpaceSlide?
        /// A slide, a swipe or a hold took this touch: no tap when it lifts.
        var gestured = false
        var hold: Task<Void, Never>?
        /// The accents shown for a held key, when they are up.
        var callout: AccentCallout?
        /// A slide from "123" put the numbers page up for this touch.
        var slidFromNumbers = false
    }

    /// The views per key: space is placed twice on a split keyboard.
    private var keyViews: [Key: [KeyView]] = [:]
    private var active: [ObjectIdentifier: Active] = [:]
    private var nextID = 1
    private let effects = CALayer()
    private lazy var fx = KeyEffects(surface: self)
    /// Letters tapped since the last word, so space or return can count one for flow.
    private var lettersSinceWord = 0
    /// One VoiceOver element per key (see `rebuildAccessibility`).
    private var keyElements: [KeyElement] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = Theme.ui(.kb)
        rebuild()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: layout.height)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        effects.frame = bounds
        fx.layout(bounds)
    }

    public override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.userInterfaceStyle != previous?.userInterfaceStyle || traitCollection.displayScale != previous?.displayScale {
            restyle()
        }
    }

    /// Draw every key in the theme's current look.
    private func restyle() {
        style = KeyStyle(theme: theme, appearance: keyAppearance, traits: traitCollection)
        let inset = style.keyInset
        for placement in layout.placements {
            for view in keyViews[placement.key] ?? [] where view.frame.midX >= placement.frame.minX && view.frame.midX <= placement.frame.maxX {
                view.frame = placement.frame.insetBy(dx: inset, dy: inset)
            }
        }
        keyViews.values.forEach { $0.forEach { $0.style = style } }
        fx.style = style
        applyHints()
        applyLetterMode()
    }

    /// The Metal letters draw the letter keys' labels while a Metal letter effect is on.
    private func applyLetterMode() {
        let elsewhere = fx.drawsLetters
        keyViews.values.forEach { $0.forEach { $0.lettersElsewhere = elsewhere } }
        fx.lettersChanged()
    }

    /// The letter keys as the Metal letters draw them: the letter, the key's frame and
    /// the letter's colour now.
    func letterKeys() -> [(key: Key, letter: Character, frame: CGRect, ink: UIColor)] {
        var out: [(key: Key, letter: Character, frame: CGRect, ink: UIColor)] = []
        for (key, views) in keyViews {
            guard let c = key.character else { continue }
            let letter = shifted ? Character(String(c).uppercased()) : c
            for view in views {
                out.append((key, letter, view.frame, view.currentInk.resolvedColor(with: traitCollection)))
            }
        }
        return out
    }

    /// The letters on the keys, both cases, for the Metal letters' atlas.
    func lettersOnKeys() -> [Character] {
        var out = Set<Character>()
        for placement in layout.placements {
            guard let c = placement.key.character else { continue }
            out.insert(c)
            for u in String(c).uppercased() { out.insert(u) }
        }
        return out.sorted()
    }

    /// Glow every key in a colour (flow at Blizzard), or none.
    func setGlow(_ color: UIColor?) {
        keyViews.values.forEach { $0.forEach { $0.setGlow(color) } }
    }

    /// Bounce a letter (the Pop letter effect).
    func popLetter(_ key: Key, scale: CGFloat) {
        keyViews[key]?.forEach { $0.pop(scale: scale) }
    }

    /// The centre of a letter's key, for "Play a burst".
    func centre(of letter: Character) -> CGPoint? {
        layout.frame(of: .letter(letter)).map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    /// Light a key the way a touch does, for "Play a burst".
    func light(_ key: Key, side: Side) { flash(key, side: side) }
    func unlight(_ key: Key) { unflash(key) }
    func key(at point: CGPoint) -> Key? { layout.key(at: point) }

    /// Type a fast run of words on the keys, without typing anything, so the effects
    /// and flow show (the app's "Play a burst"). Calls back when it is done.
    public func playBurst(completion: (@MainActor () -> Void)? = nil) {
        fx.playBurst(completion: completion)
    }

    /// Empty the flow meter (the keyboard went away).
    public func resetFlow() { fx.resetFlow() }

    private func rebuild() {
        keyViews.values.forEach { $0.forEach { $0.removeFromSuperview() } }
        keyViews = [:]
        style = KeyStyle(theme: theme, appearance: keyAppearance, traits: traitCollection)
        for placement in layout.placements {
            let keyView = KeyView(key: placement.key, spaceLabel: spaceLabel, style: style)
            keyView.frame = placement.frame.insetBy(dx: style.keyInset, dy: style.keyInset)
            keyView.lettersElsewhere = fx.drawsLetters
            keyView.shifted = shifted
            if placement.key == .returnKey {
                keyView.returnKey = returnKey
                keyView.enabled = returnEnabled
            }
            addSubview(keyView)
            keyViews[placement.key, default: []].append(keyView)
        }
        effects.removeFromSuperlayer()
        effects.frame = bounds
        fx.attach(to: layer, effects: effects)
        invalidateIntrinsicContentSize()
        applyHints()
        rebuildAccessibility()
    }

    // MARK: VoiceOver

    /// VoiceOver reads the keyboard like Apple's (DESIGN.md "Accessibility"): one
    /// element per key, touch to hear it, lift (touch typing) or double-tap to type it.
    /// Swipe typing is off then; a letter goes through the engine as a tap at the key's
    /// centre, so the bar still builds the word. Trails and flashes carry nothing
    /// VoiceOver needs, so they are layers, not elements.
    private func rebuildAccessibility() {
        isAccessibilityElement = false
        keyElements = layout.placements.map { placement in
            let element = KeyElement(container: self, key: placement.key)
            element.accessibilityFrameInContainerSpace = placement.frame
            element.accessibilityTraits = .keyboardKey
            let centre = CGPoint(x: placement.frame.midX, y: placement.frame.midY)
            element.onActivate = { [weak self] in self?.activate(placement.key, at: centre) }
            return element
        }
        refreshAccessibilityLabels()
        accessibilityElements = keyElements
    }

    private func refreshAccessibilityLabels() {
        for element in keyElements {
            element.accessibilityLabel = spokenName(of: element.key)
            if element.key == .returnKey {
                element.accessibilityTraits = returnEnabled ? .keyboardKey : [.keyboardKey, .notEnabled]
            }
        }
    }

    private func spokenName(of key: Key) -> String {
        switch key {
        case .letter(let c): shifted ? "capital \(c)" : String(c)
        case .symbol(let c): String(c)
        case .shift: shifted ? "Shift, on" : "Shift"
        case .backspace: "Delete"
        case .numbers: "Numbers"
        case .symbols: "More symbols"
        case .letters: "Letters"
        case .globe: "Next keyboard"
        case .emoji: "Emoji"
        case .space: "Space"
        case .returnKey: returnKey.spokenName
        case .text(let text): text == ".com" ? "dot com" : text
        }
    }

    /// VoiceOver activated a key: a letter is a tap for the engine, the rest the tap
    /// they are.
    private func activate(_ key: Key, at point: CGPoint) {
        let side = layout.side(at: point)
        flash(key, side: side)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            self?.unflash(key)
        }
        if key.character != nil {
            let id = nextID
            nextID += 1
            let now = ProcessInfo.processInfo.systemUptime
            delegate?.keySurface(self, touchBegan: id, at: point, time: now)
            delegate?.keySurface(self, touchEnded: id, at: point, time: now + 0.05)
        } else {
            delegate?.keySurface(self, didTap: key, side: side)
        }
    }

    private func applyHints() {
        for (key, views) in keyViews {
            views.forEach { $0.hint(color: hints[key].map { style.thumb($0) }) }
        }
    }

    // MARK: Touches

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        typeHeldSpace()
        for touch in touches {
            let point = touch.location(in: self)
            guard let key = layout.key(at: point), key != .returnKey || returnEnabled else { continue }
            let side = layout.side(at: point)
            let id = nextID
            nextID += 1
            let oid = ObjectIdentifier(touch)
            var touchState = Active(id: id, key: key, startKey: key, startPoint: point, side: side, isLetter: key.character != nil, points: [point], trail: nil)
            if key == .space { touchState.slide = SpaceSlide(at: point, time: touch.timestamp) }
            flash(key, side: side)
            switch key {
            case .backspace:
                touchState.hold = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.holdDelay))
                    while !Task.isCancelled {
                        guard let self, self.active[oid] != nil else { return }
                        self.active[oid]?.gestured = true
                        self.delegate?.keySurface(self, didTap: .backspace, side: side)
                        try? await Task.sleep(for: .seconds(Self.repeatInterval))
                    }
                }
            case .numbers:
                touchState.hold = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.holdDelay))
                    guard !Task.isCancelled, let self, let state = self.active[oid], !state.gestured else { return }
                    self.active[oid]?.gestured = true
                    self.unflash(.numbers)
                    self.delegate?.keySurfaceDidHoldNumbers(self)
                }
            case .letter(let c), .symbol(let c):
                let options = alternates(c)
                guard !options.isEmpty, !UIAccessibility.isVoiceOverRunning else { break }
                touchState.hold = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.accentDelay))
                    guard !Task.isCancelled, let self, let state = self.active[oid], !state.gestured,
                          state.key == key, let last = state.points.last,
                          hypot(last.x - state.startPoint.x, last.y - state.startPoint.y) < 18 else { return }
                    self.showCallout(for: key, options: options, touch: oid)
                }
            default:
                break
            }
            active[oid] = touchState
            if key.character != nil {
                delegate?.keySurface(self, touchBegan: id, at: point, time: touch.timestamp)
            }
        }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let oid = ObjectIdentifier(touch)
            guard var touchState = active[oid] else { continue }
            let point = touch.location(in: self)
            if let callout = touchState.callout {
                callout.select(at: convert(point, to: callout))
                continue
            }
            if touchState.isLetter {
                // No swipe typing under VoiceOver: the touch types the key it landed on.
                if UIAccessibility.isVoiceOverRunning { continue }
                let now = layout.key(at: point)
                if now != touchState.key {
                    if let was = touchState.key { unflash(was) }
                    if let now { flash(now, side: touchState.side) }
                    touchState.key = now
                }
                touchState.points.append(point)
                drawTrail(&touchState)
                active[oid] = touchState
                delegate?.keySurface(self, touchMoved: touchState.id, to: point, time: touch.timestamp)
                continue
            }
            switch touchState.startKey {
            case .space:
                guard spaceSlideEnabled, !touchState.gestured || touchState.slide?.isSliding == true,
                      let steps = touchState.slide?.move(to: point, time: touch.timestamp) else { break }
                if touchState.slide?.isSliding == true { touchState.gestured = true }
                if steps != 0 { delegate?.keySurface(self, didSlideSpace: steps) }
            case .backspace:
                if backspaceSwipeEnabled, !touchState.gestured, touchState.startPoint.x - point.x >= Self.wordSwipe {
                    touchState.gestured = true
                    touchState.hold?.cancel()
                    delegate?.keySurfaceDidSwipeBackspace(self)
                }
            default:
                var now = layout.key(at: point)
                // A tap on "123" that drifts a little past its edge is still a tap.
                if touchState.startKey == .numbers, !touchState.slidFromNumbers,
                   hypot(point.x - touchState.startPoint.x, point.y - touchState.startPoint.y) < Self.numbersSlide {
                    now = .numbers
                }
                if now != touchState.key {
                    if let was = touchState.key { unflash(was) }
                    if touchState.startKey == .numbers { touchState.hold?.cancel() }
                    if touchState.startKey == .numbers, layout.page == .letters, !touchState.gestured, !touchState.slidFromNumbers {
                        // Off "123" before the hold: the numbers page comes up under the
                        // finger (the delegate swaps `layout`).
                        touchState.slidFromNumbers = true
                        active[oid] = touchState
                        delegate?.keySurfaceDidSlideOffNumbers(self)
                        now = layout.key(at: point)
                    }
                    if let now { flash(now, side: touchState.side) }
                    touchState.key = now
                }
            }
            active[oid] = touchState
        }
    }

    /// Another finger landed while one rests on space: the space goes in now, before
    /// the new key, as on Apple's keyboard. Typed on lift, a letter tapped by the other
    /// thumb while space was still down went onto the end of the word before.
    private func typeHeldSpace() {
        for (oid, state) in active where state.startKey == .space && state.key == .space && !state.gestured {
            active[oid]?.gestured = true
            delegate?.keySurface(self, didTap: .space, side: state.side)
            countForFlow(tapped: .space, at: state.startPoint, side: state.side)
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let touchState = active.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            touchState.hold?.cancel()
            if let callout = touchState.callout {
                callout.removeFromSuperview()
                if let key = touchState.key { unflash(key) }
                let picked = callout.selected > 0 ? callout.options[callout.selected] : nil
                switch touchState.startKey {
                case .letter:
                    if let picked {
                        delegate?.keySurface(self, picked: picked, touch: touchState.id, time: touch.timestamp)
                    } else {
                        delegate?.keySurface(self, touchEnded: touchState.id, at: touchState.startPoint, time: touch.timestamp)
                    }
                case .symbol(let c):
                    delegate?.keySurface(self, didTap: .symbol(picked ?? c), side: touchState.side)
                default:
                    break
                }
                continue
            }
            let point = touchState.isLetter && UIAccessibility.isVoiceOverRunning ? touchState.startPoint : touch.location(in: self)
            if let key = touchState.key { unflash(key) }
            if touchState.isLetter {
                finish(touchState, at: point)
                delegate?.keySurface(self, touchEnded: touchState.id, at: point, time: touch.timestamp)
            } else if !touchState.gestured, let key = touchState.key {
                countForFlow(tapped: key, at: point, side: touchState.side)
                delegate?.keySurface(self, didTap: key, side: touchState.side)
            }
            if touchState.slidFromNumbers {
                delegate?.keySurface(self, didEndNumbersSlideOn: touchState.key)
            }
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let touchState = active.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            touchState.hold?.cancel()
            touchState.callout?.removeFromSuperview()
            if let key = touchState.key { unflash(key) }
            touchState.trail.map { fx.cancelTrail($0) }
            if touchState.isLetter {
                delegate?.keySurface(self, touchCancelled: touchState.id, time: touch.timestamp)
            }
            if touchState.slidFromNumbers {
                delegate?.keySurface(self, didEndNumbersSlideOn: nil)
            }
        }
    }

    // MARK: Accents

    /// The held key's letters in a row of keys above it, the plain one first and
    /// picked until the finger slides along (features/languages "Accent callout").
    private func showCallout(for key: Key, options: [Character], touch oid: ObjectIdentifier) {
        guard var state = active[oid], let frame = layout.frame(of: key, on: state.side) ?? layout.frame(of: key) else { return }
        let plain: Character
        switch key {
        case .letter(let c), .symbol(let c): plain = c
        default: return
        }
        let letters = ([plain] + options).map { shifted && key.character != nil ? Character($0.uppercased()) : $0 }
        let width = frame.width * CGFloat(letters.count)
        var x = frame.minX
        x = min(max(x, 2), bounds.width - width - 2)
        let height = frame.height
        let callout = AccentCallout(options: [plain] + options, labels: letters)
        callout.frame = CGRect(x: x, y: frame.minY - height - 6, width: width, height: height)
        addSubview(callout)
        state.callout = callout
        state.gestured = true
        state.trail.map { fx.cancelTrail($0) }
        state.trail = nil
        active[oid] = state
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: Replay

    /// Plays strokes on the keys without typing (Try it's "Show me"): each swipe's
    /// trail draws itself along the key centres and each tap rings, one after the
    /// other, in the thumb's colour. Under Reduce Motion the trails just show and go.
    public func replay(_ strokes: [(side: Side, letters: String)], completion: (@MainActor () -> Void)? = nil) {
        let steps: [(side: Side, points: [CGPoint])] = strokes.map { stroke in
            (stroke.side, stroke.letters.compactMap { layout.frame(of: .letter($0), on: stroke.side).map { CGPoint(x: $0.midX, y: $0.midY) } })
        }
        play(steps[...], completion: completion)
    }

    private func play(_ steps: ArraySlice<(side: Side, points: [CGPoint])>, completion: (@MainActor () -> Void)?) {
        guard let step = steps.first, !step.points.isEmpty else {
            completion?()
            return
        }
        let rest = steps.dropFirst()
        let color = style.thumb(step.side)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        for point in step.points {
            if let key = layout.key(at: point) { flash(key, side: step.side) }
        }
        let duration: TimeInterval = step.points.count == 1 ? 0.35 : min(1.2, 0.3 + 0.2 * Double(step.points.count))
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.strokeColor = color.cgColor
        layer.lineCap = .round
        layer.lineJoin = .round
        if step.points.count == 1 {
            let radius: CGFloat = 14
            layer.bounds = CGRect(x: 0, y: 0, width: 2 * radius, height: 2 * radius)
            layer.position = step.points[0]
            layer.path = UIBezierPath(ovalIn: layer.bounds).cgPath
            layer.lineWidth = 3
        } else {
            let path = UIBezierPath()
            path.move(to: step.points[0])
            for point in step.points.dropFirst() { path.addLine(to: point) }
            layer.path = path.cgPath
            layer.lineWidth = 9
            layer.opacity = 0.85
        }
        effects.addSublayer(layer)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            // Core Animation calls back on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                for point in step.points {
                    if let key = self.layout.key(at: point) { self.unflash(key) }
                }
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = layer.opacity
                fade.toValue = 0
                fade.duration = reduceMotion ? 0.01 : 0.5
                fade.fillMode = .forwards
                fade.isRemovedOnCompletion = false
                CATransaction.begin()
                CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
                layer.add(fade, forKey: "fade")
                CATransaction.commit()
                self.play(rest, completion: completion)
            }
        }
        if reduceMotion {
            let hold = CABasicAnimation(keyPath: "opacity")
            hold.fromValue = layer.opacity
            hold.toValue = layer.opacity
            hold.duration = duration
            layer.add(hold, forKey: "hold")
        } else if step.points.count == 1 {
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.5
            grow.toValue = 1.4
            grow.duration = duration
            layer.add(grow, forKey: "ping")
        } else {
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0
            draw.toValue = 1
            draw.duration = duration
            draw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(draw, forKey: "draw")
        }
        CATransaction.commit()
    }

    private func flash(_ key: Key, side: Side) {
        // A middle letter on a split keyboard is on both halves: light the thumb's own.
        let views = keyViews[key] ?? []
        let mine = views.count > 1 ? views.filter { layout.side(at: CGPoint(x: $0.frame.midX, y: 0)) == side } : views
        let color: UIColor?
        switch effects?.flash {
        case .thumb: color = style.thumb(side)
        case .theme: color = style.accent
        case .off, nil: color = nil
        }
        for view in mine.isEmpty ? views : mine {
            if let color { view.flash(color: color) } else { view.press() }
            if key.character != nil { fx.letterHit(key, at: CGPoint(x: view.frame.midX, y: view.frame.midY)) }
        }
        fx.keysChanged()
    }

    private func unflash(_ key: Key) {
        keyViews[key]?.forEach { $0.unflash() }
        fx.keysChanged()
    }

    // MARK: Flow

    /// A tap on a key that isn't a letter: space or return after letters is a word, a
    /// delete takes some flow back.
    private func countForFlow(tapped key: Key, at point: CGPoint, side: Side) {
        switch key {
        case .space, .returnKey:
            if lettersSinceWord > 0 { fx.word(at: point, side: side) }
            lettersSinceWord = 0
        case .backspace:
            fx.delete()
        default:
            break
        }
    }

    // MARK: Trails and taps

    private func drawTrail(_ touchState: inout Active) {
        if touchState.trail == nil {
            // A tap that wobbles a little is still a tap.
            guard let last = touchState.points.last,
                  hypot(last.x - touchState.startPoint.x, last.y - touchState.startPoint.y) > 10 else { return }
            guard let trail = fx.beginTrail(side: touchState.side, at: touchState.points[0]) else { return }
            touchState.trail = trail
        }
        if let trail = touchState.trail { fx.moveTrail(trail, points: touchState.points) }
    }

    /// After lift: a swipe's trail fades and counts as a word for flow; a tap draws its
    /// tap effect.
    private func finish(_ touchState: Active, at point: CGPoint) {
        if let trail = touchState.trail {
            fx.endTrail(trail)
            fx.word(at: point, side: touchState.side)
            lettersSinceWord = 0
        } else {
            fx.tap(at: point, side: touchState.side)
            lettersSinceWord += 1
        }
    }
}

/// A key as VoiceOver sees it.
/// A row of keys over a held key: its plain letter and its accents. The thumb picks one
/// by sliding along the row; lifting types the one picked.
final class AccentCallout: UIView {
    let options: [Character]
    private(set) var selected = 0
    private var views: [UILabel] = []

    init(options: [Character], labels: [Character]) {
        self.options = options
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = Theme.ui(.key)
        layer.cornerRadius = Theme.Radius.key
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 3
        for letter in labels {
            let label = UILabel()
            label.text = String(letter)
            label.textAlignment = .center
            label.font = UIFont.systemFont(ofSize: 23, weight: .regular)
            label.layer.cornerRadius = Theme.Radius.key
            label.layer.cornerCurve = .continuous
            addSubview(label)
            views.append(label)
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width / CGFloat(max(views.count, 1))
        for (i, label) in views.enumerated() {
            label.frame = CGRect(x: CGFloat(i) * width, y: 0, width: width, height: bounds.height).insetBy(dx: 2, dy: 2)
        }
    }

    /// The option under `point` (in this view), the nearest one at either end.
    func select(at point: CGPoint) {
        let width = bounds.width / CGFloat(max(views.count, 1))
        let index = min(max(Int(floor(point.x / width)), 0), views.count - 1)
        guard index != selected else { return }
        selected = index
        refresh()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func refresh() {
        for (i, label) in views.enumerated() {
            // On the layer, so the corner rounds it without clipping the label.
            label.layer.backgroundColor = i == selected ? Theme.ui(.accent).resolvedColor(with: traitCollection).cgColor : nil
            label.textColor = Theme.ui(i == selected ? .accentInk : .keyInk)
        }
    }
}

final class KeyElement: UIAccessibilityElement {
    let key: Key
    var onActivate: (() -> Void)?

    init(container: UIView, key: Key) {
        self.key = key
        super.init(accessibilityContainer: container)
    }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

/// One key: a rounded face with a letter, a symbol or an SF Symbol, drawn from the
/// keyboard's theme (`KeyStyle`, features/customization). Classic is Apple's keyboard's
/// colours, type and glyphs, so it feels native next to it.
final class KeyView: UIView {
    let key: Key
    let label = UILabel()
    let icon = UIImageView()
    var shifted = false {
        didSet {
            label.text = text
            if key == .shift { icon.image = symbol }
        }
    }
    /// For the return key: what it says, and whether it is blue.
    var returnKey: Field.ReturnKey = .return {
        didSet {
            label.text = text
            icon.image = symbol
            backgroundColor = restColor
            label.textColor = inkColor
        }
    }
    /// Dimmed when it does nothing (return, waiting for text).
    /// A disabled key (return in an empty field that needs text) keeps its background
    /// and greys only its label or glyph (Gabriel, 3 Nov 2026).
    var enabled = true {
        didSet {
            label.textColor = inkColor
            icon.tintColor = iconColor
        }
    }
    /// The theme the key is drawn in.
    var style = KeyStyle.classic {
        didSet { if style != oldValue { restyle() } }
    }
    /// The letter is drawn by the Metal letters layer, so the label hides.
    var lettersElsewhere = false {
        didSet { if lettersElsewhere != oldValue { refreshLabelVisibility() } }
    }
    /// Lit in a thumb's or the theme's colour now.
    private(set) var isLit = false
    /// The letter's colour now, for the Metal letters.
    var currentInk: UIColor { label.textColor ?? inkColor }

    private let spaceLabel: String
    private var glow: UIColor?

    init(key: Key, spaceLabel: String, style: KeyStyle = .classic) {
        self.key = key
        self.spaceLabel = spaceLabel
        self.style = style
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.text = text
        addSubview(label)
        icon.contentMode = .center
        icon.image = symbol
        addSubview(icon)
        restyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 0)
        icon.frame = bounds
        if layer.shadowOpacity > 0 {
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
        }
    }

    private func restyle() {
        let shape = style.shape
        layer.cornerRadius = CGFloat(shape.corner)
        layer.borderWidth = CGFloat(shape.borderWidth)
        layer.borderColor = shape.borderWidth > 0 ? style.colors.border.uiColor.cgColor : nil
        applyShadow()
        backgroundColor = restColor
        label.textColor = inkColor
        label.font = style.shape.font.uiFont(size: fontSize, weight: .regular)
        icon.tintColor = iconColor
        refreshLabelVisibility()
        setNeedsLayout()
    }

    private func applyShadow() {
        if let glow {
            layer.shadowColor = glow.cgColor
            layer.shadowOpacity = 0.9
            layer.shadowOffset = .zero
            layer.shadowRadius = 6
            return
        }
        layer.shadowColor = UIColor.black.cgColor
        switch style.shape.shadow {
        case .none:
            layer.shadowOpacity = 0
        case .soft:
            layer.shadowOpacity = 0.2
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowRadius = 0
        case .raised:
            layer.shadowOpacity = 0.3
            layer.shadowOffset = CGSize(width: 0, height: 2.5)
            layer.shadowRadius = 1.5
        }
        layer.shadowPath = layer.shadowOpacity > 0 ? UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath : nil
    }

    /// A glow around the key in a colour (flow at Blizzard), or none.
    func setGlow(_ color: UIColor?) {
        guard color != glow else { return }
        glow = color
        applyShadow()
    }

    private func refreshLabelVisibility() {
        var isLetter = false
        if case .letter = key { isLetter = true }
        label.isHidden = isLetter && (lettersElsewhere || !style.shape.showsLetters)
    }

    private var isAction: Bool { key == .returnKey && returnKey.isAction }
    private var restColor: UIColor {
        if isAction { return Theme.ui(.returnAction) }
        let color = key.isFunction ? style.colors.functionKey : style.colors.key
        return color.uiColor.withAlphaComponent(CGFloat(color.alpha * style.shape.opacity))
    }
    private var pressedColor: UIColor {
        if style.isClassic { return Theme.ui(.keyPressed) }
        let base = key.isFunction ? style.colors.functionKey : style.colors.key
        return Self.mix(base.uiColor, style.colors.letters.uiColor, 0.25)
    }
    private var inkColor: UIColor {
        let letters = style.colors.letters.uiColor
        guard enabled else { return isAction ? UIColor.white.withAlphaComponent(0.5) : letters.withAlphaComponent(0.4) }
        if isAction { return .white }
        if key == .space { return style.isClassic ? Theme.ui(.muted) : letters.withAlphaComponent(0.6) }
        return style.isClassic ? Theme.ui(.keyInk) : letters
    }
    private var iconColor: UIColor {
        let letters = style.isClassic ? Theme.ui(.keyInk) : style.colors.letters.uiColor
        return enabled ? letters : letters.withAlphaComponent(0.4)
    }

    private var fontSize: CGFloat {
        switch key {
        case .letter, .symbol: 23
        case .space: 15
        default: 16
        }
    }

    /// Apple's glyphs for the keys that have one.
    private var symbol: UIImage? {
        let name: String
        switch key {
        case .shift: name = shifted ? "shift.fill" : "shift"
        case .backspace: name = "delete.left"
        case .globe: name = "globe"
        case .emoji: name = "face.smiling"
        case .returnKey where returnKey.label == nil: name = "return.left"
        default: return nil
        }
        return UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))
    }

    private var text: String {
        switch key {
        case .letter(let c): shifted ? String(c).uppercased() : String(c)
        case .symbol(let c): String(c)
        case .numbers: "123"
        case .symbols: "#+="
        case .letters: "ABC"
        case .space: spaceLabel
        case .text(let text): text
        case .returnKey: returnKey.label ?? ""
        case .shift, .backspace, .globe, .emoji: ""
        }
    }

    /// Lit in `color` with a 6% pop; no pop under Reduce Motion.
    func flash(color: UIColor) {
        isLit = true
        backgroundColor = color
        label.textColor = .white
        icon.tintColor = .white
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIView.animate(withDuration: Theme.Motion.keyHit, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) {
            self.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
        }
    }

    /// The quiet press, with flashes off: the key darkens a shade.
    func press() {
        backgroundColor = pressedColor
    }

    func unflash() {
        isLit = false
        UIView.animate(withDuration: 0.25) {
            self.backgroundColor = self.restColor
            self.label.textColor = self.inkColor
            self.icon.tintColor = self.iconColor
            self.transform = .identity
        }
    }

    /// The letter bounces up and back (the Pop letter effect).
    func pop(scale: CGFloat) {
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1, scale, 0.94, 1]
        bounce.keyTimes = [0, 0.3, 0.7, 1]
        bounce.duration = 0.35
        bounce.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut),
                                  CAMediaTimingFunction(name: .easeOut)]
        label.layer.add(bounce, forKey: "pop")
    }

    /// Outline the key in a thumb's colour, or clear it.
    func hint(color: UIColor?) {
        guard let color else {
            layer.borderWidth = CGFloat(style.shape.borderWidth)
            layer.borderColor = style.shape.borderWidth > 0 ? style.colors.border.uiColor.cgColor : nil
            return
        }
        layer.borderWidth = 3
        layer.borderColor = color.cgColor
    }

    private static func mix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
    }
}
#endif
