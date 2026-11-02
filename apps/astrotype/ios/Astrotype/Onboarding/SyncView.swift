import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// DESIGN.md screen 3: the Full Access ask, with its one reason. Skippable.
struct SyncView: View {
    var model: AppModel
    var inSetup: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SetupPage(title: "Keep your words everywhere",
                  body: "Astrotype learns your words. With Full Access they sync over iCloud to your other devices, along with your settings. It also lets the keyboard send crash reports, if you share usage data. Nothing you type is ever sent anywhere.",
                  art: AnyView(CloudArt().frame(width: 180, height: 180))) {
            StepRow(1, text: Text("Settings › Keyboards › ") + Text("Astrotype").foregroundStyle(Theme.accent).bold())
            StepRow(2, text: Text("Turn on ") + Text("Allow Full Access").foregroundStyle(Theme.accent).bold())
        } buttons: {
            Button("Open Settings") { model.openSettingsForFullAccess() }
                .buttonStyle(.primary)
            if inSetup {
                Button(model.fullAccessAsked ? "Next" : "Skip for now") { model.skipFullAccess() }
                    .buttonStyle(.ghost)
            } else {
                Button("Done") { dismiss() }
                    .buttonStyle(.ghost)
            }
        }
    }
}
