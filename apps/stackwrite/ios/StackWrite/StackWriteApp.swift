import SwiftUI

@main
struct StackWriteApp: App {
    @State private var recognition = RecognitionService()
    @State private var samples: SampleStore
    @State private var uploader: SampleUploader
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let samples = SampleStore()
        _samples = State(initialValue: samples)
        _uploader = State(initialValue: SampleUploader(store: samples))
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(recognition)
                .environment(samples)
                .environment(uploader)
                .task { await recognition.load() }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active { uploader.upload() }
        }
    }
}
