import PenguinKit
import SquawkKit
import SwiftUI
import UIKit

/// Shows its content once Squawk can use the Home app, and the screens that get it there
/// first: "Squawk can turn on your lights" (asks for Home access), or "This needs a Home
/// hub" when timed steps can't work.
struct HomeGate<Content: View>: View {
    /// Timed steps need a hub; "When you're up" runs from the phone.
    var needsHub: Bool
    /// Where "When you're up" lives, offered when there's no hub.
    var onUseUpInstead: (() -> Void)?
    @ViewBuilder var content: Content

    @Environment(HomeAccess.self) private var home

    var body: some View {
        switch home.status {
        case .allowed where needsHub && !home.hasHub:
            NoHubView(onUseUpInstead: onUseUpInstead)
        case .allowed:
            content
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
        case .notAsked, .denied:
            HomeAccessView()
        }
    }
}

/// "Squawk can turn on your lights": what Squawk will do in your Home, then the iOS
/// prompt. Shown the first time someone adds a Home thing.
struct HomeAccessView: View {
    @Environment(HomeAccess.self) private var home
    @State private var glow = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.sun.opacity(0.3))
                    .frame(width: 190, height: 190)
                    .blur(radius: glow ? 24 : 12)
                    .scaleEffect(glow ? 1.08 : 0.92)
                PenguinView(mood: .awake).frame(width: 130, height: 130)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
            }
            Text(home.status == .denied ? "Squawk can't use your Home yet" : "Squawk can turn on your lights")
                .titleFont(28)
                .multilineTextAlignment(.center)
            Text(home.status == .denied
                 ? "Turn on Home for Squawk in Settings, then come back."
                 : "Squawk adds automations to your Home, named like \"Squawk · Wake up · 6:30\". Your Home hub runs them, so lights come on even while your phone sleeps.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer()
            if home.status == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(PillButtonStyle())
            } else {
                Button("Connect to Home") { Task { await home.requestAccess() } }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .padding(22)
        .readableWidth()
        .scrollsWhenTight()
        .background(Theme.background)
    }
}

/// "This needs a Home hub": why timed Home steps can't work, and what still does.
struct NoHubView: View {
    var onUseUpInstead: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            PenguinView(mood: .grumpy).frame(width: 130, height: 130)
            Text("This needs a Home hub")
                .titleFont(28)
                .multilineTextAlignment(.center)
            Text("To turn on lights while your phone sleeps, your home needs an Apple TV or HomePod set up as a Home hub. Your phone can't do it on its own.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Card {
                HStack(spacing: 12) {
                    ThingIcon(kind: .home(.blinds))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\"When you're up\" still works").font(Theme.label)
                        Text("Open the blinds or start the coffee once you're up.")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            Spacer()
            if let onUseUpInstead {
                Button("Set up \"When you're up\"", action: onUseUpInstead)
                    .buttonStyle(PillButtonStyle())
            }
        }
        .padding(22)
        .readableWidth()
        .scrollsWhenTight()
        .background(Theme.background)
    }
}

/// Pick what a Home thing does: which lights (or plugs, blinds, scene) and how. Lights
/// get brightness and warmth sliders with a glow that follows them; Sunrise lights get
/// a length and start and end sliders, with a preview that plays the sunrise.
struct HomeThingEditor: View {
    var kind: HomeAction.Kind
    /// The thing being changed, or nil for a new one.
    var existing: HomeAction?
    var offsetMinutes: Int = 0
    /// The alarm's wake-up time, so Sunrise lights can show "6:30 → 7:00".
    var wake: TimeOfDay?
    /// "+ Sunrise lights": the sunrise ends at the wake-up time, so its start moves with
    /// its length.
    var endsAtWakeUp = false
    var onSave: (HomeAction) -> Void

    @Environment(HomeAccess.self) private var home
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: [HomeTarget] = []
    @State private var setting = HomeSetting(isOn: true, brightness: 50, warmth: 30, position: 100)
    @State private var sunrise = Sunrise.standard
    @State private var started = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch kind {
                case .light: lightSettings
                case .sunrise: sunriseSettings
                case .plug: plugSettings
                case .blinds: blindsSettings
                case .scene: EmptyView()
                }
                if kind == .scene {
                    scenes
                } else {
                    devices
                }
            }
            .padding(20)
            .readableWidth()
        }
        .background(Theme.background)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: save)
                    .fontWeight(.heavy)
                    .disabled(selected.isEmpty)
            }
        }
        .onAppear(perform: start)
    }

    // MARK: Settings

    private var lightSettings: some View {
        VStack(spacing: 14) {
            LightGlow(brightness: setting.isOn ? (setting.brightness ?? 100) : 0, warmth: setting.warmth ?? 50)
                .frame(maxWidth: .infinity)
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("On", isOn: $setting.isOn).font(Theme.label).tint(Theme.mint)
                    if setting.isOn {
                        sliderRow("Brightness", value: binding(\.brightness, default: 100), range: 1...100, text: "\(setting.brightness ?? 100)%")
                        if selected.isEmpty || selectedDevices.contains(where: \.hasColor) {
                            sliderRow("Color", value: binding(\.warmth, default: 50), range: 0...100,
                                      text: HomeSetting.warmthName(setting.warmth ?? 50).capitalizedFirst)
                        }
                    }
                }
            }
        }
    }

    /// When the sunrise starts, in minutes from the wake-up time.
    private var sunriseStart: Int {
        if endsAtWakeUp, existing == nil { return -sunrise.minutes }
        return existing?.offsetMinutes ?? offsetMinutes
    }

    private var sunriseSettings: some View {
        let start = sunriseStart
        let end = start + sunrise.minutes
        let startTime = wake?.adding(minutes: start)
        let pairs = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        return VStack(alignment: .leading, spacing: 14) {
            SunrisePreview(sunrise: sunrise, start: startTime)
            Card {
                VStack(spacing: 12) {
                    HStack {
                        roundButton("minus", label: "5 minutes shorter") { changeLength(by: -5) }
                        VStack(spacing: 2) {
                            Text("\(sunrise.minutes) min").bigNumberFont(30)
                            Text(timing(start: start, end: end))
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        roundButton("plus", label: "5 minutes longer") { changeLength(by: 5) }
                    }
                    SunriseBars(sunrise: sunrise).frame(height: 64)
                    HStack {
                        Text(startTime?.short ?? "Start")
                        Spacer()
                        Text("\(sunrise.points.count) light changes")
                        Spacer()
                        Text(wake?.adding(minutes: end).short ?? "End")
                    }
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
                }
            }
            sectionLabel("Brightness")
            Card {
                pairs {
                    sliderRow("Start", value: sunriseBinding(\.startBrightness), range: 1...100,
                              text: "\(sunrise.startBrightness)%", label: "Start brightness")
                    sliderRow("End", value: sunriseBinding(\.endBrightness), range: 1...100,
                              text: "\(sunrise.endBrightness)%", label: "End brightness")
                }
            }
            if selected.isEmpty || selectedDevices.contains(where: \.hasColor) {
                sectionLabel("Color")
                Card {
                    pairs {
                        sliderRow("Start", value: sunriseBinding(\.startWarmth), range: 0...100,
                                  text: HomeSetting.warmthName(sunrise.startWarmth).capitalizedFirst, label: "Start color")
                        sliderRow("End", value: sunriseBinding(\.endWarmth), range: 0...100,
                                  text: HomeSetting.warmthName(sunrise.endWarmth).capitalizedFirst, label: "End color")
                    }
                }
            }
            Text("Your Home hub changes the lights every \(changeEvery) min, in small steps. Lights without color only get brighter.")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.ice.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// "6:30 → 7:00 · ends at wake-up".
    private func timing(start: Int, end: Int) -> String {
        let ending = end == 0 ? "ends at wake-up" : end < 0 ? "ends \(-end) min before" : "ends \(end) min after"
        guard let wake else { return ending }
        return "\(wake.adding(minutes: start).short) → \(wake.adding(minutes: end).short) · \(ending)"
    }

    private var changeEvery: Int {
        let points = sunrise.points
        guard points.count > 1 else { return sunrise.minutes }
        return max(1, Int((Double(sunrise.minutes) / Double(points.count - 1)).rounded()))
    }

    private func changeLength(by delta: Int) {
        let next = sunrise.minutes + delta
        guard Sunrise.minutesRange.contains(next) else { return }
        // A sunrise that starts at a step must still start within the alarm's range.
        if endsAtWakeUp, existing == nil, !Alarm.ringRange.contains(-next) { return }
        sunrise.minutes = next
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.black))
                .frame(width: 48, height: 48)
                .background(Theme.background, in: Circle())
        }
        .buttonStyle(SquishStyle())
        .foregroundStyle(Theme.ink)
        .accessibilityLabel(label)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(.footnote, design: .rounded, weight: .heavy))
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)
            .padding(.leading, 4)
    }

    private func sunriseBinding(_ path: WritableKeyPath<Sunrise, Int>) -> Binding<Double> {
        Binding(
            get: { Double(sunrise[keyPath: path]) },
            set: { sunrise[keyPath: path] = Int($0.rounded()) }
        )
    }

    private var plugSettings: some View {
        Card {
            Picker("Turn it", selection: $setting.isOn) {
                Text("On").tag(true)
                Text("Off").tag(false)
            }
            .pickerStyle(.segmented)
        }
    }

    private var blindsSettings: some View {
        Card {
            sliderRow("Open", value: binding(\.position, default: 100), range: 0...100,
                      text: HomeAction(kind: .blinds, targets: [], setting: setting).detail.capitalizedFirst)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String, label: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(Theme.label)
                Spacer()
                Text(text).font(Theme.label).monospacedDigit()
            }
            .accessibilityHidden(true)
            Slider(value: value, in: range)
                .tint(Theme.accent)
                .accessibilityLabel(label ?? title)
                .accessibilityValue(text)
        }
    }

    private func binding(_ path: WritableKeyPath<HomeSetting, Int?>, default value: Int) -> Binding<Double> {
        Binding(
            get: { Double(setting[keyPath: path] ?? value) },
            set: { setting[keyPath: path] = Int($0.rounded()) }
        )
    }

    // MARK: Picking

    private var available: [HomeDevice] { home.home?.devices(kind) ?? [] }
    private var selectedDevices: [HomeDevice] { available.filter { d in selected.contains { $0.id == d.id } } }

    @ViewBuilder private var devices: some View {
        if available.isEmpty {
            Text("No \(kind.title.lowercased()) in your Home app yet. Add them there, then come back.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
        }
        let rooms = Dictionary(grouping: available, by: \.target.room)
        ForEach(rooms.keys.sorted(), id: \.self) { room in
            Text(room.isEmpty ? "Other" : room)
                .font(.system(.footnote, design: .rounded, weight: .heavy))
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
                .padding(.leading, 4)
            ForEach(rooms[room] ?? []) { device in
                pickRow(device.target, detail: device.abilities, multiple: true)
            }
        }
        if kind.deviceKind == .light {
            Text("Lights come from your Home app. Pick several to set them together.")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private var scenes: some View {
        let scenes = home.home?.scenes ?? []
        if scenes.isEmpty {
            Text("No scenes in your Home app yet. Make one there, like \"Good morning\", then come back.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
        }
        ForEach(scenes, id: \.id) { scene in
            pickRow(scene, detail: "", multiple: false)
        }
    }

    private func pickRow(_ target: HomeTarget, detail: String, multiple: Bool) -> some View {
        let isOn = selected.contains { $0.id == target.id }
        return Button {
            if multiple {
                if isOn { selected.removeAll { $0.id == target.id } } else { selected.append(target) }
            } else {
                selected = [target]
            }
        } label: {
            HStack(spacing: 12) {
                ThingIcon(kind: .home(kind.deviceKind))
                Text(target.name).font(Theme.label)
                Spacer()
                Text(detail)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Theme.accent : Theme.muted.opacity(0.4))
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isOn ? Theme.accent : .clear, lineWidth: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Saving

    private func start() {
        guard !started else { return }
        started = true
        if let existing {
            selected = existing.targets
            setting = existing.setting
            sunrise = existing.sunrise ?? .standard
        } else if let first = LightPicks.remembered(kind.deviceKind, in: available) {
            selected = first
        }
        if kind == .plug, existing == nil { setting = HomeSetting(isOn: true) }
    }

    private func save() {
        var final = setting
        switch kind {
        case .light:
            if !selectedDevices.contains(where: \.dimmable) { final.brightness = nil }
            if !selectedDevices.contains(where: \.hasColor) { final.warmth = nil }
            final.position = nil
        case .sunrise:
            final = HomeSetting(isOn: true)
        case .plug, .scene:
            final = HomeSetting(isOn: setting.isOn)
        case .blinds:
            final = HomeSetting(isOn: true, position: setting.position ?? 100)
        }
        var action = existing ?? HomeAction(offsetMinutes: offsetMinutes, kind: kind, targets: [])
        action.targets = selected
        action.setting = final
        action.sunrise = kind == .sunrise ? sunrise : nil
        if kind == .sunrise, endsAtWakeUp, existing == nil { action.offsetMinutes = -sunrise.minutes }
        LightPicks.remember(kind.deviceKind, selected)
        onSave(action)
        if existing == nil { Telemetry.count("step.added", ["kind": kind.rawValue]) }
        dismiss()
    }
}

/// Remembers the lights (or plugs, blinds) picked last time, so the next one starts
/// with them. Sunrise uses this too.
enum LightPicks {
    private static func key(_ kind: HomeAction.Kind) -> String { "home.last.\(kind.rawValue)" }

    static func remember(_ kind: HomeAction.Kind, _ targets: [HomeTarget]) {
        UserDefaults.standard.set(targets.map(\.id.uuidString), forKey: key(kind))
    }

    /// The remembered ones that are still in the home, or nil.
    static func remembered(_ kind: HomeAction.Kind, in devices: [HomeDevice]) -> [HomeTarget]? {
        let ids = Set(UserDefaults.standard.stringArray(forKey: key(kind)) ?? [])
        let found = devices.filter { ids.contains($0.id.uuidString) }.map(\.target)
        return found.isEmpty ? nil : found
    }
}

/// A small sky and lamp that show the sunrise. "Preview" plays it in a few seconds, with
/// the clock and brightness ticking; with Reduce Motion it shows the end.
struct SunrisePreview: View {
    var sunrise: Sunrise
    /// When it starts, for the clock. Nil hides the time.
    var start: TimeOfDay?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 1.0

    var body: some View {
        SunriseSky(sunrise: sunrise, start: start, progress: progress)
            .frame(height: 180)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    guard !reduceMotion else { progress = 1; return }
                    progress = 0
                    withAnimation(.linear(duration: 4)) { progress = 1 }
                } label: {
                    Label("Preview", systemImage: "play.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.card, in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(SquishStyle())
                .padding(12)
                .accessibilityLabel("Preview the sunrise")
            }
    }
}

/// The sky and lamp at one moment of the sunrise. Animatable, so the clock and glow
/// follow the preview frame by frame.
private struct SunriseSky: View, Animatable {
    var sunrise: Sunrise
    var start: TimeOfDay?
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let setting = sunrise.setting(at: progress)
        let brightness = Double(setting.brightness ?? 100) / 100
        let glow = LightColor.color(warmth: setting.warmth ?? 50)
        let minute = Int((progress * Double(sunrise.minutes)).rounded())
        ZStack {
            Theme.ice
            LinearGradient(
                colors: [Color(hex: 0x172239).opacity(0.75 * (1 - progress)), glow.opacity(0.2 + 0.6 * progress)],
                startPoint: .top, endPoint: .bottom
            )
            Circle()
                .fill(glow.opacity(0.25 + 0.6 * brightness))
                .frame(width: 96, height: 96)
                .shadow(color: glow.opacity(brightness), radius: 8 + 36 * brightness)
            ThingIcon(kind: .home(.light), size: 50)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text([start?.adding(minutes: minute).short, "\(setting.brightness ?? 100)%"].compactMap { $0 }.joined(separator: " · "))
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.card.opacity(0.75), in: Capsule())
                .padding(12)
        }
        .accessibilityHidden(true)
    }
}

/// A lamp in a soft glow that gets brighter, and warmer or cooler, with the sliders.
struct LightGlow: View {
    var brightness: Int
    var warmth: Int

    var body: some View {
        let color = warmth < 34 ? Color(hex: 0xFFB45C) : warmth < 67 ? Color(hex: 0xFFE2A8) : Color(hex: 0xF4F7FF)
        let b = Double(brightness) / 100
        ZStack {
            Circle()
                .fill(color.opacity(0.25 + 0.6 * b))
                .frame(width: 120, height: 120)
                .shadow(color: color.opacity(b), radius: 10 + 40 * b)
            ThingIcon(kind: .home(.light), size: 56)
        }
        .frame(height: 170)
        .animation(.easeOut(duration: 0.25), value: brightness)
        .animation(.easeOut(duration: 0.25), value: warmth)
        .accessibilityHidden(true)
    }
}
