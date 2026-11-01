import StackWriteCore
import SwiftUI

@main
struct StackWriteApp: App {
    @AppStorage("onboarding.done") private var onboardingDone = false
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
            Group {
                if onboardingDone {
                    HomeView()
                } else {
                    HelloView { onboardingDone = true }
                }
            }
            .environment(recognition)
            .environment(samples)
            .environment(uploader)
            .task {
                // The v1 handwriting model only loads when the pad is on.
                if Flags.handwritingPad { await recognition.load() }
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active { uploader.upload() }
        }
    }
}
