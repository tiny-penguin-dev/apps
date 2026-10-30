import SwiftUI

@main
struct StackWriteApp: App {
    @State private var recognition = RecognitionService()
    @State private var samples = SampleStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(recognition)
                .environment(samples)
                .task { await recognition.load() }
        }
    }
}
