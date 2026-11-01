import AstrotypeCore
import AstrotypeUI
import StoreKit
import SwiftUI

/// DESIGN.md screen 10: the star tile, "Astrotype Pro", four perks and the two plans.
/// Buying goes through Apple's subscription view, which shows the prices, Restore and
/// the terms. The trial is the app's own fourteen days from first launch (no
/// introductory offer), so during it the screen says how long is left and the button
/// subscribes. With Pro on, it says so and links to managing the subscription.
struct ProView: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if model.isSubscribed {
                YoureProView { dismiss() }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                store
            }
        }
        .animation(Theme.Motion.spring, value: model.isSubscribed)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await model.refreshPro() }
    }

    private var store: some View {
        SubscriptionStoreView(productIDs: ProProducts.all) {
            ProHeader(trialDaysLeft: model.entitlement.isOnTrial ? model.trial.daysLeft(now: model.now) : nil)
        }
        .subscriptionStoreControlStyle(.compactPicker)
        .subscriptionStoreButtonLabel(.action)
        .storeButton(.visible, for: .restorePurchases, .policies)
        .containerBackground(Theme.bg, for: .subscriptionStoreFullHeight)
        .onInAppPurchaseCompletion { product, result in
            if case .success(.success(let verification)) = result, case .verified(let transaction) = verification {
                await transaction.finish()
                await model.subscribed(to: product.id)
            }
            await model.refreshPro()
        }
    }
}

/// The star tile, "Astrotype Pro", the line under it and the four perks.
private struct ProHeader: View {
    /// Days left on the trial, nil once it is over.
    var trialDaysLeft: Int?

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            StarTileArt().frame(width: 130, height: 130)
            Text("Astrotype Pro").font(.sw(.title))
            Text("The fast keyboard, all of it.")
                .font(.sw(.body))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if let days = trialDaysLeft {
                Chip("Trial · \(days) day\(days == 1 ? "" : "s") left", tint: Theme.sunInk)
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(ProPerk.all) { perk in
                        HStack(spacing: Theme.Space.m) {
                            NumberBadge(.done)
                            Text(perk.title)
                                .font(.system(.body, design: .rounded, weight: .bold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Text("Renews automatically, cancel anytime.")
                .font(.sw(.small))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.m)
        .frame(maxWidth: 560)
    }
}

/// One line on the Pro screen (DESIGN.md screen 10).
private struct ProPerk: Identifiable {
    var id: String { title }
    var title: String

    static let all = [
        ProPerk(title: "Two-thumb typing: taps and swipes from both thumbs"),
        ProPerk(title: "Snippets, shortcuts and edge swipes"),
        ProPerk(title: "Split and one-handed layouts"),
        ProPerk(title: "Drills, history and themes"),
    ]
}

/// With Pro on: the star tile, thanks, and managing the subscription.
private struct YoureProView: View {
    var onDone: () -> Void
    @State private var managing = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    StarTileArt().frame(width: 170, height: 170).padding(.top, Theme.Space.xl)
                    Text("You're Pro").font(.sw(.title))
                    Text("Both thumbs, every layout, every drill. Thanks for keeping Astrotype going.")
                        .font(.sw(.body))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    Button("Manage subscription") { managing = true }
                        .buttonStyle(.ghost)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Done", action: onDone)
                .buttonStyle(.primary)
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.bottom, Theme.Space.s)
                .frame(maxWidth: 560)
        }
        .manageSubscriptionsSheet(isPresented: $managing)
    }
}
