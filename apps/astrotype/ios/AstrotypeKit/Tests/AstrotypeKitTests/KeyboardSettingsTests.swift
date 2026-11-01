import Foundation
import Testing
@testable import AstrotypeCore

@Suite struct KeyboardSettingsTests {
    @Test func defaultsMatchTheDesign() {
        let settings = KeyboardSettings()
        #expect(settings.autospace)
        #expect(settings.autospaceDelay == 0.9)
        #expect(settings.trails)
        #expect(settings.composerSettings().autospaceDelay == 0.9)
    }

    @Test func autospaceOffMeansNoDelay() {
        var settings = KeyboardSettings()
        settings.autospace = false
        #expect(settings.composerSettings().autospaceDelay == nil)
        var base = Composer.Settings()
        base.autoCapitalize = false
        let applied = settings.composerSettings(from: base)
        #expect(applied.autospaceDelay == nil)
        #expect(!applied.autoCapitalize)
    }

    @Test func theDelayIsKeptInRange() {
        var settings = KeyboardSettings()
        settings.autospaceDelay = 3
        #expect(settings.composerSettings().autospaceDelay == 1.5)
        settings.autospaceDelay = 0.05
        #expect(settings.composerSettings().autospaceDelay == 0.1)
    }

    @Test func olderSettingsKeepTheirDefaultsForNewKeys() throws {
        let older = Data(#"{"version":1,"autospace":false,"autospaceDelay":1.1,"trails":true}"#.utf8)
        let read = try JSONDecoder().decode(KeyboardSettings.self, from: older)
        #expect(!read.autospace)
        #expect(read.autospaceDelay == 1.1)
        #expect(read.spaceSlide)
        #expect(read.backspaceSwipe)
        #expect(!read.splitOnWide)
    }

    @Test func settingsRoundTripThroughAStore() throws {
        var settings = KeyboardSettings()
        settings.autospace = false
        settings.autospaceDelay = 1.3
        settings.trails = false
        settings.backspaceSwipe = false
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(KeyboardSettings.self, from: data) == settings)

        let memory = MemorySettingsStore()
        #expect(memory.load() == nil)
        memory.save(settings)
        #expect(memory.load() == settings)

        let defaults = UserDefaults(suiteName: "AstrotypeKitTests.settings")!
        defaults.removePersistentDomain(forName: "AstrotypeKitTests.settings")
        let store = UserDefaultsSettingsStore(defaults: defaults, key: "test")
        #expect(store.load() == nil)
        store.save(settings)
        #expect(store.load() == settings)
        defaults.removePersistentDomain(forName: "AstrotypeKitTests.settings")
    }
}
