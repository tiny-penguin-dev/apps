import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// "Words it missed" (features/missed-words Phase C): the swipes the person fixed with
/// "Not it?" in the bar, newest first, each with the word meant, what the keyboard
/// wrote, and the swipe drawn on the keys. The keyboard remembers these shapes; swipe
/// one away and it is forgotten here (and not sent if it was waiting).
struct MissedWordsView: View {
    var model: AppModel
    @State private var selected: UUID?

    var body: some View {
        let words = model.missedWords
        Group {
            if words.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Nothing missed yet").font(.sw(.heading))
                    Text("When a swipe gets a word wrong, tap Not it? in the bar and type the word you meant. It shows up here, and the keyboard remembers that swipe.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                List {
                    if let word = words.first(where: { $0.id == selected }) ?? words.first {
                        Section {
                            SharedPathsView(word: word)
                                .aspectRatio(word.layoutWidth / max(1, word.layoutHeight), contentMode: .fit)
                                .accessibilityLabel("Your swipe for \(word.word)")
                                .listRowBackground(Theme.card)
                        }
                    }
                    Section {
                        ForEach(words) { word in
                            Button { selected = word.id } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(word.word).font(.sw(.body)).foregroundStyle(Theme.ink)
                                        if let typed = word.typed {
                                            Text("wrote: \(typed)").font(.sw(.small)).foregroundStyle(Theme.muted)
                                        }
                                    }
                                    Spacer()
                                    Text(status(of: word)).font(.sw(.small)).foregroundStyle(Theme.muted)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground((selected ?? words.first?.id) == word.id ? Theme.ice : Theme.card)
                            .accessibilityAddTraits((selected ?? words.first?.id) == word.id ? .isSelected : [])
                        }
                        .onDelete { offsets in
                            for offset in offsets { model.removeMissed(words[offset].id) }
                        }
                    } footer: {
                        Text("Tap one to see your swipe. Swipe left to drop it. With Include corrections on, they help tune the keyboard for everyone.")
                            .font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Words it missed")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .onAppear { model.reloadMissed() }
    }

    private func status(of word: SharedWord) -> String {
        if model.sentMisses.contains(word.id) { return "Shared" }
        if model.waitingMisses.contains(word.id) { return "Waiting to share" }
        return "On this phone"
    }
}
