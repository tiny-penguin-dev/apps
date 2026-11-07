import ActivityKit
import Foundation

// THROWAWAY SPIKE (Gabriel, 7 Nov 2026), see DictationProbeIntent.swift. The dictation
// test's Live Activity. Copied, unchanged, into the app and the widget extension
// (AstrotypeLive): both need the same type.

struct DictationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Recording what's said right now (Talk was tapped), not just holding the mic.
        var listening: Bool
        /// One short line: "Ready", "Listening…", "Heard 2.4 s".
        var note: String
    }

    var started: Date
}
