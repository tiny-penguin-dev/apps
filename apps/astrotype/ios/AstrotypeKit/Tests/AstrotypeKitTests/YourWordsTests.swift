import Foundation
import Testing
@testable import AstrotypeCore

/// features/learned-words: the word pairs list, deleting pairs on every device, and
/// adding a learned word by hand.
@Suite struct YourWordsTests {
    static let start = Date(timeIntervalSinceReferenceDate: 815_000_000)
    static let day: TimeInterval = 86_400

    static func learn(_ model: inout PersonalModel, _ word: String, after previous: String?, device: String = "a",
                      at date: Date = start) {
        model.learn(SettledWord(word: word, previous: previous, source: .tapped), device: device, at: date)
    }

    @Test func pairsAreListedAcrossDevicesWithoutSentenceStarts() {
        var model = PersonalModel()
        Self.learn(&model, "you", after: "see")
        Self.learn(&model, "you", after: "see", device: "b", at: Self.start.addingTimeInterval(2 * Self.day))
        Self.learn(&model, "the", after: NgramModel.sentenceStart)
        let pairs = model.learnedPairs(at: Self.start.addingTimeInterval(2 * Self.day))
        #expect(pairs.map(\.id) == ["see you"])
        #expect(pairs[0].count > 1.9 && pairs[0].count <= 2)
        #expect(pairs[0].lastDay == PersonalModel.day(of: Self.start) + 2)
        #expect(model.summary.pairs == 1)
    }

    @Test func aDeletedPairIsGoneEverywhereAndStaysGoneAfterAMerge() {
        var phone = PersonalModel()
        Self.learn(&phone, "you", after: "see")
        Self.learn(&phone, "way", after: "my")
        var ipad = PersonalModel()
        Self.learn(&ipad, "you", after: "see", device: "b")

        // The app on the phone deletes it; the phone's own keyboard and the iPad still
        // have their old counts.
        let staleKeyboard = phone
        var app = phone.merged(with: ipad)
        app.forgetPairs(["see you"], at: Self.start)
        #expect(app.learnedPairs(at: Self.start).map(\.id) == ["my way"])
        #expect(PersonalIndex(app, at: Self.start).pairCount("see", "you") == 0)

        let merged = staleKeyboard.merged(with: ipad).merged(with: app)
        #expect(PersonalIndex(merged, at: Self.start).pairCount("see", "you") == 0)
        #expect(merged.summary.pairs == 1)
        #expect(ipad.merged(with: app).learnedPairs(at: Self.start).map(\.id) == ["my way"])
    }

    @Test func writingADeletedPairAgainBringsItBackFromZero() {
        var model = PersonalModel()
        for _ in 0..<5 { Self.learn(&model, "you", after: "see") }
        model.forgetPairs(["see you"], at: Self.start)
        // The same day: it counts once, not six times.
        Self.learn(&model, "you", after: "see")
        #expect(PersonalIndex(model, at: Self.start).pairCount("see", "you") == 1)
        // And on a later day it keeps growing.
        Self.learn(&model, "you", after: "see", at: Self.start.addingTimeInterval(3 * Self.day))
        let later = PersonalIndex(model, at: Self.start.addingTimeInterval(3 * Self.day)).pairCount("see", "you")
        #expect(later > 1.9 && later <= 2)
    }

    @Test func forgetEverythingClearsDeletedPairs() {
        var model = PersonalModel()
        Self.learn(&model, "you", after: "see")
        model.forgetPairs(["see you"], at: Self.start)
        model.forget(at: Self.start.addingTimeInterval(Self.day))
        #expect(model.forgottenPairs.isEmpty)
    }

    @Test func deletedPairsSurviveTheFileAndOldFilesStillRead() throws {
        var model = PersonalModel()
        Self.learn(&model, "you", after: "see")
        model.forgetPairs(["see you"], at: Self.start)
        let data = try JSONEncoder().encode(model)
        #expect(try JSONDecoder().decode(PersonalModel.self, from: data) == model)

        var plain = PersonalModel()
        Self.learn(&plain, "you", after: "see")
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!json.contains("forgottenPairs"))
        #expect(try JSONDecoder().decode(PersonalModel.self, from: Data(json.utf8)) == plain)
    }

    @Test func pairSearchMatchesEitherWordFromTheStart() {
        let pair = LearnedPair(previous: "see", word: "you", count: 3, lastDay: 0)
        #expect(pair.matches(""))
        #expect(pair.matches("Yo"))
        #expect(pair.matches("see y"))
        #expect(!pair.matches("ou"))
        #expect(pair.level == 2)
    }

    @Test func aWordAddedByHandIsKeptAndMarked() {
        var words = LearnedWords()
        words.add("Lanata", at: Self.start)
        #expect(words.contains("lanata"))
        #expect(words.isAdded("lanata"))
        #expect(words.recent == ["lanata"])
        // Writing it later keeps the mark; forgetting it drops both.
        words.learn("lanata", at: Self.start.addingTimeInterval(1))
        #expect(words.isAdded("lanata"))
        words.forget("lanata", at: Self.start.addingTimeInterval(2))
        #expect(!words.contains("lanata") && !words.isAdded("lanata"))
        words.add("lanata", at: Self.start.addingTimeInterval(3))
        #expect(words.contains("lanata"))
    }

    @Test func onlyOneWordCanBeAdded() {
        #expect(LearnedWords.addable("  Mañana ") == "mañana")
        #expect(LearnedWords.addable("don't") == "don't")
        #expect(LearnedWords.addable("e-mail") == "e-mail")
        #expect(LearnedWords.addable("two words") == nil)
        #expect(LearnedWords.addable("") == nil)
        #expect(LearnedWords.addable("abc1") == nil)
        #expect(LearnedWords.addable("-ab") == nil)
    }
}
