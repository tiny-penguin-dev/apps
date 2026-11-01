import SquawkKit
import SwiftUI

/// The "Rings" card in Edit: the timeline, the two quick-add buttons and "More options".
struct RingsCard: View {
    @Binding var alarm: Alarm

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rings").font(Theme.label)
                RingTimeline(alarm: $alarm)
                HStack(spacing: 18) {
                    Button("+ Soft ring before") {
                        withAnimation(.spring(duration: 0.4, bounce: 0.4)) { alarm.addSoftRing() }
                        Telemetry.count("alarm.ring_added", ["kind": "soft"])
                    }
                    Button("+ Loud ring after") {
                        withAnimation(.spring(duration: 0.4, bounce: 0.4)) { alarm.addLoudRing() }
                        Telemetry.count("alarm.ring_added", ["kind": "loud"])
                    }
                }
                .buttonStyle(LinkButtonStyle())
                Divider()
                NavigationLink {
                    MoreOptionsView(alarm: $alarm)
                } label: {
                    HStack {
                        Text("More options").font(Theme.label)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.muted)
                    }
                    .contentShape(Rectangle())
                }
            }
        }
    }
}

/// Every ring in time order. Tap one to change it.
struct RingTimeline: View {
    @Binding var alarm: Alarm

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(alarm.sortedRings) { ring in
                NavigationLink {
                    RingDetail(alarm: $alarm, ringID: ring.id)
                } label: {
                    RingRow(ring: ring, wake: alarm.time)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.4), value: alarm.rings)
    }
}

/// One ring: a colored dot, "6:50 · Nudge" and "10 min before".
struct RingRow: View {
    var ring: Ring
    var wake: TimeOfDay

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(ring.color.color).frame(width: 14, height: 14)
            Text(ring.summary(wake: wake))
                .font(.system(.body, design: .rounded, weight: .bold))
                .lineLimit(1)
            Spacer()
            Text(ring.offsetText)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(ring.color.color.opacity(0.14), in: Capsule())
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Screen 6: any number of rings, and wake-up checks.
struct MoreOptionsView: View {
    @Binding var alarm: Alarm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rings").font(Theme.label)
                        Text("Each ring can have its own time, sound, color and name.")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        RingTimeline(alarm: $alarm)
                        NavigationLink {
                            RingDetail(alarm: $alarm, ringID: nil)
                        } label: {
                            Text("+ Add a ring")
                        }
                        .buttonStyle(LinkButtonStyle())
                    }
                }
                ChecksCard(alarm: $alarm)
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("More options")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Change one ring: when, sound, color and name. With no ring id, it adds a new ring
/// 15 minutes after the last one.
struct RingDetail: View {
    @Binding var alarm: Alarm
    @State var ringID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("When").font(Theme.label)
                        Stepper(value: ring.offsetMinutes, in: Alarm.ringRange, step: 5) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alarm.time.adding(minutes: current.offsetMinutes).full)
                                    .font(.system(.title2, design: .rounded, weight: .black))
                                    .monospacedDigit()
                                Text(current.offsetText)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        NavigationLink {
                            SoundPicker(soundID: ring.soundID)
                        } label: {
                            HStack {
                                Text("Sound").font(Theme.label)
                                Spacer()
                                Text(current.sound.name).font(Theme.body).foregroundStyle(Theme.muted)
                                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.muted)
                            }
                            .contentShape(Rectangle())
                        }
                        Divider()
                        HStack {
                            Text("Color").font(Theme.label)
                            Spacer()
                            ForEach(RingColor.allCases, id: \.self) { color in
                                Button {
                                    ring.color.wrappedValue = color
                                } label: {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 30, height: 30)
                                        .overlay(Circle().stroke(Theme.ink, lineWidth: current.color == color ? 3 : 0))
                                }
                                .buttonStyle(SquishStyle())
                                .accessibilityLabel(color.name)
                                .accessibilityAddTraits(current.color == color ? .isSelected : [])
                            }
                        }
                        Divider()
                        HStack {
                            Text("Name").font(Theme.label)
                            TextField("Optional", text: name)
                                .multilineTextAlignment(.trailing)
                                .font(Theme.body)
                        }
                    }
                }

                if alarm.rings.count > 1 {
                    Button("Remove this ring", role: .destructive) {
                        if let ringID { alarm.rings.removeAll { $0.id == ringID } }
                        dismiss()
                    }
                    .font(Theme.label)
                    .foregroundStyle(Theme.coral)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Ring")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: addIfNew)
    }

    private var current: Ring {
        alarm.rings.first { $0.id == ringID } ?? alarm.rings[0]
    }

    /// A binding to this ring inside the alarm.
    private var ring: Binding<Ring> {
        Binding(
            get: { current },
            set: { newValue in
                guard let index = alarm.rings.firstIndex(where: { $0.id == newValue.id }) else { return }
                alarm.rings[index] = newValue
            }
        )
    }

    private var name: Binding<String> {
        Binding(
            get: { current.name ?? "" },
            set: { ring.name.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private func addIfNew() {
        guard ringID == nil else { return }
        let last = alarm.rings.map(\.offsetMinutes).max() ?? 0
        let new = Ring(offsetMinutes: min(last + 15, Alarm.ringRange.upperBound), color: .mint)
        alarm.rings.append(new)
        ringID = new.id
        Telemetry.count("alarm.ring_added", ["kind": "custom"])
    }
}

extension RingColor {
    var color: Color { Color(hex: hex) }

    var name: String {
        switch self {
        case .sunrise: "Sunrise"
        case .sun: "Sun"
        case .coral: "Coral"
        case .mint: "Mint"
        }
    }
}

extension LocalDate {
    /// "today", "tomorrow", or the weekday ("Tuesday").
    var morningName: String {
        let today = LocalDate(Date())
        if self == today { return "today" }
        if self == today.adding(days: 1) { return "tomorrow" }
        return weekday().full
    }
}

extension String {
    /// "tomorrow" → "Tomorrow".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

#Preview {
    NavigationStack {
        MoreOptionsView(alarm: .constant(Alarm(rings: [Ring(), Ring(offsetMinutes: -10, color: .sun)])))
    }
}
