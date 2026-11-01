import StackWriteCore
import StackWriteUI
import SwiftUI

/// The words the keyboard learned from the person, newest first (DESIGN.md screen 9,
/// "learned words"). Swipe one away and it is not offered again, here or on any
/// synced device.
struct LearnedWordsView: View {
    var model: AppModel

    var body: some View {
        let words = model.learnedWords.recent
        Group {
            if words.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("No learned words yet").font(.sw(.heading))
                    Text("Peck out a word the keyboard doesn't know and it learns it when you write it. Hold a guess on the bar and slide up to keep it, or down to drop it.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                List {
                    Section {
                        ForEach(words, id: \.self) { word in
                            HStack {
                                Text(word).font(.sw(.body))
                                Spacer()
                                if model.learnedWords.isBoosted(word) {
                                    Chip("Kept", tint: Theme.mint)
                                }
                            }
                            .listRowBackground(Theme.card)
                        }
                        .onDelete { offsets in
                            for offset in offsets { model.forget(words[offset]) }
                        }
                    } footer: {
                        Text("Swipe a word left to drop it.")
                            .font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Learned words")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .onAppear { model.reloadWords() }
    }
}
