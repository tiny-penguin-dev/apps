import Foundation

/// A bundled alarm sound. AlarmKit only plays bundled mp3 files, about 30 seconds long.
public struct AlarmSound: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// The mp3 file name in the app bundle.
    public var fileName: String { "\(id).mp3" }

    public static let all: [AlarmSound] = [
        AlarmSound(id: "sound_default", name: "Morning squawk"),
        AlarmSound(id: "sound_nudge", name: "Nudge"),
        AlarmSound(id: "sound_clouds", name: "Clouds"),
        AlarmSound(id: "sound_garden", name: "Garden"),
        AlarmSound(id: "sound_glimmer", name: "Glimmer"),
        AlarmSound(id: "sound_lemons", name: "Lemons"),
        AlarmSound(id: "sound_rush", name: "Rush"),
        AlarmSound(id: "sound_chihuahua", name: "Chihuahua"),
    ]

    public static let standard = all[0]

    /// The sound with this id, or the standard one if it's unknown (an alarm must
    /// never end up silent).
    public static func with(id: String) -> AlarmSound {
        all.first { $0.id == id } ?? standard
    }
}
