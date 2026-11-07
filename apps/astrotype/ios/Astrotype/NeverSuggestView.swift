import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// "Never suggest" (features/word-control): the words the keyboard won't offer, blocked
/// from the bar's word menu, a slide down on a guess, a delete in Learned words or + here.
/// Newest first, with the day each went on. Swipe one away, or Select several, to allow
/// them again on every device.
struct NeverSuggestView: View {
    var model: AppModel
    @State private var editMode: EditMode = .inactive
    @State private var picked: Set<String> = []
    @State private var adding = false
    @State private var query = ""

    var body: some View {
        let all = model.learnedWords.blocked
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = needle.isEmpty ? all : all.filter { $0.word.contains(needle) }
        List(selection: $picked) {
            Section {
                ForEach(shown) { entry in
                    HStack {
                        Text(entry.word).font(.sw(.body))
                        Spacer()
                        Text(Self.day(entry.since)).font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                    .listRowBackground(Theme.card)
                    .accessibilityElement(children: .combine)
                }
                .onDelete { offsets in
                    model.allow(offsets.map { shown[$0].word }, how: .swipe)
                }
            } header: {
                Text("The keyboard won't offer these, on any of your devices. You can still type them letter by letter.")
                    .font(.sw(.small)).foregroundStyle(Theme.muted)
                    .textCase(nil)
                    .padding(.bottom, Theme.Space.s)
            } footer: {
                if !shown.isEmpty {
                    Text(editMode.isEditing ? "Tap the words to allow again." : "Swipe a word left to allow it again, or tap Select to allow several. Tap + to add one.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .searchable(text: $query, prompt: "Find a word")
        .overlay {
            if shown.isEmpty {
                Text(needle.isEmpty ? "Nothing blocked. Hold a guess on the keyboard and tap Never suggest." : "No blocked words with “\(needle)”.")
                    .font(.sw(.body)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Space.gutter)
            }
        }
        .navigationTitle("Never suggest")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SelectButton(editMode: $editMode, picked: $picked, hidden: shown.isEmpty)
                if !editMode.isEditing {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Never suggest a word")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode.isEditing {
                DeleteBar(count: picked.count, noun: "word", verb: "Allow", destructive: false) {
                    model.allow(shown.map(\.word).filter(picked.contains), how: .select)
                    picked = []
                    withAnimation { editMode = .inactive }
                }
            }
        }
        .sheet(isPresented: $adding) {
            BlockWordSheet(model: model)
        }
        .onAppear { model.reloadWords() }
    }

    /// "Today", "Yesterday", or the day ("3 Nov").
    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// + on Never suggest: one word, which the keyboard stops offering.
private struct BlockWordSheet: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let word = LearnedWords.addable(text)
        let blocked = word.map(model.learnedWords.isBlocked) ?? false
        let typed = !text.trimmingCharacters(in: .whitespaces).isEmpty
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                TextField("A word it should never suggest", text: $text)
                    .font(.sw(.body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit { block(word, blocked: blocked) }
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.card))
                Text(!typed ? "It stops offering this word, on all your devices."
                     : word == nil ? "One word, letters only."
                     : blocked ? "It already never suggests that one."
                     : "It stops offering this word, on all your devices.")
                    .font(.sw(.small))
                    .foregroundStyle(typed && (word == nil || blocked) ? Theme.danger : Theme.muted)
                    .padding(.horizontal, Theme.Space.xs)
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.gutter)
            .background(Theme.bg.ignoresSafeArea())
            .foregroundStyle(Theme.ink)
            .navigationTitle("Never suggest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { block(word, blocked: blocked) }.disabled(word == nil || blocked)
                }
            }
        }
        .presentationDetents([.height(220), .medium])
        .onAppear { focused = true }
    }

    private func block(_ word: String?, blocked: Bool) {
        guard let word, !blocked, model.blockWord(word) else { return }
        dismiss()
    }
}
