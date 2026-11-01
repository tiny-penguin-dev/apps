import Foundation
import StoreKit
import UIKit
import os

/// The two Phase 1 checks (BUILD.md) plus a memory readout, shown in the bar so they
/// can be read on a phone: whether StoreKit answers inside the extension, whether a
/// haptic plays without Full Access, and how much memory is left before the limit.
/// Phase 2 replaces the bar's note with the engine's guesses.
@MainActor
final class ExtensionChecks {
    private var storeKit = "StoreKit …"
    private var hasFullAccess = false
    private var taps = 0
    private var report: ((String) -> Void)?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    func run(hasFullAccess: Bool, report: @escaping (String) -> Void) {
        self.hasFullAccess = hasFullAccess
        self.report = report
        haptic.prepare()
        publish()
        Task { [weak self] in
            // StoreKit 2 from inside a keyboard extension: does it answer at all?
            var active = 0
            for await result in Transaction.currentEntitlements {
                if case .verified = result { active += 1 }
            }
            let payments = AppStore.canMakePayments
            await MainActor.run {
                self?.storeKit = "StoreKit ok (\(active) active, pay \(payments ? "yes" : "no"))"
                self?.publish()
            }
        }
    }

    /// On every key: a haptic and a click. Whether they can be felt and heard without
    /// Full Access is the second check.
    func keyTapped() {
        taps += 1
        haptic.impactOccurred()
        UIDevice.current.playInputClick()
        if taps % 5 == 0 { publish() }
    }

    private func publish() {
        let mb = Double(Self.availableBytes()) / 1_048_576
        report?("\(storeKit) · haptic on every key · \(String(format: "%.0f", mb)) MB left · full access \(hasFullAccess ? "on" : "off")")
    }

    /// How much memory the extension can still use before iOS kills it. The budget in
    /// BUILD.md is 40 MB in use; this says how much headroom is left under the limit.
    nonisolated static func availableBytes() -> Int {
        os_proc_available_memory()
    }
}
