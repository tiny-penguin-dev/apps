import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct NgramModelTests {
    static func tiny() throws -> NgramModel {
        var builder = NgramModel.Builder(lambda: 0.7, scale: 16)
        builder.add(previous: "<s>", word: "i", count: 60)
        builder.add(previous: "<s>", word: "the", count: 30)
        builder.add(previous: "<s>", word: "we", count: 10)
        builder.add(previous: "thank", word: "you", count: 90)
        builder.add(previous: "thank", word: "god", count: 9)
        builder.add(previous: "thank", word: "me", count: 1)
        builder.add(previous: "going", word: "home", count: 50)
        builder.add(previous: "going", word: "to", count: 150)
        builder.add(line: "the\tstore\t40")
        builder.add(line: "the\tsame\t60")
        builder.add(line: "bad line")
        return try NgramModel(data: builder.build())
    }

    @Test func buildsAndReadsBack() throws {
        let model = try Self.tiny()
        #expect(model.vocabularyCount == 13)
        #expect(model.pairCount == 10)
        #expect(model.words == model.words.sorted())
        #expect(model.id(of: "thank") != nil)
        #expect(model.id(of: "nope") == nil)
        #expect(model.likelyWords(after: "thank", limit: 5) == ["you", "god", "me"])
        #expect(model.likelyWords(after: "<s>", limit: 2) == ["i", "the"])
        #expect(model.likelyWords(after: "you", limit: 2) == [])
        let p = try #require(model.logProbability(of: "you", after: "thank"))
        #expect(abs(exp(p) - 0.9) < 0.03)
        #expect(model.logProbability(of: "thank", after: "you") == nil)
        #expect(model.logProbability(of: "zzz", after: "thank") == nil)
    }

    @Test func keepsOnlyTheMostCommonPairsButTheirShareOfTheTotal() throws {
        var builder = NgramModel.Builder()
        builder.add(previous: "a", word: "x", count: 70)
        builder.add(previous: "a", word: "y", count: 20)
        builder.add(previous: "a", word: "z", count: 10)
        let model = try NgramModel(data: builder.build(maxPairs: 2))
        #expect(model.pairCount == 2)
        #expect(model.likelyWords(after: "a", limit: 5) == ["x", "y"])
        #expect(abs(exp(try #require(model.logProbability(of: "x", after: "a"))) - 0.7) < 0.03)
    }

    @Test func contextBonusRaisesSeenPairsAndLowersUnseenOnes() throws {
        let model = try Self.tiny()
        let prior: Float = log(0.001)
        let seen = model.contextBonus(for: "you", after: "thank", unigramLogProbability: prior)
        let unseen = model.contextBonus(for: "store", after: "thank", unigramLogProbability: prior)
        #expect(seen == NgramModel.maximumBonus)
        #expect(abs(unseen - log(0.3)) < 0.01)
        #expect(model.contextBonus(for: "you", after: nil, unigramLogProbability: prior) == 0)
        #expect(model.contextBonus(for: "you", after: "unknownword", unigramLogProbability: prior) == 0)
        // A common word after a sentence start gains, but no more than the cap.
        let start = model.contextBonus(for: "i", after: "<s>", unigramLogProbability: log(0.01))
        #expect(start > 3 && start <= NgramModel.maximumBonus)
    }

    @Test func rejectsOtherData() {
        #expect(throws: NgramModel.Failure.notAModel) { try NgramModel(data: Data("hello world!".utf8)) }
        #expect(throws: NgramModel.Failure.corrupt) { try NgramModel(data: Data("ASNG".utf8)) }
        var wrong = Data("ASNG".utf8)
        wrong.append(uint16: 99)
        wrong.append(contentsOf: [UInt8](repeating: 0, count: 40))
        #expect(throws: NgramModel.Failure.unsupportedVersion(99)) { try NgramModel(data: wrong) }
    }

    @Test func theEnglishModelShips() throws {
        let english = try Language.bundled("en")
        let model = try #require(english.ngrams)
        #expect(model.pairCount >= 250_000)
        #expect(model.likelyWords(after: "thank", limit: 1) == ["you"])
        #expect(model.likelyWords(after: "<s>", limit: 3).contains("the"))
        #expect(!model.words.contains("tom"), "Tatoeba's stock names are dropped")
        let store = model.contextBonus(for: "store", after: "the", unigramLogProbability: -9)
        let stare = model.contextBonus(for: "stare", after: "the", unigramLogProbability: -9)
        #expect(store > stare)
    }
}
