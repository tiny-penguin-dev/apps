import AstrotypeCore
import Foundation

/// How the app and the keyboard talk about dictation (features/dictation): the state
/// file in the App Group, the keyboard's request file, and Darwin notifications both
/// ways (`DictationLink`).
@MainActor
protocol DictationChannel: AnyObject {
    /// Writes the state for the keyboard and tells it.
    func publish(_ state: DictationState)
    /// What the keyboard asked for with its last command.
    func request() -> DictationRequest?
    /// Calls `handle` for each command the keyboard sends, from now on.
    func listen(_ handle: @escaping @MainActor (DictationCommand) -> Void)
}

/// The App Group and the Darwin notify center.
@MainActor
final class LiveDictationChannel: DictationChannel {
    private var handle: (@MainActor (DictationCommand) -> Void)?

    func publish(_ state: DictationState) {
        DictationLink.write(state, to: DictationLink.stateURL)
        DictationLink.post(DictationLink.stateChanged)
    }

    func request() -> DictationRequest? {
        DictationLink.read(DictationRequest.self, from: DictationLink.requestURL)
    }

    func listen(_ handle: @escaping @MainActor (DictationCommand) -> Void) {
        let first = self.handle == nil
        self.handle = handle
        guard first else { return }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for command in DictationCommand.allCases {
            CFNotificationCenterAddObserver(center, observer, { _, observer, name, _, _ in
                guard let observer, let cfName = name?.rawValue else { return }
                let named = cfName as String
                guard let command = DictationCommand.allCases.first(where: { $0.name == named }) else { return }
                let pointer = UInt(bitPattern: observer)
                DispatchQueue.main.async {
                    guard let raw = UnsafeRawPointer(bitPattern: pointer) else { return }
                    MainActor.assumeIsolated {
                        Unmanaged<LiveDictationChannel>.fromOpaque(raw).takeUnretainedValue().handle?(command)
                    }
                }
            }, command.name as CFString, nil, .deliverImmediately)
        }
    }
}

/// For tests: keeps what was published, and sends commands when told.
@MainActor
final class FakeDictationChannel: DictationChannel {
    private(set) var published: [DictationState] = []
    var lastRequest: DictationRequest?
    private var handle: (@MainActor (DictationCommand) -> Void)?

    func publish(_ state: DictationState) { published.append(state) }
    func request() -> DictationRequest? { lastRequest }
    func listen(_ handle: @escaping @MainActor (DictationCommand) -> Void) { self.handle = handle }

    func send(_ command: DictationCommand) { handle?(command) }
}
