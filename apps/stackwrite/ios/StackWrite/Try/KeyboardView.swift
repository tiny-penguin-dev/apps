import SwiftUI

/// The simulated keyboard: a suggestion bar over the writing pad, with
/// punctuation keys on the left and space, delete and return on the right.
struct KeyboardView: View {
    var controller: KeyboardController
    var onDismiss: () -> Void

    private static let marks = [".", ",", "?", "!", "'"]

    var body: some View {
        VStack(spacing: 6) {
            suggestionBar
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 6) {
                    ForEach(Self.marks, id: \.self) { mark in
                        Key(mark) { controller.punctuationTapped(mark) }
                    }
                }
                WritingPad { points, _ in controller.handleStroke(points) }
                VStack(spacing: 6) {
                    Key(systemImage: "delete.left", label: "Delete") { controller.deleteTapped() }
                    Key(systemImage: "space", label: "Space") { controller.spaceTapped() }
                    Key(systemImage: "return", label: "Return") { controller.returnTapped() }
                    Key(systemImage: "keyboard.chevron.compact.down", label: "Hide keyboard", action: onDismiss)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: controller.suggestions)
    }

    private var suggestionBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                if i > 0 { Divider().frame(height: 20) }
                let word = controller.suggestions.indices.contains(i) ? controller.suggestions[i] : ""
                Button {
                    controller.pick(i)
                } label: {
                    Text(word)
                        .fontWeight(controller.chosen == i ? .semibold : .regular)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(word.isEmpty)
            }
        }
    }
}

private struct Key: View {
    var title: String?
    var systemImage: String?
    var label: String
    var action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.label = title
        self.action = action
    }

    init(systemImage: String, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else {
                    Text(title ?? "").font(.title3.weight(.medium))
                }
            }
            .frame(width: 46, height: 44)
            .background(.background, in: .rect(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
