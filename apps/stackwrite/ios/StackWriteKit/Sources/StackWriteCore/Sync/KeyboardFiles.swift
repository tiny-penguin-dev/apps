import Foundation

/// Where the keyboard's data files live (BUILD.md "Data"): the extension's own
/// container, which it can always write, and the App Group, which the app shares with
/// the extension when Full Access is on.
///
///     FileWordStore(url: KeyboardFiles.own(KeyboardFiles.words))
///     KeyboardFiles.shared(KeyboardFiles.settings)   // nil when there is no App Group
public enum KeyboardFiles {
    public static let appGroup = "group.com.tinypenguin.stackwrite"
    public static let folder = "StackWrite"

    public static let words = "words.json"
    public static let settings = "settings.json"
    /// What the extension last saw, written for the app (`ExtensionStatus`).
    public static let status = "keyboard-status.json"

    /// A file in this process's own Application Support folder.
    public static func own(_ name: String, fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(name)
    }

    /// A file in the App Group's container, nil when this process has none.
    public static func shared(_ name: String, fileManager: FileManager = .default) -> URL? {
        guard let base = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        return base.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(name)
    }
}
