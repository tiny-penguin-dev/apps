import Foundation
import Testing
@testable import StackWriteCore

@Suite struct StoreTests {
    private func tempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("StackWriteKitTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func fileStoresRoundTrip() {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let words = FileWordStore(url: folder.appendingPathComponent("deep/words.json"))
        #expect(words.load() == nil)
        var learned = LearnedWords()
        learned.learn("flotilla", at: Date(timeIntervalSince1970: 1_000))
        words.save(learned)
        #expect(words.load() == learned)

        let stamp = Date(timeIntervalSince1970: 2_000)
        let settings = FileSettingsStore(url: folder.appendingPathComponent("settings.json"), now: { stamp })
        #expect(settings.load() == nil)
        #expect(settings.lastChanged() == nil)
        var value = KeyboardSettings()
        value.trails = false
        settings.save(value)
        #expect(settings.load() == value)
        #expect(settings.lastChanged() == stamp)
    }

    @Test func mirroredWordsMergeBothCopiesAndWriteBoth() {
        let own = MemoryWordStore()
        let shared = MemoryWordStore()
        let store = MirroredWordStore(own: own, shared: shared)
        #expect(store.load() == nil)

        var mine = LearnedWords()
        mine.learn("alpha", at: Date(timeIntervalSince1970: 10))
        own.save(mine)
        var theirs = LearnedWords()
        theirs.learn("beta", at: Date(timeIntervalSince1970: 20))
        theirs.forget("alpha", at: Date(timeIntervalSince1970: 30))
        shared.save(theirs)

        let merged = store.load()!
        #expect(merged.contains("beta"))
        #expect(!merged.contains("alpha"))
        #expect(merged.weight(of: "alpha") == -10)

        store.save(merged)
        #expect(own.load() == merged)
        #expect(shared.load() == merged)
    }

    @Test func mirroredSettingsTakeTheLaterCopy() {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let own = FileSettingsStore(url: folder.appendingPathComponent("own.json"), now: { Date(timeIntervalSince1970: 100) })
        let shared = FileSettingsStore(url: folder.appendingPathComponent("shared.json"), now: { Date(timeIntervalSince1970: 200) })
        var older = KeyboardSettings()
        older.autospace = false
        var newer = KeyboardSettings()
        newer.trails = false
        own.save(older)
        shared.save(newer)
        let store = MirroredSettingsStore(own: own, shared: shared)
        #expect(store.load() == newer)
        #expect(store.lastChanged() == Date(timeIntervalSince1970: 200))

        // Only one copy: that one.
        let lonely = MirroredSettingsStore(own: own, shared: FileSettingsStore(url: folder.appendingPathComponent("none.json")))
        #expect(lonely.load() == older)
    }

    @Test func extensionStatusRoundTripsAndReadsOlderJSON() throws {
        let status = ExtensionStatus(fullAccess: true, seen: Date(timeIntervalSince1970: 5), lastSync: nil, lastSyncError: "no iCloud")
        let data = try JSONEncoder().encode(status)
        #expect(try JSONDecoder().decode(ExtensionStatus.self, from: data) == status)
        let older = Data(#"{"version":1,"fullAccess":true,"seen":0}"#.utf8)
        let read = try JSONDecoder().decode(ExtensionStatus.self, from: older)
        #expect(read.fullAccess)
        #expect(read.lastSync == nil)

        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileExtensionStatusStore(url: folder.appendingPathComponent("status.json"))
        #expect(store.load() == nil)
        store.save(status)
        #expect(store.load() == status)
    }

    @Test func backupCopiesTheFilesAndKeepsTheNewest() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let words = folder.appendingPathComponent("words.json")
        let settings = folder.appendingPathComponent("settings.json")
        let missing = folder.appendingPathComponent("missing.json")
        try Data("words".utf8).write(to: words)
        try Data("settings".utf8).write(to: settings)
        let backups = folder.appendingPathComponent("Backups", isDirectory: true)

        #expect(try Backup.make(of: [missing], into: backups, label: "none") == nil)
        for (i, label) in ["0.1.0", "0.2.0", "0.3.0", "0.4.0"].enumerated() {
            let made = try Backup.make(of: [words, settings, missing], into: backups, label: label, keep: 3)
            #expect(made?.lastPathComponent == label)
            let copied = try String(contentsOf: made!.appendingPathComponent("words.json"), encoding: .utf8)
            #expect(copied == "words")
            // Spread the folders' times so the pruning order is clear.
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(1_000 + i))], ofItemAtPath: made!.path)
        }
        let kept = Backup.list(in: backups).map(\.lastPathComponent)
        #expect(kept == ["0.4.0", "0.3.0", "0.2.0"])
    }
}

@Suite struct SyncTests {
    private func snapshot(_ words: [(String, Double)] = [], settingsChanged: TimeInterval = 0, trails: Bool = true) -> SyncSnapshot {
        var learned = LearnedWords()
        for (word, time) in words { learned.learn(word, at: Date(timeIntervalSince1970: time)) }
        var settings = KeyboardSettings()
        settings.trails = trails
        return SyncSnapshot(words: learned, settings: settings, settingsChanged: Date(timeIntervalSince1970: settingsChanged))
    }

    @Test func snapshotsMergeWordsAndTakeTheLaterSettings() throws {
        let mine = snapshot([("alpha", 10)], settingsChanged: 100, trails: false)
        let theirs = snapshot([("beta", 20)], settingsChanged: 50, trails: true)
        let merged = mine.merged(with: theirs)
        #expect(merged.words.contains("alpha"))
        #expect(merged.words.contains("beta"))
        #expect(merged.settings.trails == false)
        #expect(merged.settingsChanged == Date(timeIntervalSince1970: 100))
        #expect(theirs.merged(with: mine).settings.trails == false)

        let data = try JSONEncoder().encode(merged)
        #expect(try JSONDecoder().decode(SyncSnapshot.self, from: data) == merged)
        let older = Data(#"{"version":1}"#.utf8)
        let read = try JSONDecoder().decode(SyncSnapshot.self, from: older)
        #expect(read.words == LearnedWords())
        #expect(read.settingsChanged == .distantPast)
    }

    @Test func anEmptyCloudGetsTheLocalCopy() async throws {
        let cloud = FakeCloudSync()
        let local = snapshot([("alpha", 10)])
        let merged = try await Syncer.sync(local: local, cloud: cloud)
        #expect(merged == local)
        #expect(cloud.snapshot == local)
        #expect(cloud.saves == 1)
    }

    @Test func nothingIsWrittenWhenTheCloudAlreadyHasIt() async throws {
        let local = snapshot([("alpha", 10)])
        let cloud = FakeCloudSync(local)
        _ = try await Syncer.sync(local: local, cloud: cloud)
        #expect(cloud.saves == 0)
    }

    @Test func aConflictIsMergedAndRetried() async throws {
        let cloud = FakeCloudSync(snapshot([("beta", 20)]))
        let late = snapshot([("gamma", 30)])
        cloud.afterFetch = { cloud.write(fromElsewhere: late) }
        let merged = try await Syncer.sync(local: snapshot([("alpha", 10)]), cloud: cloud)
        #expect(merged.words.contains("alpha"))
        #expect(merged.words.contains("gamma"))
        #expect(cloud.snapshot == merged)
        #expect(cloud.saves == 2)
    }

    @Test func anUnavailableCloudThrowsItsMessage() async {
        let cloud = FakeCloudSync()
        cloud.failure = .unavailable("Sign in to iCloud")
        do {
            _ = try await Syncer.sync(local: snapshot(), cloud: cloud)
            Issue.record("expected a throw")
        } catch {
            #expect(error.localizedDescription == "Sign in to iCloud")
        }
    }
}
