import PenguinKit
import SquawkKit
import SwiftUI
import UIKit

extension Outfit {
    var accessory: PenguinAccessory {
        switch self {
        case .scarf: .scarf
        case .beanie: .beanie
        case .sunglasses: .sunglasses
        case .partyHat: .partyHat
        }
    }

    var name: String { accessory.displayName }

    /// "3 mornings in a row", or "Pro" for one you can't earn.
    var howToGet: String {
        guard let streak = streakToEarn else { return "Pro" }
        return "\(streak) first-ring mornings in a row"
    }
}

/// The outfit Squawk wears, picked in Settings. Saved by id, so a missing or no longer
/// allowed outfit just means none.
enum Wardrobe {
    static let key = "penguin.outfit"

    /// What Squawk wears now: the picked outfit, while you still have it.
    static func accessory(outfitID: String, access: ProAccess, bestStreak: Int) -> PenguinAccessory? {
        guard let outfit = Outfit(rawValue: outfitID), access.allows(outfit, bestStreak: bestStreak) else { return nil }
        return outfit.accessory
    }
}

/// The app icons. The standard one is free; the others come with Pro.
enum SquawkIcon: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case night = "Night"
    case mint = "Mint"
    case ice = "Ice"

    var id: String { rawValue }

    /// The name iOS knows it by. Nil is the main icon.
    var iconName: String? { self == .standard ? nil : "AppIcon-\(rawValue)" }

    /// A small picture of it, for the picker (an icon set can't be shown directly).
    var preview: Image { Image("IconPreview-\(rawValue)") }

    var title: String {
        switch self {
        case .standard: "Sunrise"
        case .night: "Night"
        case .mint: "Mint"
        case .ice: "Ice"
        }
    }

    @MainActor static var current: SquawkIcon {
        allCases.first { $0.iconName == UIApplication.shared.alternateIconName } ?? .standard
    }

    @MainActor func apply() async {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(iconName)
            Telemetry.count("pro.icon_changed", ["icon": rawValue.lowercased()])
        } catch {
            Telemetry.report(error)
        }
    }
}
