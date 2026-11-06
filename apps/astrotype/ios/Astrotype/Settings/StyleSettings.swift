import AstrotypeCore
import AstrotypeUI
import SwiftUI
import UIKit

/// The pages under Settings → Appearance (features/customization): General, Styling,
/// a theme's editor, and Effects. Classic and Calm are free; the rest is Pro, and a Pro
/// choice opens the Pro screen until then.
enum AppearancePage: Hashable {
    case general, styling, effects
    case theme(String)
}

// MARK: The hub

/// Settings → Appearance: a live keyboard in the chosen look, and the three pages.
struct AppearanceSettings: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]

    var body: some View {
        let settings = model.keyboardSettings
        let theme = settings.style(allows: model.entitlement.allows(.styles))
        StylePreview(theme: theme, appearance: settings.keyAppearance,
                     effects: settings.activeEffects(allows: model.entitlement.allows(.effects)))
        GroupFootnote("Try it: type on the keyboard above.")
        SettingsGroup {
            SettingsLink("General", subtitle: "Height \(Int((settings.heightScale * 100).rounded()))%, guesses bar, haptics, split",
                         symbol: "slider.horizontal.3", tint: Theme.slate) { path.append(.appearance(.general)) }
            SettingsLink("Styling", subtitle: "\(theme.name) · \(appearanceName(settings.keyAppearance))",
                         symbol: "paintpalette", tint: Theme.left) { path.append(.appearance(.styling)) }
            SettingsLink("Effects", subtitle: effectsSummary, symbol: "sparkles", tint: Theme.sun) {
                path.append(.appearance(.effects))
            }
        }
        .padding(.top, Theme.Space.s)
        if !model.entitlement.allows(.styles) {
            GroupFootnote("Classic and Calm are free. Every other theme and effect is in Astrotype Pro.")
        }
    }

    private var effectsSummary: String {
        let settings = model.keyboardSettings
        guard settings.trails else { return "Off" }
        let effects = settings.activeEffects(allows: model.entitlement.allows(.effects)) ?? .calm
        let name = effects.preset?.name ?? "Your mix"
        return effects.flow ? "\(name), builds up as you type" : name
    }
}

/// A page under Appearance, with its title.
struct AppearancePageView: View {
    var page: AppearancePage
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]
    @State private var burst = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Text(title).font(.sw(.title)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if page == .effects, model.keyboardSettings.trails {
                        Button("Play a burst") { burst += 1 }.buttonStyle(.small)
                    }
                }
                .padding(.vertical, Theme.Space.s)
                switch page {
                case .general: GeneralAppearanceSettings(model: model, path: $path)
                case .styling: StylingSettings(model: model, path: $path)
                case .effects: EffectsPage(model: model, path: $path, burst: burst)
                case .theme(let id): ThemeEditor(id: id, model: model, path: $path)
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var title: String {
        switch page {
        case .general: "General"
        case .styling: "Styling"
        case .effects: "Effects"
        case .theme: "Edit theme"
        }
    }
}

private func appearanceName(_ appearance: KeyAppearance) -> String {
    switch appearance {
    case .system: "Follows the phone"
    case .light: "Always light"
    case .dark: "Always dark"
    }
}

private extension RGBColor {
    var color: Color { Color(uiColor: uiColor) }
}

// MARK: Styling

/// Light or dark, the themes, and the person's own.
private struct StylingSettings: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]
    @Environment(\.colorScheme) private var scheme

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: Theme.Space.s)]

    var body: some View {
        let settings = model.keyboardSettings
        let pro = model.entitlement.allows(.styles)
        let shown = settings.style(allows: pro)
        StylePreview(theme: shown, appearance: settings.keyAppearance,
                     effects: settings.activeEffects(allows: model.entitlement.allows(.effects)))

        SectionLabel("Light or dark").padding(.top, Theme.Space.m)
        Picker("Light or dark", selection: $model.keyboardSettings.keyAppearance) {
            Text("System").tag(KeyAppearance.system)
            Text("Light").tag(KeyAppearance.light)
            Text("Dark").tag(KeyAppearance.dark)
        }
        .pickerStyle(.segmented)
        GroupFootnote("Every theme has a light look and a dark one. System follows the phone.")

        SectionLabel("Themes").padding(.top, Theme.Space.m)
        LazyVGrid(columns: columns, spacing: Theme.Space.s) {
            ForEach(KeyboardTheme.builtIn, id: \.id) { theme in
                card(theme, selected: shown.id == theme.id, locked: !pro && !theme.isFree)
            }
        }

        SectionLabel("Your themes", pro: true).padding(.top, Theme.Space.m)
        if !settings.customThemes.isEmpty {
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(settings.customThemes, id: \.id) { theme in
                    card(theme, selected: shown.id == theme.id, locked: !pro)
                }
            }
        }
        SettingsGroup {
            SettingsLink("New theme", subtitle: "Starts from \(shown.name). Pick every colour, the spacing and the borders.",
                         symbol: "plus", tint: Theme.accent) {
                guard pro else { path.append(.pro); return }
                let id = model.keyboardSettings.addTheme(from: shown)
                model.chooseTheme(id)
                path.append(.appearance(.theme(id)))
            }
            if pro, shown.isCustom {
                SettingsLink("Edit \(shown.name)", symbol: "slider.horizontal.3", tint: Theme.left) {
                    path.append(.appearance(.theme(shown.id)))
                }
            }
        }
        if !pro {
            Button("See Pro") { path.append(.pro) }.buttonStyle(.small).padding(.top, Theme.Space.s)
        }
    }

    private var isDark: Bool {
        switch model.keyboardSettings.keyAppearance {
        case .system: scheme == .dark
        case .light: false
        case .dark: true
        }
    }

    private func card(_ theme: KeyboardTheme, selected: Bool, locked: Bool) -> some View {
        Button {
            if locked { path.append(.pro) } else { model.chooseTheme(theme.id) }
        } label: {
            ThemeCard(theme: theme, dark: isDark, selected: selected, locked: locked)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(theme.name + (locked ? ", Pro" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A theme in small: its background, three rows of keys in its colours, and its name.
private struct ThemeCard: View {
    var theme: KeyboardTheme
    var dark: Bool
    var selected: Bool
    var locked: Bool

    var body: some View {
        let colors = theme.colors(dark: dark)
        let shape = theme.shape.clamped
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: max(2, shape.gap / 2)) {
                ForEach([7, 6, 5], id: \.self) { count in
                    HStack(spacing: max(2, shape.gap / 2)) {
                        ForEach(0..<count, id: \.self) { index in
                            let edge = count == 5 && (index == 0 || index == count - 1)
                            RoundedRectangle(cornerRadius: shape.corner / 2, style: .continuous)
                                .fill((edge ? colors.functionKey : colors.key).color.opacity(shape.opacity))
                                .overlay {
                                    RoundedRectangle(cornerRadius: shape.corner / 2, style: .continuous)
                                        .strokeBorder(colors.border.color, lineWidth: shape.borderWidth / 2)
                                }
                                .overlay {
                                    if shape.showsLetters, !edge {
                                        Circle().fill(colors.letters.color).frame(width: 3, height: 3)
                                    }
                                }
                        }
                    }
                }
            }
            .padding(6)
            .frame(height: 64)
            .background(colors.background.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 6) {
                Circle().fill(colors.left.color).frame(width: 8, height: 8)
                Circle().fill(colors.right.color).frame(width: 8, height: 8)
                Text(theme.name).font(.sw(.body)).lineLimit(1)
                Spacer(minLength: 0)
                if locked { ProBadge() }
            }
        }
        .padding(Theme.Space.s)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2.5)
        }
        .opacity(locked ? 0.75 : 1)
    }
}

/// Cards squeeze a little when pressed.
private struct CardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: Theme editor

/// One of the person's themes: its name, both looks' colours, the shape and the letters.
private struct ThemeEditor: View {
    var id: String
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]
    @State private var editingDark = false
    @State private var sameInBoth = false
    @State private var confirmingDelete = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let current = model.keyboardSettings.customThemes.first(where: { $0.id == id }) {
            editor(current)
        } else {
            GroupFootnote("This theme was deleted.")
        }
    }

    @ViewBuilder private func editor(_ current: KeyboardTheme) -> some View {
        StylePreview(theme: current, appearance: editingDark ? .dark : .light,
                     effects: model.keyboardSettings.activeEffects(allows: model.entitlement.allows(.effects)))

        SettingsGroup {
            SettingsRow("Name", symbol: "textformat", tint: Theme.slate) {
                TextField("Name", text: Binding(get: { current.name }, set: { name in edit { $0.name = name } }))
                    .multilineTextAlignment(.trailing)
                    .font(.sw(.body))
                    .submitLabel(.done)
            }
        }
        .padding(.top, Theme.Space.s)

        SectionLabel("Colours").padding(.top, Theme.Space.m)
        Picker("Look", selection: $editingDark) {
            Text("Light look").tag(false)
            Text("Dark look").tag(true)
        }
        .pickerStyle(.segmented)
        SettingsGroup {
            SettingsToggle("Same colours in both", subtitle: "Changes go to the light and dark looks at once",
                           symbol: "circle.lefthalf.filled", tint: Theme.slate, isOn: $sameInBoth)
            ForEach(KeyColors.Field.allCases, id: \.self) { field in
                SettingsRow(fieldName(field), symbol: fieldSymbol(field), tint: Theme.left) {
                    ColorPicker(fieldName(field), selection: colour(field, in: current), supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }
        let colors = current.colors(dark: editingDark)
        if colors.lettersHardToRead {
            Label("Hard to read: the letters are close to the keys' colour.", systemImage: "exclamationmark.triangle.fill")
                .font(.sw(.small)).foregroundStyle(Theme.sun)
                .padding(.horizontal, Theme.Space.xs)
        }
        swatches(current)

        SectionLabel("Shape").padding(.top, Theme.Space.m)
        SettingsGroup {
            SettingsSlider("Spacing", value: shape(\.gap, current), in: KeyShape.gapRange, step: 1, low: "Tight", high: "Airy",
                           valueText: "\(Int(current.shape.gap)) pt")
            SettingsSlider("Corners", value: shape(\.corner, current), in: KeyShape.cornerRange, step: 0.5, low: "Square",
                           high: "Round", valueText: "\(Int(current.shape.corner.rounded())) pt")
            SettingsSlider("See-through", value: shape(\.opacity, current), in: KeyShape.opacityRange, step: 0.05,
                           low: "Glassy", high: "Solid", valueText: "\(Int((current.shape.opacity * 100).rounded()))%")
            SettingsRow("Borders", symbol: "square.dashed", tint: Theme.slate) {
                Picker("Borders", selection: shape(\.border, current)) {
                    Text("None").tag(KeyShape.Border.none)
                    Text("Thin").tag(KeyShape.Border.thin)
                    Text("Bold").tag(KeyShape.Border.bold)
                }
                .labelsHidden()
            }
            SettingsRow("Shadow", symbol: "shadow", tint: Theme.slate) {
                Picker("Shadow", selection: shape(\.shadow, current)) {
                    Text("None").tag(KeyShape.Shadow.none)
                    Text("Soft").tag(KeyShape.Shadow.soft)
                    Text("Raised").tag(KeyShape.Shadow.raised)
                }
                .labelsHidden()
            }
        }
        GroupFootnote("Spacing only changes how keys are drawn. Each key still answers touches right up to its neighbours, so typing feels the same.")

        SectionLabel("Letters").padding(.top, Theme.Space.m)
        SettingsGroup {
            SettingsRow("Font", symbol: "textformat.alt", tint: Theme.right) {
                Picker("Font", selection: shape(\.font, current)) {
                    Text("Classic").tag(KeyShape.Font.classic)
                    Text("Rounded").tag(KeyShape.Font.rounded)
                    Text("Mono").tag(KeyShape.Font.mono)
                }
                .labelsHidden()
            }
            SettingsToggle("Show letters", subtitle: "Off draws blank keys, for people who know where everything is",
                           symbol: "character", tint: Theme.right, isOn: shape(\.showsLetters, current))
        }

        SettingsGroup {
            Button { confirmingDelete = true } label: {
                SettingsRow("Delete theme", titleColor: Theme.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Theme.Space.m)
        .confirmationDialog("Delete \(current.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.keyboardSettings.removeTheme(id: id)
                if !path.isEmpty { path.removeLast() }
            }
        } message: {
            Text("The keyboard goes back to Classic if this theme is on.")
        }
    }

    /// Quick colours for the keys and the background of the look being edited.
    private func swatches(_ current: KeyboardTheme) -> some View {
        let palette = editingDark ? KeyboardTheme.darkSwatches : KeyboardTheme.lightSwatches
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach([KeyColors.Field.key, .background, .letters], id: \.self) { field in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text(fieldName(field)).font(.sw(.small)).foregroundStyle(Theme.muted).frame(width: 78, alignment: .leading)
                        ForEach(palette, id: \.self) { swatch in
                            let on = current.colors(dark: editingDark)[field] == swatch
                            Button { setColour(swatch, field) } label: {
                                Circle().fill(swatch.color)
                                    .frame(width: 26, height: 26)
                                    .overlay { Circle().strokeBorder(Theme.line, lineWidth: 1) }
                                    .overlay { Circle().strokeBorder(Theme.accent, lineWidth: on ? 2.5 : 0).padding(-3) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(fieldName(field)) \(swatch.hexString)")
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.top, Theme.Space.s)
    }

    private func edit(_ change: (inout KeyboardTheme) -> Void) {
        guard var theme = model.keyboardSettings.customThemes.first(where: { $0.id == id }) else { return }
        change(&theme)
        model.keyboardSettings.updateTheme(theme)
    }

    private func setColour(_ rgb: RGBColor, _ field: KeyColors.Field) {
        edit { theme in
            if sameInBoth || editingDark { theme.dark[field] = rgb }
            if sameInBoth || !editingDark { theme.light[field] = rgb }
        }
    }

    private func colour(_ field: KeyColors.Field, in current: KeyboardTheme) -> Binding<Color> {
        Binding(get: { current.colors(dark: editingDark)[field].color },
                set: { setColour(RGBColor(UIColor($0)), field) })
    }

    private func shape<T>(_ keyPath: WritableKeyPath<KeyShape, T>, _ current: KeyboardTheme) -> Binding<T> {
        Binding(get: { current.shape[keyPath: keyPath] }, set: { value in edit { $0.shape[keyPath: keyPath] = value } })
    }

    private func fieldName(_ field: KeyColors.Field) -> String {
        switch field {
        case .background: "Background"
        case .key: "Keys"
        case .functionKey: "Shift, ⌫, return"
        case .letters: "Letters"
        case .border: "Borders"
        case .left: "Left thumb"
        case .right: "Right thumb"
        case .accent: "Accent"
        }
    }

    private func fieldSymbol(_ field: KeyColors.Field) -> String {
        switch field {
        case .background: "rectangle.fill"
        case .key: "square.fill"
        case .functionKey: "shift"
        case .letters: "character"
        case .border: "square.dashed"
        case .left: "hand.point.left"
        case .right: "hand.point.right"
        case .accent: "sparkle"
        }
    }
}

// MARK: Effects

/// Taps, letters, flashes, trails, and flow with its levels.
private struct EffectsPage: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]
    var burst: Int

    private var pro: Bool { model.entitlement.allows(.effects) }

    var body: some View {
        let settings = model.keyboardSettings
        let effects = settings.effects
        StylePreview(theme: settings.style(allows: model.entitlement.allows(.styles)), appearance: settings.keyAppearance,
                     effects: settings.activeEffects(allows: pro), burst: burst)
        SettingsGroup {
            SettingsToggle("Effects", subtitle: "Taps, trails and flashes that show which thumb did what. Off saves battery.",
                           symbol: "sparkles", tint: Theme.sun, isOn: $model.keyboardSettings.trails)
        }
        .padding(.top, Theme.Space.s)

        if settings.trails {
            SectionLabel("Presets").padding(.top, Theme.Space.m)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s) {
                    ForEach(EffectsSettings.Preset.allCases, id: \.self) { preset in
                        chip(preset.name, on: effects.preset == preset, locked: !pro && preset != .calm) {
                            model.chooseEffects(.preset(preset))
                        }
                    }
                    if effects.preset == nil {
                        chip("Your mix", on: true, locked: false) {}
                    }
                }
                .padding(.vertical, 2)
            }

            SectionLabel("Each touch").padding(.top, Theme.Space.m)
            SettingsGroup {
                pickerRow("Tap", symbol: "hand.tap", value: binding(\.tap), options: EffectsSettings.Tap.allCases) { tapName($0) }
                pickerRow("Letters", symbol: "textformat", value: binding(\.letters), options: EffectsSettings.Letters.allCases) {
                    lettersName($0)
                }
                pickerRow("Key flash", symbol: "light.max", value: binding(\.flash), options: EffectsSettings.Flash.allCases) {
                    flashName($0)
                }
                pickerRow("Trail", symbol: "scribble", value: binding(\.trail), options: EffectsSettings.Trail.allCases) {
                    $0.rawValue.capitalized
                }
            }
            GroupFootnote("Jelly, Wave, Glitch and Liquid bend the letters with Metal. In Low Power Mode they pop instead.")

            SectionLabel("Flow").padding(.top, Theme.Space.m)
            SettingsGroup {
                SettingsToggle("Build up as I type", subtitle: "Fast words without fixes make the effects grow. A pause or a delete calms them down.",
                               symbol: "flame", tint: Theme.sun, isOn: flowBinding)
                if effects.flow {
                    SettingsSlider("Builds", value: binding(\.build), in: EffectsSettings.buildRange, step: 0.05,
                                   low: "Slowly", high: "Quickly", valueText: buildName(effects.build))
                    SettingsToggle("1 · Waddle", subtitle: "A combo count and bigger taps, about \(words(.waddle, effects)) words",
                                   tint: Theme.left, isOn: binding(\.combo))
                    SettingsToggle("2 · Toboggan", subtitle: "Comets and sparks, about \(words(.toboggan, effects)) words",
                                   tint: Theme.right, isOn: binding(\.comets))
                    SettingsToggle("3 · Blizzard", subtitle: "Falling \(effects.fall.rawValue) and glowing keys, about \(words(.blizzard, effects)) words",
                                   tint: Theme.ice, isOn: binding(\.falling))
                    if effects.falling {
                        pickerRow("Falling", symbol: "snowflake", value: binding(\.fall), options: EffectsSettings.Fall.allCases) {
                            $0.rawValue.capitalized
                        }
                    }
                    SettingsToggle("4 · Aurora", subtitle: "The sky behind the keys, about \(words(.aurora, effects)) words",
                                   tint: Theme.mint, isOn: binding(\.skyOn))
                    if effects.skyOn {
                        pickerRow("Sky", symbol: "sparkles", value: binding(\.sky), options: EffectsSettings.Sky.allCases) {
                            $0 == .ice ? "Ice" : $0.rawValue.capitalized
                        }
                    }
                }
            }
            if !pro {
                GroupFootnote("Calm is free: a ring on each tap, a line for each swipe. Everything else is in Astrotype Pro.")
                Button("See Pro") { path.append(.pro) }.buttonStyle(.small)
            }
        }
    }

    /// Sets an effect, or opens Pro when the result isn't free and Pro isn't on.
    private func binding<T>(_ keyPath: WritableKeyPath<EffectsSettings, T>) -> Binding<T> {
        Binding(get: { model.keyboardSettings.effects[keyPath: keyPath] }, set: { value in
            var effects = model.keyboardSettings.effects
            effects[keyPath: keyPath] = value
            if pro || effects.isFree { model.keyboardSettings.effects = effects } else { path.append(.pro) }
        })
    }

    private var flowBinding: Binding<Bool> {
        Binding(get: { model.keyboardSettings.effects.flow }, set: { on in
            var effects = model.keyboardSettings.effects
            effects.flow = on
            if pro || effects.isFree { model.chooseEffects(effects) } else { path.append(.pro) }
        })
    }

    private func pickerRow<T: Hashable>(_ title: String, symbol: String, value: Binding<T>, options: [T],
                                        name: @escaping (T) -> String) -> some View {
        SettingsRow(title, symbol: symbol, tint: Theme.sun) {
            Picker(title, selection: value) {
                ForEach(options, id: \.self) { option in Text(name(option)).tag(option) }
            }
            .labelsHidden()
        }
    }

    private func chip(_ title: String, on: Bool, locked: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if locked { path.append(.pro) } else { action() }
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(.subheadline, design: .rounded, weight: .bold))
                if locked { ProBadge() }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(on ? Theme.accent : Theme.card, in: Capsule())
            .foregroundStyle(on ? Color.white : Theme.ink)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func words(_ level: FlowLevel, _ effects: EffectsSettings) -> Int {
        Int((level.words * effects.levelScale).rounded())
    }

    private func buildName(_ build: Double) -> String {
        build < 0.34 ? "Slowly" : build > 0.66 ? "Quickly" : "Steady"
    }

    private func tapName(_ tap: EffectsSettings.Tap) -> String {
        tap == .none ? "None" : tap.rawValue.capitalized
    }

    private func lettersName(_ letters: EffectsSettings.Letters) -> String {
        letters == .none ? "Still" : letters.rawValue.capitalized
    }

    private func flashName(_ flash: EffectsSettings.Flash) -> String {
        switch flash {
        case .thumb: "Thumb's colour"
        case .theme: "Theme's colour"
        case .off: "Off"
        }
    }
}

// MARK: The live preview

/// A real keyboard in a look, to type on: the keys, their effects and flow, over the
/// theme's background, with room above for the combo and the level pop.
struct StylePreview: UIViewRepresentable {
    var theme: KeyboardTheme
    var appearance: KeyAppearance
    var effects: EffectsSettings?
    /// Changed to play a fast run of words on the keys.
    var burst = 0

    func makeUIView(context: Context) -> StylePreviewView {
        let view = StylePreviewView()
        view.burst = burst
        return view
    }

    func updateUIView(_ view: StylePreviewView, context: Context) {
        view.apply(theme: theme, appearance: appearance, effects: effects)
        if burst != view.burst {
            view.burst = burst
            view.surface.playBurst()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: StylePreviewView, context: Context) -> CGSize? {
        let width = proposal.width ?? 360
        return CGSize(width: width, height: StylePreviewView.height(forWidth: width))
    }
}

final class StylePreviewView: UIView {
    static let top: CGFloat = 34
    let surface = KeySurfaceView()
    let hud = FlowHUDView()
    var burst = 0

    static func height(forWidth width: CGFloat) -> CGFloat {
        top + Layout.qwerty(width: max(width, 1)).height + 6
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = Theme.Radius.md
        layer.cornerCurve = .continuous
        clipsToBounds = true
        surface.backgroundColor = .clear
        addSubview(surface)
        addSubview(hud)
        surface.onFlow = { [weak self] state in
            guard let self else { return }
            hud.style = surface.style
            hud.state = state
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: StylePreviewView, _: UITraitCollection) in
            self.restyle()
        }
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(theme: KeyboardTheme, appearance: KeyAppearance, effects: EffectsSettings?) {
        surface.theme = theme
        surface.keyAppearance = appearance
        surface.effects = effects
        restyle()
    }

    private func restyle() {
        let style = KeyStyle(theme: surface.theme, appearance: surface.keyAppearance, traits: traitCollection)
        let background = style.isClassic ? Theme.ui(.kb).resolvedColor(with: UITraitCollection(userInterfaceStyle: style.isDark ? .dark : .light))
            : style.colors.background.uiColor
        UIView.transition(with: self, duration: 0.3, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.backgroundColor = background
        }
        hud.style = style
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0 else { return }
        if surface.layout.width != width { surface.layout = Layout.qwerty(width: width) }
        surface.frame = CGRect(x: 0, y: Self.top, width: width, height: surface.layout.height)
        hud.frame = CGRect(x: 0, y: 0, width: width, height: surface.frame.maxY)
        hud.keysTop = Self.top
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { surface.resetFlow() }
    }
}
