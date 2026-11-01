@preconcurrency import CoreNFC
import Foundation

/// Reads an NFC sticker's id. Any NTAG or MIFARE sticker works, blank or not: Squawk
/// only needs its id, so it never writes to the tag.
final class TagReader: NSObject, NFCTagReaderSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<String?, Never>?

    /// False on phones without NFC reading.
    static var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    /// Shows the iOS scan sheet and returns the tag's id as hex, or nil if cancelled.
    func scan(prompt: String) async -> String? {
        await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            guard let session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: nil) else {
                finish(nil)
                return
            }
            session.alertMessage = prompt
            lock.withLock { self.session = session }
            session.begin()
        }
    }

    private func finish(_ id: String?) {
        let pending = lock.withLock {
            let pending = continuation
            continuation = nil
            session = nil
            return pending
        }
        pending?.resume(returning: id)
    }

    // MARK: NFCTagReaderSessionDelegate

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        finish(nil)
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if error != nil {
                session.restartPolling()
                return
            }
            guard let id = Self.identifier(of: tag), !id.isEmpty else {
                session.invalidate(errorMessage: "I can't read this tag. Try another one.")
                return
            }
            session.alertMessage = "Got it!"
            self.finish(id.map { String(format: "%02X", $0) }.joined())
            session.invalidate()
        }
    }

    private static func identifier(of tag: NFCTag) -> Data? {
        switch tag {
        case .miFare(let t): t.identifier
        case .iso15693(let t): t.identifier
        case .iso7816(let t): t.identifier
        case .feliCa(let t): t.currentIDm
        @unknown default: nil
        }
    }
}
