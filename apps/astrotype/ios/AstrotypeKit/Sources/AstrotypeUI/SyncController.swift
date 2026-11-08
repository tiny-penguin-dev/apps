#if canImport(UIKit)
import Foundation
import AstrotypeCore
import Synchronization

/// Keeps a `KeyboardModel`'s words, settings and personal model in step with iCloud (BUILD.md "Data"):
/// one round of `Syncer.sync` on demand, and a short while after the words or settings
/// change here. Used by the keyboard extension when Full Access is on; the app syncs
/// through its own model.
///
///     let sync = SyncController(model: model, cloud: CloudKitSync())
///     sync.onResult = { result in ... }     // for the status the app reads
///     sync.sync()                           // the first time the keyboard comes up
///     sync.syncOnShow()                     // each time after: at most every few minutes
@MainActor
public final class SyncController {
    public var onResult: ((Result<Date, Error>) -> Void)?
    /// How long after a change the push waits, so a burst of changes goes up once.
    public var pushDelay: TimeInterval = 2
    /// How long after a round came back the keyboard coming up starts another
    /// (`syncOnShow`): the keyboard comes up many times an hour, and every round is a
    /// CloudKit fetch and some heap. Changes made here still go up after `pushDelay`; it
    /// is other devices' changes that wait this long at most.
    public var showInterval: TimeInterval = 5 * 60
    /// When the last round came back with iCloud's answer.
    private var lastRound: Date?

    private let model: KeyboardModel
    private let cloud: CloudSync
    private var running = false
    private var again = false
    private var pending: Task<Void, Never>?
    private var round: Task<Void, Never>?

    public init(model: KeyboardModel, cloud: CloudSync) {
        self.model = model
        self.cloud = cloud
        let before = model.onWordsChange
        model.onWordsChange = { [weak self] words in
            before?(words)
            self?.pushSoon()
        }
        let beforePersonal = model.onPersonalChange
        model.onPersonalChange = { [weak self] personal in
            beforePersonal?(personal)
            self?.pushPersonalSoon()
        }
        let beforeSettings = model.onSettingsChange
        model.onSettingsChange = { [weak self] settings in
            beforeSettings?(settings)
            self?.pushSoon()
        }
    }

    /// A round for the keyboard coming up: now, unless one came back less than
    /// `showInterval` ago.
    public func syncOnShow() {
        if let lastRound, Date().timeIntervalSince(lastRound) < showInterval { return }
        sync()
    }

    /// Fetch, merge, apply and push now. A round already running makes a note to go
    /// again when it finishes.
    public func sync() {
        pending?.cancel()
        pending = nil
        guard !running else { again = true; return }
        running = true
        LiveCount.syncs.add(1, ordering: .relaxed)
        let local = SyncSnapshot(words: model.learnedWords, settings: model.keyboardSettings, settingsChanged: model.settingsChanged,
                                 personal: model.personalStore == nil ? nil : model.personal.model)
        let cloud = self.cloud
        // Holds neither this controller nor the model while iCloud answers: a call that
        // never comes back (the keyboard closed mid-sync) kept the whole model, with its
        // dictionaries, alive for good, one more each time the keyboard opened (Gabriel,
        // 6 Nov 2026: "1 keyboard, 4 models" after a few opens, heap at 111 MB).
        round = Task { [weak self] in
            LiveCount.syncsWaiting.add(1, ordering: .relaxed)
            let result: Result<SyncSnapshot, Error>
            do { result = .success(try await Syncer.sync(local: local, cloud: cloud)) } catch { result = .failure(error) }
            LiveCount.syncsWaiting.subtract(1, ordering: .relaxed)
            self?.finish(result)
        }
    }

    private func finish(_ result: Result<SyncSnapshot, Error>) {
        round = nil
        switch result {
        case .success(let merged):
            lastRound = Date()
            model.learnedWords = merged.words
            model.adopt(merged.settings, changed: merged.settingsChanged)
            if let personal = merged.personal { model.adoptPersonal(personal) }
            onResult?(.success(Date()))
        case .failure(let error):
            onResult?(.failure(error))
        }
        running = false
        if again {
            again = false
            sync()
        }
    }

    deinit {
        round?.cancel()
        pending?.cancel()
    }

    /// What the keyboard learns changes with every word: it goes up at most once every
    /// `personalDelay`, not after every word.
    public var personalDelay: TimeInterval = 120
    private var personalPending = false

    private func pushPersonalSoon() {
        guard !personalPending else { return }
        personalPending = true
        Task { [weak self] in
            guard let delay = self?.personalDelay else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            self.personalPending = false
            self.sync()
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
