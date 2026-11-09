import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// Home's "Your keyboard" card (features/home-and-welcome): every theme in a sideways
/// row, the effect presets in a second row that each play their own effect, the height,
/// and a link to the full Appearance page. Changes go to the keyboard in every app at
/// once. The keyboard to try them on is the dock at the bottom of Home (`KeyboardDock`).
/// The welcome wizard's Make it yours step uses the same rows (`showsHeight: false`).
struct YourKeyboardCard: View {
    @Bindable var model: AppModel
    var showsHeight = true
    /// Opens Settings → Appearance; nil hides the link (the wizard).
    var moreStyling: (() -> Void)?
    /// Opens Pro (from the note while a Pro look is being tried).
    var openPro: () -> Void
    /// An effect was picked: play it on the keys.
    var played: () -> Void = {}
    /// Counted as `home.style_changed` on Home (the wizard counts its own).
    var counts = true

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if model.isPreviewingLook {
                    HStack(spacing: Theme.Space.s) {
                        Text("Trying a Pro look on this keyboard. Your keyboard keeps Classic and Calm.")
                            .font(.sw(.small))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Get Pro", action: openPro).buttonStyle(.small)
                        Button {
                            model.stopPreview()
                        } label: {
                            Image(systemName: "xmark").font(.footnote.weight(.heavy)).foregroundStyle(Theme.muted)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop trying")
                    }
                    .padding(Theme.Space.s)
                    .background(Theme.sun.opacity(0.28), in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                } else if !model.entitlement.allows(.styles) {
                    Text("Pro looks are resting. Tap one to try it on the keyboard here.")
                        .font(.sw(.small))
                        .padding(Theme.Space.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.sun.opacity(0.28), in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                }
                label("Theme")
                ThemeRow(model: model, picked: { if counts { model.homeStyleChanged("theme") } })
                    .bleeds()
                label("Effects")
                EffectRow(model: model, played: {
                    played()
                    if counts { model.homeStyleChanged("effects") }
                })
                .bleeds()
                if showsHeight {
                    SettingsSlider("Height", value: Binding(get: { model.keyboardSettings.keyboardHeight }, set: { value in
                        model.keyboardSettings.keyboardHeight = value
                    }), in: KeyboardSettings.heightRange, step: 0.05, low: "Shorter", high: "Taller",
                    valueText: "\(Int((model.keyboardSettings.heightScale * 100).rounded()))%")
                }
                if let moreStyling {
                    Button(action: moreStyling) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("More styling").font(.system(.body, design: .rounded, weight: .bold))
                                Text("Your own themes, flow levels, guesses bar, haptics")
                                    .font(.sw(.small)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.heavy)).foregroundStyle(Theme.muted)
                        }
                        .padding(Theme.Space.m)
                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.footnote, design: .rounded, weight: .black))
            .foregroundStyle(Theme.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The themes, built in then the person's own, sideways. With Pro off a Pro theme is
/// tried on the practice keyboard only (`AppModel.tryTheme`).
struct ThemeRow: View {
    @Bindable var model: AppModel
    var picked: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pro = model.entitlement.allows(.styles)
        let shown = model.demoSettings.chosenTheme
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Space.s) {
                    ForEach(KeyboardTheme.builtIn + model.keyboardSettings.customThemes, id: \.id) { theme in
                        let locked = !pro && !theme.isFree
                        Button {
                            if locked {
                                model.tryTheme(theme.id)
                            } else {
                                model.tryTheme(nil)
                                model.chooseTheme(theme.id)
                            }
                            picked()
                        } label: {
                            ThemeCard(theme: theme, dark: scheme == .dark, selected: shown.id == theme.id, locked: locked,
                                      fill: Theme.ink.opacity(0.07))
                                .frame(width: 140)
                        }
                        .buttonStyle(CardPressStyle())
                        .id(theme.id)
                        .accessibilityLabel("\(theme.name) theme" + (theme.isFree ? "" : ", Pro"))
                        .accessibilityHint(locked ? "Tries it on the keyboard here" : "")
                        .accessibilityAddTraits(shown.id == theme.id ? .isSelected : [])
                    }
                }
                .padding(.vertical, 3)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Theme.Space.l, for: .scrollContent)
            // The picked one in view when the screen opens.
            .onAppear { reader.scrollTo(shown.id, anchor: .center) }
        }
        .sensoryFeedback(.selection, trigger: shown.id)
    }
}

/// The effect presets, sideways, each card playing its own effect on one key, then Off.
/// With Pro off a Pro preset is tried on the practice keyboard only.
struct EffectRow: View {
    @Bindable var model: AppModel
    var played: () -> Void

    private enum Pick: Hashable { case preset(EffectsSettings.Preset), off }

    var body: some View {
        let pro = model.entitlement.allows(.effects)
        let demo = model.demoSettings
        let off = !demo.trails
        let current: EffectsSettings.Preset? = demo.activeEffects(allows: true)?.preset
        let picked: Pick? = off ? .off : current.map { .preset($0) }
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Space.s) {
                    ForEach(EffectsSettings.Preset.allCases, id: \.self) { preset in
                        let locked = !pro && preset != .calm
                        Button {
                            if locked {
                                model.tryEffects(.preset(preset))
                            } else {
                                model.tryEffects(nil)
                                model.keyboardSettings.trails = true
                                model.chooseEffects(.preset(preset))
                            }
                            played()
                        } label: {
                            EffectCard(look: .init(preset), name: preset.name, selected: picked == .preset(preset), pro: preset != .calm)
                        }
                        .buttonStyle(CardPressStyle())
                        .id(Pick.preset(preset))
                        .accessibilityLabel("\(preset.name) effects" + (preset == .calm ? "" : ", Pro"))
                        .accessibilityHint(locked ? "Tries it on the keyboard here" : "")
                        .accessibilityAddTraits(picked == .preset(preset) ? .isSelected : [])
                    }
                    Button {
                        model.tryEffects(nil)
                        model.keyboardSettings.trails = false
                        played()
                    } label: {
                        EffectCard(look: .off, name: "Off", selected: off, pro: false)
                    }
                    .buttonStyle(CardPressStyle())
                    .id(Pick.off)
                    .accessibilityLabel("Effects off")
                    .accessibilityAddTraits(off ? .isSelected : [])
                }
                .padding(.vertical, 3)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Theme.Space.l, for: .scrollContent)
            .onAppear { if let picked { reader.scrollTo(picked, anchor: .center) } }
        }
        .sensoryFeedback(.selection, trigger: picked)
    }
}

extension View {
    /// A sideways row inside a `Card` runs to the card's edges and is clipped there,
    /// with its first card lined up with the rest of the card's content.
    func bleeds() -> some View {
        padding(.horizontal, -Theme.Space.l)
    }
}

/// One effect preset in small: a key in the middle that the effect taps and swipes
/// across, again and again, so the presets can be told apart at a glance (Gabriel,
/// 9 Nov 2026). Drawn with SwiftUI, a sketch of what the keyboard's own effects do;
/// picking one plays the real thing on the docked keyboard. Still under Reduce Motion
/// and Low Power Mode; only cards on screen draw.
struct EffectCard: View {
    enum Look {
        case calm, arcade, glitch, rainbow, space, zen, sugar, off

        init(_ preset: EffectsSettings.Preset) {
            switch preset {
            case .calm: self = .calm
            case .arcade: self = .arcade
            case .glitch: self = .glitch
            case .rainbow: self = .rainbow
            case .space: self = .space
            case .zen: self = .zen
            case .sugarRush: self = .sugar
            }
        }

        var tint: Color {
            switch self {
            case .calm: Theme.left
            case .arcade: Color(red: 1, green: 0.18, blue: 0.67)
            case .glitch: Color(red: 0.48, green: 0.38, blue: 1)
            case .rainbow: Color(red: 1, green: 0.62, blue: 0.11)
            case .space: Color(red: 0.36, green: 0.42, blue: 1)
            case .zen: Theme.mint
            case .sugar: Color(red: 1, green: 0.44, blue: 0.71)
            case .off: Theme.muted
            }
        }
    }

    var look: Look
    var name: String
    var selected: Bool
    var pro: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One loop: the tap at the start, the swipe in the middle.
    private static let loop: Double = 1.6

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(paused: reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled || look == .off)) { context in
                let t = reduceMotion ? 0.25 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop)
                ZStack {
                    Canvas { canvas, size in draw(&canvas, size: size, t: t) }
                    key(t: t)
                }
            }
            .frame(width: 104, height: 70)
            .background(look.tint.opacity(look == .space ? 0.85 : 0.3), in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.sm + 3, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 3)
                    .padding(-4)
            }
            HStack(spacing: 4) {
                Text(name).font(.system(.subheadline, design: .rounded, weight: .heavy)).lineLimit(1)
                if pro { ProBadge() }
            }
        }
        .padding(4)
    }

    /// The little key, squeezed by the tap (and jolted by Glitch).
    private func key(t: Double) -> some View {
        let press: CGFloat = t < 0.18 ? CGFloat(1 - sin(t / 0.18 * .pi) * 0.14) : 1
        let jolt: CGFloat = look == .glitch && t < 0.2 ? (t < 0.07 ? 3 : t < 0.14 ? -3 : 0) : 0
        return Text("a")
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .frame(width: 32, height: 36)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
            .scaleEffect(press)
            .offset(x: jolt)
            .opacity(look == .off ? 0.7 : 1)
    }

    private func draw(_ canvas: inout GraphicsContext, size: CGSize, t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let tint = look.tint
        switch look {
        case .off:
            return
        case .space:
            // A few stars twinkling behind.
            for i in 0..<7 {
                let x = CGFloat((i * 37) % max(Int(size.width), 1)) + 4, y = CGFloat((i * 23) % max(Int(size.height), 1)) + 4
                let twinkle = 0.3 + 0.7 * abs(sin(t * 4 + Double(i) * 1.7))
                canvas.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(.white.opacity(twinkle)))
            }
        default:
            break
        }
        // The tap: a ring (calm, zen, rainbow) or a burst (arcade, space, sugar).
        let tapLife = min(t / (look == .zen ? 1.1 : 0.65), 1)
        if tapLife < 1 {
            switch look {
            case .calm, .zen, .rainbow, .glitch:
                let radius = CGFloat((look == .zen ? 8 : 14) + tapLife * (look == .zen ? 18 : 28))
                let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                let color: Color = look == .rainbow ? Color(hue: t / Self.loop, saturation: 0.85, brightness: 1) : tint
                canvas.stroke(ring, with: .color(color.opacity(1 - tapLife)), lineWidth: look == .zen ? 2 : 3)
            case .arcade, .space, .sugar:
                for i in 0..<12 {
                    let angle = Double(i) / 12 * 2 * .pi + 0.4
                    let distance = 10 + tapLife * 34
                    let x = center.x + CGFloat(cos(angle) * distance), y = center.y + CGFloat(sin(angle) * distance + tapLife * tapLife * 8)
                    let color: Color = switch look {
                    case .arcade: Color(hue: Double(i) / 12, saturation: 0.9, brightness: 1)
                    case .sugar: [Color(red: 1, green: 0.44, blue: 0.71), Color(red: 1, green: 0.7, blue: 0.85), Theme.sun][i % 3]
                    default: Color(red: 1, green: 0.91, blue: 0.54)
                    }
                    let dot = look == .sugar ? heart(at: CGPoint(x: x, y: y), size: 5) : Path(CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
                    canvas.fill(dot, with: .color(color.opacity(1 - tapLife)))
                }
            case .off:
                break
            }
        }
        // Glitch: split colour bars tearing across for a moment.
        if look == .glitch, t < 0.26 {
            canvas.fill(Path(CGRect(x: center.x - 30, y: center.y - 9, width: 42, height: 3)), with: .color(Color(red: 1, green: 0.18, blue: 0.67)))
            canvas.fill(Path(CGRect(x: center.x - 16, y: center.y + 6, width: 46, height: 2)), with: .color(Color(red: 0, green: 0.94, blue: 1)))
        }
        // The swipe: a trail across the card from 0.7 s to 1.3 s.
        if [.calm, .rainbow, .space, .sugar, .arcade, .zen].contains(look), t > 0.7, t < 1.5 {
            let head = min((t - 0.7) / 0.6, 1)
            let tail = max(head - 0.35, 0) + max(t - 1.3, 0) / 0.2 * 0.65
            guard tail < head else { return }
            var path = Path()
            let steps = 14
            for step in 0...steps {
                let k = tail + (head - tail) * Double(step) / Double(steps)
                let point = CGPoint(x: 8 + CGFloat(k) * (size.width - 16), y: size.height - 12 - CGFloat(sin(k * .pi) * 22))
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            let color: Color = [.rainbow, .arcade, .sugar].contains(look) ? Color(hue: (t * 0.6).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 1) : (look == .space ? .white : tint)
            canvas.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: look == .space ? 4 : 3, lineCap: .round, lineJoin: .round))
        }
    }

    private func heart(at point: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: point.x, y: point.y + size))
        path.addCurve(to: CGPoint(x: point.x, y: point.y - size * 0.4),
                      control1: CGPoint(x: point.x - size * 1.8, y: point.y - size * 0.2),
                      control2: CGPoint(x: point.x - size * 0.8, y: point.y - size * 1.6))
        path.addCurve(to: CGPoint(x: point.x, y: point.y + size),
                      control1: CGPoint(x: point.x + size * 0.8, y: point.y - size * 1.6),
                      control2: CGPoint(x: point.x + size * 1.8, y: point.y - size * 0.2))
        return path
    }
}
