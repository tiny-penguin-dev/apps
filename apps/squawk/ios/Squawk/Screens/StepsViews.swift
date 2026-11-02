import SquawkKit
import SwiftUI

/// The small rounded icon for one thing a step does: a ring, lights, a scene, a plug,
/// blinds or the wake-up check (features/steps/FEATURE.md, `ThingRow`).
struct ThingIcon: View {
    enum Kind {
        case ring, check
        case home(HomeAction.Kind)
    }

    var kind: Kind
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch kind {
        case .ring: "bell.fill"
        case .check: "checkmark"
        case .home(let kind): kind.symbol
        }
    }

    private var tint: Color {
        switch kind {
        case .ring: Theme.accent
        case .check: Theme.mint
        case .home(.light): Theme.sun
        case .home(.scene): Color(light: 0x5B7BD6, dark: 0x9DB4FF)
        case .home: Theme.ink
        }
    }
}

extension HomeAction.Kind {
    var symbol: String {
        switch self {
        case .light: "lightbulb.fill"
        case .scene: "sparkles"
        case .plug: "powerplug.fill"
        case .blinds: "blinds.horizontal.open"
        }
    }
}

/// One thing in a step: its icon, name and a detail, like "Bedroom lamp · 50% · warm".
struct ThingRow: View {
    var kind: ThingIcon.Kind
    var name: String
    var detail: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ThingIcon(kind: kind)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Text("\(Text(name).bold())\(Text(detail.isEmpty ? "" : " · \(detail)").foregroundStyle(Theme.muted))")
                .font(.system(.subheadline, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// One step on the timeline: its time and "10 min before" on the left, what happens on
/// the right. The wake-up step has an orange outline and shows the wake-up check.
struct StepCard: View {
    var step: AlarmStep
    var wake: TimeOfDay
    var checks: [WakeUpCheck] = []

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(wake.adding(minutes: step.offsetMinutes).short)
                    .bigNumberFont(22)
                Text(step.offsetText)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .frame(minWidth: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(step.rings) { ring in
                    ThingRow(kind: .ring, name: ring.name ?? ring.sound.name)
                }
                ForEach(step.actions) { action in
                    ThingRow(kind: .home(action.kind), name: action.name, detail: action.detail)
                }
                if step.isWakeUp {
                    ForEach(checks) { check in
                        ThingRow(kind: .check, name: check.kind.title, detail: check.place)
                    }
                }
                if step.rings.isEmpty, step.actions.isEmpty, !step.isWakeUp {
                    Text("Nothing yet").font(Theme.body).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if step.isWakeUp {
                RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.accent, lineWidth: 3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Every step of an alarm, top to bottom, joined by a sunrise-colored line.
struct StepTimeline<Row: View>: View {
    var alarm: Alarm
    @ViewBuilder var row: (AlarmStep) -> Row

    var body: some View {
        VStack(spacing: 10) {
            ForEach(alarm.steps) { step in
                row(step)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .background(alignment: .leading) {
            if alarm.steps.count > 1 {
                LinearGradient(colors: [Theme.sun, Theme.accent, Theme.coral], startPoint: .top, endPoint: .bottom)
                    .frame(width: 3)
                    .clipShape(Capsule())
                    .padding(.vertical, 24)
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.35), value: alarm.steps)
    }
}

#Preview("Steps") {
    var alarm = Alarm()
    alarm.addSoftRing()
    alarm.addSunrise(lights: [HomeTarget(id: UUID(), name: "Bedroom lamp")])
    alarm.checks = [WakeUpCheck(kind: .tag, place: "Bathroom mirror")]
    return ScrollView {
        StepTimeline(alarm: alarm) { step in
            StepCard(step: step, wake: alarm.time, checks: alarm.checks)
        }
        .padding()
    }
    .background(Theme.background)
}
