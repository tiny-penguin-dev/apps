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
    /// them (5 pt and 4 pt on his phone); the bottom is the home indicator's strip. On a
    /// wide screen the sides also keep out of the window's side safe areas, as the
    /// system's keyboard does (Gabriel, 9 Nov 2026: the wide and split keys ran to the
    /// screen's edges where the real ones don't).
    static func margins(safeArea: UIEdgeInsets) -> UIEdgeInsets {
        let side: CGFloat
        if #available(iOS 26, *) { side = 5 } else { side = 0 }
        let top: CGFloat
        if #available(iOS 26, *) { top = 4 } else { top = 0 }
        // The same on both sides, as the system centres its keys even when only one
        // side has a safe area (the clock's side on the Duo).
        let sides = max(side, safeArea.left, safeArea.right)
        return UIEdgeInsets(top: top, left: sides, bottom: safeArea.bottom, right: sides)
    }

    /// The panel's top corners on iOS 26.
    static let cornerRadius: CGFloat = 30

    private(set) var margins: UIEdgeInsets

    init(keyboard: AstrotypeUI.KeyboardView, safeArea: UIEdgeInsets) {
        self.keyboard = keyboard
        margins = Self.margins(safeArea: safeArea)
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

    /// The window's safe area changed (known now, or the screen turned).
    func setSafeArea(_ safeArea: UIEdgeInsets) {
        let new = Self.margins(safeArea: safeArea)
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
