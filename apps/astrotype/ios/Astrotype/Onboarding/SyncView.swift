import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// The Full Access ask, with its one reason: the last setup step, after Try it, when it
/// already has words to keep (features/home-and-welcome). Skippable.
struct SyncView: View {
    var model: AppModel
    var inSetup: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WizardPage(title: "Keep your words everywhere", step: inSetup ? model.setupStep(skip: { model.skipFullAccess() }) : nil,
                  body: "Astrotype learns your words. With Full Access they sync over iCloud to your other devices, along with your settings. It also lets the keyboard send crash reports, if you share usage data. Nothing you type is ever sent anywhere.",
                  art: AnyView(CloudArt().frame(width: 180, height: 180))) {
            StepRow(1, text: Text("Settings › Keyboards › ") + Text("Astrotype").foregroundStyle(Theme.accent).bold())
            StepRow(2, text: Text("Turn on ") + Text("Allow Full Access").foregroundStyle(Theme.accent).bold())
        } buttons: {
            Button("Open Settings") { model.openSettingsForFullAccess() }
                .buttonStyle(.primary)
            if inSetup {
                Button(model.fullAccessAsked ? "Done" : "Skip for now") { model.skipFullAccess() }
                    .buttonStyle(.ghost)
            } else {
                Button("Done") { dismiss() }
                    .buttonStyle(.ghost)
            }
        }
    }
}
