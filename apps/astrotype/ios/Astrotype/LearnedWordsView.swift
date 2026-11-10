import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// The words the keyboard learned from the person, newest first (DESIGN.md screen 9,
/// "learned words", and features/learned-words). Swipe one away, or Select several, and
/// they are not offered again, here or on any synced device; + adds one by hand.
/// "Used once" shows the words it picked up a single time, where old typos hide
/// (features/word-control). With two languages on, each word says the language it is
/// offered in (or Both), a tab per language shows that language's words, and holding a
/// word moves it (Gabriel, 10 Nov 2026). With one language none of that shows.
struct LearnedWordsView: View {
    var model: AppModel
    @State private var editMode: EditMode = .inactive
    @State private var picked: Set<String> = []
    @State private var adding = false
    @State private var filter = Filter.all
    @State private var language: String?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", usedOnce = "Used once"
        var id: Self { self }
    }

    /// The languages on, when there are two; empty with one.
    private var languages: [String] {
        let on = model.activeLanguages
        return on.count > 1 ? on : []
    }

    var body: some View {
        let all = model.learnedWords.recent
        let languages = self.languages
        let inLanguage = languages.isEmpty || language == nil ? all
            : all.filter { model.learnedWords.contains($0, in: language) }
        let words = filter == .all ? inLanguage : inLanguage.filter(model.learnedWords.isUsedOnce)
        Group {
            if all.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("No learned words yet").font(.sw(.heading))
                    Text("Peck out a word the keyboard doesn't know and it learns it once you go on to the next word. Hold a guess on the bar to teach or block it. Or tap + to add one.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                List(selection: $picked) {
                    Section {
                        if !languages.isEmpty {
                            Picker("Language", selection: $language) {
                                Text("All languages").tag(String?.none)
                                ForEach(languages, id: \.self) { Text(Language.names[$0] ?? $0).tag(String?.some($0)) }
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Theme.Space.s, trailing: 0))
                        }
                        Picker("Show", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                    .selectionDisabled()
                    Section {
                        ForEach(words, id: \.self) { word in
                            HStack {
                                Text(word).font(.sw(.body))
                                Spacer()
                                if model.learnedWords.isAdded(word) {
                                    Chip("Added", tint: Theme.accent)
                                } else if model.learnedWords.isBoosted(word) {
                                    Chip("More", tint: Theme.sun)
                                }
                                if !languages.isEmpty {
                                    Text(Self.name(of: model.learnedWords.language(of: word)))
                                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                                }
                            }
                            .listRowBackground(Theme.card)
                            .contextMenu {
                                if !languages.isEmpty {
                                    let current = model.learnedWords.language(of: word)
                                    Section("Offer it in") {
                                        ForEach([String?.none] + languages.map(Optional.some), id: \.self) { code in
                                            Button {
                                                model.setLanguage(of: word, to: code)
                                            } label: {
                                                if code == current {
                                                    Label(Self.name(of: code), systemImage: "checkmark")
                                                } else {
                                                    Text(Self.name(of: code))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            model.forget(offsets.map { words[$0] }, how: .swipe)
                        }
                    } footer: {
                        Text(editMode.isEditing ? "Tap the words to delete."
                             : filter == .usedOnce ? (words.isEmpty ? "No words it has seen only once." : "Words it has seen you write only once. Typos tend to end up here: tap Select to drop several.")
                             : languages.isEmpty ? "Swipe a word left to drop it, or tap Select to drop several. Tap + to add one."
                             : "A word is offered in the language you wrote it in. Hold a word to offer it in another language or in both. Swipe it left to drop it.")
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
            AddWordSheet(model: model, languages: languages, language: language)
        }
        .onAppear { model.reloadWords() }
    }

    /// A language's name, or "Both" for a word offered in every language.
    static func name(of code: String?) -> String {
        code.map { Language.names[$0] ?? $0 } ?? "Both"
    }
}

/// "Add a word" (features/learned-words): one word, letters only, offered by the
/// keyboard from then on.
private struct AddWordSheet: View {
    var model: AppModel
    /// The languages on, when there are two (empty with one: nothing to pick).
    var languages: [String]
    /// The one it goes in, nil for both.
    @State var language: String?
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
                if !languages.isEmpty {
                    Picker("Language", selection: $language) {
                        Text("Both").tag(String?.none)
                        ForEach(languages, id: \.self) { Text(Language.names[$0] ?? $0).tag(String?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                }
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
        .presentationDetents([.height(languages.isEmpty ? 220 : 270), .medium])
        .onAppear { focused = true }
    }

    private func add(_ word: String?, known: Bool) {
        guard let word, !known, model.addWord(word, language: language) else { return }
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

/// The bar under a list while selecting: how many are picked, and Delete N (or another
/// `verb`, like Never suggest's "Allow").
struct DeleteBar: View {
    var count: Int
    var noun: String
    var verb = "Delete"
    var destructive = true
    var delete: () -> Void
    @State private var deleted = 0

    var body: some View {
        HStack {
            Text(count == 0 ? "Select \(noun)s" : "\(count) \(noun)\(count == 1 ? "" : "s") selected")
                .font(.sw(.body)).fontWeight(.bold)
            Spacer()
            Button(count == 0 ? verb : "\(verb) \(count)", role: destructive ? .destructive : nil) {
                deleted += 1
                delete()
            }
                .font(.sw(.body)).fontWeight(.heavy)
                .foregroundStyle(count == 0 ? Theme.muted : destructive ? Theme.danger : Theme.accent)
                .disabled(count == 0)
                .sensoryFeedback(.impact(weight: .light), trigger: deleted)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
