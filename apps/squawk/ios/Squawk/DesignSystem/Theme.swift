import SwiftUI
import UIKit

/// Colors and type from DESIGN.md ("Look"). Light and dark values side by side.
enum Theme {
    static let background = Color(light: 0xF4F7FF, dark: 0x11182E)
    static let card = Color(light: 0xFFFFFF, dark: 0x1B2443)
    static let ink = Color(light: 0x1E2945, dark: 0xEEF2FF)
    static let muted = Color(light: 0x6B7594, dark: 0x9AA5C6)
    static let accent = Color(light: 0xFF8A4C, dark: 0xFF9A5E)
    static let accentInk = Color(light: 0xFFFFFF, dark: 0x1A1206)
    static let sun = Color(light: 0xFFC24D, dark: 0xFFCD66)
    /// Text on sun yellow, like the PRO badge.
    static let sunInk = Color(hex: 0x3A2600)
    static let coral = Color(light: 0xFF5C63, dark: 0xFF6F75)
    static let mint = Color(light: 0x2FBF96, dark: 0x45D3AA)
    static let ice = Color(light: 0xDCE7FF, dark: 0x24305A)

    static let body = Font.system(.body, design: .rounded)
    static let label = Font.system(.headline, design: .rounded, weight: .bold)
}

/// Rounded type at a design size that still grows with Dynamic Type. Sizes relative to
/// a large text style grow less than body text, so big titles and times stay on screen
/// at the largest sizes (DESIGN.md "Accessibility").
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private var weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .rounded))
    }
}

extension View {
    /// A black-weight title, like "Squawk Pro". Use instead of a fixed-size font.
    func titleFont(_ size: CGFloat = 34) -> some View {
        modifier(ScaledFont(size: size, weight: .black, relativeTo: .title))
    }

    /// A big number, like the alarm time or the math question, with tabular digits.
    func bigNumberFont(_ size: CGFloat, weight: Font.Weight = .black) -> some View {
        modifier(ScaledFont(size: size, weight: weight, relativeTo: .largeTitle)).monospacedDigit()
    }
}

extension Color {
    /// A color from a 0xRRGGBB number.
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// A color that switches between two 0xRRGGBB values for light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The big pill button with a soft "pressable" bottom edge.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label)
            .foregroundStyle(Theme.accentInk)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                Capsule().fill(Theme.accent)
                    .shadow(color: .black.opacity(0.18), radius: 0, y: configuration.isPressed ? 1 : 4)
            )
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.5), value: configuration.isPressed)
    }
}
