import AppIntents
import SwiftUI
import UIKit

// THROWAWAY SPIKE (Gabriel, 7 Nov 2026), see DictationProbeIntent.swift. With Settings →
// Debug → "Test panel on the keyboard" on, a small panel floats over the top of the keys:
// "Talk" asks the app's running dictation session to start or stop listening (a Darwin
// notification), "Intent" runs `DictationProbeIntent` through `Button(intent:)`, and
// "Here" records in the keyboard itself. The session's state and the last result show
// under them.

struct DictationProbePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    DictationRunner.postTalk()
                } label: {
                    Label("Talk", systemImage: "mic.fill")
                }
                Button(intent: DictationProbeIntent(source: "Keyboard intent")) {
                    Label("Intent", systemImage: "bolt")
                }
                Button {
                    Task {
                        DictationProbeLog.write("Keyboard here: recording in the keyboard…")
                        let outcome = await DictationProbeRecorder.record(seconds: 3)
                        DictationProbeLog.write("Keyboard here: \(outcome)")
                    }
                } label: {
                    Label("Here", systemImage: "mic")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                VStack(alignment: .leading, spacing: 2) {
                    if let started = DictationProbeLog.sessionStarted {
                        Text("Session on since \(started.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 10, weight: .semibold))
                    } else {
                        Text("No session (start with Siri or the Action Button)")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(DictationProbeLog.last)
                        .font(.system(size: 10))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension KeyboardViewController {
    /// Adds or removes the test panel with the App Group switch (Full Access only).
    func updateDictationProbe(_ probe: inout UIHostingController<DictationProbePanel>?) {
        let wanted = hasFullAccess && DictationProbeLog.defaults?.bool(forKey: DictationProbeLog.enabledKey) == true
        if wanted, probe == nil {
            let host = UIHostingController(rootView: DictationProbePanel())
            host.view.backgroundColor = .clear
            host.sizingOptions = .intrinsicContentSize
            addChild(host)
            view.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
                host.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                host.view.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -16),
            ])
            host.didMove(toParent: self)
            probe = host
        } else if !wanted, let host = probe {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            probe = nil
        } else if let host = probe {
            view.bringSubviewToFront(host.view)
        }
    }
}
