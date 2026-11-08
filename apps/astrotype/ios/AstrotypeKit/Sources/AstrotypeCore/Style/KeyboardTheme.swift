import Foundation

/// A colour as 0xRRGGBB plus an alpha, for themes the person makes and saves. Foundation
/// only, so it lives in Core and syncs; `AstrotypeUI` turns it into a `UIColor`
/// (features/customization).
///
///     let teal = RGBColor(hex: 0x139FB5)
///     RGBColor(hex: "#FF6F86")?.contrast(with: .white)   // about 2.7
public struct RGBColor: Codable, Hashable, Sendable {
    public var hex: UInt32
    public var alpha: Double

    public init(hex: UInt32, alpha: Double = 1) {
        self.hex = hex & 0xFFFFFF
        self.alpha = min(max(alpha, 0), 1)
    }

    /// From "#RRGGBB" or "RRGGBB"; nil for anything else.
    public init?(hex text: String) {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }

    public static let white = RGBColor(hex: 0xFFFFFF)
    public static let black = RGBColor(hex: 0x000000)

    public var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    public var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(hex & 0xFF) / 255 }

    /// "#RRGGBB".
    public var hexString: String { String(format: "#%06X", hex) }

    /// WCAG relative luminance, 0 (black) to 1 (white).
    public var luminance: Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio with another colour, 1 to 21.
    public func contrast(with other: RGBColor) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Whether text in this colour on `background` is hard to read (under 3:1, the
    /// editor's "Hard to read" chip).
    public func isHardToRead(on background: RGBColor) -> Bool { contrast(with: background) < 3 }

    /// Codable as "#RRGGBB" (and "#RRGGBB@0.5" when see-through), so saved themes read well.
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let parts = text.split(separator: "@")
        guard let color = RGBColor(hex: String(parts.first ?? "")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a colour: \(text)"))
        }
        self = color
        if parts.count > 1, let alpha = Double(parts[1]) { self.alpha = min(max(alpha, 0), 1) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(alpha < 1 ? "\(hexString)@\(alpha)" : hexString)
    }
}

/// The colours of one look (light or dark) of a theme.
public struct KeyColors: Codable, Hashable, Sendable {
    /// Behind the keys and the bar.
    public var background: RGBColor
    /// Letter keys and space.
    public var key: RGBColor
    /// Shift, delete, 123, emoji and return.
    public var functionKey: RGBColor
    /// The letters and glyphs on the keys, and the bar's words.
    public var letters: RGBColor
    /// Key borders, when the shape has one.
    public var border: RGBColor
    /// The left and right thumbs' colours: flashes, trails, taps.
    public var left: RGBColor
    public var right: RGBColor
    /// The theme's own colour: the "Theme colour" flash, the combo badge.
    public var accent: RGBColor
    /// How solid the keys are in this look, 0.3 (glass) to 1 (Gabriel, 6 Nov 2026: set
    /// for light and dark apart).
    public var opacity: Double

    public static let opacityRange: ClosedRange<Double> = 0.3...1

    /// `opacity` kept in range, for drawing.
    public var keyOpacity: Double { min(max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound) }

    public init(background: RGBColor, key: RGBColor, functionKey: RGBColor, letters: RGBColor, border: RGBColor,
                left: RGBColor, right: RGBColor, accent: RGBColor, opacity: Double = 1) {
        self.opacity = opacity
        self.background = background
        self.key = key
        self.functionKey = functionKey
        self.letters = letters
        self.border = border
        self.left = left
        self.right = right
        self.accent = accent
    }

    /// One colour by its field, for the editor's swatch rows.
    public subscript(field: Field) -> RGBColor {
        get {
            switch field {
            case .background: background
            case .key: key
            case .functionKey: functionKey
            case .letters: letters
            case .border: border
            case .left: left
            case .right: right
            case .accent: accent
            }
        }
        set {
            switch field {
            case .background: background = newValue
            case .key: key = newValue
            case .functionKey: functionKey = newValue
            case .letters: letters = newValue
            case .border: border = newValue
            case .left: left = newValue
            case .right: right = newValue
            case .accent: accent = newValue
            }
        }
    }

    public enum Field: String, CaseIterable, Sendable {
        case background, key, functionKey, letters, border, left, right, accent
    }

    /// The key as it looks: see-through keys show the background behind them.
    public var visibleKey: RGBColor {
        let a = keyOpacity
        func mix(_ k: Double, _ b: Double) -> UInt32 { UInt32((k * a + b * (1 - a)) * 255 + 0.5) }
        return RGBColor(hex: mix(key.red, background.red) << 16 | mix(key.green, background.green) << 8
                        | mix(key.blue, background.blue))
    }

    /// Letters too close in colour to the keys, as they look, to read.
    public var lettersHardToRead: Bool { letters.isHardToRead(on: visibleKey) }

    enum CodingKeys: String, CodingKey {
        case background, key, functionKey, letters, border, left, right, accent, opacity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decode(RGBColor.self, forKey: .background)
        key = try c.decode(RGBColor.self, forKey: .key)
        functionKey = try c.decode(RGBColor.self, forKey: .functionKey)
        letters = try c.decode(RGBColor.self, forKey: .letters)
        border = try c.decode(RGBColor.self, forKey: .border)
        left = try c.decode(RGBColor.self, forKey: .left)
        right = try c.decode(RGBColor.self, forKey: .right)
        accent = try c.decode(RGBColor.self, forKey: .accent)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
    }
}

/// The shape of the keys, the same in light and dark.
public struct KeyShape: Codable, Hashable, Sendable {
    public enum Border: String, Codable, CaseIterable, Sendable { case none, thin, bold }
    public enum Shadow: String, Codable, CaseIterable, Sendable { case none, soft, raised }
    public enum Font: String, Codable, CaseIterable, Sendable { case rounded, classic, mono }

    public static let gapRange: ClosedRange<Double> = 2...12
    public static let cornerRange: ClosedRange<Double> = 0...16

    /// The space between keys as drawn, in points (`Layout.keyGap`, 2, by default).
    /// Touches still reach right up to the neighbouring key: `Layout` doesn't change.
    public var gap: Double
    /// Corner radius in points.
    public var corner: Double
    public var border: Border
    public var shadow: Shadow
    public var font: Font
    /// Off draws blank letter keys.
    public var showsLetters: Bool

    public init(gap: Double = 2, corner: Double = 8.5, border: Border = .none, shadow: Shadow = .soft,
                font: Font = .classic, showsLetters: Bool = true) {
        self.gap = gap
        self.corner = corner
        self.border = border
        self.shadow = shadow
        self.font = font
        self.showsLetters = showsLetters
    }

    /// The border's width in points.
    public var borderWidth: Double {
        switch border {
        case .none: 0
        case .thin: 1
        case .bold: 2
        }
    }

    /// Kept in range, for drawing.
    public var clamped: KeyShape {
        var out = self
        out.gap = min(max(gap, Self.gapRange.lowerBound), Self.gapRange.upperBound)
        out.corner = min(max(corner, Self.cornerRange.lowerBound), Self.cornerRange.upperBound)
        return out
    }
}

/// Whether the keyboard follows the phone's light or dark mode, or keeps one.
public enum KeyAppearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

/// A keyboard theme: a name, a light and a dark look, and one shape
/// (features/customization). Eight are built in (`builtIn`); the person can make more,
/// kept in `KeyboardSettings.customThemes`.
///
///     let theme = KeyboardTheme.named("iceberg") ?? .classic
///     let colors = theme.colors(dark: traitCollection.userInterfaceStyle == .dark)
public struct KeyboardTheme: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var light: KeyColors
    public var dark: KeyColors
    public var shape: KeyShape

    public init(id: String, name: String, light: KeyColors, dark: KeyColors, shape: KeyShape = KeyShape()) {
        self.id = id
        self.name = name
        self.light = light
        self.dark = dark
        self.shape = shape
    }

    public func colors(dark isDark: Bool) -> KeyColors { isDark ? dark : light }

    enum CodingKeys: String, CodingKey { case id, name, light, dark, shape }

    /// Themes saved before see-through moved into each look kept it in the shape: it
    /// goes to both looks.
    private struct LegacyShape: Decodable { var opacity: Double? }
    private enum LookKeys: String, CodingKey { case opacity }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        light = try c.decode(KeyColors.self, forKey: .light)
        dark = try c.decode(KeyColors.self, forKey: .dark)
        shape = try c.decode(KeyShape.self, forKey: .shape)
        if let legacy = try? c.decode(LegacyShape.self, forKey: .shape).opacity {
            if !(try c.nestedContainer(keyedBy: LookKeys.self, forKey: .light)).contains(.opacity) { light.opacity = legacy }
            if !(try c.nestedContainer(keyedBy: LookKeys.self, forKey: .dark)).contains(.opacity) { dark.opacity = legacy }
        }
    }

    /// Classic is free; every other theme, and the person's own, is Pro.
    public var isFree: Bool { id == Self.classic.id }

    /// Whether this is one the person made.
    public var isCustom: Bool { Self.builtIn.allSatisfy { $0.id != id } }

    /// A new theme of the person's, starting from this one.
    public func copy(id: String, name: String) -> KeyboardTheme {
        var out = self
        out.id = id
        out.name = name
        return out
    }

    public static func named(_ id: String) -> KeyboardTheme? { builtIn.first { $0.id == id } }

    private static func c(_ background: UInt32, _ key: UInt32, _ fn: UInt32, _ letters: UInt32, _ border: UInt32,
                          _ left: UInt32, _ right: UInt32, _ accent: UInt32) -> KeyColors {
        KeyColors(background: RGBColor(hex: background), key: RGBColor(hex: key), functionKey: RGBColor(hex: fn),
                  letters: RGBColor(hex: letters), border: RGBColor(hex: border), left: RGBColor(hex: left),
                  right: RGBColor(hex: right), accent: RGBColor(hex: accent))
    }

    /// Apple-like keys with Astrotype's thumb colours, a little see-through. Free.
    /// Values set by Gabriel (8 Nov 2026), with a gray accent in place of yellow.
    public static let classic: KeyboardTheme = {
        var light = c(0xD1D3D9, 0xFFFFFF, 0xEDEEF0, 0x000000, 0x000000, 0x139FB5, 0xFF6F86, 0x636366)
        light.opacity = 0.8
        var dark = c(0x1F1F1F, 0x989898, 0x5B5B5B, 0xFFFFFF, 0xFFFFFF, 0x2FC6DC, 0xFF8A9E, 0x6F6F6F)
        dark.opacity = 0.3
        return KeyboardTheme(id: "classic", name: "Classic", light: light, dark: dark,
                             shape: KeyShape(gap: 4, corner: 10, border: .none, shadow: .none, font: .classic))
    }()

    public static let builtIn: [KeyboardTheme] = [
        classic,
        KeyboardTheme(id: "iceberg", name: "Iceberg",
                      light: c(0xD9EDF3, 0xFFFFFF, 0xBFE0EA, 0x1E2945, 0x139FB5, 0x139FB5, 0xFF6F86, 0x139FB5),
                      dark: c(0x0E1C27, 0x1D3240, 0x152836, 0xD9F4FF, 0x2FC6DC, 0x2FC6DC, 0xFF8A9E, 0x2FC6DC),
                      shape: KeyShape(gap: 4, corner: 10, font: .rounded)),
        KeyboardTheme(id: "tuxedo", name: "Tuxedo",
                      light: c(0xE9E9EC, 0x1C1C1E, 0x3A3A3C, 0xFFFFFF, 0xFF9F1C, 0xFF9F1C, 0xFFC94D, 0xFF9F1C),
                      dark: c(0x000000, 0x1C1C1E, 0x2C2C2E, 0xFFFFFF, 0xFF9F1C, 0xFF9F1C, 0xFFC94D, 0xFF9F1C),
                      shape: KeyShape(corner: 9, font: .rounded)),
        KeyboardTheme(id: "krill", name: "Krill",
                      light: c(0xFFE4E8, 0xFFFFFF, 0xFFC7D1, 0x7A2E3B, 0xFF6F86, 0xFF6F86, 0xFF9F1C, 0xFF6F86),
                      dark: c(0x26121A, 0x46222D, 0x371A23, 0xFFD9E0, 0xFF8A9E, 0xFF8A9E, 0xFFB25C, 0xFF8A9E),
                      shape: KeyShape(gap: 5, corner: 13, font: .rounded)),
        KeyboardTheme(id: "midnight", name: "Midnight",
                      light: c(0xE8EAFF, 0xFFFFFF, 0xD3D7FA, 0x283070, 0x5B6CFF, 0x5B6CFF, 0xB15CFF, 0x5B6CFF),
                      dark: c(0x0B1026, 0x1A2246, 0x141B3A, 0xC9F7FF, 0x2FC6DC, 0x2FC6DC, 0xB98CFF, 0x7B61FF),
                      shape: KeyShape(gap: 4, corner: 9, border: .thin, font: .rounded)),
        KeyboardTheme(id: "paper", name: "Paper",
                      light: c(0xF7F3EA, 0xF7F3EA, 0xECE5D3, 0x2B2A26, 0x2B2A26, 0x2B2A26, 0xC2410C, 0xC2410C),
                      dark: c(0x1A1916, 0x1A1916, 0x26241F, 0xEDE6D6, 0xEDE6D6, 0xEDE6D6, 0xFB923C, 0xFB923C),
                      shape: KeyShape(gap: 4, corner: 4, border: .thin, shadow: .none, font: .classic)),
        KeyboardTheme(id: "arcade", name: "Arcade",
                      light: c(0xFFF0FB, 0xFFFFFF, 0xFBD9F3, 0x8A00D4, 0x00B8D4, 0x00B8D4, 0xFF2DAA, 0xFF2DAA),
                      dark: c(0x0D0221, 0x1A0B3A, 0x140830, 0xFF4FD8, 0x00F0FF, 0x00F0FF, 0xFF4FD8, 0xFF4FD8),
                      shape: KeyShape(gap: 4, corner: 4, border: .thin, shadow: .none, font: .mono)),
        KeyboardTheme(id: "bold", name: "Bold",
                      light: c(0xFFFFFF, 0xFFFFFF, 0xE5E5E5, 0x000000, 0x000000, 0x0057FF, 0xE00000, 0x0057FF),
                      dark: c(0x000000, 0x000000, 0x1A1A1A, 0xFFFFFF, 0xFFFFFF, 0x4DA3FF, 0xFF5C5C, 0x4DA3FF),
                      shape: KeyShape(gap: 3, corner: 6, border: .bold, shadow: .none, font: .classic)),
    ]

    /// Suggested swatches for the editor's colour rows, per look.
    public static let lightSwatches: [RGBColor] = [0xFFFFFF, 0xF7F3EA, 0xD1D3D9, 0xD9EDF3, 0xFFE4E8, 0x1C1C1E, 0x139FB5, 0xFF6F86, 0xFFC24D,
                                                   0x2FBF96, 0x7B61FF].map { RGBColor(hex: $0) }
    public static let darkSwatches: [RGBColor] = [0x000000, 0x1F1F1F, 0x464646, 0x1D3240, 0x0B1026, 0x46222D, 0xFFFFFF, 0x2FC6DC, 0xFF8A9E,
                                                  0xFFCD66, 0x45D3AA, 0xB98CFF].map { RGBColor(hex: $0) }
}
