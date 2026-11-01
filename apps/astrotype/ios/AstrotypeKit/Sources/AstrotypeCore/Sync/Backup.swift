import Foundation

/// A copy of the data files before a new version of the app first touches them
/// (BUILD.md Phase 5: an update must leave nothing behind). Each backup is a folder
/// named after the version it was made under; the oldest go when there are more than
/// `keep`.
///
///     try Backup.make(of: [words, settings], into: backups, label: "0.2.0")
public enum Backup {
    /// Copies the files that exist into `folder/label/`, replacing a backup of the same
    /// label. Returns that folder, or nil when none of the files exist.
    @discardableResult
    public static func make(of files: [URL], into folder: URL, label: String, keep: Int = 3,
                            fileManager: FileManager = .default) throws -> URL? {
        let present = files.filter { fileManager.fileExists(atPath: $0.path) }
        guard !present.isEmpty else { return nil }
        let target = folder.appendingPathComponent(label, isDirectory: true)
        if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        for file in present {
            try fileManager.copyItem(at: file, to: target.appendingPathComponent(file.lastPathComponent))
        }
        try prune(folder, keep: keep, fileManager: fileManager)
        return target
    }

    /// The backups in `folder`, newest first.
    public static func list(in folder: URL, fileManager: FileManager = .default) -> [URL] {
        let items = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { modified($0) > modified($1) }
    }

    private static func prune(_ folder: URL, keep: Int, fileManager: FileManager) throws {
        for old in list(in: folder, fileManager: fileManager).dropFirst(max(1, keep)) {
            try fileManager.removeItem(at: old)
        }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
