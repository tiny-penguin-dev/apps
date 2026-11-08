import Foundation

/// Where the keyboard's data files live (BUILD.md "Data"): the extension's own
/// container, which it can always write, and the App Group, which the app shares with
/// the extension when Full Access is on.
///
///     FileWordStore(url: KeyboardFiles.own(KeyboardFiles.words))
///     KeyboardFiles.shared(KeyboardFiles.settings)   // nil when there is no App Group
public enum KeyboardFiles {
    public static let appGroup = "group.com.tinypenguin.astrotype"
    public static let folder = "Astrotype"

    public static let words = "words.json"
    public static let settings = "settings.json"
    /// What the extension last saw, written for the app (`ExtensionStatus`).
    public static let status = "keyboard-status.json"
    /// The keyboard's memory per session, written for the app to send (`KeyboardHealth`).
    public static let health = "keyboard-health.json"
    /// The keyboard's last memory readings, for the app's Debug page (`KeyboardDebug`); never sent.
    public static let debug = "keyboard-debug.json"
    /// Whether "Share anonymous usage data" is on, written by the app (`UsageSharing`).
    public static let usage = "usage-sharing.json"
    /// When the Pro trial started (`TrialStore`).
    public static let trial = "trial.json"
    /// The App Store's last answer about Pro (`ProCache`); the extension's own file only.
    public static let pro = "pro.json"
    /// What the keyboard learned from the person's typing (`PersonalModel`).
    public static let personal = "personal.json"
    /// Frequently used emoji and the skin tones picked (`EmojiHistory`); own file only.
    public static let emoji = "emoji.json"
    /// This install's random ID, the personal model's shard (`InstallID`); own file only.
    public static let install = "install.json"
    /// Shared words waiting for the app to send (`SharedWordStore`): practice words and,
    /// with Full Access, the keyboard's corrections.
    public static let sharing = "Sharing"
    /// Words the keyboard missed, typed with "Not it?" (`SharedWordStore`, the last 200):
    /// kept for "Words it missed" whether or not they are shared (features/missed-words).
    public static let misses = "Missed"
    /// The typing recording, the last half hour (`TypingLogFiles`): written by the
    /// keyboard while "Keep recording" is on, read by the app to send; App Group only.
    public static let typing = "Typing"
    /// The phone's own text replacements as the keyboard last read them, for the app to
    /// copy into the person's list (`PhoneReplacementsFile`); App Group only.
    public static let phoneReplacements = "phone-replacements.json"
    /// Timed stretches of typing for the everyday speed (`SpeedRuns`, features/typing-speed):
    /// written by the keyboard, read by the app; App Group only.
    public static let speedRuns = "speed-runs.json"
    /// The app's days of typing speed (`SpeedHistory`); the app's own file.
    public static let speedHistory = "speed-history.json"

    /// A file in this process's own Application Support folder.
    public static func own(_ name: String, fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(name)
    }

    /// A file in the App Group's container, nil when this process has none.
    public static func shared(_ name: String, fileManager: FileManager = .default) -> URL? {
        #if canImport(Darwin)
        guard let base = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        return base.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(name)
        #else
        return nil // No App Groups on Linux, where only the tools and tests run.
        #endif
    }
}
