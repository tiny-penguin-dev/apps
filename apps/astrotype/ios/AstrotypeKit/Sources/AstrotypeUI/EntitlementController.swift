import Foundation
import AstrotypeCore

/// Keeps a `KeyboardModel`'s entitlement in step with the App Store and the trial, for
/// the keyboard extension (the app has `AppModel` for this). Starts from the cached
/// answer so the keyboard comes up in the right mode at once, asks StoreKit, then
/// listens for changes (a purchase in the app turns two thumbs back on in Messages
/// without opening the app, BUILD.md Phase 6).
///
///     let controller = EntitlementController(model: model, store: StoreKitProStore(),
///                                            cache: ProCache(url: ...), trial: trial)
///     controller.start()
@MainActor
public final class EntitlementController {
    private let model: KeyboardModel
    private let store: any ProStore
    private let cache: ProCache?
    private let trial: Trial
    private let now: () -> Date
    private var listening: Task<Void, Never>?

    public init(model: KeyboardModel, store: any ProStore, cache: ProCache?, trial: Trial, now: @escaping () -> Date = { Date() }) {
        self.model = model
        self.store = store
        self.cache = cache
        self.trial = trial
        self.now = now
    }

    /// Applies the cached answer, then the App Store's, now and on every change.
    public func start() {
        guard listening == nil else { return }
        apply(subscribed: cache?.load()?.isPro ?? false)
        let changes = store.changes()
        listening = Task { [weak self] in
            await self?.refresh()
            for await _ in changes {
                await self?.refresh()
            }
        }
    }

    public func refresh() async {
        let subscribed = await store.isPro()
        cache?.save(ProCache.Entry(isPro: subscribed, checked: now()))
        apply(subscribed: subscribed)
    }

    private func apply(subscribed: Bool) {
        let time = now()
        model.entitlement = Entitlement(status: ProStatus.from(subscribed: subscribed, trial: trial, now: time), now: time)
    }
}
