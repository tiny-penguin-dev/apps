import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// Settings → Debug: how much memory the keyboard uses against its 40 MB budget, how
/// close it came to iOS's limit, whether iOS ended it, and the switch for the tiny
/// readout on the keys (Gabriel, 3 Nov 2026). Re-read every second while open. The
/// readings come from the keyboard through the App Group (`KeyboardDebug`), so they need
/// Full Access; nothing here is sent anywhere, except a typing recording the person
/// sends themselves (TestFlight builds only, Gabriel 6 Nov 2026).
struct DebugSettings: View {
    @Bindable var model: AppModel
    @State private var shareURL: URL?

    var body: some View {
        SectionLabel("Keyboard memory")
        SettingsGroup {
            if let debug = model.keyboardDebug, let last = debug.last {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Meter(leading: "\(MemoryReading.mb(last.footprintMB)) MB",
                          trailing: "\(Int(MemoryReading.budgetMB)) MB", fraction: last.budgetFraction)
                    if let updated = debug.updated {
                        Text(!debug.showing ? "Keyboard closed · last read \(updated, style: .relative) ago"
                             : debug.suspended ? "Keyboard is up in an app in the background · read \(updated, style: .relative) ago"
                             : "Keyboard is up · read \(updated, style: .relative) ago")
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
                      ? "Now, peak since it loaded, and what's left before iOS's limit. Amber past 30 MB, red past 40. The second line splits it: heap is the keyboard's own objects, other is drawing and images, and the layer count should stay flat while you type."
                      : "Without Full Access the keyboard in other apps keeps its own settings, so this only shows on the practice keyboard here.")

        if model.isTestBuild {
            typingRecorder
        }

        DictationTestSection()

        if !model.keyboardSessions.isEmpty {
            SectionLabel("Recent sessions").padding(.top, Theme.Space.m)
            SettingsGroup {
                ForEach(model.keyboardSessions.prefix(10), id: \.started) { session in
                    SettingsValue(session.started.formatted(date: .abbreviated, time: .shortened),
                                  subtitle: sessionSubtitle(session),
                                  value: mb(session.peakMB),
                                  valueColor: session.endedWhileShowing ? Theme.danger : color(session.peakMB))
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
            await model.checkTestBuild()
            while !Task.isCancelled {
                model.reloadDebug()
                model.reloadTyping()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// The typing recorder: keep the last half hour on the phone, send a stretch of it
    /// for Claude to replay, mark moments from the keyboard.
    @ViewBuilder private var typingRecorder: some View {
        SectionLabel("Typing recorder").padding(.top, Theme.Space.m)
        SettingsGroup {
            SettingsToggle("Keep recording", subtitle: "The last 30 minutes of typing, kept on this phone",
                           symbol: "record.circle", tint: Theme.danger, isOn: $model.keyboardSettings.recordsTyping)
            if model.keyboardSettings.recordsTyping {
                ForEach([1, 5, 30], id: \.self) { minutes in
                    sendRow("Last \(AppModel.minutes(minutes))", subtitle: nil, minutes: minutes)
                }
                ForEach(model.typingMarks.prefix(5), id: \.self) { mark in
                    let minutes = min(30, Int((model.now.timeIntervalSince(mark) / 60).rounded(.up)) + 1)
                    sendRow("Marked \(mark.formatted(date: .omitted, time: .shortened))",
                            subtitle: "Sends from a minute before it to now", minutes: minutes)
                }
            }
        }
        .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
        if let note = model.typingNote {
            GroupFootnote(note)
        }
        GroupFootnote(recorderFootnote)
        if !model.typingLogsSent.isEmpty {
            SettingsGroup {
                SettingsRow("Sent to iCloud", subtitle: sentSubtitle, symbol: "icloud", tint: Theme.slate) {
                    Button("Delete") { model.deleteSentTyping() }.buttonStyle(.small)
                }
                SettingsRow("Clear this phone's recording", symbol: "trash", tint: Theme.slate) {
                    Button("Clear") { model.clearTypingRecording() }.buttonStyle(.small)
                }
            }
        } else if model.typingKB > 0 {
            SettingsGroup {
                SettingsRow("Clear this phone's recording", symbol: "trash", tint: Theme.slate) {
                    Button("Clear") { model.clearTypingRecording() }.buttonStyle(.small)
                }
            }
        }
    }

    private func sendRow(_ title: String, subtitle: String?, minutes: Int) -> some View {
        SettingsRow(title, subtitle: subtitle, symbol: "paperplane", tint: Theme.slate) {
            if model.typingSending == minutes {
                ProgressView().tint(Theme.accent)
            } else {
                HStack(spacing: Theme.Space.s) {
                    Button {
                        shareURL = model.typingFile(minutes: minutes)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.small)
                    .accessibilityLabel("Share as a file")
                    Button("Send") { model.sendTyping(minutes: minutes) }
                        .buttonStyle(.small)
                        .disabled(model.typingSending != nil)
                }
            }
        }
    }

    private var recorderFootnote: String {
        guard model.isFullAccessOn else {
            return "Needs Full Access: the keyboard keeps the recording where this app can read it."
        }
        let kept = model.typingKB > 0 ? " Kept now: \(model.typingKB) KB." : ""
        return "Every touch and what it typed, with your settings and this build, so Claude can play it back and see the bug. "
            + "Passwords, addresses and codes are never recorded. It stays on this phone, anything older than 30 minutes is "
            + "deleted, and nothing is sent until you tap Send. To mark a moment, hold 123 on the keyboard." + kept
    }

    private var sentSubtitle: String {
        let logs = model.typingLogsSent
        let last = logs.last.map { "last \($0.sent.formatted(.relative(presentation: .named))), \($0.summary)" } ?? ""
        return (logs.count == 1 ? "1 log, " : "\(logs.count) logs, ") + last
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
        var text = "A crash or iOS's memory limit. Last \(last.formatted(.relative(presentation: .named)))."
        if debug.crashedWhileShowing + debug.killedWhileShowing > 0 {
            text += " Since 6 Nov: \(debug.crashedWhileShowing) crashed, \(debug.killedWhileShowing) ended by iOS."
        }
        return text
    }

    private func sessionSubtitle(_ session: KeyboardHealth.Session) -> String {
        var parts = ["\(MemoryReading.mb(session.lowestHeadroomMB)) MB left at the least"]
        if !session.parts.isEmpty { parts.append(KeyboardHealth.label(session.parts).replacingOccurrences(of: "_", with: " ")) }
        if session.endedWhileShowing {
            parts.insert(session.crashed == true ? "Crashed" : session.crashed == false ? "Ended by iOS" : "Ended while showing", at: 0)
        } else if !session.ended, session.suspended {
            parts.insert("Went to the background", at: 0)
        }
        return parts.joined(separator: " · ")
    }
}
