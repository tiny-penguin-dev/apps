# CLAUDE.md: Astrotype

Astrotype v2 is an iPhone keyboard for typing fast with two thumbs (it was StackWrite
until 1 Nov 2026; never write the old name). Read, in order,
`PRODUCT.md` (what and why), `DESIGN.md` (screens, the keyboard, the design system,
sizes) and `BUILD.md` (architecture, core pieces, phases). All three are approved; work
on the next unticked phase in `BUILD.md`, one PR per phase. The repo rules are in
`docs/building.md`.

`BRIEF.md` and `SAMPLES.md` describe v1, the handwriting keyboard, whose code is kept
behind `Flags.handwritingPad` (PRODUCT.md "Later").

## Layout

- `ios/`: the Xcode project (classic `.pbxproj`, synchronized folders, so new files
  are picked up without editing the project; new targets and packages are not).
  - `Astrotype/`: the app. `AstrotypeApp.swift` (starts `Telemetry`, builds the
    `AppModel` from `AppEnvironment.live()`, shows the setup screens then `HomeView`),
    `App/` (`AppModel`, the only thing views talk to; `AppEnvironment`, the one place
    real services are named; `LiveMetrics` on `Telemetry`), `Onboarding/`
    (`TurnOnView`, `SyncView`, `TryItView`, and `SetupPage`, their shared shape),
    `HelloView`, `HomeView`, `SettingsView`, `LearnedWordsView`, `PracticeView`,
    `ProView` (the subscription screen, StoreKit's `SubscriptionStoreView`),
    `TrialOverView` (the sheet, once),
    `Keyboard/KeyboardSession` (a text view whose input view is the shared keyboard,
    with Try it's replay),
    `Telemetry.swift` (Sentry, see `docs/telemetry.md`), `PrivacyInfo.xcprivacy`.
    `Try/`, `Train/` and `Shared/` are v1: the handwriting pad, training recorder and
    the CloudKit sample upload, reachable from Settings behind the flag.
  - `AstrotypeKeyboard/`: the keyboard extension (`com.tinypenguin.astrotype.keyboard`).
    `KeyboardViewController` hosts the shared `KeyboardView`, types through
    `ProxyTarget` (the text document proxy), picks the stores (own files, mirrored to
    the App Group with Full Access), starts an `EntitlementController` (Pro from
    StoreKit, the trial from the App Group or its own first run) and, with Full
    Access, writes `ExtensionStatus` and runs a `SyncController`. `ExtensionChecks`
    writes the StoreKit, memory and size readings into the bar's idle note while
    `Flags.extensionReadout` is on.
  - `AstrotypeKit/`: the local package, three targets:
    - `AstrotypeCore`: Core and Services. `Layout` (key geometry), `Lexicon` (the
      trie, built from `Resources/lexicon.tsv`), `Flags`, and `Engine/`: `Composer`
      (touches in, effects out, pure, time passed in), `Matcher` (pieces to ranked
      candidates: trie search plus DTW, two-thumb orderings and split swipes),
      `Piece`, `Geometry`, `LearnedWords`, `KeyboardSettings` (the in-keyboard settings
      and their `SettingsStore`). `Sync/` holds the data layer: `Stores` (`JSONFile`,
      `WordStore` and file, memory and mirrored stores for words and settings),
      `KeyboardFiles` (where the files are: own container and App Group), `CloudSync`
      (`SyncSnapshot`, the protocol, `Syncer`'s fetch-merge-write round, the fake),
      `CloudKitSync` (the live one), `ExtensionStatus`, `Backup`. `App/` holds the
      app's own Core and Services:
      `AppState` and `AppStateStore`, `Trial`, `Entitlement` (`ProFeature`,
      `ProStatus`, `Entitlement`, the one place Pro is checked; `ProProducts`,
      `ProStore` with `MemoryProStore`, `TrialStore` and `ProCache` as files),
      `StoreKitProStore` (the live `ProStore`), `KeyboardStatus` (is the keyboard on),
      `Metrics` (protocol; the app's live one is `Telemetry`), `TryWord` (the Try it
      words and their strokes), `Week`. `Handwriting/` holds the v1 engine (`Features`, `PhraseDecoder`, `Recognizer`,
      `Recording`, `StrokeSample`). Foundation only; tests run on Linux.
    - `AstrotypeUI`: the design system (`Theme` tokens, `Components`, `Art`) and the
      keyboard's views: `KeyboardView` (bar plus keys, the pages, the settings panel;
      owns a `KeyboardModel`), `BarView`, `KeySurfaceView` (touch stream, flashes,
      trails, rings, and the gestures: space slide, backspace swipe and hold, "123"
      hold), `SettingsPanelView`, `KeyboardModel` (applies the composer's effects to a
      `TextTarget`, runs the autospace timer, keeps the settings and the learned words,
      learns, boosts and forgets; `TextViewTarget` for a `UITextView`),
      `SyncController` (a model's words and settings in step with a `CloudSync`),
      `EntitlementController` (a model's entitlement in step with a `ProStore` and
      the trial, for the extension).
      UIKit and SwiftUI, guarded
      with `#if canImport(UIKit)` so `swift test` still builds the package on macOS.
    - `AstrotypeKitTests`: Swift Testing. `ComposerTests`, `MatcherTests` (the 50-word
      fixture in `Fixtures/swipes.json`, through `Synth`'s straight-line swipes),
      `GeometryTests`, `LayoutTests`, `KeyboardSettingsTests`, `AppCoreTests` (the
      `App/` pieces), `ProTests` (`Entitlement`, the trial and Pro files, the memory
      store), `SyncTests` (stores, snapshots, `Syncer`, `Backup`), and
      `GoldenTests` replaying
      `ml/export/golden.json` for the v1 engine.
  - `Config/`: `Astrotype.xcconfig` (bundle ID, version, `SENTRY_DSN`),
    `AstrotypeKeyboard.xcconfig` and `AstrotypeKeyboard-Info.plist` (the extension),
    `Astrotype.storekit` (the two Pro plans for local testing, on the scheme),
    `Info.plist`, `Astrotype.entitlements` and `AstrotypeKeyboard.entitlements` (the
    App Group and the iCloud container, shared by both targets),
    `testflight.json`. Keep the two `MARKETING_VERSION`s equal.
- `store/`: the App Store listing kept in the repo (`subscriptions.json`, the Pro
  plans; screenshots later), synced by `.github/workflows/app-store.yml`.
- `ml/`: the v1 Python training loop (see `ml/README.md`), still used for the opt-in
  practice-session uploads planned in Phase 7.
- `design/`: the mockup (`mockups/astrotype.html`, the keyboard in it works) and
  screenshots.

Keep `AstrotypeKit` inside this app. Don't move it to the repo's `packages/` unless a
second app needs it.

## Build and test

There is no Xcode in Claude's container: push and read the "Astrotype iOS" workflow
(`.github/workflows/astrotype-ios.yml`). PRs run `swift test` on the package and build
the app and the extension for the simulator; pushes to `main` also archive and upload to
TestFlight, with Sentry's DSN baked in. On a Mac:

```bash
cd ios
swift test --package-path AstrotypeKit
xcodebuild build -project Astrotype.xcodeproj -scheme Astrotype \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

`make` in this folder lists the v1 training commands.

## Rules

- Architecture as in `docs/building.md` §4 and `BUILD.md`: pure, tested logic in
  `AstrotypeCore`; side effects behind protocols with fakes; the extension's
  `KeyboardModel` and the app's `AppModel` are the only things views talk to; nothing in
  the package knows about either.
- Screens use `Theme` tokens and the components in `AstrotypeUI`, never a colour or a
  size of their own. `Layout.qwerty(width:)` is the one source of key geometry.
- Every phase's done-when is checked at the small size (iPhone Duo outer), the largest
  text size and the wide size (Duo inner).
- The keyboard must type without Full Access, and the extension never sends telemetry.
  Keep the extension under 40 MB; the bar's memory readout (Phase 1) says what is left.
- Nothing typed ever leaves the phone. Practice sessions upload only from the app, only
  when the person turns it on.
- Never write "Nintype" into the product, and never copy its code, data or art.
- Keep this file current as the targets and commands change.
