import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// The welcome wizard's Make it yours step (features/home-and-welcome): Home's theme and
/// effect rows, with the keyboard up at the bottom to try them. Classic and Calm are
/// picked to start; everyone is on the trial here, so every look can be picked.
struct MakeItYoursView: View {
    @Bindable var model: AppModel
    @State private var session: KeyboardSession?

    var body: some View {
        WizardPage(title: "Make it yours", step: model.setupStep(skip: { model.next() }),
                   body: "Pick a look and a little sparkle. You can change it any time on Home.") {
            YourKeyboardCard(model: model, showsHeight: false, moreStyling: nil, openPro: {},
                             played: { session?.keyboard.surface.playBurst() }, counts: false)
        } buttons: {
            if let session {
                KeyboardField(session: session, font: .preferredFont(forTextStyle: .body))
                    .frame(height: 44)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .accessibilityLabel("Try your look")
            }
            Button("Looks good") { model.styleChosen() }
                .buttonStyle(.primary)
        }
        .onAppear {
            guard session == nil else { return }
            let session = KeyboardSession(settingsStore: MemorySettingsStore(model.demoSettings), learned: model.learnedWords, personal: model.personal)
            session.apply(entitlement: model.demoEntitlement)
            self.session = session
        }
        .onChange(of: model.demoSettings) { session?.apply(model.demoSettings) }
    }
}
