import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// Settings → Debug: how much memory the keyboard uses against its 40 MB budget, how
/// close it came to iOS's limit, whether iOS ended it, and the switch for the tiny
/// readout on the keys (Gabriel, 3 Nov 2026). Re-read every second while open. The
/// readings come from the keyboard through the App Group (`KeyboardDebug`), so they need
/// Full Access; nothing here is sent anywhere.
struct DebugSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        SectionLabel("Keyboard memory")
        SettingsGroup {
            if let debug = model.keyboardDebug, let last = debug.last {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Meter(leading: "\(MemoryReading.mb(last.footprintMB)) MB",
                          trailing: "\(Int(MemoryReading.budgetMB)) MB", fraction: last.budgetFraction)
                    if let updated = debug.updated {
                        Text(debug.showing ? "Keyboard is up · read \(updated, style: .relative) ago"
                                           : "Keyboard closed · last read \(updated, style: .relative) ago")
                            .font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, Theme.Space.m)
                SettingsValue("Peak since it opened", value: mb(debug.peakMB), valueColor: color(debug.peakMB))
                SettingsValue("Peak since it loaded", subtitle: loadedSubtitle(debug),
                              value: mb(debug.processPeakMB), valueColor: color(debug.processPeakMB))
                if debug.lowestHeadroomMB > 0 {
                    SettingsValue("Least left before iOS's limit", subtitle: limitSubtitle(last),
                                  value: mb(debug.lowestHeadroomMB))
                }
                SettingsValue("Memory warnings", subtitle: "From iOS, since it opened", value: "\(debug.memoryWarnings)",
                              valueColor: debug.memoryWarnings > 0 ? Theme.sun : Theme.muted)
                SettingsValue("Ended while showing", subtitle: endedSubtitle(debug), value: "\(debug.endedWhileShowing)",
                              valueColor: debug.endedWhileShowing > 0 ? Theme.danger : Theme.muted)
            } else {
                SettingsRow("No readings yet", subtitle: model.isFullAccessOn
                            ? "Open the keyboard in any app, then come back."
                            : "Turn on Full Access and open the keyboard in any app. The readings come through the App Group.",
                            symbol: "memorychip", tint: Theme.slate)
            }
        }
        GroupFootnote("We keep the keyboard under \(Int(MemoryReading.budgetMB)) MB. iOS ends a keyboard that goes past its limit without a crash report, so \"Ended while showing\" is the one to watch.")

        SectionLabel("On the keyboard").padding(.top, Theme.Space.m)
        SettingsGroup {
            SettingsToggle("Stats on the keyboard", subtitle: "A tiny memory readout in the top corner of the keys",
                           symbol: "gauge.with.dots.needle.33percent", tint: Theme.slate,
                           isOn: $model.keyboardSettings.showsStats)
        }
        GroupFootnote(model.isFullAccessOn
                      ? "Now, peak since it loaded, and what's left before iOS's limit. Amber past 30 MB, red past 40."
                      : "Without Full Access the keyboard in other apps keeps its own settings, so this only shows on the practice keyboard here.")

        if !model.keyboardSessions.isEmpty {
            SectionLabel("Recent sessions").padding(.top, Theme.Space.m)
            SettingsGroup {
                ForEach(model.keyboardSessions.prefix(10), id: \.started) { session in
                    SettingsValue(session.started.formatted(date: .abbreviated, time: .shortened),
                                  subtitle: sessionSubtitle(session),
                                  value: mb(session.peakMB), valueColor: session.ended ? color(session.peakMB) : Theme.danger)
                }
            }
            GroupFootnote("Each time the keyboard was shown, with its peak. Kept while Share anonymous usage data is on.")
        }

        SectionLabel("This app").padding(.top, Theme.Space.m)
        SettingsGroup {
            if let memory = model.appMemory {
                SettingsValue("Memory", subtitle: "The app's own, not the keyboard's", value: mb(memory.footprintMB))
            }
            SettingsValue("Full Access", value: model.isFullAccessOn ? "On" : "Off")
            SettingsValue("Version", value: DeviceInfo.appVersion)
            SettingsValue("Phone", subtitle: DeviceInfo.system, value: DeviceInfo.model)
        }
        .task {
            while !Task.isCancelled {
                model.reloadDebug()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func mb(_ value: Double) -> String { "\(MemoryReading.mb(value)) MB" }

    /// Amber from 75% of the budget, red past it.
    private func color(_ value: Double) -> Color {
        let fraction = value / MemoryReading.budgetMB
        return fraction >= 1 ? Theme.danger : fraction >= 0.75 ? Theme.sun : Theme.muted
    }

    private func loadedSubtitle(_ debug: KeyboardDebug) -> String? {
        guard let loaded = debug.loadedAt else { return nil }
        let times = debug.shows == 1 ? "once" : "\(debug.shows) times"
        return "Loaded \(loaded.formatted(.relative(presentation: .named))), shown \(times)"
    }

    private func limitSubtitle(_ last: MemoryReading) -> String? {
        last.limitMB.map { "iOS's limit on this phone is about \(Int($0.rounded())) MB" }
    }

    private func endedSubtitle(_ debug: KeyboardDebug) -> String {
        guard let last = debug.lastEndedWhileShowing else { return "A crash or iOS's memory limit. None so far." }
        return "A crash or iOS's memory limit. Last \(last.formatted(.relative(presentation: .named)))."
    }

    private func sessionSubtitle(_ session: KeyboardHealth.Session) -> String {
        let left = "\(MemoryReading.mb(session.lowestHeadroomMB)) MB left at the least"
        return session.ended ? left : "Ended while showing · " + left
    }
}
