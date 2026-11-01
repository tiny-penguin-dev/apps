#if canImport(UIKit)
import StackWriteCore
import UIKit

/// The whole keyboard: the bar and the key surface, driven by a `KeyboardModel`. The
/// extension puts it in its input view; the app's practice field uses it as the input
/// view of a text view, so both run the same engine and the same views. Switches
/// between the letters, numbers and symbols pages, and shows the settings panel.
///
///     let keyboard = KeyboardView(model: model)
///     keyboard.onSystemKey = { key in if key == .globe { advanceToNextInputMode() } }
public final class KeyboardView: UIView, KeySurfaceDelegate, UIInputViewAudioFeedback {
    public static let barHeight: CGFloat = 44

    public let model: KeyboardModel
    public let bar = BarView()
    public let surface = KeySurfaceView()
    /// Keys the engine leaves to the host: the globe.
    public var onSystemKey: ((Key) -> Void)?
    /// The keyboard's height changed with its width (a wide screen has taller keys).
    public var onHeightChange: ((CGFloat) -> Void)?

    public private(set) var page: Layout.Page = .letters {
        didSet { if page != oldValue { surface.layout = Layout.qwerty(width: model.layout.width, page: page) } }
    }

    private var panel: SettingsPanelView?
    private let keyHaptic = UIImpactFeedbackGenerator(style: .light)
    private let commitHaptic = UIImpactFeedbackGenerator(style: .medium)

    /// The height for a width: the bar plus the keys.
    public static func height(forWidth width: CGFloat) -> CGFloat {
        barHeight + Layout.qwerty(width: width).height
    }

    public init(model: KeyboardModel) {
        self.model = model
        super.init(frame: CGRect(x: 0, y: 0, width: model.layout.width, height: Self.barHeight + model.layout.height))
        backgroundColor = Theme.ui(.kb)
        addSubview(bar)
        addSubview(surface)
        surface.delegate = self
        surface.layout = model.layout
        bar.onChoose = { [weak self] index in self?.model.choose(guess: index) }
        model.onChange = { [weak self] in self?.render() }
        model.onHaptic = { [weak self] haptic in self?.play(haptic) }
        keyHaptic.prepare()
        render()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public var enableInputClicksWhenVisible: Bool { true }

    public var height: CGFloat { Self.barHeight + model.layout.height }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0 else { return }
        if model.layout.width != width {
            let was = height
            model.layout = Layout.qwerty(width: width)
            surface.layout = Layout.qwerty(width: width, page: page)
            if height != was {
                invalidateIntrinsicContentSize()
                onHeightChange?(height)
            }
        }
        bar.frame = CGRect(x: 0, y: 0, width: width, height: Self.barHeight)
        surface.frame = CGRect(x: 0, y: Self.barHeight, width: width, height: model.layout.height)
        panel?.frame = surface.frame
    }

    private func render() {
        bar.bar = model.state.bar
        surface.shifted = model.state.isShifted
        surface.showsTrails = model.keyboardSettings.trails
        surface.spaceSlideEnabled = model.keyboardSettings.spaceSlide
        surface.backspaceSwipeEnabled = model.keyboardSettings.backspaceSwipe
    }

    private func play(_ haptic: Composer.Haptic) {
        switch haptic {
        case .key:
            keyHaptic.impactOccurred()
            UIDevice.current.playInputClick()
        case .commit:
            commitHaptic.impactOccurred()
        }
    }

    // MARK: Settings panel

    /// Show the in-keyboard settings over the keys.
    public func showSettings() {
        guard panel == nil else { return }
        let panel = SettingsPanelView(settings: model.keyboardSettings)
        panel.onChange = { [weak self] settings in self?.model.keyboardSettings = settings }
        panel.onDone = { [weak self] in self?.hideSettings() }
        panel.frame = surface.frame
        addSubview(panel)
        self.panel = panel
    }

    public func hideSettings() {
        panel?.removeFromSuperview()
        panel = nil
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
}
#endif
