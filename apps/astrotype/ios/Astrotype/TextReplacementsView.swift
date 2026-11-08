import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// Text replacements (features/text-replacements), from Settings → Your words: type a
/// shortcut as a word and the keyboard writes its phrase, with `{date}` and the other
/// variables filled in. Newest first; tap one to edit it, swipe or Select to delete,
/// + to add. The phone's own replacements work too, unless switched off here, and can
/// be copied in to edit (the keyboard writes them for the app with Full Access). Your
/// details fill `{name}`, `{email}`, `{phone}` and `{address}`.
struct TextReplacementsView: View {
    @Bindable var model: AppModel
    @State private var editMode: EditMode = .inactive
    @State private var picked: Set<UUID> = []
    @State private var editing: TextReplacement?
    @State private var query = ""
    @State private var editingDetails = false
    /// The phone's replacements the keyboard last read, not yet in the list.
    @State private var fromPhone: [TextReplacement] = []

    var body: some View {
        let all = model.keyboardSettings.textReplacements
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = needle.isEmpty ? all : all.filter {
            $0.shortcut.contains(needle) || $0.phrase.lowercased().contains(needle)
        }
        List(selection: $picked) {
            Section {
                ForEach(shown) { item in
                    Button { if !editMode.isEditing { editing = item } } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.shortcut).font(.sw(.body)).fontWeight(.bold)
                            Text(TextReplacements.oneLine(item.phrase))
                                .font(.sw(.small)).foregroundStyle(Theme.muted)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                    .accessibilityHint("Edits this replacement")
                }
                .onDelete { offsets in
                    model.deleteReplacements(Set(offsets.map { shown[$0].id }))
                }
            } header: {
                Text("Type a shortcut, by tapping or swiping, and the keyboard writes the phrase instead. The bar shows what it will write, and offers a shortcut as you start typing it. Backspace right after takes it back. The text button on the bar lists them all.")
                    .font(.sw(.small)).foregroundStyle(Theme.muted)
                    .textCase(nil)
                    .padding(.bottom, Theme.Space.s)
            } footer: {
                if !shown.isEmpty {
                    Text(editMode.isEditing ? "Tap the replacements to delete." : "Tap one to edit it. Swipe left to delete, or tap Select to delete several.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                }
            }

            if !editMode.isEditing, needle.isEmpty {
                Section {
                    Button { editingDetails = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your details").font(.sw(.body))
                                Text(model.keyboardSettings.personalDetails.isEmpty
                                     ? "Your name, email, phone and address, for {name}, {email}, {phone} and {address}."
                                     : [model.keyboardSettings.personalDetails.name, model.keyboardSettings.personalDetails.email]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.sw(.small)).foregroundStyle(Theme.muted)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                }

                if !fromPhone.isEmpty {
                    Section {
                        Button {
                            model.copyReplacements(fromPhone)
                            fromPhone = []
                        } label: {
                            Label("Copy \(fromPhone.count) from your iPhone", systemImage: "square.and.arrow.down")
                                .font(.sw(.body)).fontWeight(.semibold)
                        }
                        .tint(Theme.accent)
                        .listRowBackground(Theme.card)
                    } footer: {
                        Text("Your iPhone's own text replacements, copied into this list so you can change them here. Ones with a shortcut you already have stay as yours.")
                            .font(.sw(.small)).foregroundStyle(Theme.muted)
                    }
                }

                Section {
                    Toggle(isOn: $model.keyboardSettings.usesPhoneReplacements) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use your iPhone's too").font(.sw(.body))
                            Text("The ones in iPhone Settings → General → Keyboard → Text Replacement. Yours here win on the same shortcut.")
                                .font(.sw(.small)).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.accent)
                    .listRowBackground(Theme.card)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .searchable(text: $query, prompt: "Find a replacement")
        .overlay {
            if shown.isEmpty {
                Text(needle.isEmpty ? "No replacements yet. Tap + to make one, like “omw” for “On my way!” or “tdy” for today's date."
                     : "No replacements with “\(needle)”.")
                    .font(.sw(.body)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Space.gutter)
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle("Text replacements")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !shown.isEmpty || editMode.isEditing {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        picked = []
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .fontWeight(editMode.isEditing ? .bold : .regular)
                }
                if !editMode.isEditing {
                    Button { editing = TextReplacement(shortcut: "", phrase: "") } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add a text replacement")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode.isEditing {
                DeleteBar(count: picked.count, noun: "replacement") {
                    model.deleteReplacements(picked)
                    picked = []
                    withAnimation { editMode = .inactive }
                }
            }
        }
        .sheet(item: $editing) { item in
            ReplacementSheet(model: model, original: item)
        }
        .sheet(isPresented: $editingDetails) {
            YourDetailsSheet(model: model)
        }
        .onAppear(perform: readPhone)
        .onChange(of: model.keyboardSettings.textReplacements) { readPhone() }
    }

    private func readPhone() {
        fromPhone = PhoneReplacementsFile.toCopy(
            PhoneReplacementsFile.load(from: KeyboardFiles.shared(KeyboardFiles.phoneReplacements)),
            into: model.keyboardSettings.textReplacements)
    }
}

/// Adding or editing one replacement: the shortcut, the phrase, the variables to drop
/// into it, and what it writes right now.
private struct ReplacementSheet: View {
    var model: AppModel
    var original: TextReplacement
    @Environment(\.dismiss) private var dismiss
    @State private var shortcut = ""
    @State private var phrase = ""
    @FocusState private var focus: Focus?

    private enum Focus { case shortcut, phrase }

    var body: some View {
        let key = TextReplacements.shortcut(shortcut)
        let typed = !shortcut.trimmingCharacters(in: .whitespaces).isEmpty
        let taken = key.flatMap { k in model.keyboardSettings.textReplacements.first { $0.shortcut == k && $0.id != original.id } }
        let isNew = !model.keyboardSettings.textReplacements.contains { $0.id == original.id }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    label("Shortcut")
                    TextField("omw", text: $shortcut)
                        .font(.sw(.body))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .shortcut)
                        .onSubmit { focus = .phrase }
                        .padding(.horizontal, Theme.Space.m).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.card))
                    Text(!typed ? "One word, like omw, or with symbols, like ;addr or @@."
                         : key == nil ? "2 to 24 characters, no spaces, and not only numbers."
                         : taken != nil ? "Replaces the one you already have for “\(key!)”."
                         : TextReplacements.isWord(key!) ? "Type or swipe “\(key!)” on the keyboard."
                         : "Type “\(key!)” on the keyboard, then space.")
                        .font(.sw(.small))
                        .foregroundStyle(typed && key == nil ? Theme.danger : Theme.muted)
                        .padding(.horizontal, Theme.Space.xs)

                    label("Phrase").padding(.top, Theme.Space.s)
                    TextField("On my way!", text: $phrase, axis: .vertical)
                        .font(.sw(.body))
                        .lineLimit(3...8)
                        .focused($focus, equals: .phrase)
                        .padding(.horizontal, Theme.Space.m).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.card))

                    label("Add to the phrase").padding(.top, Theme.Space.s)
                    FlowLayout(spacing: Theme.Space.s) {
                        ForEach(TextReplacements.variables) { variable in
                            Button { phrase += variable.token } label: {
                                Text(variable.token).font(.sw(.small)).fontWeight(.bold)
                                    .padding(.horizontal, Theme.Space.m).padding(.vertical, 8)
                                    .frame(minHeight: 44)
                                    .background(Capsule().fill(Theme.card))
                                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(variable.title.lowercased())")
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("These fill in as the phrase goes in:")
                        ForEach(TextReplacements.variables) { variable in
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                                Text(variable.token).fontWeight(.bold)
                                Text(variable.title)
                            }
                        }
                        Text("{?name} asks on the bar before the phrase goes in; use any name, as many as you like. {pick:…} takes words split by |.")
                    }
                    .font(.sw(.small)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, Theme.Space.xs)

                    if !phrase.isEmpty, phrase.contains("{") {
                        label("Right now it writes").padding(.top, Theme.Space.s)
                        Text(preview)
                            .font(.sw(.body))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Space.m).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .strokeBorder(Theme.line, lineWidth: 1))
                    }
                }
                .padding(Theme.Space.gutter)
            }
            .background(Theme.bg.ignoresSafeArea())
            .foregroundStyle(Theme.ink)
            .navigationTitle(isNew ? "New replacement" : "Edit replacement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(key == nil || phrase.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            shortcut = original.shortcut
            phrase = original.phrase
            focus = original.shortcut.isEmpty ? .shortcut : .phrase
        }
    }

    /// What the phrase writes now, the cursor shown where `{cursor}` puts it.
    private var preview: String {
        let context = TextReplacements.Context(clipboard: { "[clipboard]" }, details: model.keyboardSettings.personalDetails,
                                               random: { _ in 0 })
        let out = TextReplacements.expand(phrase, in: context)
        guard let back = out.cursorFromEnd else { return out.text }
        var text = out.text
        text.insert("|", at: text.index(text.endIndex, offsetBy: -back))
        return text
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.sw(.small)).fontWeight(.bold).foregroundStyle(Theme.muted)
            .padding(.horizontal, Theme.Space.xs)
    }

    private func save() {
        var item = original
        item.shortcut = shortcut
        item.phrase = phrase
        guard model.saveReplacement(item) else { return }
        dismiss()
    }
}

/// Chips laid out in rows, wrapping to the width they're given (the variables).
private struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { row in row.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, row.count - 1)) }.max() ?? 0
        let height = rows.reduce(0) { $0 + ($1.map(\.height).max() ?? 0) } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var index = 0
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            let height = row.map(\.height).max() ?? 0
            for size in row {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
                index += 1
            }
            y += height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [[CGSize]] {
        var rows: [[CGSize]] = [[]]
        var used: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].isEmpty, used + spacing + size.width > width {
                rows.append([])
                used = 0
            }
            used += (rows[rows.count - 1].isEmpty ? 0 : spacing) + size.width
            rows[rows.count - 1].append(size)
        }
        return rows
    }
}
