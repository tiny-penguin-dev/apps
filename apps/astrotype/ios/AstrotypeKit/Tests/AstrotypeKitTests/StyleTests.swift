import Foundation
import Testing
@testable import AstrotypeCore

/// Themes, effects and flow (features/customization).
@Suite struct StyleTests {
    // MARK: Colours

    @Test func coloursReadAndWriteAsHex() throws {
        #expect(RGBColor(hex: "#139FB5") == RGBColor(hex: 0x139FB5))
        #expect(RGBColor(hex: "139fb5")?.hexString == "#139FB5")
        #expect(RGBColor(hex: "#12345") == nil)
        #expect(RGBColor(hex: "zzzzzz") == nil)
        let glass = RGBColor(hex: 0xFFFFFF, alpha: 0.5)
        let data = try JSONEncoder().encode([glass, .black])
        #expect(String(decoding: data, as: UTF8.self) == ##"["#FFFFFF@0.5","#000000"]"##)
        #expect(try JSONDecoder().decode([RGBColor].self, from: data) == [glass, .black])
    }

    @Test func contrastFollowsWCAG() {
        #expect(abs(RGBColor.white.contrast(with: .black) - 21) < 0.01)
        #expect(RGBColor.white.contrast(with: .white) == 1)
        #expect(RGBColor(hex: 0xEEEEEE).isHardToRead(on: .white))
        #expect(!RGBColor.black.isHardToRead(on: .white))
    }

    // MARK: Themes

    @Test func everyBuiltInThemeIsReadable() {
        #expect(KeyboardTheme.builtIn.count == 8)
        #expect(Set(KeyboardTheme.builtIn.map(\.id)).count == 8)
        for theme in KeyboardTheme.builtIn {
            #expect(!theme.light.lettersHardToRead, "\(theme.name) light")
            #expect(!theme.dark.lettersHardToRead, "\(theme.name) dark")
            #expect(!theme.isCustom)
        }
    }

    @Test func classicIsTodaysKeyboardAndFree() {
        let classic = KeyboardTheme.classic
        #expect(classic.isFree)
        #expect(classic.light.key == RGBColor(hex: 0xFFFFFF))
        #expect(classic.dark.background == RGBColor(hex: 0x1F1F1F))
        #expect(classic.shape == KeyShape())
        #expect(!KeyboardTheme.named("iceberg")!.isFree)
    }

    @Test func shapesKeepInRange() {
        let wild = KeyShape(gap: 40, corner: -3)
        #expect(wild.clamped.gap == 12)
        #expect(KeyShape(gap: 0).clamped.gap == 2)
        #expect(wild.clamped.corner == 0)
        var glass = KeyboardTheme.classic.dark
        glass.opacity = 0
        #expect(glass.keyOpacity == 0.3)
        #expect(KeyShape(border: .bold).borderWidth == 2)
    }

    @Test func seeThroughIsPerLook() throws {
        var theme = KeyboardTheme.classic.copy(id: "custom-1", name: "Mine")
        theme.light.opacity = 0.9
        theme.dark.opacity = 0.5
        let read = try JSONDecoder().decode(KeyboardTheme.self, from: JSONEncoder().encode(theme))
        #expect(read == theme)
        // Saved before: one see-through in the shape, for both looks.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(KeyboardTheme.classic)) as! [String: Any]
        var shape = json["shape"] as! [String: Any]
        shape["opacity"] = 0.6
        json["shape"] = shape
        for look in ["light", "dark"] {
            var colors = json[look] as! [String: Any]
            colors.removeValue(forKey: "opacity")
            json[look] = colors
        }
        let old = try JSONDecoder().decode(KeyboardTheme.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.light.opacity == 0.6)
        #expect(old.dark.opacity == 0.6)
        #expect(KeyboardTheme.classic.light.opacity == 1)
    }

    @Test func themesArePro() {
        var settings = KeyboardSettings()
        #expect(settings.style(allows: false) == .classic)
        settings.themeID = "tuxedo"
        #expect(settings.style(allows: true).id == "tuxedo")
        #expect(settings.style(allows: false) == .classic)
        #expect(settings.themeID == "tuxedo")
        settings.themeID = "gone"
        #expect(settings.chosenTheme == .classic)
    }

    @Test func peopleMakeEditAndDeleteThemes() {
        var settings = KeyboardSettings()
        settings.themeID = "krill"
        let id = settings.addTheme(from: settings.chosenTheme, now: Date(timeIntervalSince1970: 1))
        #expect(settings.themeID == id)
        #expect(settings.chosenTheme.name == "My theme")
        #expect(settings.chosenTheme.isCustom)
        #expect(settings.chosenTheme.light == KeyboardTheme.named("krill")!.light)
        var theme = settings.chosenTheme
        theme.light.key = RGBColor(hex: 0x123456)
        theme.shape.gap = 9
        settings.updateTheme(theme)
        #expect(settings.chosenTheme.light.key == RGBColor(hex: 0x123456))
        #expect(settings.style(allows: false) == .classic)
        settings.addTheme(from: .classic, now: Date(timeIntervalSince1970: 2))
        #expect(settings.chosenTheme.name == "My theme 2")
        settings.removeTheme(id: settings.themeID)
        #expect(settings.themeID == KeyboardTheme.classic.id)
        #expect(settings.customThemes.count == 1)
    }

    @Test func themesAndEffectsSync() throws {
        var settings = KeyboardSettings()
        settings.addTheme(from: KeyboardTheme.named("arcade")!)
        settings.keyAppearance = .dark
        settings.effects = .preset(.arcade)
        let read = try JSONDecoder().decode(KeyboardSettings.self, from: JSONEncoder().encode(settings))
        #expect(read == settings)
    }

    @Test func olderSettingsAreClassicAndCalm() throws {
        let older = Data(#"{"version":1,"trails":false}"#.utf8)
        let read = try JSONDecoder().decode(KeyboardSettings.self, from: older)
        #expect(read.themeID == "classic")
        #expect(read.keyAppearance == .system)
        #expect(read.effects == .calm)
        #expect(read.activeEffects(allows: true) == nil)
        // A newer effect this build doesn't know falls back, keeping the rest.
        let newer = Data(#"{"trails":true,"effects":{"tap":"lasers","trail":"comet"}}"#.utf8)
        let effects = try JSONDecoder().decode(KeyboardSettings.self, from: newer).effects
        #expect(effects.tap == .ring)
        #expect(effects.trail == .comet)
    }

    // MARK: Effects

    @Test func onlyCalmIsFree() {
        #expect(EffectsSettings.calm.isFree)
        var off = EffectsSettings.calm
        off.tap = .none
        off.trail = .none
        off.flash = .off
        #expect(off.isFree)
        for preset in EffectsSettings.Preset.allCases where preset != .calm {
            #expect(!EffectsSettings.preset(preset).isFree)
            #expect(EffectsSettings.preset(preset).preset == preset)
        }
        var settings = KeyboardSettings()
        settings.effects = .preset(.space)
        #expect(settings.activeEffects(allows: false) == .calm)
        #expect(settings.activeEffects(allows: true) == .preset(.space))
        settings.effects.letters = .glitch
        #expect(settings.effects.preset == nil)
        #expect(EffectsSettings.Letters.glitch.usesMetal)
        #expect(!EffectsSettings.Letters.pop.usesMetal)
        var flashy = EffectsSettings.calm
        flashy.flash = .candy
        #expect(!flashy.isFree)
    }

    @Test func theLivelyPresetsAreAllDifferent() {
        let lively = EffectsSettings.Preset.allCases.filter { $0 != .calm }
        #expect(lively.map(\.name) == ["Arcade", "Glitch", "Rainbow", "Space", "Zen", "Sugar Rush"])
        let looks = lively.map { EffectsSettings.preset($0) }
        #expect(Set(looks).count == lively.count)
        #expect(Set(looks.map(\.sky)).count == lively.count)
        #expect(Set(looks.map(\.fall)).count == lively.count)
        #expect(looks.allSatisfy { $0.flow && $0.topLevel == 4 })
        // Glitch letters moved from Arcade to Glitch.
        #expect(EffectsSettings.preset(.glitch).letters == .glitch)
        #expect(EffectsSettings.preset(.arcade).letters != .glitch)
    }

    @Test func effectsFromTheOldPresetsStillRead() throws {
        // Sparkle and Aurora went, but what they set is still a valid mix.
        let aurora = Data(#"{"tap":"stars","trail":"comet","letters":"liquid","flow":true,"fall":"snow","sky":"aurora"}"#.utf8)
        let effects = try JSONDecoder().decode(EffectsSettings.self, from: aurora)
        #expect(effects.sky == .aurora)
        #expect(effects.preset == nil)
        let sky = Data(#"{"sky":"blackHole","fall":"static"}"#.utf8)
        let read = try JSONDecoder().decode(EffectsSettings.self, from: sky)
        #expect(read.sky == .blackHole)
        #expect(read.fall == .static)
    }

    @Test func theTopLevelFollowsTheSwitches() {
        var effects = EffectsSettings.preset(.space)
        #expect(effects.topLevel == 4)
        effects.skyOn = false
        #expect(effects.topLevel == 3)
        effects.falling = false
        effects.comets = false
        #expect(effects.topLevel == 1)
        effects.flow = false
        #expect(effects.topLevel == 0)
        effects.build = 0
        #expect(effects.levelScale == 1.5)
        effects.build = 1
        #expect(effects.levelScale == 0.5)
    }

    // MARK: Flow

    @Test func fastWordsClimbTheLevels() {
        var flow = FlowMeter()
        var t = 0.0
        for _ in 0..<4 { flow.word(at: t); t += 1 }
        // 1 + 1.5 * 3 = 5.5: Waddle.
        #expect(flow.score == 5.5)
        #expect(flow.level() == .waddle)
        #expect(flow.combo == 4)
        for _ in 0..<30 { flow.word(at: t); t += 1 }
        #expect(flow.level() == .aurora)
        #expect(flow.level(cap: 2) == .toboggan)
        #expect(flow.progress(cap: 4) == 1)
    }

    @Test func slowWordsCountOnce() {
        var flow = FlowMeter()
        flow.word(at: 0)
        flow.word(at: 2)
        // No quick bonus, and the first word drained away during the 1 s after the rest.
        #expect(flow.score == 1)
        #expect(flow.combo == 1)
    }

    @Test func aDeleteTakesSomeBack() {
        var flow = FlowMeter()
        for i in 0..<10 { flow.word(at: Double(i) * 0.5) }
        let before = flow.score
        flow.delete(at: 5)
        #expect(flow.score == before - 3)
        #expect(flow.combo == 7)
        var small = FlowMeter()
        small.word(at: 0)
        small.delete(at: 0.5)
        #expect(small.score == 0)
        #expect(small.combo == 0)
    }

    @Test func aPauseDrainsIt() {
        var flow = FlowMeter()
        for i in 0..<10 { flow.word(at: Double(i)) }
        let full = flow.score   // 14.5
        flow.tick(now: 9 + 1)
        #expect(flow.score == full)
        #expect(flow.combo == 10)
        flow.tick(now: 9 + 1.5)
        #expect(flow.combo == 10)
        flow.tick(now: 9 + 3)
        // Two seconds of draining: the combo drops 2 and the score 2 × 1.45.
        #expect(flow.combo == 8)
        #expect(abs(flow.score - (full - 2.9)) < 1e-9)
        flow.tick(now: 9 + 3)
        #expect(flow.combo == 8)
        flow.tick(now: 9 + 11)
        #expect(flow.combo == 0)
        #expect(flow.score == 0)
        flow.tick(now: 100)
        #expect(flow.score == 0)
        #expect(flow.combo == 0)
        #expect(flow.level() == .calm)
    }

    @Test func theBuildScalesTheWordCounts() {
        var flow = FlowMeter()
        for i in 0..<4 { flow.word(at: Double(i)) }   // 5.5
        #expect(flow.level(scale: 1.5) == .calm)
        #expect(flow.level(scale: 0.5) == .waddle)
        #expect(abs(flow.progress(scale: 1.5) - 5.5 / 7.5) < 1e-9)
    }
}
