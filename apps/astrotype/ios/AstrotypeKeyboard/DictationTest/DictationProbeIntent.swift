import AppIntents
import Foundation

// THROWAWAY SPIKE (Gabriel, 7 Nov 2026): can dictation start without switching apps?
// This file is copied, unchanged, into the app (Astrotype/DictationTest), the keyboard
// (AstrotypeKeyboard/DictationTest) and the widget extension (AstrotypeLive), so all
// three have the same intent types. Each target has its own `DictationRunner` that does
// the work: the app's runs a dictation session (Live Activity first, then the mic, like
// Lanata's Talk to Lanata), the keyboard's tries the mic in the keyboard, and the
// widget's should never run (these are LiveActivityIntents, which iOS runs in the app).
//
// Round 1 (7 Nov): a keyboard `Button(intent:)` ran in the keyboard and the mic failed;
// Siri ran it in the app, but the audio session was refused without a Live Activity.

/// Starts the dictation test session in the app, or ends it if it's running.
struct DictationProbeIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Test dictation"
    static let description = IntentDescription("Astrotype test: starts or stops a dictation session in the background, with a Live Activity.")

    @Parameter(title: "Started from", default: "Shortcut")
    var source: String

    init() {}

    init(source: String) {
        self.source = source
    }

    func perform() async throws -> some IntentResult {
        DictationProbeLog.write("\(source): running in \(DictationProbeLog.place)…")
        try await DictationRunner.toggle(source: source)
        return .result()
    }
}

/// Starts or stops listening in a running session (the Live Activity's Talk button).
struct DictationTalkIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Talk (dictation test)"
    static let description = IntentDescription("Astrotype test: starts or stops listening in the running dictation session.")

    func perform() async throws -> some IntentResult {
        await DictationRunner.talk(source: "Live Activity Talk, in \(DictationProbeLog.place)")
        return .result()
    }
}

/// Ends the session (the Live Activity's Stop button).
struct StopDictationProbeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop dictation test"
    static let description = IntentDescription("Astrotype test: ends the dictation session.")

    func perform() async throws -> some IntentResult {
        await DictationRunner.stop(source: "Live Activity Stop, in \(DictationProbeLog.place)")
        return .result()
    }
}

/// The last result and the session's state, in the App Group so all three see them.
enum DictationProbeLog {
    static let key = "dictationProbe.result"
    static let enabledKey = "dictationProbe.keyboardButton"
    static let sessionKey = "dictationProbe.session"
    /// Posted by the keyboard's Talk button; the app's session listens for it.
    static let talkNotification = "com.tinypenguin.astrotype.dictation.talk"
    static var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.tinypenguin.astrotype") }

    static var place: String {
        let id = Bundle.main.bundleIdentifier ?? "?"
        if id.hasSuffix(".keyboard") { return "the keyboard" }
        if id.hasSuffix(".live") { return "the widget extension" }
        return "the app"
    }

    static func write(_ text: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        defaults?.set("\(stamp) · \(text)", forKey: key)
    }

    static var last: String { defaults?.string(forKey: key) ?? "Not run yet" }

    /// When the app's session started, or nil when none is running.
    static var sessionStarted: Date? {
        get { defaults?.object(forKey: sessionKey) as? Date }
        set { defaults?.set(newValue, forKey: sessionKey) }
    }
}

/// A short failure the intent shows (Siri says it, Shortcuts shows it).
struct DictationProbeFailure: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}
