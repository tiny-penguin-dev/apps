import Foundation
import StoreKit
import UIKit
import os

/// The Phase 1 checks (BUILD.md) plus a memory readout, shown as the bar's idle note so
/// they can be read on a phone: whether StoreKit answers inside the extension, and how
/// much memory is left before the limit. Haptics play from `KeyboardView` on every key.
/// Goes away once the readings are in BUILD.md.
@MainActor
final class ExtensionChecks {
    private var storeKit = "StoreKit …"
    private var hasFullAccess = false
    private var report: ((String) -> Void)?
    private var granted: CGFloat = 0
    private var wanted: CGFloat = 0
    private var width: CGFloat = 0
    private var screenWidth: CGFloat = 0

    func run(hasFullAccess: Bool, report: @escaping (String) -> Void) {
        self.hasFullAccess = hasFullAccess
        self.report = report
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

    /// Re-read memory, every few edits.
    func refresh() {
        publish()
    }

    /// The height iOS granted the keyboard against the height it asked for, and the
    /// width it got against the screen's (a wide screen should give the whole width).
    func sized(granted: CGFloat, wanted: CGFloat, width: CGFloat, screenWidth: CGFloat) {
        guard granted != self.granted || wanted != self.wanted || width != self.width || screenWidth != self.screenWidth else { return }
        self.granted = granted
        self.wanted = wanted
        self.width = width
        self.screenWidth = screenWidth
        publish()
    }

    private func publish() {
        let mb = Double(Self.availableBytes()) / 1_048_576
        report?("\(storeKit) · \(String(format: "%.0f", mb)) MB · h \(Int(granted))/\(Int(wanted)) · w \(Int(width))/\(Int(screenWidth)) · full access \(hasFullAccess ? "on" : "off")")
    }

    /// How much memory the extension can still use before iOS kills it. The budget in
    /// BUILD.md is 40 MB in use; this says how much headroom is left under the limit.
    nonisolated static func availableBytes() -> Int {
        os_proc_available_memory()
    }
}
