import Foundation

/// The answers to the guided new-alarm setup (features/steps/FEATURE.md, "Guided new
/// alarm"). Each answer maps straight to steps, so the guide and the full edit screen
/// always build the same alarm. The defaults are the simple choice: tapping Next all the
/// way through gives one ring at the wake-up time.
///
/// ```swift
/// var guide = NewAlarmGuide()
/// guide.wake = .gentle
/// guide.check = WakeUpCheck(kind: .game)
/// model.save(guide.alarm)
/// ```
public struct NewAlarmGuide: Hashable, Sendable {
    /// "How should Squawk wake you?"
    public enum Wake: String, CaseIterable, Identifiable, Sendable {
        /// Morning squawk at the wake-up time.
        case one
        /// A soft peep 10 minutes early, then Morning squawk.
        case gentle
        /// Morning squawk, then the loud ring 5 minutes later.
        case nudge

        public var id: String { rawValue }
    }

    /// "Want your lights to help?"
    public enum Lights: String, CaseIterable, Identifiable, Sendable {
        /// The lamp brightens over the 30 minutes before you wake up.
        case sunrise
        /// The lamp turns on with the alarm.
        case atWakeUp
        case none

        public var id: String { rawValue }
    }

    public var time: TimeOfDay
    public var days: Set<Weekday>
    public var wake: Wake
    public var lights: Lights
    /// The lights to use for `lights`. Picked with the Home picker.
    public var lightTargets: [HomeTarget]
    /// "Make sure you get up?" Nil is no check.
    public var check: WakeUpCheck?
    /// "Anything once you're up?"
    public var upActions: [HomeAction]

    public init(
        time: TimeOfDay = .sevenAM, days: Set<Weekday> = Weekday.weekdays, wake: Wake = .one,
        lights: Lights = .none, lightTargets: [HomeTarget] = [], check: WakeUpCheck? = nil,
        upActions: [HomeAction] = []
    ) {
        self.time = time
        self.days = days
        self.wake = wake
        self.lights = lights
        self.lightTargets = lightTargets
        self.check = check
        self.upActions = upActions
    }

    /// True when the answers turn on lights, so "When you're up" (which needs Home) is
    /// worth asking about.
    public var usesLights: Bool { lights != .none && !lightTargets.isEmpty }

    /// The alarm these answers make.
    public var alarm: Alarm {
        var alarm = Alarm(time: time, days: days)
        switch wake {
        case .one: break
        case .gentle: alarm.addSoftRing()
        case .nudge: alarm.addLoudRing()
        }
        if usesLights {
            switch lights {
            case .sunrise:
                alarm.addSunrise(lights: lightTargets)
            case .atWakeUp:
                alarm.homeActions.append(HomeAction(
                    kind: .light, targets: lightTargets,
                    setting: HomeSetting(isOn: true, brightness: 100, warmth: 80)
                ))
            case .none:
                break
            }
            alarm.upActions = upActions
        }
        if let check { alarm.checks = [check] }
        return alarm
    }

    /// The Pro features these answers use. Saving with any of them shows the Pro screen
    /// for someone without Pro; "Not now" saves `freeAlarm` instead.
    public var proFeatures: Set<ProFeature> {
        var features: Set<ProFeature> = []
        if check != nil { features.insert(.checks) }
        if usesLights || !alarm.upActions.isEmpty { features.insert(.home) }
        return features
    }

    /// The alarm without its Pro parts.
    public var freeAlarm: Alarm {
        var copy = self
        copy.check = nil
        copy.lights = .none
        copy.upActions = []
        return copy.alarm
    }
}
