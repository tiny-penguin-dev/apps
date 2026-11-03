import AstrotypeCore
import Darwin
import Foundation
import os

/// Writes the keyboard's memory for each time it is shown, and how many words went in
/// as the first guess (`KeyboardHealth`), to the
/// App Group, where the app picks it up and sends it. Only with Full Access (the App
/// Group needs it) and "Share anonymous usage data" on; otherwise it does nothing.
/// Writes when the keyboard appears, when the peak grows or the headroom shrinks by a
/// megabyte, and when it goes away, so a keyboard ended for memory still leaves its
/// last readings.
@MainActor
final class KeyboardHealthRecorder {
    private let store: FileKeyboardHealthStore?
    private var health: KeyboardHealth

    init(fullAccess: Bool) {
        let url = KeyboardFiles.shared(KeyboardFiles.health)
        if fullAccess, let url, UsageSharing.load(from: KeyboardFiles.shared(KeyboardFiles.usage)) {
            let store = FileKeyboardHealthStore(url: url)
            self.store = store
            health = store.load() ?? KeyboardHealth()
        } else {
            store = nil
            health = KeyboardHealth()
        }
    }

    func appeared() {
        guard let store else { return }
        health = store.load() ?? health
        health.begin(at: Date(), footprintMB: Self.footprintMB(), headroomMB: Self.headroomMB())
        store.save(health)
    }

    func sample() {
        guard let store else { return }
        if health.sample(footprintMB: Self.footprintMB(), headroomMB: Self.headroomMB()) { store.save(health) }
    }

    /// A word went in (`KeyboardModel.onSettled`): counted for how often the first
    /// guess is right, never kept.
    func settled(_ word: SettledWord) {
        guard let store else { return }
        if health.settled(word) { store.save(health) }
    }

    func disappeared() {
        guard let store else { return }
        health.end(footprintMB: Self.footprintMB(), headroomMB: Self.headroomMB())
        store.save(health)
    }

    /// The memory iOS counts against the extension's limit (its physical footprint), in MB.
    nonisolated static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO),
                      UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: integer_t.self), &count)
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// How much more the extension can use before iOS ends it, in MB.
    nonisolated static func headroomMB() -> Double {
        Double(os_proc_available_memory()) / 1_048_576
    }
}
