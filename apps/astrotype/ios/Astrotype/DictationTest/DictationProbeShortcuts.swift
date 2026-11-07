import AppIntents

// THROWAWAY SPIKE (Gabriel, 7 Nov 2026), see DictationProbeIntent.swift. Offers the test
// to Siri and Shortcuts, so it can run from "Hey Siri", the Action Button or Back Tap.

struct DictationProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DictationProbeIntent(),
                    phrases: ["Test dictation in \(.applicationName)", "Start \(.applicationName) dictation test"],
                    shortTitle: "Test dictation",
                    systemImageName: "mic")
    }
}
