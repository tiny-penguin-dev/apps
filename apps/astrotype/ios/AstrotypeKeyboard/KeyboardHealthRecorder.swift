import AstrotypeCore
import Foundation

/// Writes the keyboard's memory for each time it is shown, and how many words went in
/// as the first guess (`KeyboardHealth`), to the
/// App Group, where the app picks it up and sends it. Only with Full Access (the App
/// Group needs it) and "Share anonymous usage data" on; otherwise it does nothing.
/// Writes when the keyboard appears, when the peak grows or the headroom shrinks by a
/// megabyte (read once a second while it is up, `MemorySampler`), when something new opens
/// (`KeyboardHealth.Part`), when the app it is in goes to the background and comes
/// back, and when it goes away, so a keyboard ended for memory still leaves its last
/// readings and what was open.
///
/// The keyboard in each app is its own process, and all of them write the one file: this
/// one keeps its own session and puts it in as it stands (`KeyboardHealth.put`), so a
/// keyboard waking up in one app doesn't write over what the keyboard in another wrote.
@MainActor
final class KeyboardHealthRecorder {
    private let store: FileKeyboardHealthStore?
    /// This keyboard's session, from `appeared` on.
    private var session: KeyboardHealth.Session?

    init(fullAccess: Bool) {
        let url = KeyboardFiles.shared(KeyboardFiles.health)
        if fullAccess, let url, UsageSharing.load(from: KeyboardFiles.shared(KeyboardFiles.usage)) {
            let store = FileKeyboardHealthStore(url: url)
            self.store = store
            // A session still open was ended while showing: say whether it crashed.
            if var health = store.load(), health.restarted(crashed: KeyboardTelemetry.crashedLastRun) { store.save(health) }
        } else {
            store = nil
        }
    }

    func appeared() {
        guard store != nil else { return }
        session = KeyboardHealth.Session(started: Date(), peakMB: Self.footprintMB(), lowestHeadroomMB: Self.headroomMB())
        write()
    }

    func sample() {
        if let reading = MemoryReading.current() { sample(reading) }
    }

    func sample(_ reading: MemoryReading) {
        change { $0.sample(footprintMB: reading.footprintMB, headroomMB: reading.headroomMB) }
    }

    /// Something opened or loaded while the keyboard is up.
    func used(_ part: KeyboardHealth.Part) {
        change { $0.use(part) }
    }

    /// A word went in (`KeyboardModel.onSettled`): counted for how often the first
    /// guess is right, never kept.
    func settled(_ word: SettledWord) {
        change { $0.settled(word) }
    }

    /// Something done to a word from the bar (`KeyboardModel.onWordAction`).
    func wordAction(_ name: String, how: String?) {
        change { $0.wordAction(name, how: how) }
    }

    /// The app the keyboard is in went to the background with it up: iOS suspends the
    /// process and may end it there, which is normal. Marked, so that the next process
    /// (or the app sending the file) doesn't take this session for one ended by iOS.
    func suspended() {
        change { $0.suspend() }
    }

    /// The app came back with the keyboard still up.
    func resumed() {
        change { $0.resume() }
    }

    func disappeared() {
        change { $0.end(footprintMB: Self.footprintMB(), headroomMB: Self.headroomMB()) }
    }

    /// Changes this keyboard's session, and writes it when `change` says it is worth it.
    private func change(_ change: (inout KeyboardHealth.Session) -> Bool) {
        guard store != nil, var session else { return }
        let worth = change(&session)
        self.session = session
        if worth { write() }
    }

    /// Puts this keyboard's session into the file as it stands now.
    private func write() {
        guard let store, let session else { return }
        var health = store.load() ?? KeyboardHealth()
        health.put(session)
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
