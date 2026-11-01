import PenguinKit
import SquawkKit
import SwiftUI
import UIKit

/// Screen 4: the sleeping penguin and the alarm cards.
struct HomeView: View {
    @Environment(AlarmsModel.self) private var model
    @Environment(ProModel.self) private var pro
    @AppStorage(Wardrobe.key) private var outfitID = ""
    @State private var editing: EditTarget?
    @State private var showGallery = false
    @State private var showSettings = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                if wide {
                    // The iPhone Duo's inner screen and other wide windows: the penguin on
                    // the left, the alarms on the right (docs/building.md "Every size").
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        banners
                        HStack(alignment: .top, spacing: 20) {
                            sleepCard
                                .frame(maxWidth: 380)
                            VStack(spacing: 14) { alarmList }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 100)
                    .frame(maxWidth: 1000)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        banners
                        sleepCard
                        alarmList
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showGallery) {
            NavigationStack {
                PenguinGallery().toolbar { Button("Done") { showGallery = false } }
            }
        }
    }

    /// Wide enough for two columns.
    private var wide: Bool { sizeClass == .regular }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(greeting)
                .titleFont(32)
            Spacer()
            if model.log.streak > 0 {
                StreakChip(streak: model.log.streak)
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(SquishStyle())
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var sleepCard: some View {
        SleepCard(
            nextRing: model.nextRing(), anyOn: model.alarms.contains(where: \.isOn),
            outfit: Wardrobe.accessory(outfitID: outfitID, access: pro.access, bestStreak: model.log.bestStreak)
        )
        .onLongPressGesture(minimumDuration: 1.2) { showGallery = true }
    }

    @ViewBuilder private var alarmList: some View {
        if model.alarms.isEmpty {
            EmptyAlarms { editing = .new }
        } else {
            ForEach(model.sortedAlarms) { alarm in
                AlarmCard(alarm: alarm) { editing = .existing(alarm) }
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

/// The penguin on its iceberg: asleep with a nightcap when an alarm is set, awake in
/// its outfit when not.
struct SleepCard: View {
    var nextRing: Date?
    var anyOn: Bool
    var outfit: PenguinAccessory?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                PenguinView(mood: anyOn ? .asleep : .awake, accessory: anyOn ? .nightcap : outfit)
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

/// One alarm: big time, schedule line, on/off, and the next morning's skip or change.
struct AlarmCard: View {
    var alarm: Alarm
    var onTap: () -> Void
    @Environment(AlarmsModel.self) private var model
    @Environment(ProModel.self) private var pro
    @State private var changingNext = false
    @State private var paywall: ProFeature?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At the largest text sizes the switch goes under the time (DESIGN.md "Accessibility").
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center))
        Card {
            VStack(alignment: .leading, spacing: 12) {
                layout {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(alarm.time.short)
                                .bigNumberFont(48)
                            Text(alarm.time.period)
                                .font(.system(.title3, design: .rounded, weight: .heavy))
                        }
                        Text(subtitle)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .opacity(alarm.isOn ? 1 : 0.55)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(alarm.time.full), \(subtitle)")
                    if !stacked { Spacer() }
                    Toggle(alarm.time.full, isOn: Binding(get: { alarm.isOn }, set: { model.setOn($0, for: alarm) }))
                        .labelsHidden()
                        .tint(Theme.mint)
                        .wobble(on: alarm.isOn)
                        .sensoryFeedback(.selection, trigger: alarm.isOn)
                }
                if alarm.isOn, let day = alarm.upcomingMorning(after: Date()) {
                    nextMorning(day)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Edit", onTap)
        .sheet(isPresented: $changingNext) {
            if let day = alarm.upcomingMorning(after: Date()) {
                ChangeNextSheet(alarm: alarm, day: day)
            }
        }
        .proSheet($paywall)
    }

    /// "Skip tomorrow · Change", or what's changed with an Undo.
    @ViewBuilder private func nextMorning(_ day: LocalDate) -> some View {
        let name = day.morningName
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { nextMorningButtons(day, name: name) }
            VStack(alignment: .leading, spacing: 10) { nextMorningButtons(day, name: name) }
        }
        .buttonStyle(LinkButtonStyle())
        .sensoryFeedback(.selection, trigger: alarm.changes)
    }

    @ViewBuilder private func nextMorningButtons(_ day: LocalDate, name: String) -> some View {
        switch alarm.change(on: day) {
        case .skip:
            Label("Skipping \(name)", systemImage: "moon.zzz.fill")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            Spacer()
            Button("Undo") { model.undoNext(alarm) }
        case .time(let time):
            Label("\(name.capitalizedFirst) at \(time.full) only", systemImage: "clock.fill")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            Spacer()
            Button("Undo") { model.undoNext(alarm) }
        case .done, nil:
            Button("Skip \(name)") { model.skipNext(alarm) }
            ProLinkButton(
                title: "Change \(name) only", locked: !pro.access.allows(.changeNextTime),
                action: { changingNext = true }, onLocked: { paywall = .changeNextTime }
            )
            Spacer()
        }
    }

    private var subtitle: String {
        if !alarm.isOn { return "Off. Squawk will sleep in too." }
        var parts = [alarm.scheduleLine()]
        if alarm.rings.count > 1 { parts.append("\(alarm.rings.count) rings") }
        if !alarm.label.isEmpty { parts.append(alarm.label) }
        return parts.joined(separator: " · ")
    }
}

/// The "change next morning only" sheet: a new time for one morning.
struct ChangeNextSheet: View {
    var alarm: Alarm
    var day: LocalDate
    @State private var time: TimeOfDay
    @Environment(AlarmsModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    init(alarm: Alarm, day: LocalDate) {
        self.alarm = alarm
        self.day = day
        _time = State(initialValue: alarm.scheduledTime(on: day) ?? alarm.time)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker("Time", selection: $time.asDate, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                Text("Only \(day.morningName) changes. Every other morning stays the same.")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("\(day.morningName.capitalizedFirst) only")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.changeNext(alarm, time: time)
                        dismiss()
                    }
                    .fontWeight(.heavy)
                }
            }
        }
        .presentationDetents([.medium])
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
    }
}

/// No alarms yet.
struct EmptyAlarms: View {
    var onAdd: () -> Void

    var body: some View {
        Card {
            VStack(spacing: 12) {
                Text("No alarms yet")
                    .titleFont(22)
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
        .environment(ProModel.preview())
        .background(Theme.background)
}

#Preview("Dark, largest text") {
    HomeView()
        .environment(AlarmsModel.preview())
        .environment(ProModel.preview())
        .background(Theme.background)
        .dynamicTypeSize(.accessibility5)
        .preferredColorScheme(.dark)
}

#Preview("Wide (iPhone Duo inner screen)") {
    HomeView()
        .environment(AlarmsModel.preview())
        .environment(ProModel.preview())
        .background(Theme.background)
        .environment(\.horizontalSizeClass, .regular)
        .frame(width: 900, height: 700)
}
