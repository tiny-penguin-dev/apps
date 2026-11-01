import Foundation
import Observation
import SquawkKit

/// Whether this person has Squawk Pro, kept up to date from the App Store. Screens read
/// `access` and open the Pro screen (`.proSheet`) when it says no.
@MainActor
@Observable
final class ProModel {
    private(set) var access: ProAccess = .free

    private let store: any ProStore
    private var listening: Task<Void, Never>?

    init(store: any ProStore) {
        self.store = store
    }

    /// The app's one Pro model, on StoreKit.
    static let shared = ProModel(store: StoreKitProStore())

    static func preview(isPro: Bool = false) -> ProModel {
        let model = ProModel(store: MemoryProStore(isPro: isPro))
        model.access = ProAccess(isPro: isPro)
        return model
    }

    /// Checks Pro now and every time purchases change. Call once at launch.
    func start() {
        guard listening == nil else { return }
        let changes = store.changes()
        listening = Task { [weak self] in
            await self?.refresh()
            for await _ in changes {
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        let isPro = await store.isPro()
        if isPro != access.isPro {
            access = ProAccess(isPro: isPro)
        }
    }

    /// "Restore purchases". True when Pro is on afterwards.
    func restore() async -> Bool {
        do {
            try await store.restore()
        } catch {
            Telemetry.report(error)
        }
        await refresh()
        Telemetry.count("pro.restored", ["found": access.isPro ? "yes" : "no"])
        return access.isPro
    }
}
