#if canImport(UIKit)
import Foundation
import AstrotypeCore

/// Keeps a `KeyboardModel`'s words and settings in step with iCloud (BUILD.md "Data"):
/// one round of `Syncer.sync` on demand, and a short while after the words or settings
/// change here. Used by the keyboard extension when Full Access is on; the app syncs
/// through its own model.
///
///     let sync = SyncController(model: model, cloud: CloudKitSync())
///     sync.onResult = { result in ... }     // for the status the app reads
///     sync.sync()                           // when the keyboard comes up
@MainActor
public final class SyncController {
    public var onResult: ((Result<Date, Error>) -> Void)?
    /// How long after a change the push waits, so a burst of changes goes up once.
    public var pushDelay: TimeInterval = 2

    private let model: KeyboardModel
    private let cloud: CloudSync
    private var running = false
    private var again = false
    private var pending: Task<Void, Never>?

    public init(model: KeyboardModel, cloud: CloudSync) {
        self.model = model
        self.cloud = cloud
        let before = model.onWordsChange
        model.onWordsChange = { [weak self] words in
            before?(words)
            self?.pushSoon()
        }
        let beforeSettings = model.onSettingsChange
        model.onSettingsChange = { [weak self] settings in
            beforeSettings?(settings)
            self?.pushSoon()
        }
    }

    /// Fetch, merge, apply and push now. A round already running makes a note to go
    /// again when it finishes.
    public func sync() {
        pending?.cancel()
        pending = nil
        guard !running else { again = true; return }
        running = true
        let local = SyncSnapshot(words: model.learnedWords, settings: model.keyboardSettings, settingsChanged: model.settingsChanged)
        Task { [weak self] in
            guard let self else { return }
            do {
                let merged = try await Syncer.sync(local: local, cloud: cloud)
                self.model.learnedWords = merged.words
                self.model.adopt(merged.settings, changed: merged.settingsChanged)
                self.onResult?(.success(Date()))
            } catch {
                self.onResult?(.failure(error))
            }
            self.running = false
            if self.again {
                self.again = false
                self.sync()
            }
        }
    }

    /// Sync after `pushDelay`, unless another change comes first.
    public func pushSoon() {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(pushDelay))
            guard !Task.isCancelled else { return }
            self.sync()
        }
    }
}
#endif
