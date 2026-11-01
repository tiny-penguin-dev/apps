# CLAUDE.md: StackWrite

StackWrite v2 is an iPhone keyboard for typing fast with two thumbs. Read, in order,
`PRODUCT.md` (what and why), `DESIGN.md` (screens, the keyboard, the design system,
sizes) and `BUILD.md` (architecture, core pieces, phases). All three are approved; work
on the next unticked phase in `BUILD.md`, one PR per phase. The repo rules are in
`docs/building.md`.

`BRIEF.md` and `SAMPLES.md` describe v1, the handwriting keyboard, whose code is kept
behind `Flags.handwritingPad` (PRODUCT.md "Later").

## Layout

- `ios/`: the Xcode project (classic `.pbxproj`, synchronized folders, so new files
  are picked up without editing the project; new targets and packages are not).
  - `StackWrite/`: the app. `StackWriteApp.swift` (starts `Telemetry`, shows
    `HelloView` until onboarding is done, then `HomeView`), `Telemetry.swift` (Sentry,
    see `docs/telemetry.md`), `PrivacyInfo.xcprivacy`. `Try/`, `Train/` and `Shared/`
    are v1: the handwriting pad, training recorder and the CloudKit sample upload.
  - `StackWriteKeyboard/`: the keyboard extension (`com.tinypenguin.stackwrite.keyboard`).
    `KeyboardViewController` draws the shared key surface and types. `ExtensionChecks`
    is Phase 1 only: it writes the StoreKit, haptics and memory results into the bar.
  - `StackWriteKit/`: the local package, three targets:
    - `StackWriteCore`: Core and Services. `Layout` (key geometry), `Lexicon` (the
      trie), `Flags`. `Handwriting/` holds the v1 engine (`Features`, `PhraseDecoder`,
      `Recognizer`, `Recording`, `StrokeSample`). Foundation only; tests run on Linux.
    - `StackWriteUI`: the design system (`Theme` tokens, `Components`, `Art`) and the
      keyboard's views (`KeySurfaceView`). UIKit and SwiftUI, guarded with
      `#if canImport(UIKit)` so `swift test` still builds the package on macOS.
    - `StackWriteKitTests`: Swift Testing. `LayoutTests`, and `GoldenTests` replaying
      `ml/export/golden.json` for the v1 engine.
  - `Config/`: `StackWrite.xcconfig` (bundle ID, version, `SENTRY_DSN`),
    `StackWriteKeyboard.xcconfig` and `StackWriteKeyboard-Info.plist` (the extension),
    `Info.plist`, `StackWrite.entitlements` (iCloud container for v1 sample uploads),
    `testflight.json`. Keep the two `MARKETING_VERSION`s equal.
- `ml/`: the v1 Python training loop (see `ml/README.md`), still used for the opt-in
  practice-session uploads planned in Phase 7.
- `design/`: the mockup (`mockups/stackwrite.html`, the keyboard in it works) and
  screenshots.

Keep `StackWriteKit` inside this app. Don't move it to the repo's `packages/` unless a
second app needs it.

## Build and test

There is no Xcode in Claude's container: push and read the "StackWrite iOS" workflow
(`.github/workflows/stackwrite-ios.yml`). PRs run `swift test` on the package and build
the app and the extension for the simulator; pushes to `main` also archive and upload to
TestFlight, with Sentry's DSN baked in. On a Mac:

```bash
cd ios
swift test --package-path StackWriteKit
xcodebuild build -project StackWrite.xcodeproj -scheme StackWrite \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

`make` in this folder lists the v1 training commands.

## Rules

- Architecture as in `docs/building.md` §4 and `BUILD.md`: pure, tested logic in
  `StackWriteCore`; side effects behind protocols with fakes; the extension's
  `KeyboardModel` and the app's `AppModel` are the only things views talk to; nothing in
  the package knows about either.
- Screens use `Theme` tokens and the components in `StackWriteUI`, never a colour or a
  size of their own. `Layout.qwerty(width:)` is the one source of key geometry.
- Every phase's done-when is checked at the small size (iPhone Duo outer), the largest
  text size and the wide size (Duo inner).
- The keyboard must type without Full Access, and the extension never sends telemetry.
  Keep the extension under 40 MB; the bar's memory readout (Phase 1) says what is left.
- Nothing typed ever leaves the phone. Practice sessions upload only from the app, only
  when the person turns it on.
- Never write "Nintype" into the product, and never copy its code, data or art.
- Keep this file current as the targets and commands change.
