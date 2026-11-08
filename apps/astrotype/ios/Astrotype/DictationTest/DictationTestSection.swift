import AstrotypeCore
import AstrotypeUI
import AVFoundation
import SwiftUI
import UIKit
import UserNotifications

// THROWAWAY SPIKE (Gabriel, 7 Nov 2026), see DictationProbeIntent.swift. The Debug page's
// "Dictation test" section: let the app use the microphone, turn on the keyboard's test
// panel, run the test from here, and read the last result.

struct DictationTestSection: View {
    @State private var keyboardButton = DictationProbeLog.defaults?.bool(forKey: DictationProbeLog.enabledKey) ?? false
    @State private var permission = AVAudioApplication.shared.recordPermission
    @State private var last = DictationProbeLog.last
    @State private var started = DictationProbeLog.sessionStarted
    @State private var pushToken = DictationProbeLog.pushToken
    @State private var pauseMic = DictationPause.pauseMic
    @State private var keepAwake = DictationPause.keepAwake
    @State private var notifications = UNAuthorizationStatus.notDetermined

    var body: some View {
        SectionLabel("Dictation test").padding(.top, Theme.Space.m)
        SettingsGroup {
            SettingsRow("Microphone", subtitle: permissionText, symbol: "mic", tint: Theme.slate) {
                if permission == .undetermined {
                    Button("Allow") {
                        Task {
                            _ = await AVAudioApplication.requestRecordPermission()
                            permission = AVAudioApplication.shared.recordPermission
                        }
                    }
                    .buttonStyle(.small)
                }
            }
            SettingsToggle("Test panel on the keyboard", subtitle: "Talk, Intent and Here buttons over the keys (needs Full Access)",
                           symbol: "waveform", tint: Theme.slate, isOn: $keyboardButton)
            SettingsRow("Session", subtitle: sessionText, symbol: "dot.radiowaves.left.and.right", tint: Theme.slate) {
                Button(started == nil ? "Start" : "End") {
                    Task { try? await DictationSession.shared.toggle(source: "App button") }
                }
                .buttonStyle(.small)
            }
            SettingsRow("Notifications", subtitle: notificationText, symbol: "bell", tint: Theme.slate) {
                if notifications == .notDetermined {
                    Button("Allow") {
                        Task {
                            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                            notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                        }
                    }
                    .buttonStyle(.small)
                }
            }
            SettingsRow("Push-to-start token", subtitle: pushToken.map { "\($0.prefix(12))…" } ?? "Not yet (open this page again in a moment)",
                        symbol: "paperplane", tint: Theme.slate) {
                if let pushToken {
                    Button("Copy") { UIPasteboard.general.string = pushToken }
                        .buttonStyle(.small)
                }
            }
            SettingsToggle("Pause mic between dictations", subtitle: "Mic off after Done; Talk turns it back on (round 5)",
                           symbol: "mic.slash", tint: Theme.slate, isOn: $pauseMic)
            SettingsToggle("Keep app awake while paused", subtitle: "Plays silence so iOS doesn't suspend the app",
                           symbol: "moon.zzz", tint: Theme.slate, isOn: $keepAwake)
            SettingsRow("Last result", subtitle: last, symbol: "text.bubble", tint: Theme.slate)
        }
        .onChange(of: keyboardButton) { _, on in
            DictationProbeLog.defaults?.set(on, forKey: DictationProbeLog.enabledKey)
        }
        .onChange(of: pauseMic) { _, on in
            DictationProbeLog.defaults?.set(on, forKey: DictationPause.pauseKey)
        }
        .onChange(of: keepAwake) { _, on in
            DictationProbeLog.defaults?.set(on, forKey: DictationPause.awakeKey)
        }
        .task {
            while !Task.isCancelled {
                last = DictationProbeLog.last
                started = DictationProbeLog.sessionStarted
                permission = AVAudioApplication.shared.recordPermission
                pushToken = DictationProbeLog.pushToken
                notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                try? await Task.sleep(for: .seconds(1))
            }
        }
        GroupFootnote("Throwaway test. Start a session with Siri (\"Test dictation in Astrotype\"), the Action Button or Back Tap (the \"Test dictation\" shortcut), or Start here. It shows a Live Activity and keeps the mic open in the background. Then Talk on the keyboard's panel or the Live Activity starts and stops listening. \"Intent\" and \"Here\" on the keyboard are round 1's tests. The result says where each one ran and how much audio came in. Nothing is kept.")
    }

    private var sessionText: String {
        guard let started else { return "Off" }
        return "On since \(started.formatted(date: .omitted, time: .shortened))"
    }

    private var notificationText: String {
        switch notifications {
        case .authorized, .provisional, .ephemeral: "Allowed (only for the keyboard's Notify test)"
        case .denied: "Denied: turn it on in Settings → Astrotype"
        default: "Not asked yet (only for the keyboard's Notify test)"
        }
    }

    private var permissionText: String {
        switch permission {
        case .granted: "Allowed"
        case .denied: "Denied: turn it on in Settings → Astrotype"
        default: "Not asked yet"
        }
    }
}
