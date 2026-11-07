import AppIntents
import AVFoundation
import Foundation

// THROWAWAY SPIKE (Gabriel, 7 Nov 2026): can the keyboard start the microphone without
// switching apps? This file is copied, unchanged, into the app (Astrotype/DictationTest)
// and the keyboard (AstrotypeKeyboard/DictationTest), so both have the same intent type.
//
// The question: when the keyboard shows `Button(intent: DictationProbeIntent())`, does
// iOS run `perform()` in the APP's process in the background (as it does for a widget's
// or Live Activity's `LiveActivityIntent` / `AudioRecordingIntent`), or right here in the
// keyboard? `perform()` writes down which process ran it, then tries to record for three
// seconds and writes how loud it was. The keyboard and Settings → Debug show the result.
//
// The app also offers it to Shortcuts and Siri (`DictationProbeShortcuts`, app only), so
// the Action Button, Back Tap or "Hey Siri" can start it without opening the app.
//
// No Live Activity yet: Apple says recording from the background stops unless one is
// showing. If the mic starts for a moment and then goes silent, that's why, and the
// real build adds one (it needs a widget extension).

struct DictationProbeIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Test dictation"
    static let description = IntentDescription("Astrotype test: records three seconds in the background and notes where it ran.")

    @Parameter(title: "Started from", default: "Shortcut")
    var source: String

    init() {}

    init(source: String) {
        self.source = source
    }

    func perform() async throws -> some IntentResult {
        let started = Date()
        let process = Bundle.main.bundleIdentifier ?? "?"
        let place = process.hasSuffix(".keyboard") ? "the keyboard" : "the app"
        DictationProbeLog.write("\(source): running in \(place)…")
        let outcome = await DictationProbeRecorder.record(seconds: 3)
        let took = Date().timeIntervalSince(started)
        DictationProbeLog.write("\(source): ran in \(place) (\(process)). \(outcome) Took \(String(format: "%.1f", took)) s.")
        return .result()
    }
}

/// The last result, in the App Group so the keyboard and the app both see it.
enum DictationProbeLog {
    static let key = "dictationProbe.result"
    static let enabledKey = "dictationProbe.keyboardButton"
    static var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.tinypenguin.astrotype") }

    static func write(_ text: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        defaults?.set("\(stamp) · \(text)", forKey: key)
    }

    static var last: String { defaults?.string(forKey: key) ?? "Not run yet" }
}

/// Records from the microphone for a few seconds and says what it heard (not kept).
enum DictationProbeRecorder {
    static func record(seconds: Double) async -> String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: break
        case .denied: return "Mic: permission denied."
        default: return "Mic: permission not asked yet (Settings → Debug → Allow microphone)."
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
        let meter = Meter()
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            meter.add(buffer)
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
        return meter.summary(expected: seconds * format.sampleRate)
    }

    /// Counts frames and the loudest moment, from the audio thread.
    final class Meter: @unchecked Sendable {
        private let lock = NSLock()
        private var frames = 0.0
        private var peak: Float = 0
        private var silent = 0

        func add(_ buffer: AVAudioPCMBuffer) {
            guard let data = buffer.floatChannelData?[0] else { return }
            var loudest: Float = 0
            for i in 0..<Int(buffer.frameLength) { loudest = max(loudest, abs(data[i])) }
            lock.lock()
            frames += Double(buffer.frameLength)
            peak = max(peak, loudest)
            if loudest < 0.0001 { silent += 1 }
            lock.unlock()
        }

        func summary(expected: Double) -> String {
            lock.lock(); defer { lock.unlock() }
            guard frames > 0 else { return "Mic: started but no audio came in." }
            let db = peak > 0 ? 20 * log10(peak) : -160
            let heard = Int((frames / expected * 100).rounded())
            return "Mic: got \(heard)% of the audio, loudest \(Int(db)) dB\(silent > 0 ? ", \(silent) silent chunks" : "")."
        }
    }
}
