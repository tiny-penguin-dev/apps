import AVFoundation
import Foundation

// THROWAWAY SPIKE (Gabriel, 7 Nov 2026), see DictationProbeIntent.swift. The keyboard's
// side: if iOS runs one of the shared intents here (round 1: it does, for a keyboard
// `Button(intent:)`), try the mic in the keyboard and say so.

enum DictationRunner {
    static func toggle(source: String) async throws {
        let outcome = await DictationProbeRecorder.record(seconds: 3)
        DictationProbeLog.write("\(source): ran in the keyboard, not the app. \(outcome)")
    }

    static func talk(source: String) async {
        DictationProbeLog.write("\(source): ran in the keyboard, not the app.")
    }

    static func stop(source: String) async {
        DictationProbeLog.write("\(source): ran in the keyboard, not the app.")
    }

    /// The keyboard's Talk button: asks the app's session to start or stop listening.
    static func postTalk() {
        // If the app is suspended it never hears this, and this line stays.
        DictationProbeLog.write("Keyboard Talk: sent to the app, no answer yet (is the app awake?)")
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(DictationProbeLog.talkNotification as CFString),
            nil, nil, true
        )
    }
}

/// Records from the microphone for a few seconds and says what it heard (not kept).
enum DictationProbeRecorder {
    static func record(seconds: Double) async -> String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: break
        case .denied: return "Mic: permission denied."
        default: return "Mic: permission not asked yet."
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            return "Mic: session failed (\((error as NSError).code))."
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return "Mic: no input (sample rate 0)."
        }
        let frames = Counter()
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            frames.add(Double(buffer.frameLength))
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return "Mic: engine failed (\((error as NSError).code))."
        }
        try? await Task.sleep(for: .seconds(seconds))
        engine.stop()
        input.removeTap(onBus: 0)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        return String(format: "Mic: got %.1f s of audio.", frames.value / format.sampleRate)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var total = 0.0
        func add(_ n: Double) { lock.withLock { total += n } }
        var value: Double { lock.withLock { total } }
    }
}
