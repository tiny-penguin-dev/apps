import AstrotypeCore
import Foundation

// astrotype-tools: the command line for the data loop (features/smart-matching).
//
//     swift run -c release astrotype-tools build-ngrams pairs.tsv Sources/AstrotypeCore/Resources/en/bigrams.bin
//     swift run -c release astrotype-tools replay ../../ml/samples/practice
//     swift run astrotype-tools next "thank"
//
// Everything it does is in AstrotypeCore (`NgramModel.Builder`, `Replay`), so the
// tests cover it; this file only parses arguments and prints.

let usage = """
usage:
  astrotype-tools build-ngrams <pairs.tsv> <out.bin> [--max-pairs N] [--lambda L]
      the word-pair binary from `previous<TAB>next<TAB>count` lines (ml/ngrams/count_pairs.py)
  astrotype-tools replay <folder-or-file.json> [--language en] [--misses N]
      plays practice recordings through the engine and reports first-guess accuracy
  astrotype-tools next <word> [--language en] [--limit N]
      the words the model expects after `word` (`<s>` for a sentence start)
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
    do { return try Language.bundled(code) } catch { fail("no bundled language \(code): \(error)") }
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

func recordings(at path: String) -> [PracticeRecording] {
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
    let decoder = JSONDecoder()
    return files.sorted { $0.path < $1.path }.compactMap { file in
        guard let data = try? Data(contentsOf: file) else { return nil }
        if let recording = try? decoder.decode(PracticeRecording.self, from: data) { return recording }
        FileHandle.standardError.write(Data("skipping \(file.lastPathComponent): not a practice recording\n".utf8))
        return nil
    }
}

func replay(_ plain: [String], _ options: [String: String]) {
    guard plain.count == 1 else { fail(usage) }
    let language = language(options)
    var outcomes: [Replay.Outcome] = []
    var skipped = 0
    for recording in recordings(at: plain[0]) {
        do {
            outcomes.append(try Replay.run(recording, language: language))
        } catch {
            skipped += 1
        }
    }
    let report = Replay.Report(outcomes, skipped: skipped)
    print(report.summary)
    let limit = options["misses"].flatMap(Int.init) ?? 40
    for line in report.missLines.prefix(limit) { print("  " + line) }
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

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else { fail(usage) }
let (plain, options) = parse(arguments.dropFirst())
switch command {
case "build-ngrams": buildNgrams(plain, options)
case "replay": replay(plain, options)
case "next": next(plain, options)
default: fail(usage)
}
