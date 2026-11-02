import SquawkKit
import SwiftUI

/// Screen 5: time, days or a date, different times on some days, steps, "When you're
/// up", label, and skip next morning.
struct EditAlarmView: View {
    @State var alarm: Alarm
    var isNew: Bool

    @Environment(AlarmsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    DatePicker("Wake-up time", selection: $alarm.time.asDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("Repeat", selection: oneTime) {
                                Text("Repeat").tag(false)
                                Text("Only once").tag(true)
                            }
                            .pickerStyle(.segmented)
                            if alarm.isOneTime {
                                DatePicker("Date", selection: oneTimeDate, in: Date()..., displayedComponents: .date)
                                    .font(Theme.label)
                            } else {
                                DayButtons(selection: $alarm.days)
                                Text(alarm.scheduleLine())
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }

                    if !alarm.isOneTime {
                        dayTimesCard
                    }

                    StepsSection(alarm: $alarm)

                    MoreOptionsLink(alarm: $alarm)

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Label").font(Theme.label)
                                TextField("Wake up", text: $alarm.label)
                                    .multilineTextAlignment(.trailing)
                                    .font(Theme.body)
                            }
                        }
                    }

                    if !isNew, let day = alarm.upcomingMorning(after: Date()) {
                        Card {
                            Toggle(isOn: skipNext(day)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Skip next morning").font(Theme.label)
                                    Text(day.morningName.capitalizedFirst + ", " + day.formatted())
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .tint(Theme.mint)
                        }
                    }

                    if !isNew {
                        Button("Delete alarm", role: .destructive) { confirmDelete = true }
                            .font(Theme.label)
                            .foregroundStyle(Theme.coral)
                            .padding(.top, 8)
                    }
                }
                .padding(20)
                .readableWidth()
            }
            .background(Theme.background)
            .navigationTitle(isNew ? "New alarm" : "Edit alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.save(cleaned)
                        dismiss()
                    }
                    .fontWeight(.heavy)
                    .disabled(!alarm.isOneTime && alarm.days.isEmpty)
                }
            }
            .confirmationDialog("Delete this alarm?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    model.delete(alarm)
                    dismiss()
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
    }

    // MARK: Different times on some days

    private var dayTimesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Different times on some days").font(Theme.label)
                ForEach(alarm.dayTimes.keys.sorted()) { day in
                    HStack {
                        Text(day.short).font(Theme.label).frame(width: 44, alignment: .leading)
                        DatePicker(day.full, selection: dayTime(day), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Spacer()
                        Button {
                            alarm.dayTimes[day] = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.muted)
                        }
                        .accessibilityLabel("Use the normal time on \(day.full)")
                    }
                }
                let free = alarm.days.sorted().filter { alarm.dayTimes[$0] == nil }
                if !free.isEmpty {
                    Menu {
                        ForEach(free) { day in
                            Button(day.full) { alarm.dayTimes[day] = alarm.time.adding(minutes: 30) }
                        }
                    } label: {
                        Text("+ Different time on a day")
                    }
                    .buttonStyle(LinkButtonStyle())
                }
            }
        }
    }

    // MARK: Helpers

    private func skipNext(_ day: LocalDate) -> Binding<Bool> {
        Binding(
            get: { alarm.change(on: day) == .skip },
            set: { alarm.setChange($0 ? .skip : nil, on: day) }
        )
    }

    private var oneTime: Binding<Bool> {
        Binding(
            get: { alarm.isOneTime },
            set: { once in alarm.date = once ? LocalDate(nextDate(for: alarm.time)) : nil }
        )
    }

    private var oneTimeDate: Binding<Date> {
        Binding(
            get: { alarm.date.flatMap { Calendar.current.date(from: DateComponents(year: $0.year, month: $0.month, day: $0.day)) } ?? Date() },
            set: { alarm.date = LocalDate($0) }
        )
    }

    private func dayTime(_ day: Weekday) -> Binding<Date> {
        Binding(
            get: { (alarm.dayTimes[day] ?? alarm.time).pickerDate },
            set: { alarm.dayTimes[day] = TimeOfDay(pickerDate: $0) }
        )
    }

    /// Today if the time is still ahead, otherwise tomorrow.
    private func nextDate(for time: TimeOfDay) -> Date {
        let today = time.pickerDate
        return today > Date() ? today : Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// Drops day times for days that are no longer selected, or that match the normal time.
    private var cleaned: Alarm {
        var copy = alarm
        copy.dayTimes = copy.dayTimes.filter { copy.days.contains($0.key) && $0.value != copy.time }
        return copy
    }
}

#Preview {
    EditAlarmView(alarm: Alarm(dayTimes: [.friday: TimeOfDay(hour: 7, minute: 30)]), isNew: false)
        .environment(AlarmsModel.preview())
        .environment(ProModel.preview())
}
