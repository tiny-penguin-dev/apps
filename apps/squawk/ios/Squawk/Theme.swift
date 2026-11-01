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
    static let coral = Color(light: 0xFF5C63, dark: 0xFF6F75)
    static let mint = Color(light: 0x2FBF96, dark: 0x45D3AA)
    static let ice = Color(light: 0xDCE7FF, dark: 0x24305A)

    static func title(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .black, design: .rounded) }
    static let body = Font.system(.body, design: .rounded)
    static let label = Font.system(.headline, design: .rounded, weight: .bold)
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
