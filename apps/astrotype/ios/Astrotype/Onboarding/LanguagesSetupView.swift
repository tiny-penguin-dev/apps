import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// Setup's languages question (features/languages), only on a phone that lists more than
/// one language the keyboard knows (`AppModel.asksLanguages`). Every one the phone lists
/// starts ticked; the trial covers having two on.
struct LanguagesSetupView: View {
    var model: AppModel
    @State private var chosen: [String] = []

    var body: some View {
        SetupPage(title: "Which languages do you type in?",
                  body: "With two on, Astrotype guesses from both as you go. No switching. Free types in one; your trial covers both.") {
            SettingsGroup {
                ForEach(Language.bundledCodes, id: \.self) { code in
                    SettingsToggle(Language.names[code] ?? code, subtitle: Language.englishNames[code],
                                   symbol: "character.bubble", tint: code == "en" ? Theme.left : Theme.right,
                                   isOn: Binding(get: { chosen.contains(code) }, set: { on in
                                       if on, !chosen.contains(code) { chosen.append(code) }
                                       if !on, chosen.count > 1 { chosen.removeAll { $0 == code } }
                                   }))
                        .disabled(chosen == [code])
                }
            }
        } buttons: {
            Button("Continue") {
                model.setLanguages(chosen)
                model.next()
            }
            .buttonStyle(.primary)
        }
        .onAppear {
            if chosen.isEmpty { chosen = KeyboardSettings.phoneLanguages(model.preferredLanguages) }
        }
    }
}
