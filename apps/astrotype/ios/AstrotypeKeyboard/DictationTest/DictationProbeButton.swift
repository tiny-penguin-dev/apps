import AppIntents
import SwiftUI
import UIKit

// THROWAWAY SPIKE (Gabriel, 7 Nov 2026), see DictationProbeIntent.swift. With Settings →
// Debug → "Dictation test button" on, a small panel floats over the top of the keys:
// "Mic (intent)" runs `DictationProbeIntent` through `Button(intent:)`, the way a widget
// would, and "Mic (here)" records in the keyboard itself. The last result shows under them.

struct DictationProbePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button(intent: DictationProbeIntent(source: "Keyboard intent")) {
                    Label("Mic (intent)", systemImage: "mic.fill")
                }
                Button {
                    Task {
                        DictationProbeLog.write("Keyboard direct: recording in the keyboard…")
                        let outcome = await DictationProbeRecorder.record(seconds: 3)
                        DictationProbeLog.write("Keyboard direct: \(outcome)")
                    }
                } label: {
                    Label("Mic (here)", systemImage: "mic")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(DictationProbeLog.last)
                    .font(.system(size: 10))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
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
