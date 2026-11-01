#if canImport(UIKit)
import SwiftUI
import UIKit

/// The design system's tokens, from DESIGN.md ("Design system"). Nothing in a screen
/// names a colour, a size or a timing: it names one of these.
///
///     Text("Both flippers, go.").font(.sw(.title)).foregroundStyle(Theme.ink)
///     view.backgroundColor = Theme.ui(.kb)
public enum Theme {
    /// A colour with a light and a dark value (0xRRGGBB).
    public enum Tone: CaseIterable, Sendable {
        case bg, card, ink, muted, line, accent, accentInk, left, right, sun, sunInk, mint, ice, key, keyDark, keyInk, kb

        var values: (light: UInt32, dark: UInt32) {
            switch self {
            case .bg: (0xF3F8FA, 0x111A24)
            case .card: (0xFFFFFF, 0x1A2634)
            case .ink: (0x1E2945, 0xEEF4F8)
            case .muted: (0x67748F, 0x97A6B8)
            case .line: (0xDCE6EC, 0x2A3B4C)
            case .accent: (0x139FB5, 0x2FC6DC)
            case .accentInk: (0xFFFFFF, 0x06202A)
            case .left: (0x139FB5, 0x2FC6DC)
            case .right: (0xFF6F86, 0xFF8A9E)
            case .sun: (0xFFC24D, 0xFFCD66)
            case .sunInk: (0x3A2600, 0x3A2600)
            case .mint: (0x2FBF96, 0x45D3AA)
            case .ice: (0xD9EDF3, 0x1D3240)
            case .key: (0xFFFFFF, 0x2A3A4A)
            case .keyDark: (0xC9D6DE, 0x1C2834)
            case .keyInk: (0x1E2945, 0xEEF4F8)
            case .kb: (0xDCE6EC, 0x131E29)
            }
        }
    }

    /// A token as a UIKit colour that follows light and dark mode.
    public static func ui(_ tone: Tone) -> UIColor {
        let (light, dark) = tone.values
        return UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    public static let bg = Color(uiColor: ui(.bg))
    public static let card = Color(uiColor: ui(.card))
    public static let ink = Color(uiColor: ui(.ink))
    public static let muted = Color(uiColor: ui(.muted))
    public static let line = Color(uiColor: ui(.line))
    public static let accent = Color(uiColor: ui(.accent))
    public static let accentInk = Color(uiColor: ui(.accentInk))
    /// The left thumb's colour (teal). Every trail, flash and hint for that thumb.
    public static let left = Color(uiColor: ui(.left))
    /// The right thumb's colour (coral).
    public static let right = Color(uiColor: ui(.right))
    public static let sun = Color(uiColor: ui(.sun))
    public static let sunInk = Color(uiColor: ui(.sunInk))
    public static let mint = Color(uiColor: ui(.mint))
    public static let ice = Color(uiColor: ui(.ice))
    public static let key = Color(uiColor: ui(.key))
    public static let keyDark = Color(uiColor: ui(.keyDark))
    public static let kb = Color(uiColor: ui(.kb))

    /// Type: SF Pro Rounded everywhere. The app's styles follow Dynamic Type; the key
    /// face is fixed because the keyboard's size is what thumbs learned.
    public enum TextStyle: Sendable {
        case title, heading, body, small, big, key
    }

    public static func font(_ style: TextStyle) -> Font {
        switch style {
        case .title: .system(.title, design: .rounded, weight: .black)
        case .heading: .system(.title3, design: .rounded, weight: .heavy)
        case .body: .system(.body, design: .rounded)
        case .small: .system(.footnote, design: .rounded, weight: .semibold)
        case .big: .system(size: 64, weight: .black, design: .rounded).monospacedDigit()
        case .key: .system(size: 21, weight: .bold, design: .rounded)
        }
    }

    /// The key face and other fixed-size type for UIKit.
    public static func uiFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    public enum Space {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let gutter: CGFloat = 22
        public static let xl: CGFloat = 32
    }

    public enum Radius {
        public static let lg: CGFloat = 28
        public static let md: CGFloat = 18
        public static let sm: CGFloat = 12
        public static let key: CGFloat = 7
    }

    public enum Motion {
        /// Buttons, toggles and screens: a small overshoot.
        public static let spring = Animation.spring(duration: 0.35, bounce: 0.35)
        public static let quickSpring = Animation.spring(duration: 0.25, bounce: 0.5)
        /// How long a swipe's trail takes to fade after lift.
        public static let trailFade: TimeInterval = 1.2
        /// How long a tap's ring takes to ping out.
        public static let tapRing: TimeInterval = 0.6
        /// A key's scale-up when hit.
        public static let keyHit: TimeInterval = 0.15
    }
}

public extension Font {
    /// A Astrotype text style, like `.font(.sw(.title))`.
    static func sw(_ style: Theme.TextStyle) -> Font { Theme.font(style) }
}

public extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
