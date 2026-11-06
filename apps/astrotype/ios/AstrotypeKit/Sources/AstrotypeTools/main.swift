import AstrotypeCore
import Foundation

// astrotype-tools: the command line for the data loop (features/smart-matching).
//
//     swift run -c release astrotype-tools build-ngrams pairs.tsv Sources/AstrotypeCore/Resources/en/bigrams.bin
//     swift run -c release astrotype-tools replay ../../ml/samples/practice
//     swift run astrotype-tools next "thank"
//     swift run -c release astrotype-tools typing ../../ml/samples/typing/<id>.json
//     swift run -c release astrotype-tools synth /tmp/synth && swift run -c release astrotype-tools tune /tmp/synth
//
// Everything it does is in AstrotypeCore (`NgramModel.Builder`, `Replay`, `Tuning`, `SyntheticTyping`, `PracticeWords`), so the
// tests cover it; this file only parses arguments and prints.

let usage = """
usage:
  astrotype-tools build-ngrams <pairs.tsv> <out.bin> [--max-pairs N] [--lambda L]
      the word-pair binary from `previous<TAB>next<TAB>count` lines (ml/ngrams/count_pairs.py)
  astrotype-tools replay <folder-or-file.json> [--language en|es|en+es] [--misses N] [--prior P --context C --length L]
      plays practice recordings and shared words through the engine and reports first-guess accuracy
  astrotype-tools tune <folder> [--language en|es|en+es] [--rounds N]
      searches the matcher's weights for the best first-guess rate on those items
  astrotype-tools synth <out-folder> [--sessions N] [--noise σ] [--seed S] [--thumbs 1|2] [--wobble s]
      writes made-up shared words (noisy swipes of practice prompts) to measure against
  astrotype-tools prompts [--count N] [--seed S]
      the "Practice words" prompts
  astrotype-tools next <word> [--language en|es|en+es] [--limit N]
      the words the model expects after `word` (`<s>` for a sentence start)
  astrotype-tools nexteval <test.txt> [--language en|es] [--limit N]
      scores the word pairs' next-word guesses on held-back sentences (ml/nextword/make_text.py)
  astrotype-tools typing <log.json> [--show timeline|replay]
      a typing recording from Settings → Debug: what happened, line by line, then the replay
      through the engine and every place it writes something else than the phone did
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// `--name value` options, with the plain arguments left over.
func parse(_ arguments: ArraySlice<String>) -> (plain: [String], options: [String: String]) {
    var plain: [String] = []
    var options: [String: String] = [:]
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        if argument.hasPrefix("--") {
            options[String(argument.dropFirst(2))] = iterator.next() ?? ""
        } else {
            plain.append(argument)
        }
    }
    return (plain, options)
}

func language(_ options: [String: String]) -> Language {
    let code = options["language"] ?? "en"
    // "en+es" for two at once.
    do { return try Language.bundled(code.split(separator: "+").map(String.init)) } catch { fail("no bundled language \(code): \(error)") }
}

func buildNgrams(_ plain: [String], _ options: [String: String]) {
    guard plain.count == 2 else { fail(usage) }
    guard let text = try? String(contentsOfFile: plain[0], encoding: .utf8) else { fail("cannot read \(plain[0])") }
    var builder = NgramModel.Builder()
    if let lambda = options["lambda"].flatMap(Float.init) { builder.lambda = lambda }
    var lines = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        builder.add(line: line)
        lines += 1
    }
    let maxPairs = options["max-pairs"].flatMap(Int.init) ?? 300_000
    let data = builder.build(maxPairs: maxPairs)
    do { try data.write(to: URL(fileURLWithPath: plain[1])) } catch { fail("cannot write \(plain[1]): \(error)") }
    guard let model = try? NgramModel(data: data) else { fail("the model written does not read back") }
    print("\(lines) pair lines in · \(model.vocabularyCount) words · \(model.pairCount) pairs · \(data.count / 1024) KB · λ \(model.lambda)")
    print("after <s>: " + model.likelyWords(after: NgramModel.sentenceStart, limit: 8).joined(separator: " "))
}

func items(at path: String) -> [Replay.Item] {
    let url = URL(fileURLWithPath: path)
    var files: [URL] = []
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { fail("no such file: \(path)") }
    if isDirectory.boolValue {
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        while let file = enumerator?.nextObject() as? URL {
            if file.pathExtension == "json" { files.append(file) }
        }
    } else {
        files = [url]
    }
    return files.sorted { $0.path < $1.path }.compactMap { file in
        guard let data = try? Data(contentsOf: file) else { return nil }
        if let item = Replay.Item(json: data) { return item }
        FileHandle.standardError.write(Data("skipping \(file.lastPathComponent): not a practice recording or shared word\n".utf8))
        return nil
    }
}

/// `--prior 0.1 --context 0.15 --length 0.2` over the defaults.
func weights(_ options: [String: String]) -> Matcher.Weights {
    var weights = Matcher.Weights()
    if let value = options["prior"].flatMap(Double.init) { weights.prior = value }
    if let value = options["context"].flatMap(Double.init) { weights.context = value }
    if let value = options["length"].flatMap(Double.init) { weights.length = value }
    if let value = options["near"].flatMap(Double.init) { weights.near = value }
    if let value = options["stand-in"].flatMap(Double.init) { weights.standIn = value }
    return weights
}

func replay(_ plain: [String], _ options: [String: String]) {
    guard plain.count == 1 else { fail(usage) }
    let report = Replay.report(items(at: plain[0]), language: language(options), weights: weights(options))
    print(report.summary)
    let limit = options["misses"].flatMap(Int.init) ?? 40
    for line in report.missLines.prefix(limit) { print("  " + line) }
}

func tune(_ plain: [String], _ options: [String: String]) {
    guard plain.count == 1 else { fail(usage) }
    let all = items(at: plain[0])
    guard !all.isEmpty else { fail("nothing to replay in \(plain[0])") }
    let rounds = options["rounds"].flatMap(Int.init) ?? 2
    let steps = Tuning.search(all, language: language(options), start: weights(options), rounds: rounds)
    print("\(all.count) items · \(steps.first?.words ?? 0) words")
    print("start  " + steps[0].line)
    for step in steps.dropFirst() { print("better " + step.line) }
}

func synth(_ plain: [String], _ options: [String: String]) {
    guard plain.count == 1 else { fail(usage) }
    let language = language(options)
    let count = options["sessions"].flatMap(Int.init) ?? 100
    let noise = options["noise"].flatMap(Double.init) ?? 0.2
    let seed = options["seed"].flatMap(UInt64.init) ?? 1
    // Both thumbs per word, landing `wobble` seconds off their turn (SyntheticTyping.Thumbs).
    let thumbs: SyntheticTyping.Thumbs = options["thumbs"] == "2" ? .two(wobble: options["wobble"].flatMap(Double.init) ?? 0.04) : .one
    let folder = URL(fileURLWithPath: plain[0])
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var prompts = PracticeWords(language: language, seed: seed)
    // A different habit per writer: thumbs land low, high or to the side.
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var words = 0
    for index in 0..<count {
        let habit = Double(index % 5 - 2) * 0.08
        var typing = SyntheticTyping(layout: .qwerty(width: 390), noise: noise,
                                     left: KeyOffset(dx: habit, dy: 0.12), right: KeyOffset(dx: -habit, dy: 0.12),
                                     thumbs: thumbs, seed: seed &+ UInt64(index))
        var text: [String] = []
        while text.count < 8 { text += prompts.next().split(separator: " ").map(String.init) }
        let recording = typing.record(text, kind: "synthetic")
        for word in SharedWord.words(of: recording) {
            guard let data = try? encoder.encode(word) else { continue }
            try? data.write(to: folder.appendingPathComponent(word.id.uuidString + ".json"))
            words += 1
        }
    }
    print("\(words) synthetic words in \(folder.path) (noise \(noise), seed \(seed))")
}

func prompts(_ plain: [String], _ options: [String: String]) {
    var prompts = PracticeWords(language: language(options), seed: options["seed"].flatMap(UInt64.init))
    for _ in 0..<(options["count"].flatMap(Int.init) ?? 20) { print(prompts.next()) }
}

func next(_ plain: [String], _ options: [String: String]) {
    guard plain.count == 1 else { fail(usage) }
    let language = language(options)
    guard let model = language.ngrams else { fail("\(language.code) has no word-pair model") }
    let limit = options["limit"].flatMap(Int.init) ?? 10
    for word in model.likelyWords(after: plain[0].lowercased(), limit: limit) {
        let p = model.logProbability(of: word, after: plain[0].lowercased()).map { exp($0) } ?? 0
        print(String(format: "%@\t%.3f", word, p))
    }
}

func nextEval(_ plain: [String], _ options: [String: String]) {
    guard plain.count == 1 else { fail(usage) }
    let models = language(options).ngramModels
    let limit = options["limit"].flatMap(Int.init) ?? .max
    guard let text = try? String(contentsOfFile: plain[0], encoding: .utf8) else { fail("can't read \(plain[0])") }
    let sentences = text.split(separator: "\n").prefix(limit).map { $0.split(separator: " ").map(String.init) }
    let eval = NextWordEval.run(sentences: sentences) { NextWordEval.pairGuesses($0, models: models) }
    print("Word pairs: \(sentences.count) sentences · \(eval.summary)")
}

func typing(_ plain: [String], _ options: [String: String]) {
    guard plain.count == 1 else { fail(usage) }
    let log: TypingLog
    do { log = try TypingLog.decode(Data(contentsOf: URL(fileURLWithPath: plain[0]))) } catch { fail("not a typing log: \(error)") }
    let formatter = ISO8601DateFormatter()
    print("Typing log \(log.id.uuidString) · \(log.summary)")
    print("From \(formatter.string(from: log.from)) to \(formatter.string(from: log.to)), sent by \(log.app)")
    if let device = log.device { print("Keyboard \(device.app) on \(device.model), \(device.system)") }
    for mark in log.marks { print("Mark at \(formatter.string(from: mark))") }
    if options["show"] != "replay" {
        print("")
        print(log.timeline())
    }
    guard options["show"] != "timeline" else { return }
    let result = TypingReplay.run(log)
    print("")
    print("Replay: \(result.commits.count) words · \(result.differences.count) differences from the phone")
    for difference in result.differences { print("  " + difference.description) }
    print("Field at the end: \"\(result.text.suffix(80))\"")
}

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else { fail(usage) }
let (plain, options) = parse(arguments.dropFirst())
switch command {
case "build-ngrams": buildNgrams(plain, options)
case "replay": replay(plain, options)
case "next": next(plain, options)
case "nexteval": nextEval(plain, options)
case "tune": tune(plain, options)
case "synth": synth(plain, options)
case "prompts": prompts(plain, options)
case "typing": typing(plain, options)
default: fail(usage)
}
