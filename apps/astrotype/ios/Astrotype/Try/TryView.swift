import SwiftUI
import UIKit

/// Type with the Astrotype keyboard without installing it.
struct TryView: View {
    @Environment(RecognitionService.self) private var recognition
    @State private var controller: KeyboardController?
    @State private var box = TextBox()

    var body: some View {
        VStack(spacing: 0) {
            if let controller {
                AstrotypeTextView(controller: controller, box: box)
                if let reading = controller.lastReading {
                    Text(reading)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Try it")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = box.text }
                Button("Clear", systemImage: "trash") { box.clear() }
            }
        }
        .onAppear {
            if controller == nil { controller = KeyboardController(recognition: recognition) }
        }
        .task {
            // Let the text view join the window before asking for the keyboard.
            try? await Task.sleep(for: .milliseconds(300))
            box.focus()
        }
        .onDisappear { box.unfocus() }
    }
}
