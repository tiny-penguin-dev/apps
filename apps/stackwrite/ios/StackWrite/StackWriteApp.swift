import StackWriteCore
import StackWriteUI
import SwiftUI

@main
struct StackWriteApp: App {
    @State private var model = AppModel(environment: .live())
    @State private var recognition = RecognitionService()
    @State private var samples: SampleStore
    @State private var uploader: SampleUploader
    @Environment(\.scenePhase) private var scenePhase

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
                    // The v1 handwriting model only loads when the pad is on.
                    if Flags.handwritingPad { await recognition.load() }
                }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                model.refreshKeyboardStatus()
            } else {
                uploader.upload()
            }
        }
    }
}

/// Setup (DESIGN.md "First launch"), then Home.
struct RootView: View {
    var model: AppModel

    var body: some View {
        ZStack {
            switch model.screen {
            case .hello:
                HelloView { model.next() }
                    .transition(.opacity)
            case .turnOn:
                TurnOnView(model: model, inSetup: true)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .sync:
                SyncView(model: model, inSetup: true)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .tryIt:
                TryItView(model: model)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .home:
                HomeView(model: model)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.spring, value: model.screen)
    }
}
