import Foundation

/// The phone's own text replacements, which only the keyboard can read from iOS
/// (`UILexicon`), written to the App Group for the app to offer "Copy from your iPhone"
/// (features/text-replacements). Needs Full Access; without it the app sees none.
///
///     PhoneReplacementsFile.save(items, to: KeyboardFiles.shared(KeyboardFiles.phoneReplacements))
///     let phone = PhoneReplacementsFile.load(from: url)
///     let new = PhoneReplacementsFile.toCopy(phone, into: settings.textReplacements)
public enum PhoneReplacementsFile {
    /// Writes the list, unless it is already what the file holds.
    public static func save(_ items: [TextReplacement], to url: URL?) {
        guard let url, load(from: url) != items, let data = try? JSONEncoder().encode(items) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL?) -> [TextReplacement] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TextReplacement].self, from: data)) ?? []
    }

    /// The phone's replacements the person's own list doesn't have a shortcut for, each
    /// with an id of its own, ready to add: then they can be edited here.
    public static func toCopy(_ phone: [TextReplacement], into own: [TextReplacement]) -> [TextReplacement] {
        var taken = Set(own.compactMap { TextReplacements.shortcut($0.shortcut) })
        var out: [TextReplacement] = []
        for item in phone {
            guard let shortcut = TextReplacements.shortcut(item.shortcut), !item.phrase.isEmpty,
                  taken.insert(shortcut).inserted else { continue }
            out.append(TextReplacement(shortcut: shortcut, phrase: item.phrase))
        }
        return out
    }
}
