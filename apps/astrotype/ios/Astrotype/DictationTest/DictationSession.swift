@preconcurrency import ActivityKit
import AppIntents
import AVFoundation
import Foundation
import UIKit

// THROWAWAY SPIKE (Gabriel, 7 Nov 2026), see DictationProbeIntent.swift. The app's side:
// a dictation session the way Lanata's Talk to Lanata does it. The Live Activity starts
// first, then the microphone (iOS refuses background recording without one, and ends an
// app that records without one). The mic then stays open in the background; Talk (on the
// keyboard, through a Darwin notification, or on the Live Activity) starts and stops
// counting what's heard. Nothing is kept or turned into text yet: the result line says how
// many seconds of audio came in and how loud. Ends itself after 10 minutes.

/// What the shared intents call in the app.
enum DictationRunner {
    @MainActor static func toggle(source: String) async throws {
        try await DictationSession.shared.toggle(source: source)
    }

    @MainActor static func talk(source: String) async {
        await DictationSession.shared.talkFromActivity(source: source)
    }

    @MainActor static func stop(source: String) async {
        await DictationSession.shared.stop(source: source)
    }
}

/// "Hey Siri, test dictation in Astrotype", and "Test dictation" for the Action Button.
struct DictationProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DictationProbeIntent(),
                    phrases: ["Test dictation in \(.applicationName)", "Start \(.applicationName) dictation test"],
                    shortTitle: "Test dictation",
                    systemImageName: "mic")
    }
}

@MainActor
final class DictationSession {
    static let shared = DictationSession()

    private var activity: Activity<DictationActivityAttributes>?
    private var engine: AVAudioEngine?
    private let meter = Meter()
    private var observing = false
    private var timeout: Task<Void, Never>?

    var isRunning: Bool { engine != nil }

    private init() {}

    func toggle(source: String) async throws {
        // A session the app crashed with (or iOS ended) is still in the App Group and
        // may still have its Live Activity up.
        if !isRunning, DictationProbeLog.sessionStarted != nil {
            DictationProbeLog.sessionStarted = nil
        }
        if isRunning {
            await stop(source: source)
        } else {
            try await start(source: source)
        }
    }

    func start(source: String) async throws {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            return try fail(source, "the microphone isn't allowed yet. Open Astrotype → Settings → Debug → Dictation test and allow it.")
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return try fail(source, "Live Activities are off for Astrotype in Settings.")
        }

        // 1. The Live Activity, before any audio.
        for old in Activity<DictationActivityAttributes>.activities {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        do {
            activity = try Activity.request(
                attributes: DictationActivityAttributes(started: .now),
                content: content(listening: false, note: "Ready"),
                pushType: nil
            )
        } catch {
            return try fail(source, "the Live Activity didn't start (\(error.localizedDescription)).")
        }

        try await startMic(source: source)
    }

    /// Round 3: something woke the app in the background (a notification button, a
    /// CloudKit nudge). Try the whole start from there and say where it stops.
    func wake(source: String) async {
        let label = "\(source) (app \(Self.appState))"
        if isRunning {
            DictationProbeLog.write("\(label): woke the app, session already on.")
            return
        }
        DictationProbeLog.sessionStarted = nil
        try? await start(source: label)
    }

    /// Round 3: a push started our Live Activity and iOS woke the app. Take it as the
    /// session's activity and try the mic.
    func adopt(_ pushed: Activity<DictationActivityAttributes>) async {
        let label = "Push-started Live Activity (app \(Self.appState))"
        if pushed.id == activity?.id { return }
        if isRunning {
            DictationProbeLog.write("\(label): session already on.")
            return
        }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            DictationProbeLog.write("\(label): the app woke, but the microphone isn't allowed yet.")
            return
        }
        activity = pushed
        DictationProbeLog.write("\(label): the app woke and saw it. Trying the mic…")
        do {
            try await startMic(source: label, endActivityOnFailure: false)
        } catch {
            update(listening: false, note: "Tap Talk to start the mic")
        }
    }

    /// Round 4: the Live Activity's Talk. In a running session it starts or stops
    /// listening; with no session (a push started the Live Activity, the mic was
    /// refused) it's the user's tap that should let the mic start.
    func talkFromActivity(source: String) async {
        if isRunning {
            toggleListening(source: source)
            return
        }
        if activity == nil {
            activity = Activity<DictationActivityAttributes>.activities.first
        }
        let label = "\(source), no session yet (app \(Self.appState))"
        do {
            if activity == nil {
                try await start(source: label)
            } else {
                try await startMic(source: label, endActivityOnFailure: false)
            }
            toggleListening(source: label)
        } catch {
            update(listening: false, note: "Mic refused again")
        }
    }

    private func startMic(source: String, endActivityOnFailure: Bool = true) async throws {
        // 2. The microphone.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            if endActivityOnFailure { await endActivity() }
            return try fail(source, "Mic: session failed (\((error as NSError).code)) even with the Live Activity.")
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            if endActivityOnFailure { await endActivity() }
            return try fail(source, "Mic: no input (sample rate 0).")
        }
        Self.installTap(on: input, format: format, meter: meter)
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            if endActivityOnFailure { await endActivity() }
            return try fail(source, "Mic: engine failed (\((error as NSError).code)) even with the Live Activity.")
        }
        self.engine = engine
        meter.sampleRate = format.sampleRate
        observeKeyboard()
        DictationProbeLog.sessionStarted = .now
        DictationProbeLog.write("\(source): session ON in \(DictationProbeLog.place). Mic open, Live Activity showing. Tap Talk on the keyboard or the Live Activity.")

        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            await self?.stop(source: "10-minute limit")
        }

        // Hold the intent a moment with the mic running, then check the activity is
        // still up: iOS ends the app if audio runs without one when perform() returns.
        try? await Task.sleep(for: .seconds(1))
        if activity?.activityState != .active {
            await stop(source: "\(source) (the Live Activity went away)")
            throw DictationProbeFailure(message: "The Live Activity didn't stay up, so iOS won't allow recording.")
        }
    }

    /// The keyboard's or the Live Activity's Talk: start or stop counting what's heard.
    func toggleListening(source: String) {
        guard isRunning else {
            DictationProbeLog.write("\(source): no session running. Start one with Siri, the Action Button or Shortcuts first.")
            return
        }
        if meter.isOn {
            let heard = meter.finish()
            DictationProbeLog.write("\(source): stopped listening. \(heard)")
            update(listening: false, note: "Heard: \(heard)")
        } else {
            meter.begin()
            DictationProbeLog.write("\(source): listening… (tap Talk again to stop)")
            update(listening: true, note: "Listening…")
        }
    }

    func stop(source: String) async {
        timeout?.cancel()
        timeout = nil
        let heard = meter.isOn ? " Last: \(meter.finish())" : ""
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        engine = nil
        await endActivity()
        DictationProbeLog.sessionStarted = nil
        DictationProbeLog.write("\(source): session OFF.\(heard)")
    }

    // MARK: - Private

    static var appState: String {
        switch UIApplication.shared.applicationState {
        case .active: "in front"
        case .inactive: "inactive"
        case .background: "in the background"
        @unknown default: "unknown"
        }
    }

    private func fail(_ source: String, _ why: String) throws {
        DictationProbeLog.write("\(source): ran in \(DictationProbeLog.place), but \(why)")
        throw DictationProbeFailure(message: why)
    }

    private func endActivity() async {
        let current = activity
        activity = nil
        await current?.end(nil, dismissalPolicy: .immediate)
    }

    private func update(listening: Bool, note: String) {
        guard let activity else { return }
        let content = content(listening: listening, note: note)
        Task { await activity.update(content) }
    }

    private func content(listening: Bool, note: String) -> ActivityContent<DictationActivityAttributes.ContentState> {
        ActivityContent(state: .init(listening: listening, note: note), staleDate: nil)
    }

    /// The keyboard's Talk button posts a Darwin notification; the app hears it while
    /// it's running (the open mic keeps it running in the background).
    private func observeKeyboard() {
        guard !observing else { return }
        observing = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in
                    DictationSession.shared.toggleListening(source: "Keyboard Talk, heard in the app")
                }
            },
            DictationProbeLog.talkNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Not on the main actor: the tap's closure runs on the audio thread, and a closure
    /// made inside a main-actor method is main-actor too, so Swift 6 stopped the app the
    /// first time audio came in (ASTROTYPE-5, 7 Nov 2026).
    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, meter: Meter) {
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            meter.add(buffer)
        }
    }

    /// Counts what comes in while listening, from the audio thread.
    final class Meter: @unchecked Sendable {
        private let lock = NSLock()
        private var on = false
        private var frames = 0.0
        private var peak: Float = 0
        var sampleRate = 48_000.0

        var isOn: Bool { lock.withLock { on } }

        func begin() {
            lock.withLock { on = true; frames = 0; peak = 0 }
        }

        func add(_ buffer: AVAudioPCMBuffer) {
            guard let data = buffer.floatChannelData?[0] else { return }
            var loudest: Float = 0
            for i in 0..<Int(buffer.frameLength) { loudest = max(loudest, abs(data[i])) }
            lock.withLock {
                guard on else { return }
                frames += Double(buffer.frameLength)
                peak = max(peak, loudest)
            }
        }

        func finish() -> String {
            lock.withLock {
                on = false
                guard frames > 0 else { return "no audio came in." }
                let db = peak > 0 ? Int(20 * log10(peak)) : -160
                return String(format: "%.1f s of audio, loudest %d dB.", frames / sampleRate, db)
            }
        }
    }
}
