#if canImport(StoreKit)
import StoreKit

/// Pro from the App Store: an active, verified Squawk Pro subscription on this Apple
/// Account. Works after reinstalling, since StoreKit keeps the purchases.
public struct StoreKitProStore: ProStore {
    public init() {}

    public func isPro() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProProducts.all.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            return true
        }
        return false
    }

    /// Listens to `Transaction.updates` (renewals, refunds, Ask to Buy, purchases on other
    /// devices) and finishes each transaction. Start it at launch so none are missed.
    public func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result {
                        await transaction.finish()
                    }
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func restore() async throws {
        try await AppStore.sync()
    }
}
#endif
