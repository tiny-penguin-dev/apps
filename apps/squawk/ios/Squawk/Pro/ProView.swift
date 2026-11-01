import PenguinKit
import SquawkKit
import StoreKit
import SwiftUI

/// Screen 7: what Pro adds and the two plans. Buying goes through Apple's subscription
/// view, which shows the launch price when you can get it, the renewal price, Restore and
/// the terms. With Pro on, it says thanks and links to managing the subscription.
struct ProView: View {
    /// The Pro thing that was tapped to get here, highlighted in the list.
    var from: ProFeature?
    @Environment(ProModel.self) private var pro
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if pro.access.isPro {
                YoureProView { dismiss() }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                store
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.3), value: pro.access.isPro)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .onAppear {
            Telemetry.count("pro.shown", ["from": from?.rawValue ?? "settings"])
        }
    }

    private var store: some View {
        SubscriptionStoreView(productIDs: ProProducts.all) {
            ProHeader(highlight: from)
        }
        .subscriptionStoreControlStyle(.compactPicker)
        .subscriptionStoreButtonLabel(.action)
        .storeButton(.visible, for: .restorePurchases, .policies)
        .containerBackground(Theme.background, for: .subscriptionStoreFullHeight)
        .onInAppPurchaseCompletion { product, result in
            if case .success(.success(let verification)) = result, case .verified(let transaction) = verification {
                await transaction.finish()
                Telemetry.count("pro.started", ["plan": product.id == ProProducts.yearly ? "yearly" : "monthly"])
            }
            await pro.refresh()
        }
    }
}

/// The proud penguin, "Squawk Pro" and the list of what it adds.
private struct ProHeader: View {
    var highlight: ProFeature?

    var body: some View {
        VStack(spacing: 14) {
            PenguinView(mood: .proud)
                .frame(width: 130, height: 130)
            Text("Squawk Pro").font(Theme.title(34))
            Text("For mornings that need a bigger plan.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ProPerk.all) { perk in
                        let on = highlight.map(perk.features.contains) ?? false
                        HStack(spacing: 12) {
                            Image(systemName: perk.symbol)
                                .font(.body.weight(.heavy))
                                .foregroundStyle(on ? Theme.accentInk : Theme.accent)
                                .frame(width: 36, height: 36)
                                .background(on ? Theme.accent : Theme.ice, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(perk.title)
                                .font(.system(.body, design: .rounded, weight: .bold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(maxWidth: 560)
    }
}

/// One line on the Pro screen, and the Pro features it covers.
private struct ProPerk: Identifiable {
    var id: String { title }
    var title: String
    var symbol: String
    var features: Set<ProFeature>

    static let all = [
        ProPerk(title: "As many rings as you want", symbol: "plus", features: [.moreRings]),
        ProPerk(title: "Wake-up checks: tag, code, penguin game", symbol: "checkmark", features: [.checks]),
        ProPerk(title: "Change tomorrow to a new time, just once", symbol: "clock", features: [.changeNextTime]),
        ProPerk(title: "Every sound, color and ring name", symbol: "music.note", features: [.allSounds, .ringStyle]),
        ProPerk(title: "Penguin outfits and app icons", symbol: "star.fill", features: [.outfits, .appIcons]),
    ]
}

/// With Pro on: a party-hat penguin, thanks, and managing the subscription.
private struct YoureProView: View {
    var onDone: () -> Void
    @State private var managing = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    PenguinView(mood: .proud, accessory: .partyHat)
                        .frame(width: 170, height: 170)
                        .padding(.top, 40)
                    Text("You're Pro!").font(Theme.title(34))
                    Text("Every ring, check, sound and outfit is yours. Thanks for helping Squawk.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    Button("Manage subscription") { managing = true }
                        .buttonStyle(LinkButtonStyle())
                        .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Done", action: onDone)
                .buttonStyle(PillButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .frame(maxWidth: 560)
        }
        .manageSubscriptionsSheet(isPresented: $managing)
    }
}

extension View {
    /// Shows the Pro screen while `feature` is set, for a Pro thing someone tapped.
    func proSheet(_ feature: Binding<ProFeature?>) -> some View {
        sheet(item: feature) { feature in
            ProView(from: feature)
        }
    }
}

#Preview("Free") {
    ProView(from: .checks).environment(ProModel.preview())
}

#Preview("Pro") {
    ProView().environment(ProModel.preview(isPro: true))
}
