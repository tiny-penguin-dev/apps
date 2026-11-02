import Foundation
import Testing
@testable import AstrotypeCore

/// features/smart-matching Phase B: the keyboard learns the person's words, pairs and
/// thumbs, keeps them per device, merges and forgets them.
@Suite struct PersonalModelTests {
    static let start = Date(timeIntervalSinceReferenceDate: 815_000_000)

    static func word(_ text: String, after previous: String? = nil, source: SettledWord.Source = .tapped,
                     touches: [SettledWord.Touch] = []) -> SettledWord {
        SettledWord(word: text, previous: previous, source: source, touches: touches)
    }

    @Test func wordsAndPairsAreCounted() {
        var model = PersonalModel()
        model.learn(Self.word("flotilla", after: "the"), device: "a", at: Self.start)
        model.learn(Self.word("flotilla", after: "the"), device: "a", at: Self.start)
        model.learn(Self.word("ships", after: "flotilla", source: .swiped), device: "a", at: Self.start)
        let index = PersonalIndex(model, at: Self.start)
        #expect(index.wordCount("flotilla") == 2)
        #expect(index.pairCount("the", "flotilla") == 2)
        #expect(abs(index.pairCount("flotilla", "ships") - 0.6) < 0.001)
        #expect(index.pairCount("the", "ships") == 0)
        #expect(model.summary.words == 2)
        #expect(model.summary.pairs == 2)
    }

    @Test func countsFadeWithTheHalfLife() {
        var model = PersonalModel()
        model.learn(Self.word("penguin"), device: "a", at: Self.start)
        let later = Self.start.addingTimeInterval(PersonalModel.halfLifeDays * 86_400)
        #expect(abs(PersonalIndex(model, at: later).wordCount("penguin") - 0.5) < 0.01)
        // A new use adds to the faded count.
        model.learn(Self.word("penguin"), device: "a", at: later)
        #expect(abs(PersonalIndex(model, at: later).wordCount("penguin") - 1.5) < 0.01)
    }

    @Test func onlyPlainWordsAreLearned() {
        var model = PersonalModel()
        model.learn(Self.word("Hello"), device: "a", at: Self.start)
        model.learn(Self.word("x2"), device: "a", at: Self.start)
        model.learn(Self.word("don't"), device: "a", at: Self.start)
        let index = PersonalIndex(model, at: Self.start)
        #expect(index.wordCount("hello") == 1)
        #expect(index.words.count == 1)
    }

    /// A made-up word for a number: "qa", "qb", … (a filler no dictionary ranks).
    static func letters(_ i: Int) -> String {
        "q" + String(i, radix: 26).map { Character(UnicodeScalar(Int(String($0), radix: 26)! + 97)!) }
    }

    @Test func aShardStaysUnderItsCap() {
        var model = PersonalModel()
        for i in 0..<(PersonalModel.maxWords + 50) {
            model.learn(Self.word(Self.letters(i)), device: "a", at: Self.start)
        }
        #expect(model.shards["a"]!.words.count <= PersonalModel.maxWords)
    }

    @Test func devicesMergeWithoutCountingTwice() {
        var phone = PersonalModel()
        phone.learn(Self.word("hello"), device: "phone", at: Self.start)
        var duo = PersonalModel()
        duo.learn(Self.word("hello"), device: "duo", at: Self.start)
        let merged = phone.merged(with: duo)
        #expect(PersonalIndex(merged, at: Self.start).wordCount("hello") == 2)
        // Merging the same copies again (a sync round trip) changes nothing.
        #expect(merged.merged(with: duo).merged(with: phone) == merged)
        // The newer copy of a device's shard wins.
        var phoneLater = phone
        phoneLater.learn(Self.word("hello"), device: "phone", at: Self.start.addingTimeInterval(60))
        #expect(PersonalIndex(merged.merged(with: phoneLater), at: Self.start).wordCount("hello") == 3)
    }

    @Test func forgetReachesOtherDevices() {
        var phone = PersonalModel()
        phone.learn(Self.word("secret"), device: "phone", at: Self.start)
        var duo = phone
        duo.learn(Self.word("plan"), device: "duo", at: Self.start)
        phone.forget(at: Self.start.addingTimeInterval(10))
        // The duo's shard began before the forget: it goes when the copies meet.
        let merged = duo.merged(with: phone)
        #expect(merged.isEmpty)
        // What the duo learns after the forget is kept.
        var after = merged
        after.learn(Self.word("fresh"), device: "duo", at: Self.start.addingTimeInterval(20))
        #expect(PersonalIndex(after.merged(with: duo), at: Self.start).wordCount("fresh") == 1)
        #expect(PersonalIndex(after.merged(with: duo), at: Self.start).wordCount("plan") == 0)
    }

    @Test func roundTripsCompactly() throws {
        var model = PersonalModel()
        model.learn(Self.word("hello", after: "<s>", touches: [.init(letter: "h", side: .right, dx: 0.1, dy: 0.25)]),
                    device: "a", at: Self.start)
        let data = try JSONEncoder().encode(model)
        let back = try JSONDecoder().decode(PersonalModel.self, from: data)
        #expect(back == model)
        #expect(String(decoding: data, as: UTF8.self).contains("\"hello\":[1,"))
    }

    // MARK: Thumbs

    @Test func aKeysOffsetLeansOnTheThumbUntilItHasItsOwn() {
        var model = PersonalModel()
        // The left thumb lands low on every key it touched.
        for letter in "qwertasdfg" {
            for _ in 0..<10 {
                model.learn(Self.word(String(letter), touches: [.init(letter: letter, side: .left, dx: 0, dy: 0.3)]), device: "a", at: Self.start)
            }
        }
        let index = PersonalIndex(model, at: Self.start)
        let own = index.offset(for: "e", side: .left)
        #expect(own.dy > 0.2 && own.dy <= 0.3)
        // "z" was never touched: it borrows the thumb's habit, a little less.
        let borrowed = index.offset(for: "z", side: .left)
        #expect(borrowed.dy > 0.15 && borrowed.dy < own.dy)
        // The right thumb learned nothing.
        #expect(index.offset(for: "e", side: .right) == .zero)
    }

    @Test func offsetsAreCapped() {
        var model = PersonalModel()
        for _ in 0..<50 {
            model.learn(Self.word("e", touches: [.init(letter: "e", side: .left, dx: 0.9, dy: -0.9)]), device: "a", at: Self.start)
        }
        let offset = PersonalIndex(model, at: Self.start).offset(for: "e", side: .left)
        #expect(offset.dx == PersonalIndex.maximumOffset)
        #expect(offset.dy == -PersonalIndex.maximumOffset)
    }

    /// The person's left thumb lands well below "e": the keyboard reads the row below until it
    /// learns that, then "e".
    @Test func aLearnedThumbReadsTheKeyItMeant() {
        let layout = Synth.layout
        let e = layout.frame(of: .letter("e"))!
        let low = CGPoint(x: e.midX, y: e.midY + e.height * 0.75)
        #expect(layout.key(at: low) != .letter("e"))

        var composer = Synth.composer()
        _ = composer.touchDown(id: 1, at: low, time: 0)
        _ = composer.touchUp(id: 1, at: low, time: 0.08)
        #expect(composer.pieces.first?.keys != ["e"])

        var model = PersonalModel()
        for letter in "qwertasdfgzxcv" {
            for _ in 0..<12 {
                model.learn(Self.word(String(letter), touches: [.init(letter: letter, side: .left, dx: 0, dy: 0.7)]), device: "a", at: Self.start)
            }
        }
        composer = Synth.composer()
        composer.personal = PersonalIndex(model, at: Self.start)
        _ = composer.touchDown(id: 1, at: low, time: 0)
        _ = composer.touchUp(id: 1, at: low, time: 0.08)
        #expect(composer.pieces.first?.keys == ["e"])
        // Where the finger really was is kept, to learn from.
        #expect(composer.pieces.first?.landing == low)
    }

    // MARK: Settling

    @Test func aWordSettlesWhenTheNextOneStarts() {
        var composer = ContextMatcherTests.composer()
        composer.setContext(before: "I ")
        let t = Synth.taps(&composer, "hope")
        var effects = composer.press(.space, time: t)
        #expect(!effects.contains { if case .settled = $0 { true } else { false } })
        composer.setContext(before: "I hope ")
        effects = Synth.tap(&composer, "s", at: t + 1)
        let settled = effects.compactMap { effect -> SettledWord? in
            if case .settled(let word) = effect { word } else { nil }
        }
        #expect(settled.count == 1)
        #expect(settled.first?.word == "hope")
        #expect(settled.first?.previous == "i")
        #expect(settled.first?.source == .tapped)
        #expect(settled.first?.touches.map(\.letter) == Array("hope"))
        #expect(settled.first?.touches.allSatisfy { abs($0.dx) < 0.01 && abs($0.dy) < 0.01 } == true)
    }

    @Test func aFixSettlesAsTheWordChosen() {
        var composer = ContextMatcherTests.composer()
        Synth.swipe(&composer, "pot")
        _ = composer.press(.space, time: 1)
        guard case .fix(let words, let chosen) = composer.state.bar, let other = words.indices.first(where: { $0 != chosen }) else {
            Issue.record("no fix bar: \(composer.state.bar)"); return
        }
        _ = composer.choose(guess: other, time: 1.2)
        let effects = composer.press(.space, time: 1.5)
        let settled = effects.compactMap { effect -> SettledWord? in
            if case .settled(let word) = effect { word } else { nil }
        }
        #expect(settled.first?.word == words[other])
        #expect(settled.first?.fixedFrom == words[chosen])
        #expect(settled.first?.source == .fixed)
        // A lone swipe teaches where it started, lightly.
        #expect(settled.first?.touches.count == 1)
        #expect(settled.first?.touches.first?.weight == 0.3)
    }

    @Test func aReopenedWordDoesNotSettle() {
        var composer = Synth.composer()
        let t = Synth.taps(&composer, "the")
        _ = composer.press(.space, time: t)
        let effects = composer.press(.backspace, time: t + 0.5)
        #expect(!effects.contains { if case .settled = $0 { true } else { false } })
        #expect(composer.hasOpenWord)
    }

    // MARK: The matcher

    @Test func yourPairsWinAnAmbiguousSwipe() {
        var composer = ContextMatcherTests.composer()
        composer.setContext(before: "My ")
        Synth.swipe(&composer, "pot")
        let before = composer.state.openWord
        #expect(before != "pit")

        var model = PersonalModel()
        for _ in 0..<12 { model.learn(Self.word("pit", after: "my"), device: "a", at: Self.start) }
        composer = ContextMatcherTests.composer()
        composer.personal = PersonalIndex(model, at: Self.start)
        composer.setContext(before: "My ")
        Synth.swipe(&composer, "pot")
        #expect(composer.state.openWord == "pit")
    }

    @Test func commonWordsGainNothingForBeingCommon() {
        // A thousand words, "the" about as often as in English at large.
        var model = PersonalModel()
        for _ in 0..<55 { model.learn(Self.word("the"), device: "a", at: Self.start) }
        for i in 0..<945 { model.learn(Self.word(Self.letters(i)), device: "a", at: Self.start) }
        var matcher = Matcher(language: ContextMatcherTests.english, layout: Synth.layout)
        matcher.personal = PersonalIndex(model, at: Self.start)
        let the = Synth.lexicon.logPrior(of: "the")!
        #expect(matcher.personalBonus(for: "the", prior: the) < 0.15)
        #expect(matcher.personalBonus(for: "pit", prior: Synth.lexicon.logPrior(of: "pit")!) == 0)
    }

    // MARK: The learner

    @Test func theSwitchStopsLearningAndUsing() {
        var learner = PersonalLearner(model: PersonalModel(), device: "a", now: Self.start)
        let learned = learner.learn(Self.word("hello"), now: Self.start)
        #expect(learned)
        #expect(!learner.index.isEmpty)
        var settings = KeyboardSettings()
        settings.learnsFromYou = false
        learner.apply(settings, now: Self.start)
        #expect(learner.index.isEmpty)
        let whileOff = learner.learn(Self.word("again"), now: Self.start)
        #expect(!whileOff)
        // Fields that may not teach (passwords, addresses) teach nothing.
        settings.learnsFromYou = true
        learner.apply(settings, now: Self.start)
        let inAPasswordField = learner.learn(Self.word("again"), allowed: false, now: Self.start)
        #expect(!inAPasswordField)
        #expect(learner.index.wordCount("hello") == 1)
    }

    @Test func aForgetInTheSettingsClearsTheModelOnce() {
        var learner = PersonalLearner(model: PersonalModel(), device: "a", now: Self.start)
        learner.learn(Self.word("hello"), now: Self.start)
        var settings = KeyboardSettings()
        settings.forgetPersonalAt = Self.start.addingTimeInterval(5)
        let forgot = learner.apply(settings, now: Self.start.addingTimeInterval(6))
        #expect(forgot)
        #expect(learner.model.isEmpty)
        learner.learn(Self.word("again"), now: Self.start.addingTimeInterval(7))
        // The same settings again forget nothing new.
        let again = learner.apply(settings, now: Self.start.addingTimeInterval(8))
        #expect(!again)
        #expect(learner.index.wordCount("again") == 1)
    }

    // MARK: Storage and sync

    @Test func mirroredStoresMerge() {
        var mine = PersonalModel()
        mine.learn(Self.word("alpha"), device: "own", at: Self.start)
        var theirs = PersonalModel()
        theirs.learn(Self.word("beta"), device: "other", at: Self.start)
        let store = MirroredPersonalStore(own: MemoryPersonalStore(mine), shared: MemoryPersonalStore(theirs))
        let loaded = PersonalIndex(store.load()!, at: Self.start)
        #expect(loaded.wordCount("alpha") == 1 && loaded.wordCount("beta") == 1)
    }

    @Test func theInstallIDIsKept() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("astrotype-\(UUID().uuidString)/install.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = InstallID.load(from: url)
        #expect(!first.isEmpty)
        #expect(InstallID.load(from: url) == first)
    }

    @Test func snapshotsCarryThePersonalModel() throws {
        var model = PersonalModel()
        model.learn(Self.word("hello"), device: "a", at: Self.start)
        let a = SyncSnapshot(words: LearnedWords(), settings: KeyboardSettings(), settingsChanged: Self.start, personal: model)
        var other = PersonalModel()
        other.learn(Self.word("there"), device: "b", at: Self.start)
        let b = SyncSnapshot(words: LearnedWords(), settings: KeyboardSettings(), settingsChanged: Self.start, personal: other)
        let merged = a.merged(with: b)
        #expect(merged.personal?.shards.count == 2)
        // A copy from before Phase B has none and takes ours.
        let old = try JSONDecoder().decode(SyncSnapshot.self, from: Data(#"{"version":1,"words":{"entries":{}},"settings":{},"settingsChanged":0}"#.utf8))
        #expect(old.personal == nil)
        #expect(old.merged(with: a).personal == model)
        #expect(a.merged(with: old).personal == model)
        // Settings saved before Phase B learn by default.
        #expect(old.settings.learnsFromYou)
    }
}
