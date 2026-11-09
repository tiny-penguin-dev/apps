import AstrotypeCore
import AVFoundation
import Foundation
import Speech

/// Why the mic or speech to text didn't work, with the step for `dictation.failed`.
struct DictationFailure: Error {
    enum Step: String {
        case permission, mic, speech
    }

    var step: Step
    /// The iOS error code, for Sentry.
    var code: Int?
    var problem: DictationProblem {
        switch step {
        case .permission: .micDenied
        case .speech: code == nil ? .noSpeech : .failed
        case .mic: .failed
        }
    }
}

/// The mic and speech to text (features/dictation). The mic is turned on once, while
/// the app is open, and stays on (iOS won't start it again from the background); each
/// listen then turns what it hears into text, on the phone.
@MainActor
protocol SpeechListener: AnyObject {
    /// Whether the mic may be used: nil until the person has been asked.
    var micAllowed: Bool? { get }
    /// Asks for the mic (the system's alert). Returns whether it was allowed.
    func askForMic() async -> Bool
    /// Gets speech to text ready for `language` (it may download Apple's model the
    /// first time). Throws `.speech` when the language isn't offered.
    func prepare(language: String) async throws
    /// Turns the mic on. Only works while the app is in front.
    func micOn() async throws
    func micOff()
    var isMicOn: Bool { get }
    /// Starts hearing: `onWords` gets everything heard so far each time it changes,
    /// `onLevel` how loud it is (0 to 1), both on the main actor.
    func listen(language: String, onWords: @escaping @MainActor (String) -> Void,
                onLevel: @escaping @MainActor (Double) -> Void) async throws
    /// Stops hearing and gives the final words.
    func stop() async -> String
    /// iOS took the mic away (a call, another app): the mic is off.
    var onMicLost: (@MainActor () -> Void)? { get set }
}

/// The real one: `AVAudioEngine` for the mic and Apple's on-device `SpeechAnalyzer`
/// (iOS 26) for the words.
@available(iOS 26, *)
@MainActor
final class LiveSpeechListener: SpeechListener {
    var onMicLost: (@MainActor () -> Void)?
    private var engine: AVAudioEngine?
    /// Where the mic's audio goes while listening (the audio thread reads it).
    private let sink = AudioSink()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var results: Task<String, Never>?
    private var interruption: NSObjectProtocol?

    var isMicOn: Bool { engine?.isRunning == true }

    var micAllowed: Bool? {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .denied: false
        default: nil
        }
    }

    func askForMic() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func prepare(language: String) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw DictationFailure(step: .speech)
        }
        let transcriber = Self.transcriber(locale)
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw DictationFailure(step: .speech, code: (error as NSError).code)
        }
    }

    func micOn() async throws {
        guard engine == nil else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            // The same as the spike that kept the mic in the background (round 7).
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            throw DictationFailure(step: .mic, code: (error as NSError).code)
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw DictationFailure(step: .mic, code: 0)
        }
        Self.installTap(on: input, format: format, sink: sink)
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw DictationFailure(step: .mic, code: (error as NSError).code)
        }
        self.engine = engine
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                                              object: session, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated {
                guard let self, self.engine != nil else { return }
                self.micOff()
                self.onMicLost?()
            }
        }
    }

    func micOff() {
        // Ends the analyzer's input, so a listen still going finishes with what it has.
        sink.set(nil)
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        engine = nil
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        interruption = nil
    }

    /// A transcriber and analyzer for one listen, with the formats to feed it.
    private struct Prepared {
        var language: String
        var transcriber: SpeechTranscriber
        var analyzer: SpeechAnalyzer
        var format: AVAudioFormat
        var converter: AVAudioConverter
    }

    private func make(language: String) async throws -> Prepared {
        guard let engine else { throw DictationFailure(step: .mic) }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw DictationFailure(step: .speech)
        }
        let transcriber = Self.transcriber(locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let micFormat = engine.inputNode.outputFormat(forBus: 0)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              let converter = AVAudioConverter(from: micFormat, to: format) else {
            throw DictationFailure(step: .speech, code: 1)
        }
        return Prepared(language: language, transcriber: transcriber, analyzer: analyzer, format: format, converter: converter)
    }

    func listen(language: String, onWords: @escaping @MainActor (String) -> Void,
                onLevel: @escaping @MainActor (Double) -> Void) async throws {
        // Made for each listen and let go after it, so nothing sits in memory while
        // the mic waits (Gabriel, 9 Nov 2026).
        let prepared = try await make(language: language)
        let transcriber = prepared.transcriber
        let analyzer = prepared.analyzer
        // The mic's audio goes in from now; the stream holds it until the analyzer runs.
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        sink.set(AudioSink.Target(input: input, converter: prepared.converter, format: prepared.format) { level in
            Task { @MainActor in onLevel(level) }
        })
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            sink.set(nil)
            throw DictationFailure(step: .speech, code: (error as NSError).code)
        }
        self.transcriber = transcriber
        self.analyzer = analyzer
        // Final words, then the part that may still change.
        results = Task { @MainActor in
            var final = ""
            var volatile = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        final = Self.join(final, text)
                        volatile = ""
                    } else {
                        volatile = text
                    }
                    onWords(Self.join(final, volatile))
                }
            } catch {}
            return Self.join(final, volatile)
        }
    }

    func stop() async -> String {
        sink.set(nil)
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        let words = await results?.value ?? ""
        analyzer = nil
        transcriber = nil
        results = nil
        return words
    }

    private static func transcriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
    }

    /// Two pieces of what was said, with one space between.
    static func join(_ a: String, _ b: String) -> String {
        let a = a.trimmingCharacters(in: .whitespaces)
        let b = b.trimmingCharacters(in: .whitespaces)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    /// Not on the main actor: the tap's closure runs on the audio thread (ASTROTYPE-5).
    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, sink: AudioSink) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            sink.add(buffer)
        }
    }
}

/// Where the audio thread sends the mic's buffers while listening: converted to the
/// analyzer's format, with how loud they are.
@available(iOS 26, *)
final class AudioSink: @unchecked Sendable {
    struct Target {
        var input: AsyncStream<AnalyzerInput>.Continuation
        var converter: AVAudioConverter
        var format: AVAudioFormat
        var onLevel: @Sendable (Double) -> Void
    }

    private let lock = NSLock()
    private var target: Target?
    private var lastLevel: TimeInterval = 0

    /// A new target, or nil to stop; the old one's stream ends.
    func set(_ new: Target?) {
        let old: Target? = lock.withLock {
            let old = target
            target = new
            return old
        }
        old?.input.finish()
    }

    func add(_ buffer: AVAudioPCMBuffer) {
        guard let target = lock.withLock({ target }) else { return }
        // About ten level readings a second for the keyboard's wave.
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastLevel > 0.1 {
            lastLevel = now
            target.onLevel(Self.level(of: buffer))
        }
        guard let converted = convert(buffer, with: target) else { return }
        target.input.yield(AnalyzerInput(buffer: converted))
    }

    private func convert(_ buffer: AVAudioPCMBuffer, with target: Target) -> AVAudioPCMBuffer? {
        let ratio = target.format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: target.format, frameCapacity: capacity) else { return nil }
        var given = false
        var error: NSError?
        let status = target.converter.convert(to: out, error: &error) { _, outStatus in
            if given {
                outStatus.pointee = .noDataNow
                return nil
            }
            given = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, out.frameLength > 0 else { return nil }
        return out
    }

    /// Loudness 0 to 1 from the buffer's RMS (-50 dB is silence).
    private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(buffer.frameLength))
        let db = 20 * log10(max(rms, 0.000_01))
        return Double(min(1, max(0, (db + 50) / 50)))
    }
}

/// For tests and older systems: hears what it's told to.
@MainActor
final class FakeSpeechListener: SpeechListener {
    var micAllowed: Bool? = true
    var isMicOn = false
    var onMicLost: (@MainActor () -> Void)?
    var words = ""
    var failure: DictationFailure?
    private var onWords: (@MainActor (String) -> Void)?

    func askForMic() async -> Bool { micAllowed == true }
    func prepare(language: String) async throws {
        if let failure, failure.step == .speech { throw failure }
    }

    func micOn() async throws {
        if let failure, failure.step == .mic { throw failure }
        isMicOn = true
    }

    func micOff() { isMicOn = false }

    func listen(language: String, onWords: @escaping @MainActor (String) -> Void,
                onLevel: @escaping @MainActor (Double) -> Void) async throws {
        self.onWords = onWords
    }

    /// The person said `text` (everything so far).
    func hear(_ text: String) {
        words = text
        onWords?(text)
    }

    func stop() async -> String {
        onWords = nil
        return words
    }
}
