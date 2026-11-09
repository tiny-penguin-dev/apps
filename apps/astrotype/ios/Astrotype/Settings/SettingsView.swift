import AstrotypeCore
import AstrotypeUI
import StoreKit
import SwiftUI

/// The pages Settings opens, one per area (features/settings/FEATURE.md). A new setting
/// goes on the page it belongs to: what a touch does is Typing, what you see or feel is
/// Appearance, what the keyboard remembers is Your words.
enum SettingsPage: Hashable, CaseIterable {
    case typing, languages, appearance, words, dictation, privacy, about, debug
}

/// DESIGN.md screen 9: the main page of Settings. Status tiles (keyboard, sync, Pro),
/// then links to a page per area and the account rows. On a phone a page pushes over
/// this one; on a wide screen this page is a sidebar with the open page beside it, and
/// the open page survives the change either way.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]
    /// The open page. On a phone it is pushed; on a wide screen it sits beside the list
    /// (Typing when nothing was picked).
    @State private var open: SettingsPage?
    @State private var wide = false
    @State private var managing = false
    @State private var restoring = false
    @State private var restoreNote: String?

    var body: some View {
        Group {
            if wide {
                HStack(spacing: 0) {
                    ScrollView { main.padding(.horizontal, Theme.Space.l).padding(.bottom, Theme.Space.xl) }
                        .frame(width: 340)
                    Rectangle().fill(Theme.line).frame(width: 1).ignoresSafeArea(edges: .bottom)
                    SettingsPageView(page: open ?? .typing, model: model, path: $path)
                        .id(open ?? .typing)
                        .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    main
                        .padding(.horizontal, Theme.Space.gutter)
                        .padding(.bottom, Theme.Space.xl)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { wide = $0 }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Only a phone pushes the page; going wide pops it into the side-by-side view
        // and going back to a phone pushes it again.
        .navigationDestination(item: Binding(get: { wide ? nil : open }, set: { if !wide { open = $0 } })) { page in
            SettingsPageView(page: page, model: model, path: $path)
        }
        .manageSubscriptionsSheet(isPresented: $managing)
        .onAppear {
            model.refreshKeyboardStatus()
            model.reloadWords()
            model.reloadShared()
            model.reloadDebug()
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Settings").font(.sw(.title)).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.s)
                .accessibilityAddTraits(.isHeader)
            statusTiles
            if !model.isFullAccessOn {
                GroupFootnote("Without Full Access, the keyboard in other apps keeps its own settings. Hold 123 on it to change them.")
            }

            SectionLabel("Keyboard").padding(.top, Theme.Space.m)
            SettingsGroup {
                link(.typing, "Typing", subtitle: "Autospace, real words, gestures", symbol: "keyboard", tint: Theme.right)
                link(.languages, "Languages", subtitle: languagesSubtitle, symbol: "character.bubble", tint: Theme.sun)
                link(.appearance, "Appearance",
                     subtitle: "\(model.keyboardSettings.style(allows: model.entitlement.allows(.styles)).name) theme, height \(Int((model.keyboardSettings.heightScale * 100).rounded()))%, effects",
                     symbol: "paintpalette", tint: Theme.left)
                link(.words, "Your words", subtitle: wordsSubtitle, symbol: "text.book.closed", tint: Theme.mint)
                link(.dictation, "Dictation", subtitle: dictationSubtitle, symbol: "mic", tint: Theme.right)
            }

            SectionLabel("Account").padding(.top, Theme.Space.m)
            SettingsGroup {
                link(.privacy, "Privacy and sharing",
                     subtitle: model.sharePractice ? "Sending practice sessions" : "Nothing you type is sent",
                     symbol: "lock", tint: Theme.slate)
                SettingsLink("Astrotype Pro", subtitle: proSubtitle, symbol: "star.fill", tint: Theme.sun) {
                    if model.isSubscribed { managing = true } else { path.append(.pro) }
                }
                SettingsRow("Restore purchases", subtitle: restoreNote, symbol: "arrow.clockwise", tint: Theme.ice) {
                    if restoring {
                        ProgressView().tint(Theme.accent)
                    } else {
                        Button("Restore") { restore() }.buttonStyle(.small)
                    }
                }
                link(.about, "About", subtitle: "Version \(DeviceInfo.appVersion)", symbol: "info.circle", tint: Theme.ice)
            }

            SectionLabel("Debug").padding(.top, Theme.Space.m)
            SettingsGroup {
                link(.debug, "Debug", subtitle: debugSubtitle, symbol: "ladybug", tint: Theme.slate)
            }

            if Flags.handwritingPad {
                HandwritingSettings()
            }
        }
    }

    private func link(_ page: SettingsPage, _ title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        SettingsLink(title, subtitle: subtitle, symbol: symbol, tint: tint,
                     selected: wide && (open ?? .typing) == page) { open = page }
    }

    // MARK: Status

    private var statusTiles: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.s) { tiles }.fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Theme.Space.s) { tiles }
        }
    }

    @ViewBuilder private var tiles: some View {
        StatusTile("Keyboard", status: model.isKeyboardOn ? "On" : "Not on yet", ok: model.isKeyboardOn) {
            if !model.isKeyboardOn { path.append(.turnOn) }
        }
        StatusTile("iCloud sync", status: syncStatus, ok: syncOK) {
            switch model.syncState {
            case .needsFullAccess: path.append(.sync)
            case .syncing: break
            case .idle, .failed: model.sync()
            }
        }
        StatusTile(isTrial ? "Pro trial" : "Astrotype Pro",
                   status: proStatus, ok: model.proStatus != .free) {
            if model.isSubscribed { managing = true } else { path.append(.pro) }
        }
    }

    private var isTrial: Bool {
        if case .trial = model.proStatus { return true }
        return false
    }

    private var syncOK: Bool {
        switch model.syncState {
        case .idle, .syncing: true
        case .needsFullAccess, .failed: false
        }
    }

    private var syncStatus: String {
        switch model.syncState {
        case .needsFullAccess: return "Needs Full Access"
        case .syncing: return "Syncing…"
        case .idle(let last):
            guard let last else { return "On" }
            return "Synced \(last.formatted(.relative(presentation: .named)))"
        case .failed: return "Didn't sync. Tap to retry"
        }
    }

    private var proStatus: String {
        switch model.proStatus {
        case .pro: return "On"
        case .trial:
            let days = model.trial.daysLeft(now: model.now)
            return "\(days) day\(days == 1 ? "" : "s") left"
        case .free: return "Trial over"
        }
    }

    private var proSubtitle: String {
        switch model.proStatus {
        case .pro: return "On. Both thumbs, every layout, every drill."
        case .trial:
            let days = model.trial.daysLeft(now: model.now)
            return "Trial · \(days) day\(days == 1 ? "" : "s") left"
        case .free: return "Two thumbs, split layouts and drills"
        }
    }

    private var languagesSubtitle: String {
        model.activeLanguages.map { Language.names[$0] ?? $0 }.joined(separator: ", ")
    }

    private var debugSubtitle: String {
        guard let last = model.keyboardDebug?.last else { return "Keyboard memory, stats on the keys" }
        return "Keyboard memory \(MemoryReading.mb(last.footprintMB)) of \(Int(MemoryReading.budgetMB)) MB"
    }

    private var dictationSubtitle: String {
        guard model.keyboardSettings.dictation else { return "Off" }
        return "Mic ready for \(model.keyboardSettings.dictationMinutes) min after you dictate"
    }

    private var wordsSubtitle: String {
        let count = model.learnedWords.recent.count
        return "\(count) learned · learning \(model.learnsFromYou ? "on" : "off")"
    }

    private func restore() {
        restoring = true
        restoreNote = nil
        Task { @MainActor in
            do {
                let found = try await model.restorePurchases()
                restoreNote = found ? "Found it. You're Pro." : "No Pro subscription on this Apple Account."
            } catch {
                restoreNote = "I couldn't reach the App Store. Try again in a moment."
            }
            restoring = false
        }
    }
}
