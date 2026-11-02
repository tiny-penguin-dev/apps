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
        /// Lights that brighten and warm up slowly over a few minutes (`Sunrise`).
        case sunrise

        public var id: String { rawValue }

        /// The kind of device it controls: sunrise lights use lights.
        public var deviceKind: Kind { self == .sunrise ? .light : self }

        /// "Lights", as in the Add something sheet.
        public var title: String {
            switch self {
            case .light: "Lights"
            case .scene: "Home scene"
            case .plug: "Plug or switch"
            case .blinds: "Blinds"
            case .sunrise: "Sunrise lights"
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
    /// For `.sunrise`: how long it takes and where brightness and color start and end.
    /// Nil for every other kind (and in alarms saved before Sunrise lights).
    public var sunrise: Sunrise?

    public init(
        id: UUID = UUID(), offsetMinutes: Int = 0, kind: Kind,
        targets: [HomeTarget], setting: HomeSetting = HomeSetting(), sunrise: Sunrise? = nil
    ) {
        self.id = id
        self.offsetMinutes = offsetMinutes
        self.kind = kind
        self.targets = targets
        self.setting = setting
        self.sunrise = sunrise ?? (kind == .sunrise ? .standard : nil)
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
        case .sunrise:
            return (sunrise ?? .standard).detail
        }
    }

    /// "Bedroom lamp · 50% · warm".
    public var summary: String {
        detail.isEmpty ? name : "\(name) · \(detail)"
    }
}

/// Sunrise lights: lights that start dim and warm and slowly get brighter and closer to
/// daylight (features/sunrise-lights/FEATURE.md). HomeKit can't fade a light over time,
/// so `points` spreads it into a few timed light changes, which the Home hub runs.
///
/// ```swift
/// let sunrise = Sunrise(minutes: 30, startBrightness: 5, endBrightness: 100)
/// sunrise.points   // [(0, 5%), (3, 6%), (6, 9%), ... (30, 100%)]
/// alarm.addSunrise(lights: [lamp], sunrise: sunrise)   // ends at wake-up
/// ```
public struct Sunrise: Codable, Hashable, Sendable {
    /// How long it takes, in minutes (`minutesRange`).
    public var minutes: Int
    /// 1 to 100.
    public var startBrightness: Int
    public var endBrightness: Int
    /// 0 is warm, 100 is daylight, like `HomeSetting.warmth`.
    public var startWarmth: Int
    public var endWarmth: Int

    public init(minutes: Int = 30, startBrightness: Int = 5, endBrightness: Int = 100, startWarmth: Int = 0, endWarmth: Int = 70) {
        self.minutes = minutes
        self.startBrightness = startBrightness
        self.endBrightness = endBrightness
        self.startWarmth = startWarmth
        self.endWarmth = endWarmth
    }

    /// 30 minutes, 5% warm to 100% near daylight.
    public static let standard = Sunrise()
    public static let minutesRange = 5...60
    /// The most light changes one sunrise makes, so the Home app doesn't fill up.
    public static let maxChanges = 10

    /// One light change: minutes after the sunrise starts, and what the lights are set to.
    public struct Point: Hashable, Sendable {
        public var minutes: Int
        public var setting: HomeSetting
    }

    /// The light changes, from the start to the end, on whole minutes (Home automations
    /// can't run between minutes). Up to `maxChanges` after the first. Brightness eases
    /// in (slow at first, faster near the end, like a real sunrise); color moves evenly.
    public var points: [Point] {
        let length = min(max(minutes, Self.minutesRange.lowerBound), Self.minutesRange.upperBound)
        let changes = min(length, Self.maxChanges)
        var result: [Point] = []
        for k in 0...changes {
            let t = Double(k) / Double(changes)
            let at = Int((t * Double(length)).rounded())
            if result.last?.minutes == at { continue }
            result.append(Point(minutes: at, setting: setting(at: t)))
        }
        return result
    }

    /// The lights at `t` (0 is the start, 1 the end).
    public func setting(at t: Double) -> HomeSetting {
        let t = min(max(t, 0), 1)
        func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(v, r.lowerBound), r.upperBound) }
        let b0 = Double(clamp(startBrightness, 1...100)), b1 = Double(clamp(endBrightness, 1...100))
        let w0 = Double(clamp(startWarmth, 0...100)), w1 = Double(clamp(endWarmth, 0...100))
        return HomeSetting(
            isOn: true,
            brightness: Int((b0 + (b1 - b0) * t * t).rounded()),
            warmth: Int((w0 + (w1 - w0) * t).rounded())
        )
    }

    /// "30 min · 5% → 100%".
    public var detail: String {
        "\(minutes) min · \(startBrightness)% → \(endBrightness)%"
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

    public init(offsetMinutes: Int, rings: [Ring] = [], actions: [HomeAction] = []) {
        self.offsetMinutes = offsetMinutes
        self.rings = rings
        self.actions = actions
    }

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

    /// "+ Sunrise lights": one Sunrise lights step that ends at the wake-up time.
    /// Replaces an earlier sunrise for the same lights.
    public mutating func addSunrise(lights: [HomeTarget], sunrise: Sunrise = .standard) {
        guard !lights.isEmpty else { return }
        let ids = Set(lights.map(\.id))
        homeActions.removeAll { $0.kind == .sunrise && Set($0.targets.map(\.id)) == ids }
        let minutes = min(max(sunrise.minutes, Sunrise.minutesRange.lowerBound), Sunrise.minutesRange.upperBound)
        homeActions.append(HomeAction(offsetMinutes: -minutes, kind: .sunrise, targets: lights, sunrise: sunrise))
    }

    /// The Home things to run, by minute, for planning automations: like `steps`, but each
    /// Sunrise lights is spread into its light changes. A change that lands on another
    /// Home step's minute joins it, so they share one automation.
    public var homeSteps: [AlarmStep] {
        var byOffset: [Int: [HomeAction]] = [:]
        for action in homeActions {
            guard action.kind == .sunrise else {
                byOffset[action.offsetMinutes, default: []].append(action)
                continue
            }
            for point in (action.sunrise ?? .standard).points {
                let offset = action.offsetMinutes + point.minutes
                byOffset[offset, default: []].append(HomeAction(
                    id: StableID.make("sunrise|\(action.id)|\(point.minutes)"),
                    offsetMinutes: offset, kind: .light, targets: action.targets, setting: point.setting
                ))
            }
        }
        return byOffset.keys.sorted().map { AlarmStep(offsetMinutes: $0, actions: byOffset[$0] ?? []) }
    }

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
