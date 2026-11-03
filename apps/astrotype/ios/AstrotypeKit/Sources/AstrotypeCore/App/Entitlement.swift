import Foundation

/// Something Astrotype Pro adds (PRODUCT.md §6). The features that have a phase yet
/// are here; snippets, custom gestures, themes and extra languages join as they land.
public enum ProFeature: String, CaseIterable, Sendable {
    /// Taps and swipes from both thumbs, mixed in one word.
    case twoThumbs
    /// The split layout on wide screens (and one-handed layouts later).
    case splitLayout
    /// The practice drills (Phase 7). The speed test stays free.
    case drills
    /// Typing in two languages at once (features/languages). Every language is free
    /// on its own.
    case twoLanguages

    /// Features that are free for everyone. Moving a feature out of Pro is adding it here.
    public static let free: Set<ProFeature> = []
}

/// Where this person stands with Pro: on the two-week trial, subscribed, or on the
/// free keyboard.
public enum ProStatus: Sendable, Equatable {
    case free
    case trial(endsOn: Date)
    case pro

    /// From what the App Store says and when the trial started.
    public static func from(subscribed: Bool, trial: Trial, now: Date) -> ProStatus {
        if subscribed { return .pro }
        return trial.isOver(now: now) ? .free : .trial(endsOn: trial.end)
    }
}

/// What the person may use, from one status: the one place Pro is checked (BUILD.md
/// "Pro is checked in one place"). The app, the practice keyboard and the extension all
/// ask it before doing a Pro thing.
///
///     let ent = Entitlement(status: .trial(endsOn: date), now: now)
///     ent.allows(.twoThumbs)                       // true
///     ent.allows(.splitLayout)                     // true on trial, false on .free
///     Entitlement.features(for: .free)             // the table in PRODUCT.md §6
public struct Entitlement: Sendable, Equatable {
    public var status: ProStatus
    public var now: Date

    public init(status: ProStatus, now: Date) {
        self.status = status
        self.now = now
    }

    /// Everything allowed: the default before a host knows better, and the Try it screen
    /// (everyone starts on the trial).
    public static let full = Entitlement(status: .pro, now: .distantPast)

    /// Pro features are on: subscribed, or on a trial that has not ended.
    public var isPro: Bool {
        switch status {
        case .pro: true
        case .trial(let endsOn): now < endsOn
        case .free: false
        }
    }

    public var isSubscribed: Bool { status == .pro }

    public var isOnTrial: Bool {
        if case .trial = status { return isPro }
        return false
    }

    public func allows(_ feature: ProFeature) -> Bool {
        isPro || ProFeature.free.contains(feature)
    }

    /// The features a status brings, as the table in PRODUCT.md §6 reads.
    public static func features(for status: ProStatus, now: Date = Date()) -> Set<ProFeature> {
        let ent = Entitlement(status: status, now: now)
        return Set(ProFeature.allCases.filter(ent.allows))
    }
}

/// Astrotype Pro's App Store products: one subscription group, two plans, at the
/// prices Gabriel set (PRODUCT.md, 1 Nov 2026). The trial is the app's own fourteen
/// days from first launch, so the products carry no introductory offer.
public enum ProProducts {
    public static let yearly = "com.tinypenguin.astrotype.pro.yearly"
    public static let monthly = "com.tinypenguin.astrotype.pro.monthly"
    /// Yearly first, as on the Pro screen.
    public static let all = [yearly, monthly]

    /// The plan name metrics use for a product.
    public static func plan(of productID: String) -> String {
        productID == yearly ? "yearly" : "monthly"
    }
}

/// Tells whether this person has Astrotype Pro. StoreKit in the app and the extension
/// (Phase 1 showed StoreKit 2 answers inside the extension), a fake in tests.
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
    public private(set) var restores = 0

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

    public func restore() async throws {
        lock.withLock { restores += 1 }
    }
}

// MARK: Trial start and the Pro cache, as files

/// When the trial started, as a file: the app writes its first launch to the App Group
/// (readable by the extension with Full Access); the extension keeps its own copy from
/// the first time it ran, which is minutes after the app's at most, for when there is
/// no Full Access (BUILD.md "Pro status inside the extension").
public struct TrialStore: Sendable {
    private let file: JSONFile<Trial>

    public init(url: URL) {
        file = JSONFile(url)
    }

    public func load() -> Trial? { file.read() }
    public func save(_ trial: Trial) { file.write(trial) }

    /// The saved trial, or one that starts now, saved.
    public func loadOrStart(now: Date) -> Trial {
        if let trial = load() { return trial }
        let trial = Trial(start: now)
        save(trial)
        return trial
    }

    /// The earlier of two starts (the app's and the extension's own), so a trial never
    /// grows longer by being read from two places.
    public static func earliest(_ trials: Trial?...) -> Trial? {
        trials.compactMap { $0 }.min { $0.start < $1.start }
    }
}

/// The App Store's last answer, as a file, so the keyboard comes up in the right mode
/// before StoreKit answers again (a cold start inside an extension takes a moment).
public struct ProCache: Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public var isPro: Bool
        public var checked: Date

        public init(isPro: Bool, checked: Date) {
            self.isPro = isPro
            self.checked = checked
        }
    }

    private let file: JSONFile<Entry>

    public init(url: URL) {
        file = JSONFile(url)
    }

    public func load() -> Entry? { file.read() }
    public func save(_ entry: Entry) { file.write(entry) }
}
