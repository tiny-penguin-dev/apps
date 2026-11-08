import Foundation

/// The person's own details offered on the bar (features/autofill): what a field asks
/// for, what an unlabelled one likely wants, a chat that just asked ("my email is "), or
/// the start of a detail being typed. Pure: the composer asks it after every change.
///
///     let details = PersonalDetails(firstName: "Ada", lastName: "Byron", email: "ada@example.com")
///     Autofill.offers(for: [.email], details: details, before: "")          // ada@example.com
///     Autofill.offers(for: [], details: details, before: "My email is ")    // ada@example.com
///     Autofill.completion(of: ["ad"], slots: [], details: details)          // Ada Byron, in place of "ad"
public enum Autofill {
    /// One detail, as a field asks for it (UIKit's `UITextContentType`, read plainly).
    public enum Slot: String, Codable, Sendable, CaseIterable {
        case name, givenName, familyName, email, phone, username
        case street, city, state, cityAndState, postalCode, country, address
        case company, jobTitle

        /// The detail's value, trimmed; empty when it isn't set.
        public func value(in details: PersonalDetails) -> String {
            let raw: String = switch self {
            case .name: details.name
            case .givenName: details.firstName
            case .familyName: details.lastName
            case .email: details.email
            case .phone: details.phone
            case .username: details.username
            case .street: details.street
            case .city: details.city
            case .state: details.state
            case .cityAndState: details.cityAndState
            case .postalCode: details.postalCode
            case .country: details.country
            case .address: details.address
            case .company: details.company
            case .jobTitle: details.jobTitle
            }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// A detail on the bar: tapped, `text` goes in, in place of `replacing` (what is
    /// before the cursor that it finishes; empty when nothing is typed yet).
    public struct Offer: Sendable, Equatable {
        public var slot: Slot
        public var text: String
        public var replacing: String

        public init(slot: Slot, text: String, replacing: String = "") {
            self.slot = slot
            self.text = text
            self.replacing = replacing
        }
    }

    /// The most the bar shows at once.
    public static let limit = 3

    /// With nothing being typed: the details the field wants (`slots`, best first)
    /// while it is still empty, or the one a chat just asked for ("my address is ").
    public static func offers(for slots: [Slot], details: PersonalDetails, before: String) -> [Offer] {
        guard !details.isEmpty else { return [] }
        let empty = before.allSatisfy { $0.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) } }
        let wanted = empty ? slots : (asked(before: before) ?? [])
        var out: [Offer] = []
        for slot in wanted {
            let text = slot.value(in: details)
            guard !text.isEmpty, !out.contains(where: { $0.text == text }) else { continue }
            out.append(Offer(slot: slot, text: text))
        }
        return Array(out.prefix(limit))
    }

    /// While a word is being typed: the detail that `typed` begins (each candidate is
    /// what is before the cursor that the detail would replace, longest first), the
    /// field's own slots first. At least two letters, and never one already whole.
    public static func completion(of typed: [String], slots: [Slot], details: PersonalDetails) -> Offer? {
        guard !details.isEmpty else { return nil }
        var order = slots
        for slot in typingOrder where !order.contains(slot) { order.append(slot) }
        for start in typed where start.count >= 2 {
            let lower = start.lowercased()
            for slot in order {
                let text = slot.value(in: details)
                guard text.count > start.count, text.lowercased().hasPrefix(lower) else { continue }
                return Offer(slot: slot, text: text, replacing: start)
            }
        }
        return nil
    }

    /// The details a start of typing is matched against, when the field doesn't say.
    /// The full name comes before the first name, which it starts with.
    static let typingOrder: [Slot] = [.email, .name, .username, .street, .address, .company]

    /// The detail a chat just asked for: the text before the cursor ends with one of
    /// these and a space ("My email is ", "mi correo es ").
    static func asked(before: String) -> [Slot]? {
        guard let last = before.last, last == " " else { return nil }
        // Only the end can hold a phrase, so only the end is lowercased: this runs on
        // every keystroke, and the whole text before the cursor can be long.
        let end = before.lastIndex(where: { !Composer.isSpace($0) }).map { before.index(after: $0) } ?? before.startIndex
        let text = before[..<end].suffix(longestPhrase + 1).lowercased()
        for (slots, phrases) in phrases {
            for phrase in phrases where text.hasSuffix(phrase) {
                let start = text.dropLast(phrase.count)
                // A whole phrase, not the end of a longer word.
                if let previous = start.last, previous.isLetter { continue }
                return slots
            }
        }
        return nil
    }

    /// The longest phrase, in characters: how much of the end is read.
    static let longestPhrase = phrases.flatMap(\.1).map(\.count).max() ?? 0

    /// What people write right before giving a detail, in each bundled language.
    static let phrases: [([Slot], [String])] = [
        ([.email], ["my email is", "my email address is", "my e-mail is", "email me at", "my email:",
                    "mi correo es", "mi email es", "mi correo electrónico es", "mi mail es"]),
        ([.phone], ["my number is", "my phone number is", "my phone is", "my cell is", "my mobile is",
                    "call me at", "text me at", "my phone:",
                    "mi número es", "mi teléfono es", "mi celular es", "mi móvil es"]),
        ([.address], ["my address is", "i live at", "my address:", "mi dirección es", "vivo en"]),
        ([.username], ["my username is", "my user is", "mi usuario es"]),
        ([.name], ["my name is", "my full name is", "me llamo", "mi nombre es"]),
    ]
}
