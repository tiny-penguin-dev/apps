/// How the penguin feels. Each mood sets the eyes, beak, flippers and animation.
public enum PenguinMood: String, CaseIterable, Identifiable, Sendable {
    case asleep
    case awake
    case proud
    case grumpy
    case squawk
    case faint

    public var id: String { rawValue }

    /// A short name for galleries and accessibility labels.
    public var displayName: String {
        switch self {
        case .asleep: "Asleep"
        case .awake: "Awake"
        case .proud: "Proud"
        case .grumpy: "Grumpy"
        case .squawk: "Squawk!"
        case .faint: "Faint"
        }
    }

    /// Flippers lift up for big moments.
    public var flippersUp: Bool { self == .proud || self == .squawk }

    /// Pink cheeks only show when the penguin is proud.
    public var showsCheeks: Bool { self == .proud }

    /// The beak opens wide only when squawking.
    public var beakOpen: Bool { self == .squawk }

    /// The looping motion for this mood.
    public var motion: PenguinMotion {
        switch self {
        case .asleep: .breathe(seconds: 3.2)
        case .awake: .breathe(seconds: 2.4)
        case .proud: .hop
        case .grumpy: .breathe(seconds: 3.2)
        case .squawk: .shake
        case .faint: .still
        }
    }
}

/// The looping motion a mood plays. Reduce Motion turns all of these off.
public enum PenguinMotion: Equatable, Sendable {
    case breathe(seconds: Double)
    case hop
    case shake
    case still

    /// How long one half of the loop takes.
    public var halfCycle: Double {
        switch self {
        case .breathe(let seconds): seconds / 2
        case .hop: 0.35
        case .shake: 0.25
        case .still: 0
        }
    }
}
