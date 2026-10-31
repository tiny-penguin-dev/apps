import SwiftUI

/// Placeholder screen from the new-app template. Replace it with the app's first
/// screen from DESIGN.md.
struct ContentView: View {
    @State private var waddle = false

    var body: some View {
        VStack(spacing: 16) {
            Text("🐧")
                .font(.system(size: 96))
                .rotationEffect(.degrees(waddle ? 8 : -8))
                .animation(.spring(duration: 0.6, bounce: 0.5).repeatForever(), value: waddle)
                .onAppear { waddle = true }
            Text("__DISPLAY__")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(version)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }
}

#Preview {
    ContentView()
}
