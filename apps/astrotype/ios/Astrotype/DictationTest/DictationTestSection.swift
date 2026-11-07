import AstrotypeCore
import AstrotypeUI
import AVFoundation
import SwiftUI

// THROWAWAY SPIKE (Gabriel, 7 Nov 2026), see DictationProbeIntent.swift. The Debug page's
// "Dictation test" section: let the app use the microphone, turn on the keyboard's test
// panel, run the test from here, and read the last result.

struct DictationTestSection: View {
    @State private var keyboardButton = DictationProbeLog.defaults?.bool(forKey: DictationProbeLog.enabledKey) ?? false
    @State private var permission = AVAudioApplication.shared.recordPermission
    @State private var last = DictationProbeLog.last

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
            SettingsToggle("Test panel on the keyboard", subtitle: "Two mic buttons over the keys (needs Full Access)",
                           symbol: "waveform", tint: Theme.slate, isOn: $keyboardButton)
            SettingsRow("Last result", subtitle: last, symbol: "text.bubble", tint: Theme.slate)
        }
        .onChange(of: keyboardButton) { _, on in
            DictationProbeLog.defaults?.set(on, forKey: DictationProbeLog.enabledKey)
        }
        .task {
            while !Task.isCancelled {
                last = DictationProbeLog.last
                permission = AVAudioApplication.shared.recordPermission
                try? await Task.sleep(for: .seconds(1))
            }
        }
        GroupFootnote("Throwaway test. On the keyboard, \"Mic (intent)\" asks iOS to run the recording in the app in the background, and \"Mic (here)\" records in the keyboard itself. Siri: \"Test dictation in Astrotype\", or add \"Test dictation\" to the Action Button or Back Tap in Shortcuts. The result says where it ran and whether audio came in. Nothing is kept.")
    }

    private var permissionText: String {
        switch permission {
        case .granted: "Allowed"
        case .denied: "Denied: turn it on in Settings → Astrotype"
        default: "Not asked yet"
        }
    }
}
