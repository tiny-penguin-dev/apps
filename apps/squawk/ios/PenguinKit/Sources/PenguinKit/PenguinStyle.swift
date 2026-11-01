import SwiftUI

/// The penguin's colors. Apps can make their own style without touching the drawing.
public struct PenguinStyle: Sendable, Equatable {
    public var body: Color
    /// Body color in dark mode, a bit lighter so the penguin doesn't vanish.
    public var bodyInDark: Color
    public var belly: Color
    public var beak: Color
    public var cheek: Color
    public var mouth: Color
    public var tongue: Color
    /// Main and second color for outfits (nightcap, scarf, beanie, party hat).
    public var outfit: Color
    public var outfitTrim: Color

    public init(
        body: Color, bodyInDark: Color? = nil, belly: Color = .white, beak: Color,
        cheek: Color, mouth: Color, tongue: Color, outfit: Color, outfitTrim: Color
    ) {
        self.body = body
        self.bodyInDark = bodyInDark ?? body
        self.belly = belly
        self.beak = beak
        self.cheek = cheek
        self.mouth = mouth
        self.tongue = tongue
        self.outfit = outfit
        self.outfitTrim = outfitTrim
    }

    /// Squawk's colors from the approved design.
    public static let squawk = PenguinStyle(
        body: Color(hex: 0x172239),
        bodyInDark: Color(hex: 0x2A3762),
        beak: Color(hex: 0xFFB020),
        cheek: Color(hex: 0xFF9CA6),
        mouth: Color(hex: 0x4A1526),
        tongue: Color(hex: 0xFF7D8C),
        outfit: Color(hex: 0xFF8A4C),
        outfitTrim: Color(hex: 0xFFC24D)
    )

    func body(in scheme: ColorScheme) -> Color { scheme == .dark ? bodyInDark : body }
}

/// Something the penguin wears on top of its mood.
public enum PenguinAccessory: String, CaseIterable, Identifiable, Sendable {
    case nightcap
    case scarf
    case beanie
    case sunglasses
    case partyHat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nightcap: "Nightcap"
        case .scarf: "Scarf"
        case .beanie: "Beanie"
        case .sunglasses: "Sunglasses"
        case .partyHat: "Party hat"
        }
    }
}

extension Color {
    /// A color from a 0xRRGGBB number.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
