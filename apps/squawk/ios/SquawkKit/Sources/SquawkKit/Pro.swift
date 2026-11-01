import Foundation

/// Something Squawk Pro adds (PRODUCT.md section 6).
///
/// ```swift
/// if pro.access.allows(.checks) { addCheck() } else { paywall = .checks }
/// pro.access.canAddRing(to: alarm)
/// pro.access.allows(sound: .standard)
/// pro.access.allows(.scarf, bestStreak: log.bestStreak)
/// ```
public enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    /// More than `ProAccess.freeRings` rings on one alarm.
    case moreRings
    /// Wake-up checks: tag, code, penguin game.
    case checks
    /// "Change tomorrow only" to a new time. Skipping a morning is free.
    case changeNextTime
    /// Sounds beyond the three the free rings use.
    case allSounds
    /// A ring's own color and name.
    case ringStyle
    /// Every penguin outfit, without earning it with a streak.
    case outfits
    /// Other app icons.
    case appIcons

    public var id: String { rawValue }

    /// Features that are free for everyone. Moving a feature out of Pro is adding it here.
    public static let free: Set<ProFeature> = []
}

/// What this person can use: the one place Pro is checked (BUILD.md "Pro is checked in
/// one place"). Screens ask it before showing a Pro thing and open the Pro screen when
/// it says no.
///
/// Losing Pro never changes an alarm that's already set: its rings and checks keep
/// working, since an alarm that quietly changes is worse than no alarm. Only adding more
/// needs Pro.
public struct ProAccess: Equatable, Sendable {
    public var isPro: Bool

    public init(isPro: Bool) {
        self.isPro = isPro
    }

    public static let free = ProAccess(isPro: false)
    public static let pro = ProAccess(isPro: true)

    /// Rings a free alarm can have.
    public static let freeRings = 2

    /// The sounds free rings use: the standard one and the two quick-add rings.
    public static let freeSounds: Set<String> = [AlarmSound.standard.id, AlarmSound.soft.id, AlarmSound.loud.id]

    public func allows(_ feature: ProFeature) -> Bool {
        isPro || ProFeature.free.contains(feature)
    }

    /// True when one more ring can be added to this alarm.
    public func canAddRing(to alarm: Alarm) -> Bool {
        allows(.moreRings) || alarm.rings.count < Self.freeRings
    }

    public func allows(sound: AlarmSound) -> Bool {
        allows(.allSounds) || Self.freeSounds.contains(sound.id)
    }

    /// An outfit is yours with Pro, or once your best streak earned it.
    public func allows(_ outfit: Outfit, bestStreak: Int) -> Bool {
        if allows(.outfits) { return true }
        guard let needed = outfit.streakToEarn else { return false }
        return bestStreak >= needed
    }
}

/// Something Squawk can wear (DESIGN.md "Outfits"). Some are earned with a streak of
/// first-ring mornings; all come with Pro.
public enum Outfit: String, CaseIterable, Identifiable, Codable, Sendable {
    case scarf
    case beanie
    case sunglasses
    case partyHat

    public var id: String { rawValue }

    /// Mornings in a row up on the first ring that earn it. Nil means Pro only.
    public var streakToEarn: Int? {
        switch self {
        case .scarf: 3
        case .beanie: 7
        case .sunglasses: 14
        case .partyHat: nil
        }
    }

    /// The outfit this morning just earned: the streak reached its number for the first
    /// time. Nil on any other morning.
    public static func newlyEarned(streak: Int, bestStreak: Int) -> Outfit? {
        guard streak == bestStreak else { return nil }
        return allCases.first { $0.streakToEarn == streak }
    }
}

/// Squawk Pro's App Store products: one subscription group, two plans. The launch
/// prices ($2.99 a month, $29.99 a year) are introductory offers on these, set up in
/// App Store Connect.
public enum ProProducts {
    public static let monthly = "com.tinypenguin.squawk.pro.monthly"
    public static let yearly = "com.tinypenguin.squawk.pro.yearly"
    /// Yearly first, as on the Pro screen.
    public static let all = [yearly, monthly]
}

/// Tells whether this person has Squawk Pro. StoreKit in the app, a fake in tests.
public protocol ProStore: Sendable {
    /// True while a Pro subscription is active.
    func isPro() async -> Bool
    /// Yields whenever purchases change (bought, renewed, refunded, expired, or bought on
    /// another device). Ask `isPro()` again after each.
    func changes() -> AsyncStream<Void>
    /// Asks the App Store for this Apple Account's purchases, for "Restore purchases".
    func restore() async throws
}

/// Pro on or off by hand, for previews and tests.
public final class MemoryProStore: ProStore, @unchecked Sendable {
    private let lock = NSLock()
    private var pro: Bool
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(isPro: Bool = false) {
        pro = isPro
    }

    public func isPro() async -> Bool {
        lock.withLock { pro }
    }

    /// Turns Pro on or off and tells everyone listening.
    public func set(isPro: Bool) {
        let listeners = lock.withLock {
            pro = isPro
            return Array(continuations.values)
        }
        for listener in listeners { listener.yield() }
    }

    public func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.lock.withLock { self.continuations.removeValue(forKey: id) }
            }
        }
    }

    public func restore() async throws {}
}
