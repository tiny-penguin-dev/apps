import Foundation

/// Something an alarm does in your Home: lights, a scene, a plug or switch, or blinds
/// (features/steps/FEATURE.md). Timed ones belong to a step, like rings; "When you're
/// up" ones run when the morning ends. New kinds are new `Kind` cases.
public struct HomeAction: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case light
        case scene
        case plug
        case blinds

        public var id: String { rawValue }

        /// "Lights", as in the Add something sheet.
        public var title: String {
            switch self {
            case .light: "Lights"
            case .scene: "Scene"
            case .plug: "Plug or switch"
            case .blinds: "Blinds"
            }
        }
    }

    public var id: UUID
    /// Minutes from the wake-up time, like `Ring.offsetMinutes`. Ignored for "When
    /// you're up".
    public var offsetMinutes: Int
    public var kind: Kind
    /// What it controls: one or more accessories, or one scene.
    public var targets: [HomeTarget]
    public var setting: HomeSetting

    public init(
        id: UUID = UUID(), offsetMinutes: Int = 0, kind: Kind,
        targets: [HomeTarget], setting: HomeSetting = HomeSetting()
    ) {
        self.id = id
        self.offsetMinutes = offsetMinutes
        self.kind = kind
        self.targets = targets
        self.setting = setting
    }

    /// "Bedroom lamp", "Bedroom lamp + 1", or the scene's name.
    public var name: String {
        guard let first = targets.first?.name else { return kind.title }
        return targets.count > 1 ? "\(first) + \(targets.count - 1)" : first
    }

    /// "50% · warm", "on", "open", or "" for a scene.
    public var detail: String {
        switch kind {
        case .scene:
            return ""
        case .plug:
            return setting.isOn ? "on" : "off"
        case .blinds:
            let position = setting.position ?? 100
            return position >= 100 ? "open" : position <= 0 ? "closed" : "\(position)% open"
        case .light:
            guard setting.isOn else { return "off" }
            var parts = ["\(setting.brightness ?? 100)%"]
            if let warmth = setting.warmth { parts.append(HomeSetting.warmthName(warmth)) }
            return parts.joined(separator: " · ")
        }
    }

    /// "Bedroom lamp · 50% · warm".
    public var summary: String {
        detail.isEmpty ? name : "\(name) · \(detail)"
    }
}

/// One HomeKit accessory or scene, by its HomeKit id. The name and room are kept so the
/// alarm reads well even before HomeKit has loaded, or after the thing was removed.
public struct HomeTarget: Codable, Hashable, Sendable {
    /// The HomeKit `uniqueIdentifier` of the service (for accessories) or action set (for
    /// scenes).
    public var id: UUID
    public var name: String
    public var room: String

    public init(id: UUID, name: String, room: String = "") {
        self.id = id
        self.name = name
        self.room = room
    }
}

/// What a Home thing is set to. Each kind uses the parts that make sense for it.
public struct HomeSetting: Codable, Hashable, Sendable {
    /// Lights, plugs and switches: on or off.
    public var isOn: Bool
    /// Lights: 1 to 100.
    public var brightness: Int?
    /// Lights: 0 is warm, 100 is daylight. Nil leaves the color alone.
    public var warmth: Int?
    /// Blinds: 0 is closed, 100 is open.
    public var position: Int?

    public init(isOn: Bool = true, brightness: Int? = nil, warmth: Int? = nil, position: Int? = nil) {
        self.isOn = isOn
        self.brightness = brightness
        self.warmth = warmth
        self.position = position
    }

    /// "warm", "soft white" or "daylight".
    public static func warmthName(_ warmth: Int) -> String {
        warmth < 34 ? "warm" : warmth < 67 ? "soft white" : "daylight"
    }
}

/// One moment of a morning: everything that happens at the same time. Steps aren't
/// saved; they're the alarm's rings and Home actions grouped by offset, so moving a step
/// moves everything in it.
public struct AlarmStep: Identifiable, Hashable, Sendable {
    /// Minutes from the wake-up time. 0 is the wake-up step.
    public var offsetMinutes: Int
    public var rings: [Ring]
    public var actions: [HomeAction]

    public var id: Int { offsetMinutes }
    public var isWakeUp: Bool { offsetMinutes == 0 }
}

extension Alarm {
    /// Every step in time order. There's always a wake-up step, even when nothing in it
    /// has been set up yet.
    public var steps: [AlarmStep] {
        var offsets = Set(rings.map(\.offsetMinutes)).union(homeActions.map(\.offsetMinutes))
        offsets.insert(0)
        return offsets.sorted().map { offset in
            AlarmStep(
                offsetMinutes: offset,
                rings: rings.filter { $0.offsetMinutes == offset },
                actions: homeActions.filter { $0.offsetMinutes == offset }
            )
        }
    }

    /// The step at this offset, or nil if nothing happens then.
    public func step(at offset: Int) -> AlarmStep? {
        steps.first { $0.offsetMinutes == offset && (offset == 0 || !$0.rings.isEmpty || !$0.actions.isEmpty) }
    }

    /// Moves everything at one time to another. A step that lands on another step joins
    /// it. The wake-up step doesn't move (change the wake-up time instead).
    public mutating func moveStep(from old: Int, to new: Int) {
        guard old != 0, old != new else { return }
        let target = min(max(new, Self.ringRange.lowerBound), Self.ringRange.upperBound)
        for i in rings.indices where rings[i].offsetMinutes == old { rings[i].offsetMinutes = target }
        for i in homeActions.indices where homeActions[i].offsetMinutes == old { homeActions[i].offsetMinutes = target }
    }

    /// Removes a step and everything in it. The wake-up step stays.
    public mutating func removeStep(at offset: Int) {
        guard offset != 0 else { return }
        rings.removeAll { $0.offsetMinutes == offset }
        homeActions.removeAll { $0.offsetMinutes == offset }
        if rings.isEmpty { rings = [Ring()] }
    }

    /// True when the alarm uses anything in your Home, so HomeKit has work to do.
    public var usesHome: Bool { !homeActions.isEmpty || !upActions.isEmpty }

    /// The lights for "+ Sunrise": three steps over the 30 minutes before you wake up,
    /// getting brighter, then full brightness at wake-up. Replaces an earlier sunrise
    /// for the same lights.
    public mutating func addSunrise(lights: [HomeTarget]) {
        guard !lights.isEmpty else { return }
        let ids = Set(lights.map(\.id))
        homeActions.removeAll { $0.kind == .light && $0.offsetMinutes <= 0 && Set($0.targets.map(\.id)) == ids }
        for (offset, brightness, warmth) in Self.sunrise {
            homeActions.append(HomeAction(
                offsetMinutes: offset, kind: .light, targets: lights,
                setting: HomeSetting(isOn: true, brightness: brightness, warmth: warmth)
            ))
        }
    }

    /// Offset, brightness and warmth of each sunrise step.
    static let sunrise: [(Int, Int, Int)] = [(-30, 10, 0), (-20, 40, 20), (-10, 80, 50), (0, 100, 80)]

    /// The first offset 15 minutes before the earliest step that's free, for "+ Add a
    /// step".
    public var nextFreeStepOffset: Int {
        let taken = Set(steps.map(\.offsetMinutes))
        var offset = (steps.first?.offsetMinutes ?? 0) - 15
        while taken.contains(offset), offset > Self.ringRange.lowerBound { offset -= 5 }
        return max(offset, Self.ringRange.lowerBound)
    }
}

extension AlarmStep {
    /// "30 min before", "Wake-up time", "5 min after".
    public var offsetText: String {
        isWakeUp ? "Wake-up time" : Ring(offsetMinutes: offsetMinutes).offsetText
    }
}
