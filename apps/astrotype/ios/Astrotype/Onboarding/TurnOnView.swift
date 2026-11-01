import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// DESIGN.md screen 2: the Settings steps and a chip that flips to "On" by itself.
/// In setup the main button goes on to the next screen; from Home it goes back.
struct TurnOnView: View {
    var model: AppModel
    var inSetup: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            SetupPage(title: "Turn on Astrotype",
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
                .animation(Theme.Motion.spring, value: model.isKeyboardOn)
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

/// A setup screen's shape: a title, a line, some rows, and the buttons at the bottom.
struct SetupPage<Content: View, Buttons: View>: View {
    var title: String
    var body_: String
    var art: AnyView?
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons

    init(title: String, body: String, art: AnyView? = nil,
         @ViewBuilder content: () -> Content, @ViewBuilder buttons: () -> Buttons) {
        self.title = title
        self.body_ = body
        self.art = art
        self.content = content()
        self.buttons = buttons()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let art {
                        art.frame(maxWidth: .infinity).padding(.top, Theme.Space.l)
                    }
                    Text(title)
                        .font(.sw(.title))
                        .padding(.top, art == nil ? Theme.Space.xl : Theme.Space.s)
                    Text(body_)
                        .font(.sw(.body))
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, Theme.Space.s)
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.gutter)
            }
            VStack(spacing: Theme.Space.xs) {
                buttons
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.l)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Theme.ink)
        .background(Theme.bg.ignoresSafeArea())
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
