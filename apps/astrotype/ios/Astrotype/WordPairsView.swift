import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// "Word pairs" (features/learned-words): the pairs of words the person writes, which
/// "Learns from you" counts, with a search, two orders, and deleting them one by one or
/// several at once. A deleted pair is forgotten on every device until it is written
/// again.
struct WordPairsView: View {
    var model: AppModel
    @State private var pairs: [LearnedPair] = []
    @State private var loaded = false
    @State private var query = ""
    @State private var order = Order.mostUsed
    @State private var editMode: EditMode = .inactive
    @State private var picked: Set<String> = []

    enum Order: String, CaseIterable, Identifiable {
        case mostUsed = "Most used", newest = "Newest"
        var id: Self { self }
    }

    var body: some View {
        let shown = sorted(pairs.filter { $0.matches(query) })
        List(selection: $picked) {
            Section {
                Picker("Order", selection: $order) {
                    ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Words you write one after another. It uses them to guess your next word and to pick between close swipes. They fade if you stop writing them.")
                    .font(.sw(.small)).foregroundStyle(Theme.muted)
                    .textCase(nil)
                    .padding(.bottom, Theme.Space.s)
            }
            .selectionDisabled()

            if !shown.isEmpty {
                Section {
                    ForEach(shown) { pair in
                        PairRow(pair: pair).listRowBackground(Theme.card)
                    }
                    .onDelete { offsets in
                        forget(offsets.map { shown[$0].id }, how: .swipe)
                    }
                } footer: {
                    Text(editMode.isEditing ? "Tap the pairs to delete." : "Swipe a pair left to drop it, or tap Select to drop several. A pair comes back if you keep writing it.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .overlay {
            if loaded && shown.isEmpty {
                Text(query.isEmpty ? "No word pairs yet. It learns them as you type in other apps." : "No pairs with “\(query)”.")
                    .font(.sw(.body)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Space.gutter)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a word")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle("Word pairs")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SelectButton(editMode: $editMode, picked: $picked, hidden: pairs.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode.isEditing {
                DeleteBar(count: picked.count, noun: "pair") {
                    forget(Array(picked), how: .select)
                    picked = []
                    withAnimation { editMode = .inactive }
                }
            }
        }
        .onAppear {
            pairs = model.learnedPairs()
            loaded = true
            model.pairsOpened()
        }
    }

    private func sorted(_ pairs: [LearnedPair]) -> [LearnedPair] {
        switch order {
        case .mostUsed: pairs.sorted { ($0.count, $1.id) > ($1.count, $0.id) }
        case .newest: pairs.sorted { ($0.lastDay, $0.count, $1.id) > ($1.lastDay, $1.count, $0.id) }
        }
    }

    private func forget(_ ids: [String], how: AppModel.DeleteGesture) {
        model.forgetPairs(ids, how: how)
        let gone = Set(ids)
        withAnimation { pairs.removeAll { gone.contains($0.id) } }
    }
}

/// One pair: the first word muted, the second in ink, and how often it is written.
private struct PairRow: View {
    var pair: LearnedPair

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text("\(Text(pair.previous).foregroundStyle(Theme.muted)) \(Text(pair.word).fontWeight(.heavy))")
                .font(.sw(.body))
            Spacer(minLength: 0)
            UseMeter(level: pair.level)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pair.previous), then \(pair.word)")
        .accessibilityValue(UseMeter.label(pair.level))
    }
}

/// Four rising bars, filled to how often something is used (1 to 4).
struct UseMeter: View {
    var level: Int
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 18

    static func label(_ level: Int) -> String {
        ["Rarely", "Sometimes", "Often", "Very often"][min(max(level, 1), 4) - 1]
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(bar <= level ? Theme.mint : Theme.line)
                    .frame(width: 5, height: height * CGFloat(bar + 1) / 5)
            }
        }
        .accessibilityHidden(true)
    }
}
