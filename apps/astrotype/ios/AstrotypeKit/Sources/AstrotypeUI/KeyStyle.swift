#if canImport(UIKit)
import AstrotypeCore
import UIKit

public extension RGBColor {
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }

    /// From a colour the person picked (the editor's colour well).
    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        self.init(hex: byte(r) << 16 | byte(g) << 8 | byte(b), alpha: Double(a))
    }
}

public extension KeyShape.Font {
    /// The key face in this style. Classic is Apple's keyboard's font.
    func uiFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        switch self {
        case .classic: UIFont.systemFont(ofSize: size, weight: weight)
        case .rounded: Theme.uiFont(size: size, weight: weight)
        case .mono: UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}

/// A theme as the keys draw it now: the light or dark look picked by the person's
/// choice (`KeyAppearance`) and the phone's mode (features/customization).
///
///     let style = KeyStyle(theme: settings.style(allows: pro), appearance: .system, traits: traitCollection)
///     key.backgroundColor = style.colors.key.uiColor
public struct KeyStyle: Equatable, Sendable {
    public var theme: KeyboardTheme
    public var isDark: Bool

    public init(theme: KeyboardTheme, isDark: Bool) {
        self.theme = theme
        self.isDark = isDark
    }

    public init(theme: KeyboardTheme, appearance: KeyAppearance, traits: UITraitCollection) {
        let dark: Bool
        switch appearance {
        case .system: dark = traits.userInterfaceStyle == .dark
        case .light: dark = false
        case .dark: dark = true
        }
        self.init(theme: theme, isDark: dark)
    }

    public static let classic = KeyStyle(theme: .classic, isDark: false)

    public var colors: KeyColors { theme.colors(dark: isDark) }
    public var shape: KeyShape { theme.shape.clamped }
    public var isClassic: Bool { theme.id == KeyboardTheme.classic.id }

    /// Whether the keyboard's backdrop is dark. The backdrop is always the system's
    /// (themes don't paint one, Gabriel, 6 Nov 2026), so it follows the look in use.
    public var backgroundIsDark: Bool { isDark }

    /// The interface style for views drawn on the backdrop.
    public var interfaceStyle: UIUserInterfaceStyle { isDark ? .dark : .light }

    public func thumb(_ side: Side) -> UIColor { (side == .left ? colors.left : colors.right).uiColor }
    public var accent: UIColor { colors.accent.uiColor }

    /// How far each key is drawn in from its place in `Layout`, on each side.
    public var keyInset: CGFloat { max(0, (CGFloat(shape.gap) - Layout.keyGap) / 2) }

    public func letterFont(size: CGFloat = 23) -> UIFont { shape.font.uiFont(size: size, weight: .regular) }
}
#endif
