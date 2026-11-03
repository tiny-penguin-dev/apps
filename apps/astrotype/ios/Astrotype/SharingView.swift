import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// "What gets shared" (features/smart-matching Phase C): the words waiting to go up,
/// exactly as they will be sent, one drawn on the keyboard with its thumb paths. Each
/// can be taken off the list; "Send now" sends the rest.
struct SharingView: View {
    var model: AppModel
    @State private var selected: UUID?

    var body: some View {
        let words = model.pendingShared
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("What gets shared").font(.sw(.title)).padding(.top, Theme.Space.s)
                Text("Each item is one word: the word, the paths your thumbs drew over the keys, your phone model and system version, the day, and a random ID for this install. Never a sentence, your name or your account.")
                    .font(.sw(.small)).foregroundStyle(Theme.muted)

                if let word = words.first(where: { $0.id == selected }) ?? words.first {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            SharedPathsView(word: word)
                                .aspectRatio(word.layoutWidth / max(1, word.layoutHeight), contentMode: .fit)
                                .accessibilityLabel("The paths your thumbs drew for \(word.word)")
                            Text(fields(of: word)).font(.sw(.small)).foregroundStyle(Theme.muted)
                        }
                    }
                }

                if words.isEmpty {
                    Text(model.sharePractice ? "Nothing waiting. Speed tests and drills add words here." : "Nothing waiting. Turn on Send practice sessions in Settings to share.")
                        .font(.sw(.body))
                } else {
                    HStack {
                        Text("\(words.count) waiting").font(.sw(.heading))
                        Spacer()
                        if model.uploadingPractice {
                            ProgressView().tint(Theme.accent)
                        } else {
                            Button("Send \(words.count) now") { model.uploadPractice() }
                                .buttonStyle(.small)
                                .disabled(!model.sharePractice)
                        }
                    }
                    ForEach(words) { word in
                        Row(title(of: word), subtitle: subtitle(of: word)) {
                            Button("Remove") { model.removeShared(word.id) }.buttonStyle(.ghost)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selected = word.id }
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .stroke(Theme.accent, lineWidth: (selected ?? words.first?.id) == word.id ? 2 : 0)
                        }
                        .accessibilityAddTraits((selected ?? words.first?.id) == word.id ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { model.reloadShared() }
    }

    private func title(of word: SharedWord) -> String {
        if let typed = word.typed { return "\(typed) → \(word.word)" }
        return word.word
    }

    private func subtitle(of word: SharedWord) -> String {
        if word.isMiss { return "A word the keyboard missed (Not it?)" }
        if word.isCorrection { return "A fix you made in another app" }
        let kind = word.kind.hasPrefix("word.drill") ? "Drill" : "Speed test"
        return word.typed == nil ? kind : "\(kind) · the keyboard got it wrong"
    }

    /// The record's fields in plain words, the device line as the upload will add it.
    private func fields(of word: SharedWord) -> String {
        var lines = ["Word: \(word.word)"]
        if let typed = word.typed { lines.append("The keyboard wrote: \(typed)") }
        if let previous = word.previous, previous != NgramModel.sentenceStart { lines.append("Word asked for before it: \(previous)") }
        lines.append("Touches: \(word.touches.count), \(word.touches.reduce(0) { $0 + $1.points.count }) points")
        lines.append("Phone: \(model.device.model), \(model.device.system) · Astrotype \(model.device.app)")
        lines.append("Day: \(word.day) · Install ID: \(model.device.writer.prefix(8))…")
        return lines.joined(separator: "\n")
    }
}

/// The keyboard as the word was typed on it, with each thumb's path in its colour.
/// One shared word drawn on the keys it was typed on, with its thumbs' paths.
struct SharedPathsView: View {
    let word: SharedWord

    var body: some View {
        Canvas { context, size in
            let layout = Layout.qwerty(width: word.layoutWidth, split: word.split, height: word.layoutHeight)
            let scale = min(size.width / max(1, layout.width), size.height / max(1, layout.height))
            for placement in layout.placements where placement.key.character != nil {
                let frame = placement.frame.applying(CGAffineTransform(scaleX: scale, y: scale)).insetBy(dx: 1, dy: 1)
                context.fill(Path(roundedRect: frame, cornerRadius: 4 * scale), with: .color(Theme.key.opacity(0.6)))
                if let letter = placement.key.character {
                    context.draw(Text(String(letter)).font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.muted), at: CGPoint(x: frame.midX, y: frame.midY))
                }
            }
            for touch in word.touches {
                let points = touch.points.filter { $0.count >= 2 }.map {
                    CGPoint(x: $0[0] * layout.width * scale, y: $0[1] * layout.height * scale)
                }
                guard let first = points.first else { continue }
                let color = first.x < size.width / 2 ? Theme.left : Theme.right
                if points.count == 1 {
                    context.fill(Path(ellipseIn: CGRect(x: first.x - 5, y: first.y - 5, width: 10, height: 10)), with: .color(color))
                } else {
                    var path = Path()
                    path.addLines(points)
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    context.fill(Path(ellipseIn: CGRect(x: first.x - 4, y: first.y - 4, width: 8, height: 8)), with: .color(color))
                }
            }
        }
        .background(Theme.kb, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}
