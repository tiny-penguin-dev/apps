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
/// get brightness and warmth sliders with a glow that follows them.
struct HomeThingEditor: View {
    var kind: HomeAction.Kind
    /// The thing being changed, or nil for a new one.
    var existing: HomeAction?
    var offsetMinutes: Int = 0
    var onSave: (HomeAction) -> Void

    @Environment(HomeAccess.self) private var home
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [HomeTarget] = []
    @State private var setting = HomeSetting(isOn: true, brightness: 50, warmth: 30, position: 100)
    @State private var started = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch kind {
                case .light: lightSettings
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

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(Theme.label)
                Spacer()
                Text(text).font(Theme.label).monospacedDigit()
            }
            Slider(value: value, in: range).tint(Theme.accent)
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
        if kind == .light {
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
                ThingIcon(kind: .home(kind))
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
        } else if let first = LightPicks.remembered(kind, in: available) {
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
        case .plug, .scene:
            final = HomeSetting(isOn: setting.isOn)
        case .blinds:
            final = HomeSetting(isOn: true, position: setting.position ?? 100)
        }
        var action = existing ?? HomeAction(offsetMinutes: offsetMinutes, kind: kind, targets: [])
        action.targets = selected
        action.setting = final
        LightPicks.remember(kind, selected)
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
