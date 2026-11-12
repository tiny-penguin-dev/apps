import AstrotypeCore
import Foundation

/// Writes the keyboard's own memory readings (`KeyboardDebug`) to the App Group for the
/// app's Debug page: when the process starts, when the keyboard shows and hides, when
/// the app it is in goes to the background and comes back, on
/// memory warnings, and on each of the keyboard's once-a-second readings while it is up
/// (`MemorySampler`; a write only when memory moved or a few seconds went by). Needs Full Access, the App Group's price; without it
/// it does nothing. The file stays on the phone and is never sent.
@MainActor
final class KeyboardDebugRecorder {
    private let store: FileKeyboardDebugStore?
    private var debug: KeyboardDebug
    /// The last process ended while the keyboard was showing, for the typing log's open
    /// line: "crashed", "ended by iOS" or "ended" (unknown). Nil when it didn't.
    private var endedBefore: String?

    init(fullAccess: Bool) {
        if fullAccess, let url = KeyboardFiles.shared(KeyboardFiles.debug) {
            let store = FileKeyboardDebugStore(url: url)
            self.store = store
            debug = store.load() ?? KeyboardDebug()
            let crashed = KeyboardTelemetry.crashedLastRun
            if debug.loaded(at: Date(), crashed: crashed) {
                endedBefore = crashed == true ? "crashed" : crashed == false ? "ended by iOS" : "ended"
            }
            store.save(debug)
        } else {
            store = nil
            debug = KeyboardDebug()
        }
    }

    /// How the last process ended while showing, once (nil if it didn't).
    func takeEndedBefore() -> String? {
        defer { endedBefore = nil }
        return endedBefore
    }

    func appeared() {
        guard let store else { return }
        debug.shown(at: Date(), reading: MemoryReading.current())
        store.save(debug)
    }

    func sample(_ reading: MemoryReading) {
        guard let store else { return }
        if debug.sample(reading, at: Date()) { store.save(debug) }
    }

    func memoryWarning() {
        guard let store else { return }
        debug.memoryWarning(at: Date(), reading: MemoryReading.current())
        store.save(debug)
    }

    /// The app the keyboard is in went to the background with it up.
    func suspended() {
        guard let store else { return }
        debug.backgrounded(at: Date(), reading: MemoryReading.current())
        store.save(debug)
    }

    /// The app came back with the keyboard still up.
    func resumed() {
        guard let store else { return }
        debug.foregrounded(at: Date(), reading: MemoryReading.current())
        store.save(debug)
    }

    func disappeared() {
        guard let store else { return }
        debug.hidden(at: Date(), reading: MemoryReading.current())
        store.save(debug)
    }
}
