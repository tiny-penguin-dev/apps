import Foundation

/// What the keys do when thumbs hit them, and what builds up with flow
/// (features/customization, "Effects"). `KeyboardSettings.trails` stays the switch for
/// all of it; this says which effects.
///
///     var effects = EffectsSettings.preset(.space)
///     effects.letters = .glitch
///     effects.isFree   // false: only Calm is free
public struct EffectsSettings: Codable, Hashable, Sendable {
    /// What a tap throws. Everything but Ring flies out in every direction.
    public enum Tap: String, Codable, CaseIterable, Sendable {
        case none, ring, ripple, sparks, stars, snow, pixels, fireworks, glitch, hearts, petals
        public var name: String { self == .none ? "None" : rawValue.capitalized }
    }
    public enum Flash: String, Codable, CaseIterable, Sendable {
        case thumb, theme, rainbow, candy, off
        public var name: String {
            switch self {
            case .thumb: "Thumb's colour"
            case .theme: "Theme's colour"
            case .rainbow: "Rainbow"
            case .candy: "Candy pinks"
            case .off: "Off"
            }
        }
    }
    public enum Trail: String, Codable, CaseIterable, Sendable {
        case none, line, comet, glitter, rainbow, pixels, glitch, hearts, silk
        public var name: String { self == .none ? "None" : rawValue.capitalized }
    }
    /// What a hit letter does. All but None and Pop are drawn with Metal.
    public enum Letters: String, Codable, CaseIterable, Sendable {
        case none, pop, jelly, wave, glitch, liquid, pixel, disco, warp
        public var usesMetal: Bool { self != .none && self != .pop }
        public var name: String { self == .none ? "Still" : rawValue.capitalized }
    }
    /// What the keys themselves do, drawn with Metal over them: a hit key lights up in
    /// the preset's way, and with flow every key joins in (Gabriel, 7 Nov 2026: "make it
    /// affect keys in cool ways").
    public enum Keys: String, Codable, CaseIterable, Sendable {
        case none, neon, glitch, prism, warp, ripple, candy
        public var name: String {
            switch self {
            case .none: "Plain"
            case .prism: "Holo foil"
            case .candy: "Candy gloss"
            default: rawValue.capitalized
            }
        }
    }
    /// What flies across the keys at Blizzard, from every side.
    public enum Fall: String, Codable, CaseIterable, Sendable {
        case stars, snow, confetti, pixels, `static`, warp, petals, hearts
        public var name: String {
            switch self {
            case .warp: "Warp speed"
            default: rawValue.capitalized
            }
        }
    }
    /// The sky behind the keys at the top level.
    public enum Sky: String, Codable, CaseIterable, Sendable {
        case aurora, starfield, ice, retro, glitch, prism, blackHole, ripples, candy
        public var name: String {
            switch self {
            case .ice: "Ice"
            case .retro: "Retro grid"
            case .blackHole: "Black hole"
            case .candy: "Candy clouds"
            default: rawValue.capitalized
            }
        }
    }

    /// The looks to start from (Gabriel, 7 Nov 2026: quicker, wilder, in every
    /// direction; Sparkle and Aurora went).
    public enum Preset: String, Codable, CaseIterable, Sendable {
        case calm, arcade, glitch, rainbow, space, zen, sugarRush
        public var name: String {
            switch self {
            case .calm: "Calm"
            case .arcade: "Arcade"
            case .glitch: "Glitch"
            case .rainbow: "Rainbow"
            case .space: "Space"
            case .zen: "Zen"
            case .sugarRush: "Sugar Rush"
            }
        }
    }

    public static let buildRange: ClosedRange<Double> = 0...1

    public var tap: Tap
    public var flash: Flash
    public var trail: Trail
    public var letters: Letters
    public var keys: Keys
    /// Effects grow as the person types fast without fixes (`FlowMeter`).
    public var flow: Bool
    /// How quickly flow builds, 0 (slowly) to 1 (quickly). Scales the word counts.
    public var build: Double
    /// Each level's own switch: 1 Waddle (combo count, bigger taps), 2 Toboggan
    /// (comets and sparks), 3 Blizzard (falling things, glow), 4 Aurora (the sky).
    public var combo: Bool
    public var comets: Bool
    public var falling: Bool
    public var fall: Fall
    public var skyOn: Bool
    public var sky: Sky

    public init(tap: Tap = .ring, flash: Flash = .thumb, trail: Trail = .line, letters: Letters = .none, keys: Keys = .none, flow: Bool = false,
                build: Double = 0.5, combo: Bool = true, comets: Bool = true, falling: Bool = true, fall: Fall = .snow,
                skyOn: Bool = true, sky: Sky = .aurora) {
        self.tap = tap
        self.flash = flash
        self.trail = trail
        self.letters = letters
        self.keys = keys
        self.flow = flow
        self.build = build
        self.combo = combo
        self.comets = comets
        self.falling = falling
        self.fall = fall
        self.skyOn = skyOn
        self.sky = sky
    }

    /// Today's look: a ring on each tap, a line for each swipe, keys flashing in the
    /// thumb's colour, no flow. Free.
    public static let calm = EffectsSettings()

    public static func preset(_ preset: Preset) -> EffectsSettings {
        switch preset {
        case .calm: calm
        // An old arcade: 8-bit blasts, blocky letters, a neon grid racing in.
        case .arcade: EffectsSettings(tap: .pixels, flash: .theme, trail: .pixels, letters: .pixel, keys: .neon, flow: true, fall: .pixels, sky: .retro)
        // The keys themselves glitch: split colours, static, torn rows.
        case .glitch: EffectsSettings(tap: .glitch, flash: .theme, trail: .glitch, letters: .glitch, keys: .glitch, flow: true, fall: .static, sky: .glitch)
        case .rainbow: EffectsSettings(tap: .fireworks, flash: .rainbow, trail: .rainbow, letters: .disco, keys: .prism, flow: true, fall: .confetti, sky: .prism)
        // Lift off, warp, and at the top fall into a black hole.
        case .space: EffectsSettings(tap: .stars, trail: .comet, letters: .warp, keys: .warp, flow: true, fall: .warp, sky: .blackHole)
        // Still playful, but slow and soft: petals, silk, ripples.
        case .zen: EffectsSettings(tap: .petals, trail: .silk, letters: .wave, keys: .ripple, flow: true, fall: .petals, sky: .ripples)
        case .sugarRush: EffectsSettings(tap: .hearts, flash: .candy, trail: .hearts, letters: .jelly, keys: .candy, flow: true, fall: .hearts, sky: .candy)
        }
    }

    /// The preset these settings are, if any ("Your mix" otherwise).
    public var preset: Preset? { Preset.allCases.first { Self.preset($0) == self } }

    /// Only Calm's choices are free: ring or no taps, line or no trails, thumb flashes
    /// or none, still letters, no flow.
    public var isFree: Bool {
        (tap == .ring || tap == .none) && (trail == .line || trail == .none) && (flash == .thumb || flash == .off) && letters == .none
            && keys == .none && !flow
    }

    /// The highest level the switches allow (Aurora needs the sky on, and so on down);
    /// 0 without flow.
    public var topLevel: Int {
        guard flow else { return 0 }
        if skyOn { return 4 }
        if falling { return 3 }
        if comets { return 2 }
        return 1
    }

    /// The factor on `FlowMeter`'s word counts: 1.5 at slowly, 0.5 at quickly.
    public var levelScale: Double { 1.5 - min(max(build, Self.buildRange.lowerBound), Self.buildRange.upperBound) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EffectsSettings()
        tap = (try? c.decodeIfPresent(Tap.self, forKey: .tap)) ?? d.tap
        flash = (try? c.decodeIfPresent(Flash.self, forKey: .flash)) ?? d.flash
        trail = (try? c.decodeIfPresent(Trail.self, forKey: .trail)) ?? d.trail
        letters = (try? c.decodeIfPresent(Letters.self, forKey: .letters)) ?? d.letters
        keys = (try? c.decodeIfPresent(Keys.self, forKey: .keys)) ?? d.keys
        flow = try c.decodeIfPresent(Bool.self, forKey: .flow) ?? d.flow
        build = try c.decodeIfPresent(Double.self, forKey: .build) ?? d.build
        combo = try c.decodeIfPresent(Bool.self, forKey: .combo) ?? d.combo
        comets = try c.decodeIfPresent(Bool.self, forKey: .comets) ?? d.comets
        falling = try c.decodeIfPresent(Bool.self, forKey: .falling) ?? d.falling
        fall = (try? c.decodeIfPresent(Fall.self, forKey: .fall)) ?? d.fall
        skyOn = try c.decodeIfPresent(Bool.self, forKey: .skyOn) ?? d.skyOn
        sky = (try? c.decodeIfPresent(Sky.self, forKey: .sky)) ?? d.sky
    }
}

/// The flow levels, penguin themed.
public enum FlowLevel: Int, CaseIterable, Sendable, Comparable {
    case calm = 0, waddle, toboggan, blizzard, aurora

    public var name: String {
        switch self {
        case .calm: "Calm"
        case .waddle: "Waddle"
        case .toboggan: "Toboggan"
        case .blizzard: "Blizzard"
        case .aurora: "Aurora"
        }
    }

    /// Words of flow to reach this level at the steady build.
    public var words: Double {
        switch self {
        case .calm: 0
        case .waddle: 5
        case .toboggan: 15
        case .blizzard: 30
        case .aurora: 50
        }
    }

    public static func < (a: FlowLevel, b: FlowLevel) -> Bool { a.rawValue < b.rawValue }
}

/// The flow meter (features/customization "Flow, exactly"): words typed fast without
/// fixes fill it, a delete takes some back, a pause drains it. Pure; time is passed in.
///
///     var flow = FlowMeter()
///     flow.word(at: now)                  // +1, or +1.5 within 1.5 s of the last word
///     flow.delete(at: now)                // -3
///     flow.tick(now: now)                 // after 1 s without typing, the combo drops 1 a second
///     flow.level(scale: 1, cap: 4)        // .toboggan
public struct FlowMeter: Equatable, Sendable {
    /// A word within this long of the last one counts extra.
    public static let quick: TimeInterval = 1.5
    public static let quickBonus = 1.5
    public static let deletePenalty = 3.0
    /// The meter starts draining this long after the last word or delete, then the
    /// combo drops 1 a second and the score with it, so both reach 0 together
    /// (Gabriel, 6 Nov 2026).
    public static let rest: TimeInterval = 1

    public private(set) var score = 0.0
    /// Words in this run; back to 0 when the meter empties.
    public private(set) var combo = 0
    private var lastWord: TimeInterval?
    private var lastInput: TimeInterval?
    private var lastTick: TimeInterval?
    /// Score per combo word at the last input: what one second of draining takes.
    private var perWord = 1.0

    public init() {}

    public mutating func word(at time: TimeInterval) {
        tick(now: time)
        let quick = lastWord.map { time - $0 <= Self.quick } ?? false
        score += quick ? Self.quickBonus : 1
        combo += 1
        lastWord = time
        lastInput = time
        perWord = score / Double(combo)
    }

    public mutating func delete(at time: TimeInterval) {
        tick(now: time)
        score = max(0, score - Self.deletePenalty)
        combo = max(0, combo - 3)
        if score == 0 { combo = 0 }
        lastInput = time
        perWord = combo > 0 ? score / Double(combo) : 1
    }

    /// Drain for the time since the last tick that falls after the rest.
    public mutating func tick(now: TimeInterval) {
        defer { lastTick = now }
        guard let input = lastInput, score > 0 else { return }
        let restEnds = input + Self.rest
        let from = max(restEnds, lastTick ?? restEnds)
        guard now > from else { return }
        score = max(0, score - (now - from) * perWord)
        // Whole words left; the small slack keeps float error from dropping one early.
        combo = score > 1e-9 ? Int((score / perWord - 1e-9).rounded(.up)) : 0
        if combo == 0 { score = 0 }
    }

    /// Empty the meter (the keyboard went away).
    public mutating func reset() { self = FlowMeter() }

    /// The level reached, with the word counts times `scale`, no higher than `cap`.
    public func level(scale: Double = 1, cap: Int = 4) -> FlowLevel {
        var reached = FlowLevel.calm
        for level in FlowLevel.allCases where level != .calm && score >= level.words * scale { reached = level }
        return FlowLevel(rawValue: min(reached.rawValue, max(0, cap))) ?? .calm
    }

    /// How far toward the next level, 0 to 1 (1 at the cap).
    public func progress(scale: Double = 1, cap: Int = 4) -> Double {
        let now = level(scale: scale, cap: cap)
        guard now.rawValue < min(cap, 4), let next = FlowLevel(rawValue: now.rawValue + 1) else { return score > 0 ? 1 : 0 }
        let from = now.words * scale, to = next.words * scale
        return min(max((score - from) / (to - from), 0), 1)
    }
}
