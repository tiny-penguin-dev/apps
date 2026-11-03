import AppIntents

/// The "Turn off Squawk" action in Shortcuts. People run it from an automation, like
/// tapping an NFC tag or a Focus turning off, to stop the alarm that's ringing. It's
/// also the "Run a Shortcut" wake-up check (PRODUCT.md 5.5). It runs in the background
/// and never skips another kind of check.
struct TurnOffSquawkIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn off Squawk"
    static let description = IntentDescription(
        "Turns off the Squawk alarm that's ringing. Use it in an automation, like tapping an NFC tag or turning off a Focus."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await AlarmsModel.shared.turnOffFromShortcut() {
        case .turnedOff:
            .result(dialog: "Squawk is off. Good morning!")
        case .oneCheckLeft:
            .result(dialog: "Nice! Open Squawk to finish your other wake-up checks.")
        case .needsCheck:
            .result(dialog: "This alarm has a wake-up check. Open Squawk to do it.")
        case .nothingRinging:
            .result(dialog: "No Squawk alarm is ringing right now.")
        }
    }
}

/// Puts "Turn off Squawk" in the Shortcuts app and Siri without any setup.
struct SquawkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TurnOffSquawkIntent(),
            phrases: [
                "Turn off \(.applicationName)",
                "Stop \(.applicationName)",
            ],
            shortTitle: "Turn off Squawk",
            systemImageName: "alarm.waves.left.and.right"
        )
    }
}
