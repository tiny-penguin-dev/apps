import SwiftUI

struct ContentView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("StackWrite")
                .font(.largeTitle.bold())
            Text("Write words with one stacked stroke.")
                .foregroundStyle(.secondary)
            Text(version)
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
