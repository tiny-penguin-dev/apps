import PenguinKit
import SquawkKit
import SwiftUI
import UIKit

/// Screen 4: the sleeping penguin and the alarm cards.
struct HomeView: View {
    @Environment(AlarmsModel.self) private var model
    @State private var editing: EditTarget?
    @State private var showGallery = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(greeting)
                        .font(Theme.title(32))
                        .padding(.top, 8)
                    banners
                    SleepCard(nextRing: model.nextRing(), anyOn: model.alarms.contains(where: \.isOn))
                        .onLongPressGesture(minimumDuration: 1.2) { showGallery = true }
                    if model.alarms.isEmpty {
                        EmptyAlarms { editing = .new }
                    } else {
                        ForEach(model.sortedAlarms) { alarm in
                            AlarmCard(alarm: alarm) { editing = .existing(alarm) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            Button { editing = .new } label: {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Theme.accent).shadow(color: .black.opacity(0.18), radius: 0, y: 4))
            }
            .buttonStyle(SquishStyle())
            .padding(24)
            .accessibilityLabel("Add alarm")
        }
        .sheet(item: $editing) { target in
            EditAlarmView(alarm: target.alarm, isNew: target.isNew)
        }
        .sheet(isPresented: $showGallery) {
            NavigationStack {
                PenguinGallery().toolbar { Button("Done") { showGallery = false } }
            }
        }
    }

    @ViewBuilder private var banners: some View {
        switch model.access {
        case .denied:
            Banner(text: "Alarms are off in Settings, so I can't ring. Turn them on in Settings > Squawk.",
                   button: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        case .notAsked:
            Banner(text: "Squawk can't ring until you allow alarms.", button: "Allow") {
                Task { await model.requestAccess() }
            }
        case .allowed:
            EmptyView()
        }
        if let message = model.errorMessage {
            Banner(text: message, button: "OK") { model.errorMessage = nil }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}

/// Which alarm the edit sheet is showing.
enum EditTarget: Identifiable {
    case new
    case existing(Alarm)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let alarm): alarm.id.uuidString
        }
    }

    var alarm: Alarm {
        switch self {
        case .new: Alarm()
        case .existing(let alarm): alarm
        }
    }

    var isNew: Bool {
        switch self {
        case .new: true
        case .existing: false
        }
    }
}

/// The penguin on its iceberg: asleep with a nightcap when an alarm is set.
struct SleepCard: View {
    var nextRing: Date?
    var anyOn: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                PenguinView(mood: anyOn ? .asleep : .awake, accessory: anyOn ? .nightcap : nil)
                    .frame(width: 150, height: 150)
                Capsule()
                    .fill(Theme.card.opacity(0.9))
                    .frame(width: 170, height: 18)
                    .offset(y: -10)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            if let bubble {
                Text(bubble)
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
                    .padding(14)
            }
        }
        .background(Theme.ice, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// "7h 40m of sleep" when the next ring is tonight, otherwise when it is.
    private var bubble: String? {
        guard let nextRing else { return anyOn ? nil : "No alarms on" }
        let seconds = nextRing.timeIntervalSinceNow
        if seconds < 16 * 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes / 60)h \(minutes % 60)m of sleep"
        }
        return "Next: " + nextRing.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

/// One alarm: big time, schedule line, on/off.
struct AlarmCard: View {
    var alarm: Alarm
    var onTap: () -> Void
    @Environment(AlarmsModel.self) private var model

    var body: some View {
        Card {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(alarm.time.short)
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .monospacedDigit()
                        Text(alarm.time.period)
                            .font(.system(.title3, design: .rounded, weight: .heavy))
                    }
                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .opacity(alarm.isOn ? 1 : 0.55)
                Spacer()
                Toggle("On", isOn: Binding(get: { alarm.isOn }, set: { model.setOn($0, for: alarm) }))
                    .labelsHidden()
                    .tint(Theme.mint)
                    .sensoryFeedback(.selection, trigger: alarm.isOn)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alarm.time.full), \(subtitle), \(alarm.isOn ? "on" : "off")")
        .accessibilityAction(named: "Edit", onTap)
    }

    private var subtitle: String {
        if !alarm.isOn { return "Off. Squawk will sleep in too." }
        let line = alarm.scheduleLine()
        return alarm.label.isEmpty ? line : "\(line) · \(alarm.label)"
    }
}

/// No alarms yet.
struct EmptyAlarms: View {
    var onAdd: () -> Void

    var body: some View {
        Card {
            VStack(spacing: 12) {
                Text("No alarms yet")
                    .font(Theme.title(22))
                Button("Add your first alarm", action: onAdd)
                    .buttonStyle(PillButtonStyle())
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    HomeView()
        .environment(AlarmsModel.preview())
        .background(Theme.background)
}
