import Foundation

// THROWAWAY SPIKE (Gabriel, 7 Nov 2026), see DictationProbeIntent.swift. The widget
// extension's stand-in for the app's `DictationRunner`. The intents that call it are
// LiveActivityIntents, so iOS should run them in the app and these never run. If one
// does, it says so instead of doing nothing.

enum DictationRunner {
    static func toggle(source: String) async throws {
        throw DictationProbeFailure(message: "\(source) ran in the widget extension, not the app.")
    }

    static func talk(source: String) async {}

    static func stop(source: String) async {}
}
