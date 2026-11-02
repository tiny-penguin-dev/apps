import SquawkKit
import SwiftUI

/// The small rounded icon for one thing a step does: a ring, lights, a scene, a plug,
/// blinds or the wake-up check (features/steps/FEATURE.md, `ThingRow`).
struct ThingIcon: View {
    enum Kind {
        case ring, check
        case home(HomeAction.Kind)
        /// "Home control": lights, plugs and blinds together.
        case devices
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
        case .devices: "house.fill"
        case .home(let kind): kind.symbol
        }
    }

    private var tint: Color {
        switch kind {
        case .ring: Theme.accent
        case .check: Theme.mint
        case .home(.light): Theme.sun
        case .home(.sunrise): Theme.accent
        case .home(.scene): Color(light: 0x5B7BD6, dark: 0x9DB4FF)
        case .home, .devices: Theme.ink
        }
    }
}

extension HomeAction.Kind {
    var symbol: String {
        switch self {
        case .light: "lightbulb.fill"
        case .scene: "play.rectangle.fill"
        case .plug: "powerplug.fill"
        case .blinds: "blinds.horizontal.open"
        case .sunrise: "sunrise.fill"
        }
    }
}

/// One thing in a step: its icon, name and a detail, like "Bedroom lamp · 50% · warm".
struct ThingRow: View {
    var kind: ThingIcon.Kind
    var name: String
    var detail: String = ""

    // The detail sits under the name, so long ones like "30 min · 5% → 100%" fit.
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ThingIcon(kind: kind)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).bold()
                if !detail.isEmpty {
                    Text(detail).foregroundStyle(Theme.muted)
                }
            }
            .font(.system(.subheadline, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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
                    if let sunrise = action.sunrise {
                        SunriseBars(sunrise: sunrise)
                            .frame(height: 18)
                            .padding(.leading, 34)
                    }
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

/// Sunrise lights as a strip of bars: one per light change, as tall as its brightness and
/// tinted its color, so you can see what the Home hub will do
/// (features/sunrise-lights/FEATURE.md, `SunriseBars`).
struct SunriseBars: View {
    var sunrise: Sunrise

    var body: some View {
        let points = sunrise.points
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(points, id: \.minutes) { point in
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 4, style: .continuous)
                        .fill(LightColor.color(warmth: point.setting.warmth ?? 50))
                        .frame(height: max(geo.size.height * Double(point.setting.brightness ?? 100) / 100, 3))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .animation(.spring(duration: 0.45, bounce: 0.4), value: sunrise)
        .accessibilityHidden(true)
    }
}

/// The color a light glows at a warmth (0 warm, 100 daylight), for previews.
enum LightColor {
    static func color(warmth: Int) -> Color {
        let warm = (r: 1.0, g: 0.67, b: 0.31), soft = (r: 1.0, g: 0.89, b: 0.66), day = (r: 0.93, g: 0.95, b: 1.0)
        let t = Double(min(max(warmth, 0), 100)) / 100
        func mix(_ a: (r: Double, g: Double, b: Double), _ c: (r: Double, g: Double, b: Double), _ u: Double) -> Color {
            Color(red: a.r + (c.r - a.r) * u, green: a.g + (c.g - a.g) * u, blue: a.b + (c.b - a.b) * u)
        }
        return t < 0.5 ? mix(warm, soft, t * 2) : mix(soft, day, (t - 0.5) * 2)
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
