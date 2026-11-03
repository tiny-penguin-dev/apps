import Foundation
import Testing
@testable import AstrotypeCore

/// features/missed-words Phase A: "Not it?" after a swiped word, the word meant typed
/// into the bar, written in place of the guess, learned, and settled as a miss to keep
/// and share.
@Suite struct MissedWordTests {
    /// The field's text after the effects, as a host would apply them.
    struct Field {
        var text = ""
        var marked = ""

        mutating func apply(_ effects: [Composer.Effect]) {
            for effect in effects {
                switch effect {
                case .insert(let s): text += s
                case .deleteBackward(let n): text = String(text.dropLast(n))
                case .mark(let s): marked = s
                case .commit(let s): text += s; marked = ""
                case .clearMark: marked = ""
                default: break
                }
            }
        }

        var shown: String { text + marked }
    }

    static func taps(_ composer: inout Composer, _ letters: String, at time: TimeInterval) -> [Composer.Effect] {
        var effects: [Composer.Effect] = []
        for (i, letter) in letters.enumerated() {
            effects += Synth.tap(&composer, letter, id: 10 + i, at: time + 0.15 * Double(i))
        }
        return effects
    }

    static func settled(_ effects: [Composer.Effect]) -> SettledWord? {
        effects.compactMap { effect -> SettledWord? in
            if case .settled(let word) = effect { word } else { nil }
        }.first
    }

    /// Gabriel saved "second" and closed the keyboard (3 Nov 2026): the miss has to be
    /// kept then, not at a next word that never comes.
    @Test func aMissSettlesWhenTheKeyboardHides() throws {
        var composer = Synth.composer()
        _ = Synth.swipe(&composer, "sold")
        composer.beginCorrection()
        _ = Self.taps(&composer, "second", at: 1)
        _ = composer.saveCorrection(time: 3)
        let word = try #require(Self.settled(composer.keyboardWillHide()))
        #expect(word.word == "second")
        #expect(word.missed)
        // Once only.
        #expect(Self.settled(Synth.swipe(&composer, "the", at: 4)) == nil)
        // An open word is left alone.
        #expect(composer.keyboardWillHide().isEmpty)
        #expect(composer.state.openWord != nil)
    }

    @Test func notItReplacesTheOpenWord() throws {
        var composer = Synth.composer()
        var field = Field()
        field.apply(Synth.swipe(&composer, "sold"))
        let guess = try #require(composer.state.openWord)
        #expect(composer.state.canCorrect)

        composer.beginCorrection()
        #expect(composer.state.bar == .correcting(""))
        #expect(!composer.state.canCorrect)
        // The keys type into the bar, not the text.
        field.apply(Self.taps(&composer, "secom", at: 1))
        field.apply(composer.press(.backspace, time: 2))
        field.apply(Self.taps(&composer, "nd", at: 2.1))
        #expect(composer.state.bar == .correcting("second"))
        #expect(field.shown == guess)
        // Autospace waits while the field is open.
        #expect(composer.tick(time: 10).isEmpty)

        field.apply(composer.saveCorrection(time: 3))
        #expect(field.shown == "second ")
        #expect(composer.state.bar == .idle)
        #expect(!composer.state.canCorrect)

        // The next word settles it as a miss, from the guess to the word meant.
        let word = try #require(Self.settled(Synth.swipe(&composer, "the", at: 4)))
        #expect(word.word == "second")
        #expect(word.missed)
        #expect(word.fixedFrom == guess.lowercased())
        let miss = try #require(SharedWord.correction(word, layout: Synth.layout, now: Date()))
        #expect(miss.kind == SharedWord.missKind)
        #expect(miss.isMiss && miss.isCorrection)
        #expect(miss.word == "second")
        #expect(miss.typed == guess.lowercased())
        // It replays through the engine, the swipe against the word meant.
        let replayed = try Replay.run(miss, language: ContextMatcherTests.english)
        #expect(replayed.words.first?.expected == "second")
    }

    @Test func notItFixesTheWordJustWritten() throws {
        var composer = Synth.composer(autoCapitalize: true)
        var field = Field()
        composer.setContext(before: "")
        field.apply(Synth.swipe(&composer, "sold"))
        field.apply(composer.press(.space, time: 1))
        composer.setContext(before: field.text)
        let written = field.text
        #expect(written.first?.isUppercase == true)
        #expect(composer.state.canCorrect)

        composer.beginCorrection()
        _ = Self.taps(&composer, "second", at: 2)
        field.apply(composer.press(.space, time: 3))
        // Cased like the word it replaced, with its space.
        #expect(field.text == "Second ")
        #expect(!composer.state.canCorrect)
    }

    @Test func cancelLeavesEverythingAsItWas() {
        var composer = Synth.composer()
        var field = Field()
        field.apply(Synth.swipe(&composer, "sold"))
        let bar = composer.state.bar
        composer.beginCorrection()
        _ = Self.taps(&composer, "sec", at: 1)
        composer.cancelCorrection(time: 2)
        #expect(composer.state.bar == bar)
        #expect(composer.state.canCorrect)
        // Autospace is back on.
        #expect(!composer.tick(time: 10).isEmpty)
    }

    @Test func aWordTheDictionaryLacksIsLearned() {
        var composer = Synth.composer()
        _ = Synth.swipe(&composer, "sold")
        composer.beginCorrection()
        _ = Self.taps(&composer, "zorbly", at: 1)
        let effects = composer.saveCorrection(time: 2)
        #expect(effects.contains(.learn("zorbly")))
    }

    @Test func peckedWordsOfferNoNotIt() {
        var composer = Synth.composer()
        Synth.taps(&composer, "cat")
        #expect(!composer.state.canCorrect)
        composer.beginCorrection()
        #expect(composer.state.bar != .correcting(""))
    }

    @Test func missesAreCounted() {
        var tally = GuessTally()
        tally.add(SettledWord(word: "second", previous: nil, source: .fixed, fixedFrom: "song", firstGuess: "song",
                              pecked: false, missed: true))
        #expect(tally.missed == 1)
        #expect(tally.swiped == 1 && tally.swipedFirst == 0)
    }

    // MARK: Phase B, remembered shapes

    /// A sloppy swipe: each turn misses its key's centre, then the corners are cut
    /// (a moving average over `window` points either side), as a fast thumb does.
    static func sloppy(_ word: String, seed: UInt64, window: Int = 10) -> [CGPoint] {
        let layout = Synth.layout
        let unit = layout.frame(of: .letter("q"))!
        var typing = SeededGenerator(seed: seed)
        func gauss() -> CGFloat {
            let u = max(1e-9, Double.random(in: 0..<1, using: &typing)), v = Double.random(in: 0..<1, using: &typing)
            return CGFloat(sqrt(-2 * log(u)) * cos(2 * .pi * v))
        }
        let aims = word.map { letter -> CGPoint in
            let f = layout.frame(of: .letter(letter))!
            return CGPoint(x: f.midX + gauss() * 0.2 * unit.width, y: f.midY + gauss() * 0.16 * unit.height)
        }
        let path = Geometry.walk(aims, step: 4)
        return path.indices.map { i in
            let near = path[max(0, i - window)...min(path.count - 1, i + window)]
            return CGPoint(x: near.map(\.x).reduce(0, +) / CGFloat(near.count), y: near.map(\.y).reduce(0, +) / CGFloat(near.count))
        }
    }

    static func swipe(_ composer: inout Composer, _ path: [CGPoint], at time: TimeInterval) -> [Composer.Effect] {
        var effects = composer.touchDown(id: 1, at: path[0], time: time)
        for (i, point) in path.enumerated().dropFirst() {
            effects += composer.touchMoved(id: 1, to: point, time: time + 0.5 * Double(i) / Double(path.count))
        }
        return effects + composer.touchUp(id: 1, at: path[path.count - 1], time: time + 0.5)
    }

    static func guess(_ path: [CGPoint], personal: PersonalIndex = PersonalIndex()) -> String? {
        var composer = Composer(language: ContextMatcherTests.english, layout: Synth.layout, settings: Replay.settings)
        composer.personal = personal
        _ = swipe(&composer, path, at: 0)
        return composer.state.openWord
    }

    /// Gabriel's "second" (3 Nov 2026): a swipe that cuts the corners comes out "song".
    /// Saved once with Not it?, the next sloppy swipes like it give "second".
    @Test func aSavedMissTeachesTheShape() throws {
        let seed = try #require((1...200).first { Self.guess(Self.sloppy("second", seed: $0)) != "second" })
        var composer = Composer(language: ContextMatcherTests.english, layout: Synth.layout, settings: Replay.settings)
        _ = Self.swipe(&composer, Self.sloppy("second", seed: seed), at: 0)
        composer.beginCorrection()
        for letter in "second" { _ = composer.press(.letter(letter), time: 1) }
        _ = composer.saveCorrection(time: 2)
        let settled = try #require(Self.settled(Synth.swipe(&composer, "the", at: 3)))
        let shape = try #require(settled.shape)
        #expect(shape.count == PersonalModel.shapePoints)

        var learner = PersonalLearner(model: PersonalModel(), device: "phone", now: Date())
        let learned = learner.learn(settled, now: Date())
        #expect(learned)
        #expect(learner.index.shapes.map(\.word) == ["second"])
        // It survives the trip through the file and iCloud.
        let data = try JSONEncoder().encode(learner.model)
        let decoded = try JSONDecoder().decode(PersonalModel.self, from: data)
        #expect(decoded.shards["phone"]?.shapes == learner.model.shards["phone"]?.shapes)

        var before = 0, after = 0
        for other in UInt64(300)..<330 {
            let path = Self.sloppy("second", seed: other)
            if Self.guess(path) == "second" { before += 1 }
            if Self.guess(path, personal: learner.index) == "second" { after += 1 }
        }
        #expect(after >= 24, "\(before) → \(after) of 30")
        #expect(after >= before + 5)
        // Words that start and end elsewhere are left alone.
        for word in ["song", "sold", "send", "should", "sound", "said", "spend"] {
            for other in UInt64(1)...5 {
                let path = Self.sloppy(word, seed: other, window: 4)
                #expect(Self.guess(path, personal: learner.index) == Self.guess(path), "\(word) \(other)")
            }
        }
    }

    @Test func oldShardsReadWithoutShapes() throws {
        let json = #"{"version":1,"shards":{"a":{"since":0,"changed":0,"words":{"hi":[1,9000]},"pairs":{},"touches":{}}}}"#
        let model = try JSONDecoder().decode(PersonalModel.self, from: Data(json.utf8))
        #expect(model.shards["a"]?.shapes.isEmpty == true)
        #expect(model.shards["a"]?.words["hi"] != nil)
    }

    // MARK: Phase C, the list

    @Test func theStoreKnowsWhatWasSent() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SharedWordStore(folder: folder, limit: 200)
        let words = ["second", "third"].map {
            SharedWord(kind: SharedWord.missKind, word: $0, typed: "song", layoutWidth: 390, layoutHeight: 216,
                       split: false, touches: [], day: "2026-11-03")
        }
        store.save(words)
        #expect(store.uploadedIDs().isEmpty)
        store.markUploaded([words[0].id])
        #expect(store.uploadedIDs() == [words[0].id])
        #expect(store.pending().map(\.id) == [words[1].id])
    }
}
