import PenguinKit
import SquawkKit
import SwiftUI

/// The "Wake-up checks" card in More options: the checks this alarm has, and adding one.
struct ChecksCard: View {
    @Binding var alarm: Alarm
    @Environment(ProModel.self) private var pro
    @State private var adding: WakeUpCheck.Kind?
    @State private var paywall: ProFeature?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("Wake-up checks").font(Theme.label)
                    if !pro.access.allows(.checks) { ProBadge() }
                }
                Text("With a check on, the last ring comes back every 30 seconds for up to 10 minutes, until you do it.")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                ForEach(alarm.checks) { check in
                    HStack(spacing: 10) {
                        Image(systemName: check.kind.symbol)
                            .font(.body.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.kind.title).font(.system(.body, design: .rounded, weight: .bold))
                            if !check.place.isEmpty {
                                Text(check.place)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                        Button {
                            withAnimation(.spring) { alarm.checks.removeAll { $0.id == check.id } }
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.muted)
                        }
                        .accessibilityLabel("Remove \(check.kind.title)")
                    }
                }
                if !pro.access.allows(.checks) {
                    ProLinkButton(title: "+ Add a check", locked: true, action: {}, onLocked: { paywall = .checks })
                } else {
                    Menu {
                        ForEach(availableKinds, id: \.self) { kind in
                            Button {
                                if kind == .game {
                                    withAnimation(.spring) { alarm.checks.append(WakeUpCheck(kind: .game)) }
                                    Telemetry.count("check.added", ["kind": "game"])
                                } else {
                                    adding = kind
                                }
                            } label: {
                                Label(kind.title, systemImage: kind.symbol)
                            }
                        }
                    } label: {
                        Text("+ Add a check")
                    }
                    .buttonStyle(LinkButtonStyle())
                }
                Divider()
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "function").font(.body.weight(.bold)).foregroundStyle(Theme.muted).frame(width: 28)
                    Text("Stuck? A math question always turns it off too.")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .proSheet($paywall)
        .sheet(item: $adding) { kind in
            AddCheckSheet(kind: kind) { check in
                withAnimation(.spring) { alarm.checks.append(check) }
                Telemetry.count("check.added", ["kind": kind.rawValue])
            }
        }
    }

    /// Kinds this phone can do. The game can be added once.
    private var availableKinds: [WakeUpCheck.Kind] {
        WakeUpCheck.Kind.allCases.filter { kind in
            switch kind {
            case .tag: TagReader.isAvailable
            case .code: CodeScanner.isAvailable
            case .game: !alarm.checks.contains { $0.kind == .game }
            }
        }
    }
}

/// Set up a tag or code: scan it once here, and say where it is.
private struct AddCheckSheet: View {
    var kind: WakeUpCheck.Kind
    var onAdd: (WakeUpCheck) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var secret = ""
    @State private var place = ""
    @State private var reader = TagReader()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(intro)
                        .font(Theme.body)
                        .foregroundStyle(Theme.muted)
                    if secret.isEmpty {
                        scanner
                    } else {
                        Card {
                            HStack(spacing: 12) {
                                PenguinView(mood: .proud, animated: false).frame(width: 56, height: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(kind == .tag ? "Tag saved" : "Code saved").font(Theme.label)
                                    Button("Scan a different one") { secret = "" }
                                        .buttonStyle(LinkButtonStyle())
                                }
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Where is it?").font(Theme.label)
                            TextField(kind == .tag ? "Bathroom mirror" : "Coffee bag", text: $place)
                                .font(Theme.body)
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(WakeUpCheck(kind: kind, secret: secret, place: place.trimmingCharacters(in: .whitespaces)))
                        dismiss()
                    }
                    .fontWeight(.heavy)
                    .disabled(secret.isEmpty)
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
    }

    private var intro: String {
        switch kind {
        case .tag: "Stick an NFC tag somewhere far from bed, like the bathroom mirror. Scan it once now so Squawk knows it."
        case .code: "Pick any QR code or barcode far from bed, like your coffee bag or toothpaste. Scan it once now so Squawk knows it."
        case .game: ""
        }
    }

    @ViewBuilder private var scanner: some View {
        switch kind {
        case .tag:
            Button("Scan my tag") {
                Task {
                    if let id = await reader.scan(prompt: "Hold the top of your iPhone near the tag.") {
                        withAnimation(.spring) { secret = id }
                    }
                }
            }
            .buttonStyle(PillButtonStyle())
        case .code:
            CodeScanner { code in
                guard secret.isEmpty else { return }
                withAnimation(.spring) { secret = code.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        case .game:
            EmptyView()
        }
    }
}

extension WakeUpCheck.Kind {
    var title: String {
        switch self {
        case .tag: "Scan a tag"
        case .code: "Scan a code"
        case .game: "Penguin game"
        }
    }

    var symbol: String {
        switch self {
        case .tag: "wave.3.right"
        case .code: "qrcode.viewfinder"
        case .game: "gamecontroller.fill"
        }
    }
}
