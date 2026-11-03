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
    /// Whether "Share anonymous usage data" is on, written by the app (`UsageSharing`).
    public static let usage = "usage-sharing.json"
    /// When the Pro trial started (`TrialStore`).
    public static let trial = "trial.json"
    /// The App Store's last answer about Pro (`ProCache`); the extension's own file only.
    public static let pro = "pro.json"
    /// What the keyboard learned from the person's typing (`PersonalModel`).
    public static let personal = "personal.json"
    /// This install's random ID, the personal model's shard (`InstallID`); own file only.
    public static let install = "install.json"
    /// Shared words waiting for the app to send (`SharedWordStore`): practice words and,
    /// with Full Access, the keyboard's corrections.
    public static let sharing = "Sharing"
    /// Words the keyboard missed, typed with "Not it?" (`SharedWordStore`, the last 200):
    /// kept for "Words it missed" whether or not they are shared (features/missed-words).
    public static let misses = "Missed"

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
