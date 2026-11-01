import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct EntitlementTests {
    let start = Date(timeIntervalSince1970: 1_793_491_200)

    @Test func statusComesFromTheStoreAndTheTrial() {
        let trial = Trial(start: start)
        #expect(ProStatus.from(subscribed: true, trial: trial, now: start) == .pro)
        #expect(ProStatus.from(subscribed: true, trial: trial, now: start.addingTimeInterval(40 * 86_400)) == .pro)
        #expect(ProStatus.from(subscribed: false, trial: trial, now: start) == .trial(endsOn: trial.end))
        #expect(ProStatus.from(subscribed: false, trial: trial, now: trial.end.addingTimeInterval(-1)) == .trial(endsOn: trial.end))
        #expect(ProStatus.from(subscribed: false, trial: trial, now: trial.end) == .free)
    }

    @Test func proAndTheTrialAllowEverythingFreeAllowsTheBasics() {
        let trial = Trial(start: start)
        let onTrial = Entitlement(status: .trial(endsOn: trial.end), now: start)
        #expect(onTrial.isPro)
        #expect(onTrial.isOnTrial)
        #expect(!onTrial.isSubscribed)
        #expect(onTrial.allows(.twoThumbs))
        #expect(onTrial.allows(.splitLayout))

        let pro = Entitlement(status: .pro, now: start)
        #expect(pro.isPro && pro.isSubscribed && !pro.isOnTrial)

        let free = Entitlement(status: .free, now: start)
        #expect(!free.isPro)
        #expect(!free.allows(.twoThumbs))
        #expect(!free.allows(.splitLayout))
        #expect(!free.allows(.drills))
        #expect(Entitlement.features(for: .free, now: start).isEmpty)
        #expect(Entitlement.features(for: .pro, now: start) == Set(ProFeature.allCases))
        #expect(Entitlement.full.isPro)
    }

    @Test func aTrialReadWithAStaleClockEndsWhenTheClockSaysSo() {
        let trial = Trial(start: start)
        // The status says "trial", but the entitlement's own clock is past its end.
        let stale = Entitlement(status: .trial(endsOn: trial.end), now: trial.end)
        #expect(!stale.isPro)
        #expect(!stale.isOnTrial)
    }

    @Test func productsHaveTheirPlans() {
        #expect(ProProducts.all == [ProProducts.yearly, ProProducts.monthly])
        #expect(ProProducts.plan(of: ProProducts.yearly) == "yearly")
        #expect(ProProducts.plan(of: ProProducts.monthly) == "monthly")
    }
}

@Suite struct ProStoresTests {
    let start = Date(timeIntervalSince1970: 1_793_491_200)

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AstrotypeKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func trialStoreStartsOnceAndKeepsTheEarliest() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TrialStore(url: dir.appendingPathComponent("trial.json"))
        #expect(store.load() == nil)
        let first = store.loadOrStart(now: start)
        #expect(first.start == start)
        // A later run finds the same start.
        #expect(store.loadOrStart(now: start.addingTimeInterval(3600)) == first)
        #expect(store.load() == first)

        let earlier = Trial(start: start.addingTimeInterval(-600))
        #expect(TrialStore.earliest(first, earlier) == earlier)
        #expect(TrialStore.earliest(nil, first) == first)
        #expect(TrialStore.earliest(nil, nil) == nil)
    }

    @Test func proCacheRoundTrips() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = ProCache(url: dir.appendingPathComponent("pro.json"))
        #expect(cache.load() == nil)
        let entry = ProCache.Entry(isPro: true, checked: start)
        cache.save(entry)
        #expect(cache.load() == entry)
    }

    @Test func memoryStoreTellsListenersAboutChanges() async {
        let store = MemoryProStore()
        #expect(await store.isPro() == false)
        let changes = store.changes()
        let heard = Task { () -> Bool in
            for await _ in changes { return true }
            return false
        }
        // Give the listener a moment to be in place, then flip.
        try? await Task.sleep(for: .milliseconds(20))
        store.set(isPro: true)
        #expect(await heard.value)
        #expect(await store.isPro())
        try? await store.restore()
        #expect(store.restores == 1)
    }
}
