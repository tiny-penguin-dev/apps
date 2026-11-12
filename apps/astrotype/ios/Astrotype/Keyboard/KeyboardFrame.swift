import AstrotypeCore
import AstrotypeUI
import UIKit

/// The app's own keyboard dressed the way iOS dresses the extension, so practice looks
/// like typing in any other app (Gabriel, 8 Nov 2026). It is the text view's input view;
/// the `KeyboardView` sits inside it.
///
/// iOS draws a margin around a keyboard extension in its own process: on iOS 26 a glass
/// panel with rounded top corners, a little room beside and above the keys, and on every
/// version a strip under them (where its globe and mic go). An app can't show the real
/// extension in place of this: it only comes up when the person switches to it, and
/// practice needs the keys' touches (recording, drill hints, the speed test's clock). So
/// the margin is drawn here, measured from Gabriel's screenshots of the extension.
@MainActor
final class KeyboardFrame: UIView {
    let keyboard: AstrotypeUI.KeyboardView
    /// The backdrop: Liquid Glass on iOS 26, like the system's panel (Gabriel, 9 Nov
    /// 2026: the practice keyboard should be glass like the real one), solid before.
    private let panel: UIView

    /// Room around the keys. Sides and top only on iOS 26, where the system's panel has
    /// them; the bottom is the home indicator's strip. The sides are a fixed padding,
    /// not the window's side safe areas (Gabriel, 12 Nov 2026: following the safe area
    /// squeezed the keys on the Duo closed, where the status bar runs down one side).
    /// Measured from his screenshots of the real keyboard on the iPhone Duo, 12 Nov 2026:
    /// 10 pt each side closed (466 pt wide), 76 pt each side open (951 pt wide).
    static func margins(bottom: CGFloat, width: CGFloat) -> UIEdgeInsets {
        if #available(iOS 26, *) {
            let side: CGFloat = width >= Layout.wideWidth ? 76 : 10
            return UIEdgeInsets(top: 4, left: side, bottom: bottom, right: side)
        }
        return UIEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0)
    }

    /// The panel's top corners on iOS 26.
    static let cornerRadius: CGFloat = 30

    private(set) var margins: UIEdgeInsets

    init(keyboard: AstrotypeUI.KeyboardView, safeArea: UIEdgeInsets, width: CGFloat) {
        self.keyboard = keyboard
        margins = Self.margins(bottom: safeArea.bottom, width: width)
        panel = Self.makePanel()
        super.init(frame: CGRect(x: 0, y: 0, width: keyboard.bounds.width, height: keyboard.bounds.height + margins.top + margins.bottom))
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .clear
        addSubview(panel)
        // The panel draws the backdrop, as the system's does for the extension.
        keyboard.usesSystemBackdrop = true
        keyboard.bar.backgroundColor = .clear
        keyboard.surface.backgroundColor = .clear
        keyboard.autoresizingMask = []
        addSubview(keyboard)
    }

    private static func makePanel() -> UIView {
        if #available(iOS 26, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = Theme.ui(.kbGlass).withAlphaComponent(0.55)
            let effect = UIVisualEffectView(effect: glass)
            effect.layer.cornerRadius = cornerRadius
            effect.layer.cornerCurve = .continuous
            effect.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            effect.clipsToBounds = true
            return effect
        }
        let panel = UIView()
        panel.backgroundColor = Theme.ui(.kb)
        return panel
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The window's safe area or width changed (known now, the screen turned, or the
    /// Duo opened or closed).
    func setSafeArea(_ safeArea: UIEdgeInsets, width: CGFloat) {
        let new = Self.margins(bottom: safeArea.bottom, width: width)
        guard margins != new else { return }
        margins = new
        setNeedsLayout()
    }

    /// The whole height at a width: the keys' plus the margins.
    func height(forWidth width: CGFloat) -> CGFloat {
        margins.top + keyboard.height(forWidth: width - margins.left - margins.right) + margins.bottom
    }

    /// The height for a keyboard height (`KeyboardView.onHeightChange`).
    func height(forKeys keys: CGFloat) -> CGFloat {
        margins.top + keys + margins.bottom
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: height(forKeys: keyboard.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        panel.frame = bounds
        keyboard.frame = bounds.inset(by: margins)
    }
}
