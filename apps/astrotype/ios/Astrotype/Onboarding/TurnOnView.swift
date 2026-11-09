import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// DESIGN.md screen 2: the Settings steps and a chip that flips to "On" by itself.
/// In setup the main button goes on to the next screen; from Home it goes back.
struct TurnOnView: View {
    var model: AppModel
    var inSetup: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WizardPage(title: "Turn on Astrotype", step: inSetup ? model.setupStep(skip: { model.next() }) : nil,
                      body: "iPhone keyboards switch on in Settings. It takes three taps, and I'll know when it's done.") {
                StepRow(1, text: Text("Open ") + Text("Settings").foregroundStyle(Theme.accent).bold())
                StepRow(2, text: Text("Tap ") + Text("Keyboards").foregroundStyle(Theme.accent).bold())
                StepRow(3, text: Text("Turn on ") + Text("Astrotype").foregroundStyle(Theme.accent).bold())
                Card {
                    HStack(spacing: Theme.Space.m) {
                        if model.isKeyboardOn {
                            Chip("On", tint: Theme.mint)
                            Text("Astrotype is on. Hold 🌐 in any app to pick it.")
                                .font(.system(.body, design: .rounded, weight: .bold))
                        } else {
                            Chip("Not on yet")
                            Text("Come back here after Settings.")
                                .font(.sw(.small)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .animation(Theme.Motion.spring(reduceMotion: reduceMotion), value: model.isKeyboardOn)
            } buttons: {
                if model.isKeyboardOn {
                    Button(inSetup ? "Next" : "Done") { finish() }
                        .buttonStyle(.primary)
                } else {
                    Button("Open Settings") { model.openSettings() }
                        .buttonStyle(.primary)
                    Button(inSetup ? "I'll do it later" : "Done") { finish() }
                        .buttonStyle(.ghost)
                }
            }
            if model.celebrateKeyboardOn, model.isKeyboardOn {
                Confetti().ignoresSafeArea()
            }
        }
        .task {
            // Settings changes the list while we are away; read it again as it comes back.
            while !Task.isCancelled {
                model.refreshKeyboardStatus()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func finish() {
        if inSetup { model.next() } else { dismiss() }
    }
}
