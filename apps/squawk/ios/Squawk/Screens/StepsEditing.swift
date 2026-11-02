import SquawkKit
import SwiftUI

/// The "Steps" part of the edit screen: the timeline (tap a step to change it), quick
/// adds, and the "When you're up" card.
struct StepsSection: View {
    @Binding var alarm: Alarm
    @Environment(ProModel.self) private var pro
    @State private var paywall: ProFeature?
    @State private var openStep: Int?
    @State private var sunrise = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Steps")
                .font(.system(.footnote, design: .rounded, weight: .heavy))
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
                .padding(.leading, 4)
            StepTimeline(alarm: alarm) { step in
                Button { openStep = step.offsetMinutes } label: {
                    StepCard(step: step, wake: alarm.time, checks: alarm.checks)
                }
                .buttonStyle(SquishStyle())
                .accessibilityHint("Change this step")
            }
            quickAdds
            UpCard(alarm: $alarm)
        }
        .navigationDestination(item: $openStep) { offset in
            StepDetailView(alarm: $alarm, offset: offset)
        }
        .navigationDestination(isPresented: $sunrise) {
            HomeGate(needsHub: true) {
                HomeThingEditor(kind: .sunrise, existing: nil, wake: alarm.time, endsAtWakeUp: true) { picked in
                    let sunrise = picked.sunrise ?? .standard
                    withAnimation(.spring(duration: 0.5, bounce: 0.35)) { alarm.addSunrise(lights: picked.targets, sunrise: sunrise) }
                    Telemetry.count("step.sunrise_added", ["minutes": String(sunrise.minutes)])
                }
            }
        }
        .proSheet($paywall)
    }

    private var quickAdds: some View {
        let ringsLocked = !pro.access.canAddRing(to: alarm)
        let homeLocked = !pro.access.allows(.home)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            if alarm.rings.count < 2 {
                QuickAdd(title: "+ Soft ring before", locked: ringsLocked) {
                    withAnimation(.spring(duration: 0.4, bounce: 0.4)) { alarm.addSoftRing() }
                    Telemetry.count("step.added", ["kind": "ring"])
                } onLocked: { paywall = .moreRings }
                QuickAdd(title: "+ Loud ring after", locked: ringsLocked) {
                    withAnimation(.spring(duration: 0.4, bounce: 0.4)) { alarm.addLoudRing() }
                    Telemetry.count("step.added", ["kind": "ring"])
                } onLocked: { paywall = .moreRings }
            }
            QuickAdd(title: "+ Sunrise lights", locked: homeLocked) { sunrise = true } onLocked: { paywall = .home }
            QuickAdd(title: "+ Add a step", locked: ringsLocked && homeLocked) {
                let offset = alarm.nextFreeStepOffset
                withAnimation(.spring(duration: 0.4, bounce: 0.4)) {
                    alarm.rings.append(Ring(offsetMinutes: offset, soundID: AlarmSound.soft.id, color: .sun))
                }
                Telemetry.count("step.added", ["kind": "ring"])
                openStep = offset
            } onLocked: { paywall = .moreRings }
        }
    }
}

/// A dashed "+" button for the quick adds, with a PRO tag when it needs Pro.
private struct QuickAdd: View {
    var title: String
    var locked: Bool
    var action: () -> Void
    var onLocked: () -> Void

    var body: some View {
        Button {
            if locked { onLocked() } else { action() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if locked { ProBadge() }
            }
            .font(.system(.subheadline, design: .rounded, weight: .heavy))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 46)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.muted.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle())
    }
}

/// "When you're up" on the edit screen: what runs when the morning ends.
private struct UpCard: View {
    @Binding var alarm: Alarm
    @Environment(ProModel.self) private var pro
    @State private var paywall: ProFeature?

    var body: some View {
        Group {
            if pro.access.allows(.home) || !alarm.upActions.isEmpty {
                NavigationLink {
                    UpActionsView(alarm: $alarm)
                } label: {
                    content
                }
            } else {
                Button { paywall = .home } label: { content }
            }
        }
        .buttonStyle(SquishStyle())
        .proSheet($paywall)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("When you're up").font(Theme.label)
                if !pro.access.allows(.home) { ProBadge() }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.muted)
            }
            if alarm.upActions.isEmpty {
                Text("Open the blinds or start the coffee when your morning ends.")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.leading)
            } else {
                ForEach(alarm.upActions) { action in
                    ThingRow(kind: .home(action.kind), name: action.name, detail: action.detail)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.sun.opacity(0.3), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .contentShape(Rectangle())
    }
}

/// One step: when it happens and everything it does. The wake-up step always rings and
/// holds the wake-up check.
struct StepDetailView: View {
    @Binding var alarm: Alarm
    @State var offset: Int
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var editing: HomeEditTarget?

    var body: some View {
        let step = alarm.step(at: offset) ?? AlarmStep(offsetMinutes: offset, rings: [], actions: [])
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("When").font(Theme.label)
                        if step.isWakeUp {
                            Text(alarm.time.full).bigNumberFont(34)
                            Text("Wake-up time. Change it on the edit screen.")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                        } else {
                            Stepper {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alarm.time.adding(minutes: offset).full).bigNumberFont(30)
                                    Text(step.offsetText)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(Theme.muted)
                                }
                            } onIncrement: {
                                move(by: 5)
                            } onDecrement: {
                                move(by: -5)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What happens").font(Theme.label)
                        ForEach(step.rings) { ring in
                            HStack {
                                NavigationLink {
                                    RingDetail(alarm: $alarm, ringID: ring.id)
                                } label: {
                                    ThingRow(kind: .ring, name: ring.name ?? ring.sound.name, detail: ring.color.name)
                                }
                                if alarm.rings.count > 1, !(step.isWakeUp && step.rings.count == 1) {
                                    removeButton("Remove \(ring.sound.name)") { alarm.rings.removeAll { $0.id == ring.id } }
                                }
                            }
                        }
                        ForEach(step.actions) { action in
                            HStack {
                                Button { editing = HomeEditTarget(kind: action.kind, existing: action) } label: {
                                    ThingRow(kind: .home(action.kind), name: action.name, detail: action.detail)
                                }
                                removeButton("Remove \(action.name)") { alarm.homeActions.removeAll { $0.id == action.id } }
                            }
                            if let sunrise = action.sunrise {
                                SunriseBars(sunrise: sunrise).frame(height: 22).padding(.leading, 34)
                                Text("Starts \(alarm.time.adding(minutes: offset).short), bright by \(alarm.time.adding(minutes: offset + sunrise.minutes).short). Moving this step moves the whole sunrise.")
                                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                                    .padding(.leading, 34)
                            }
                        }
                        if step.isWakeUp {
                            ForEach(alarm.checks) { check in
                                ThingRow(kind: .check, name: check.kind.title, detail: "set in More options")
                            }
                        }
                    }
                    .tint(Theme.ink)
                }

                Button { adding = true } label: {
                    Text("+ Add something")
                        .font(Theme.label)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Theme.muted.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        )
                }
                .buttonStyle(SquishStyle())

                if step.isWakeUp {
                    Text("The wake-up step always rings. Its ring comes back until you do the wake-up check.")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(12)
                        .background(Theme.ice.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Button("Remove step", role: .destructive) {
                        withAnimation { alarm.removeStep(at: offset) }
                        dismiss()
                    }
                    .font(Theme.label)
                    .foregroundStyle(Theme.coral)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .readableWidth()
        }
        .background(Theme.background)
        .navigationTitle(step.isWakeUp ? "Wake-up step" : "Step")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            AddThingSheet(timed: true) { choice in
                adding = false
                switch choice {
                case .ring:
                    alarm.rings.append(Ring(offsetMinutes: offset, soundID: AlarmSound.soft.id, color: offset < 0 ? .sun : .coral))
                    Telemetry.count("step.added", ["kind": "ring"])
                case .home(let kind):
                    editing = HomeEditTarget(kind: kind, existing: nil)
                case .devices:
                    editing = HomeEditTarget(kind: .light, existing: nil, anyDevice: true)
                }
            }
        }
        .navigationDestination(item: $editing) { target in
            HomeGate(needsHub: true) {
                HomeThingEditor(kind: target.kind, existing: target.existing, offsetMinutes: offset, wake: alarm.time, anyDevice: target.anyDevice) { action in
                    if let index = alarm.homeActions.firstIndex(where: { $0.id == action.id }) {
                        alarm.homeActions[index] = action
                    } else {
                        alarm.homeActions.append(action)
                    }
                }
            }
        }
    }

    private func removeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring) { action() }
        } label: {
            Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Moves this step 5 minutes, skipping the wake-up time.
    private func move(by delta: Int) {
        var next = offset + delta
        if next == 0 { next += delta }
        guard Alarm.ringRange.contains(next) else { return }
        alarm.moveStep(from: offset, to: next)
        offset = next
    }
}

/// Which Home thing the editor is showing.
struct HomeEditTarget: Identifiable, Hashable {
    var kind: HomeAction.Kind
    var existing: HomeAction?
    /// "Home devices": pick any light, plug, switch or blind, and the editor follows it.
    var anyDevice = false
    var id: String { "\(kind.rawValue)|\(existing?.id.uuidString ?? "new")|\(anyDevice)" }
}

/// "Add to this step": a ring, Sunrise lights, a scene, or Home devices (lights, plugs,
/// switches and blinds in one row, so the sheet stays short). Home things need Pro.
struct AddThingSheet: View {
    enum Choice { case ring, home(HomeAction.Kind), devices }

    /// False for "When you're up", which has no rings.
    var timed: Bool
    var onPick: (Choice) -> Void

    @Environment(ProModel.self) private var pro
    @State private var paywall: ProFeature?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timed ? "Add to this step" : "Add to \"When you're up\"")
                .font(.system(.title3, design: .rounded, weight: .black))
                .padding(.bottom, 8)
            let locked = !pro.access.allows(.home)
            if timed {
                row(.ring, "Ring", locked: false)
                // Sunrise lights take time, so they only fit a timed step.
                row(.home(.sunrise), HomeAction.Kind.sunrise.title, locked: locked)
            }
            row(.home(.scene), HomeAction.Kind.scene.title, locked: locked)
            row(.devices, "Home devices", subtitle: "Lights, plugs, switches and blinds", locked: locked)
        }
        .padding(22)
        .presentationDetents([.medium])
        .presentationBackground(Theme.background)
        .proSheet($paywall)
    }

    private func row(_ choice: Choice, _ title: String, subtitle: String? = nil, locked: Bool) -> some View {
        Button {
            if locked { paywall = .home } else { onPick(choice) }
        } label: {
            HStack(spacing: 12) {
                switch choice {
                case .ring: ThingIcon(kind: .ring)
                case .home(let kind): ThingIcon(kind: .home(kind))
                case .devices: ThingIcon(kind: .devices)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.label)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                if locked { ProBadge() }
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "When you're up": Home things that run when the morning ends. Runs from the phone,
/// so it works without a Home hub.
struct UpActionsView: View {
    @Binding var alarm: Alarm
    @State private var adding = false
    @State private var editing: HomeEditTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Runs when your morning ends: you finish the wake-up check, tap \"I'm up\", or open Squawk after the last ring.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.muted)
                if !alarm.upActions.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(alarm.upActions) { action in
                                HStack {
                                    Button { editing = HomeEditTarget(kind: action.kind, existing: action) } label: {
                                        ThingRow(kind: .home(action.kind), name: action.name, detail: action.detail)
                                    }
                                    .tint(Theme.ink)
                                    Button {
                                        withAnimation(.spring) { alarm.upActions.removeAll { $0.id == action.id } }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.muted)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(action.name)")
                                }
                            }
                        }
                    }
                }
                Button { adding = true } label: {
                    Text("+ Add something")
                        .font(Theme.label)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Theme.muted.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        )
                }
                .buttonStyle(SquishStyle())
                Text("This runs from your phone, so it works without a Home hub.")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(12)
                    .background(Theme.ice.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(20)
            .readableWidth()
        }
        .background(Theme.background)
        .navigationTitle("When you're up")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            AddThingSheet(timed: false) { choice in
                adding = false
                switch choice {
                case .ring: break
                case .home(let kind): editing = HomeEditTarget(kind: kind, existing: nil)
                case .devices: editing = HomeEditTarget(kind: .light, existing: nil, anyDevice: true)
                }
            }
        }
        .navigationDestination(item: $editing) { target in
            HomeGate(needsHub: false) {
                HomeThingEditor(kind: target.kind, existing: target.existing, anyDevice: target.anyDevice) { action in
                    if let index = alarm.upActions.firstIndex(where: { $0.id == action.id }) {
                        alarm.upActions[index] = action
                    } else {
                        alarm.upActions.append(action)
                    }
                }
            }
        }
    }
}
