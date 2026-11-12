import AstrotypeCore
import AstrotypeUI
import SwiftUI

/// The pages Settings opens, one per area (features/settings/FEATURE.md). A new setting
/// goes on the page it belongs to: what a touch does is Typing, what you see or feel is
/// Appearance, what the keyboard remembers is Your words.
enum SettingsPage: Hashable, CaseIterable {
    case typing, languages, appearance, words, dictation, privacy, about, debug
}

/// DESIGN.md screen 9: the main page of Settings. Status tiles (keyboard, sync),
/// then the account rows. Typing, Languages and Your words are on Home, and Appearance
/// is Home's Your keyboard card (Gabriel, 9 Nov 2026), so Settings keeps the serious things. Pro and Restore purchases live on the Pro
/// screen, which Home links to (Gabriel, 9 Nov 2026). On a phone a page pushes over
/// this one; on a wide screen this page is a sidebar with the open page beside it, and
/// the open page survives the change either way.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Binding var path: [HomeView.Route]
    /// The open page. On a phone it is pushed; on a wide screen it sits beside the list
    /// (Privacy and sharing when nothing was picked).
    @State private var open: SettingsPage?
    @State private var wide = false

    var body: some View {
        Group {
            if wide {
                HStack(spacing: 0) {
                    ScrollView { main.padding(.horizontal, Theme.Space.l).padding(.bottom, Theme.Space.xl) }
                        .frame(width: 340)
                    Rectangle().fill(Theme.line).frame(width: 1).ignoresSafeArea(edges: .bottom)
                    SettingsPageView(page: open ?? .privacy, model: model, path: $path)
                        .id(open ?? .privacy)
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

            SectionLabel("General").padding(.top, Theme.Space.m)
            SettingsGroup {
                SettingsLink("Run setup again", subtitle: "Turn it on, languages, your look and the lesson, step by step",
                             symbol: "arrow.counterclockwise", tint: Theme.mint) {
                    model.restartSetup()
                }
                link(.privacy, "Privacy and sharing",
                     subtitle: model.sharePractice ? "Sending practice sessions" : "Nothing you type is sent",
                     symbol: "lock", tint: Theme.slate)
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
                     selected: wide && (open ?? .privacy) == page) { open = page }
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

    private var debugSubtitle: String {
        guard let last = model.keyboardDebug?.last else { return "Keyboard memory, stats on the keys" }
        return "Keyboard memory \(MemoryReading.mb(last.footprintMB)) of \(Int(MemoryReading.budgetMB)) MB"
    }

}
