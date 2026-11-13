import Foundation
import Testing
@testable import AstrotypeCore

/// Return in a field where it acts (search, go, send): the app only acts on a "\n" that
/// reaches it alone, and it has acted by the time anything after it could change the
/// text (Gabriel, 13 Nov 2026).
@Suite struct ReturnKeyTests {
    static func typed(_ letters: String, returnActs: Bool) -> (effects: [Composer.Effect], composer: Composer) {
        var composer = ContextMatcherTests.composer()
        composer.settings.returnActs = returnActs
        composer.setContext(before: "")
        let t = Synth.taps(&composer, letters)
        let effects = composer.press(.returnKey, time: t + 0.5)
        return (effects, composer)
    }

    static func commits(_ effects: [Composer.Effect]) -> [String] {
        effects.compactMap { if case .commit(let word) = $0 { word } else { nil } }
    }

    /// "sli" searched once the app offered Slickdeals: searched as typed. As a new
    /// line, the letters still have to make a word, as on space.
    @Test func searchTakesPeckedLettersAsTheyAre() {
        for letters in ["sli", "netf", "yout"] {
            let search = Self.typed(letters, returnActs: true)
            #expect(Self.commits(search.effects) == [letters])
            #expect(search.effects.last(where: { if case .insert = $0 { true } else { false } }) == .insert("\n"))
            #expect(Self.commits(Self.typed(letters, returnActs: false).effects) != [letters])
        }
    }

    /// Letters searched as they are aren't learned as a new word.
    @Test func searchedLettersAreNotLearned() {
        let learned = Self.typed("sli", returnActs: true).effects.contains { if case .learn = $0 { true } else { false } }
        #expect(!learned)
    }

    /// The "\n" is an insert of its own, after the word.
    @Test func returnIsItsOwnInsert() {
        let effects = Self.typed("hello", returnActs: true).effects
        let i = effects.firstIndex(of: .commit("hello")), j = effects.firstIndex(of: .insert("\n"))
        #expect(i != nil && j != nil && i! < j!)
    }
}
