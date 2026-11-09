import AstrotypeCore
import AstrotypeUI
import SwiftUI

@main
struct AstrotypeApp: App {
    @State private var model = AppModel(environment: .live())
    @State private var recognition = RecognitionService()
    @State private var samples: SampleStore
    @State private var uploader: SampleUploader
    @Environment(\.scenePhase) private var scenePhase
    /// Throwaway dictation test, round 3 (DictationTest/DictationWake.swift).
    @UIApplicationDelegateAdaptor(DictationWakeDelegate.self) private var dictationWake

    init() {
        Telemetry.start()
        let samples = SampleStore()
        _samples = State(initialValue: samples)
        _uploader = State(initialValue: SampleUploader(store: samples))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .environment(recognition)
                .environment(samples)
                .environment(uploader)
                .task {
                    model.startPro()
                    await model.refreshLeaderboards()
                    // The v1 handwriting model only loads when the pad is on.
                    if Flags.handwritingPad { await recognition.load() }
                }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                model.refreshKeyboardStatus()
                model.reloadWords()
                model.sync()
                model.uploadPractice()
                model.sendKeyboardHealth()
                model.refreshSpeed()
                Task { await model.refreshPro() }
                Task { await model.refreshLeaderboards() }
            } else {
                uploader.upload()
            }
        }
    }
}

/// The welcome wizard (features/home-and-welcome: Hello, Turn it on, Languages, Make it
/// yours, Try it, Keep your words), then Home. Screens slide in with a small
/// overshoot, or fade under Reduce Motion.
struct RootView: View {
    var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var slide: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
    }

    var body: some View {
        ZStack {
            switch model.screen {
            case .hello:
                HelloView { model.next() }
                    .transition(.opacity)
            case .turnOn:
                TurnOnView(model: model, inSetup: true)
                    .transition(slide)
            case .languages:
                LanguagesSetupView(model: model)
                    .transition(slide)
            case .style:
                MakeItYoursView(model: model)
                    .transition(slide)
            case .tryIt:
                TryItView(model: model)
                    .transition(slide)
            case .sync:
                SyncView(model: model, inSetup: true)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .home:
                HomeView(model: model)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.spring(reduceMotion: reduceMotion), value: model.screen)
    }
}
