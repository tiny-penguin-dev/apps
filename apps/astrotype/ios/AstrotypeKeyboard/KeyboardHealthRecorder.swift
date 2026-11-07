import AstrotypeCore
import Foundation

/// Writes the keyboard's memory for each time it is shown, and how many words went in
/// as the first guess (`KeyboardHealth`), to the
/// App Group, where the app picks it up and sends it. Only with Full Access (the App
/// Group needs it) and "Share anonymous usage data" on; otherwise it does nothing.
/// Writes when the keyboard appears, when the peak grows or the headroom shrinks by a
/// megabyte (read once a second while it is up, `MemorySampler`), when something new opens
/// (`KeyboardHealth.Part`), and when it goes away, so a keyboard ended for memory still
/// leaves its last readings and what was open.
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
            // A session still open was ended while showing: say whether it crashed.
            if health.restarted(crashed: KeyboardTelemetry.crashedLastRun) { store.save(health) }
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
        if let reading = MemoryReading.current() { sample(reading) }
    }

    func sample(_ reading: MemoryReading) {
        guard let store else { return }
        if health.sample(footprintMB: reading.footprintMB, headroomMB: reading.headroomMB) { store.save(health) }
    }

    /// Something opened or loaded while the keyboard is up.
    func used(_ part: KeyboardHealth.Part) {
        guard let store else { return }
        if health.use(part) { store.save(health) }
    }

    /// A word went in (`KeyboardModel.onSettled`): counted for how often the first
    /// guess is right, never kept.
    func settled(_ word: SettledWord) {
        guard let store else { return }
        if health.settled(word) { store.save(health) }
    }

    /// Something done to a word from the bar (`KeyboardModel.onWordAction`).
    func wordAction(_ name: String, how: String?) {
        guard let store else { return }
        if health.wordAction(name, how: how) { store.save(health) }
    }

    func disappeared() {
        guard let store else { return }
        health.end(footprintMB: Self.footprintMB(), headroomMB: Self.headroomMB())
        store.save(health)
    }

    /// The memory iOS counts against the extension's limit (its physical footprint), in MB.
    nonisolated static func footprintMB() -> Double {
        MemoryReading.current()?.footprintMB ?? 0
    }

    /// How much more the extension can use before iOS ends it, in MB.
    nonisolated static func headroomMB() -> Double {
        MemoryReading.current()?.headroomMB ?? 0
    }
}
