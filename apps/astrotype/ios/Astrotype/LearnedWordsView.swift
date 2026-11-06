import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// The words the keyboard learned from the person, newest first (DESIGN.md screen 9,
/// "learned words", and features/learned-words). Swipe one away, or Select several, and
/// they are not offered again, here or on any synced device; + adds one by hand.
struct LearnedWordsView: View {
    var model: AppModel
    @State private var editMode: EditMode = .inactive
    @State private var picked: Set<String> = []
    @State private var adding = false

    var body: some View {
        let words = model.learnedWords.recent
        Group {
            if words.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("No learned words yet").font(.sw(.heading))
                    Text("Peck out a word the keyboard doesn't know and it learns it when you write it. Hold a guess on the bar and slide up to keep it, or down to drop it. Or tap + to add one.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                List(selection: $picked) {
                    Section {
                        ForEach(words, id: \.self) { word in
                            HStack {
                                Text(word).font(.sw(.body))
                                Spacer()
                                if model.learnedWords.isAdded(word) {
                                    Chip("Added", tint: Theme.accent)
                                } else if model.learnedWords.isBoosted(word) {
                                    Chip("Kept", tint: Theme.mint)
                                }
                            }
                            .listRowBackground(Theme.card)
                        }
                        .onDelete { offsets in
                            model.forget(offsets.map { words[$0] }, how: .swipe)
                        }
                    } footer: {
                        Text(editMode.isEditing ? "Tap the words to delete." : "Swipe a word left to drop it, or tap Select to drop several. Tap + to add one.")
                            .font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, $editMode)
            }
        }
        .navigationTitle("Learned words")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SelectButton(editMode: $editMode, picked: $picked, hidden: words.isEmpty)
                if !editMode.isEditing {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add a word")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode.isEditing {
                DeleteBar(count: picked.count, noun: "word") {
                    model.forget(words.filter(picked.contains), how: .select)
                    picked = []
                    withAnimation { editMode = .inactive }
                }
            }
        }
        .sheet(isPresented: $adding) {
            AddWordSheet(model: model)
        }
        .onAppear { model.reloadWords() }
    }
}

/// "Add a word" (features/learned-words): one word, letters only, offered by the
/// keyboard from then on.
private struct AddWordSheet: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let word = LearnedWords.addable(text)
        let known = word.map(model.learnedWords.contains) ?? false
        let typed = !text.trimmingCharacters(in: .whitespaces).isEmpty
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                TextField("A word the keyboard should know", text: $text)
                    .font(.sw(.body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit { add(word, known: known) }
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.card))
                Text(!typed ? "The keyboard offers it from now on, on all your devices."
                     : word == nil ? "One word, letters only."
                     : known ? "It already knows that one."
                     : "The keyboard offers it from now on, on all your devices.")
                    .font(.sw(.small))
                    .foregroundStyle(typed && (word == nil || known) ? Theme.danger : Theme.muted)
                    .padding(.horizontal, Theme.Space.xs)
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.gutter)
            .background(Theme.bg.ignoresSafeArea())
            .foregroundStyle(Theme.ink)
            .navigationTitle("Add a word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add(word, known: known) }.disabled(word == nil || known)
                }
            }
        }
        .presentationDetents([.height(220), .medium])
        .onAppear { focused = true }
    }

    private func add(_ word: String?, known: Bool) {
        guard let word, !known, model.addWord(word) else { return }
        dismiss()
    }
}

/// Select / Done in a list's top bar: Select puts the circles on the rows.
struct SelectButton: View {
    @Binding var editMode: EditMode
    @Binding var picked: Set<String>
    var hidden = false

    var body: some View {
        if !hidden || editMode.isEditing {
            Button(editMode.isEditing ? "Done" : "Select") {
                picked = []
                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
            }
            .fontWeight(editMode.isEditing ? .bold : .regular)
        }
    }
}

/// The bar under a list while selecting: how many are picked, and Delete N.
struct DeleteBar: View {
    var count: Int
    var noun: String
    var delete: () -> Void
    @State private var deleted = 0

    var body: some View {
        HStack {
            Text(count == 0 ? "Select \(noun)s" : "\(count) \(noun)\(count == 1 ? "" : "s") selected")
                .font(.sw(.body)).fontWeight(.bold)
            Spacer()
            Button(count == 0 ? "Delete" : "Delete \(count)", role: .destructive) {
                deleted += 1
                delete()
            }
                .font(.sw(.body)).fontWeight(.heavy)
                .foregroundStyle(count == 0 ? Theme.muted : Theme.danger)
                .disabled(count == 0)
                .sensoryFeedback(.impact(weight: .light), trigger: deleted)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
