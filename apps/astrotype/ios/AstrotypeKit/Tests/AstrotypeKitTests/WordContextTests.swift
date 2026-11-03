import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct WordContextTests {
    @Test func takesTheLastWordsOfTheSentence() {
        #expect(WordContext.words(before: "Hi! Going to the ") == ["to", "the"])
        #expect(WordContext.words(before: "Hi! Going to the ", count: 3) == ["going", "to", "the"])
        #expect(WordContext.words(before: "Hi! Going to the ", count: 1) == ["the"])
        #expect(WordContext.words(before: "we are going to the ") == ["to", "the"])
    }

    @Test func marksTheStartOfASentence() {
        #expect(WordContext.words(before: "") == ["<s>"])
        #expect(WordContext.words(before: "Hi! ") == ["<s>"])
        #expect(WordContext.words(before: "Hi!\n") == ["<s>"])
        #expect(WordContext.words(before: "Hi! Going ") == ["<s>", "going"])
        #expect(WordContext.words(before: "Done. Going ") == ["<s>", "going"])
        #expect(WordContext.words(before: "Why? ") == ["<s>"])
    }

    @Test func saysNothingInsideAWordOrAfterABreak() {
        #expect(WordContext.words(before: "going to th") == [])
        #expect(WordContext.words(before: "Hi") == [])
        #expect(WordContext.words(before: "yes, ") == [])
        #expect(WordContext.words(before: "he said: ") == [])
        #expect(WordContext.words(before: "well, so the ") == ["so", "the"])
        #expect(WordContext.words(before: "x", count: 0) == [])
    }

    @Test func normalisesTokensLikeTheModel() {
        #expect(WordContext.words(before: "Don't you ") == ["dont", "you"])
        #expect(WordContext.words(before: "I'll ") == ["<s>", "ill"])
        #expect(WordContext.words(before: "It's 10 o'clock ") == ["its", "oclock"])
        // Accents come off, as the trie and the word pairs file words (Lexicon.fold).
        #expect(WordContext.words(before: "Café ") == ["<s>", "cafe"])
    }
}
