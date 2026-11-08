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
        case bg, card, ink, muted, line, accent, accentInk, left, right, sun, sunInk, mint, ice, danger, slate, key, keyDark, keyInk, kb, keyPressed,
             returnAction, kbGlass

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
            // The right thumb's coral, darker so red text passes contrast (Forget).
            case .danger: (0xE0526A, 0xFF7A8E)
            // Settings icon tiles for system rows (privacy, haptics, about).
            case .slate: (0x5B6B8C, 0x6E7FA0)
            // The keys are Apple's keyboard's (iOS 26), so ours sits beside it unnoticed
            // (Gabriel, 2 Nov 2026); dark measured from his screenshots.
            case .key: (0xFFFFFF, 0x464646)
            // Function keys a step lighter than Apple's, halfway to the letter keys, so
            // they stand off the keyboard (Gabriel, 3 Nov 2026).
            case .keyDark: (0xEDEEF0, 0x404040)
            case .keyInk: (0x000000, 0xFFFFFF)
            case .kb: (0xD1D3D9, 0x1F1F1F)
            case .keyPressed: (0xC4C6CC, 0x6B6B6B)
            // Apple's system blue, for a return key that acts ("go", "search", "send"),
            // as on Apple's keyboard (features/field-types).
            case .returnAction: (0x007AFF, 0x0A84FF)
            // The glass iOS 26 draws around a keyboard extension, for the app's own
            // keyboard to sit on (`KeyboardFrame`). Measured from Gabriel's
            // screenshots in light and dark (8 Nov 2026).
            case .kbGlass: (0xDFE0E5, 0x212121)
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
    /// Destructive text, like Forget.
    public static let danger = Color(uiColor: ui(.danger))
    /// Icon tiles for system rows in Settings.
    public static let slate = Color(uiColor: ui(.slate))
    public static let key = Color(uiColor: ui(.key))
    public static let keyDark = Color(uiColor: ui(.keyDark))
    public static let kb = Color(uiColor: ui(.kb))

    /// A background you can't see that still takes touches. In a keyboard extension
    /// iOS drops touches on fully clear pixels, so a see-through key surface (the
    /// system's backdrop showing through) would ignore taps in the gaps between keys.
    /// The keyboard's own grey (`kb`: light grey in light mode, dark grey in dark mode)
    /// at 1%: invisible on the backdrop and enough to be hit.
    public static let seeThrough = UIColor { ui(.kb).resolvedColor(with: $0).withAlphaComponent(0.01) }

    /// Type: SF Pro Rounded everywhere. The app's styles follow Dynamic Type (the big
    /// number and the wide title through `bigNumberFont()` and `displayTitleFont()`,
    /// up to a cap); the key face is fixed because the keyboard's size is what thumbs
    /// learned.
    public enum TextStyle: Sendable {
        case title, heading, body, small, key
    }

    public static func font(_ style: TextStyle) -> Font {
        switch style {
        case .title: .system(.title, design: .rounded, weight: .black)
        case .heading: .system(.title3, design: .rounded, weight: .heavy)
        case .body: .system(.body, design: .rounded)
        case .small: .system(.footnote, design: .rounded, weight: .semibold)
        case .key: .system(size: 21, weight: .bold, design: .rounded)
        }
    }

    /// The key face and other fixed-size type for UIKit.
    public static func uiFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Rounded type that follows the person's text size like `style` does, from `size`
    /// at the default setting up to `maximum` (the bar's text scales one step; the big
    /// numbers further).
    public static func uiFont(size: CGFloat, weight: UIFont.Weight, scaledWith style: UIFont.TextStyle, upTo maximum: CGFloat) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: uiFont(size: size, weight: weight), maximumPointSize: maximum)
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
        public static let key: CGFloat = 8.5
    }

    public enum Motion {
        /// Buttons, toggles and screens: a small overshoot. Under Reduce Motion the
        /// same change happens without the bounce (`spring(reduceMotion:)`).
        public static let spring = Animation.spring(duration: 0.35, bounce: 0.35)
        public static let quickSpring = Animation.spring(duration: 0.25, bounce: 0.5)
        public static func spring(reduceMotion: Bool) -> Animation { reduceMotion ? .easeInOut(duration: 0.2) : spring }
        public static func quickSpring(reduceMotion: Bool) -> Animation { reduceMotion ? .easeInOut(duration: 0.15) : quickSpring }
        /// How long a swipe's trail takes to fade after lift.
        public static let trailFade: TimeInterval = 1.2
        /// How long a tap's ring takes to ping out.
        public static let tapRing: TimeInterval = 0.6
        /// A key's scale-up when hit.
        public static let keyHit: TimeInterval = 0.15
    }
}

public extension Font {
    /// An Astrotype text style, like `.font(.sw(.title))`.
    static func sw(_ style: Theme.TextStyle) -> Font { Theme.font(style) }
}

/// Rounded type at a fixed design size that still follows the person's text size, up
/// to a cap, for the sizes the text styles do not have.
public struct ScaledRoundedFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let maximum: CGFloat
    private let monospacedDigits: Bool

    public init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle, upTo maximum: CGFloat, monospacedDigits: Bool = false) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.maximum = maximum
        self.monospacedDigits = monospacedDigits
    }

    public func body(content: Content) -> some View {
        let font = Font.system(size: min(size, maximum), weight: weight, design: .rounded)
        content.font(monospacedDigits ? font.monospacedDigit() : font)
    }
}

public extension View {
    /// The result screen's number: 64 pt, scaling to 96 at the largest text sizes.
    func bigNumberFont() -> some View {
        modifier(ScaledRoundedFont(size: 64, weight: .black, relativeTo: .largeTitle, upTo: 96, monospacedDigits: true))
    }

    /// The wide size's title: 36 pt, scaling to 48.
    func displayTitleFont() -> some View {
        modifier(ScaledRoundedFont(size: 36, weight: .black, relativeTo: .largeTitle, upTo: 48))
    }
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
