import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// Where a setup screen sits in the welcome wizard (features/home-and-welcome): its
/// number, how many there are, and what Skip does. Nil outside setup (the same screens
/// opened from Home or Settings have no bar and no Skip).
struct WizardStep {
    var number: Int
    var count: Int
    var skip: (() -> Void)?
}

/// Every setup step's shape (features/home-and-welcome): the progress bar and Skip on
/// top, a title, a line, some content, and the buttons at the bottom.
struct WizardPage<Content: View, Buttons: View>: View {
    var title: String
    var step: WizardStep?
    var body_: String
    var art: AnyView?
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons

    init(title: String, step: WizardStep? = nil, body: String, art: AnyView? = nil,
         @ViewBuilder content: () -> Content, @ViewBuilder buttons: () -> Buttons) {
        self.title = title
        self.step = step
        self.body_ = body
        self.art = art
        self.content = content()
        self.buttons = buttons()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let step {
                HStack(spacing: Theme.Space.m) {
                    StepProgress(number: step.number, count: step.count)
                    if let skip = step.skip {
                        Button("Skip", action: skip)
                            .font(.system(.body, design: .rounded, weight: .heavy))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, Theme.Space.s)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let art {
                        art.frame(maxWidth: .infinity).padding(.top, Theme.Space.l)
                    }
                    Text(title)
                        .font(.sw(.title))
                        .padding(.top, art == nil ? (step == nil ? Theme.Space.xl : Theme.Space.l) : Theme.Space.s)
                        .accessibilityAddTraits(.isHeader)
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

/// The wizard's progress bar; it fills with a spring as the steps go by.
struct StepProgress: View {
    var number: Int
    var count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        let fraction = Double(number) / Double(max(count, 1))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(Theme.accent).frame(width: proxy.size.width * shown)
            }
        }
        .frame(height: 8)
        .onAppear {
            // Starts from the step before, so each screen's bar visibly fills.
            shown = Double(number - 1) / Double(max(count, 1))
            withAnimation(Theme.Motion.spring(reduceMotion: reduceMotion).delay(0.15)) { shown = fraction }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(number) of \(count)")
    }
}
