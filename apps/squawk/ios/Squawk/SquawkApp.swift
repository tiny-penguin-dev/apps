import SwiftUI

@main
struct SquawkApp: App {
    init() {
        Telemetry.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
