import PenguinKit
import SquawkKit
import SwiftUI

/// Settings: Squawk Pro, Squawk's outfit, the app icon, restoring purchases and sharing
/// usage data.
struct SettingsView: View {
    @Environment(ProModel.self) private var pro
    @Environment(AlarmsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Wardrobe.key) private var outfitID = ""
    @State private var paywall: ProFeature?
    @State private var showingPro = false
    @State private var icon = SquawkIcon.current
    @State private var restoring = false
    @State private var restoreNote: String?
    @State private var shareData = Telemetry.isEnabled

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    proCard
                    outfitCard
                    iconCard
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $shareData) {
                                Text("Share anonymous usage data").font(Theme.label)
                            }
                            .tint(Theme.mint)
                            Text("Crash reports and counts like \"alarm created\". Nothing about you. Changes on the next launch.")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    VStack(spacing: 6) {
                        Button(restoring ? "Restoring…" : "Restore purchases", action: restore)
                            .buttonStyle(LinkButtonStyle())
                            .disabled(restoring)
                        if let restoreNote {
                            Text(restoreNote)
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                        }
                        Text("Squawk \(version)")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.heavy)
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .onChange(of: shareData) { _, on in Telemetry.isEnabled = on }
        .proSheet($paywall)
        .sheet(isPresented: $showingPro) { ProView() }
    }

    // MARK: Pro

    private var proCard: some View {
        Button { showingPro = true } label: {
            HStack(spacing: 14) {
                PenguinView(mood: .proud, accessory: pro.access.isPro ? .partyHat : nil, animated: false)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pro.access.isPro ? "You're Pro!" : "Squawk Pro").font(Theme.title(22))
                    Text(pro.access.isPro ? "Thanks for helping Squawk." : "More rings, wake-up checks, every sound and outfit.")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.muted)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sun.opacity(0.22), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(SquishStyle())
    }

    // MARK: Outfit

    private var outfitCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Squawk's outfit").font(Theme.label)
                Text("Earn outfits by getting up on the first ring, or get them all with Pro.")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    OutfitTile(name: "None", accessory: nil, note: nil, selected: wearing == nil, locked: false) {
                        outfitID = ""
                    }
                    ForEach(Outfit.allCases) { outfit in
                        let allowed = pro.access.allows(outfit, bestStreak: model.log.bestStreak)
                        OutfitTile(
                            name: outfit.name, accessory: outfit.accessory,
                            note: allowed ? nil : outfit.howToGet,
                            selected: wearing == outfit, locked: !allowed
                        ) {
                            if allowed {
                                outfitID = outfit.rawValue
                                Telemetry.count("outfit.changed", ["outfit": outfit.rawValue])
                            } else {
                                paywall = .outfits
                            }
                        }
                    }
                }
            }
        }
    }

    private var wearing: Outfit? {
        Outfit(rawValue: outfitID).flatMap { pro.access.allows($0, bestStreak: model.log.bestStreak) ? $0 : nil }
    }

    // MARK: App icon

    private var iconCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("App icon").font(Theme.label)
                    if !pro.access.allows(.appIcons) { ProBadge() }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                    ForEach(SquawkIcon.allCases) { choice in
                        let locked = choice != .standard && !pro.access.allows(.appIcons)
                        Button {
                            if locked {
                                paywall = .appIcons
                            } else {
                                icon = choice
                                Task { await choice.apply() }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                choice.preview
                                    .resizable()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .stroke(Theme.accent, lineWidth: icon == choice ? 3 : 0)
                                            .padding(-4)
                                    )
                                    .opacity(locked ? 0.6 : 1)
                                Text(choice.title)
                                    .font(.system(.caption, design: .rounded, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        .buttonStyle(SquishStyle())
                        .accessibilityLabel("\(choice.title) icon\(locked ? ", needs Pro" : "")")
                        .accessibilityAddTraits(icon == choice ? .isSelected : [])
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func restore() {
        restoring = true
        restoreNote = nil
        Task {
            let found = await pro.restore()
            restoring = false
            restoreNote = found ? "Pro is back. Welcome back!" : "No Squawk Pro found for this Apple Account."
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

/// One outfit choice: Squawk wearing it, its name, and how to get it when locked.
private struct OutfitTile: View {
    var name: String
    var accessory: PenguinAccessory?
    var note: String?
    var selected: Bool
    var locked: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                PenguinView(mood: .awake, accessory: accessory, animated: false)
                    .frame(width: 60, height: 60)
                    .opacity(locked ? 0.45 : 1)
                    .overlay(alignment: .topTrailing) {
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                Text(name)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let note {
                    Text(note)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 8)
            .background(selected ? Theme.accent.opacity(0.15) : Theme.ice.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.accent, lineWidth: selected ? 2.5 : 0))
        }
        .buttonStyle(SquishStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(locked ? "\(name), locked. \(note ?? "")" : name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    SettingsView()
        .environment(ProModel.preview())
        .environment(AlarmsModel.preview())
}

#Preview("Pro, large text") {
    SettingsView()
        .environment(ProModel.preview(isPro: true))
        .environment(AlarmsModel.preview())
        .dynamicTypeSize(.accessibility3)
}
