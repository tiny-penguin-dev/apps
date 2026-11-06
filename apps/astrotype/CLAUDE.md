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
    (`TurnOnView`, `LanguagesSetupView` (only on a phone set to two languages), `SyncView`, `TryItView`, and `SetupPage`, their shared shape),
    `HelloView`, `HomeView`, `Settings/` (`SettingsView`, the main page with its
    `SettingsPage`s, and `SettingsPages`, one view per page; `StyleSettings`, Appearance's hub and its General, Styling, theme editor and Effects pages with the live `StylePreview` (features/customization); `DebugSettings`, the Debug page:
    the keyboard's memory against 40 MB from `KeyboardDebug`, the switch for the
    stats overlay on the keys, and in TestFlight builds the typing recorder: "Keep
    recording", send the last 1/5/30 minutes or from a mark, share as a file, delete
    what was sent), `LearnedWordsView` (+ to add a word, Select to drop several), `WordPairsView` ("Word pairs", what Learns from you learned, features/learned-words), `MissedWordsView` ("Words it missed", features/missed-words), `SharingView` ("What
    gets shared": the words waiting to go up, drawn on the keys), `PracticeView`,
    `ProView` (the subscription screen, StoreKit's `SubscriptionStoreView`),
    `TrialOverView` (the sheet, once), `MilestoneView` (the sheet, once each),
    `Practice/` (`SpeedTestView` on ours or Apple's keyboard, `SpeedResultView`,
    `PracticeWordsView` (one prompt at a time from `PracticeWords`, from Settings → Privacy),
    `DrillView`),
    `Keyboard/KeyboardSession` (a text view whose input view is the shared keyboard,
    with Try it's replay),
    `Telemetry.swift` (Sentry, see `docs/telemetry.md`), `PrivacyInfo.xcprivacy`.
    `Try/`, `Train/` and `Shared/` are v1: the handwriting pad, training recorder and
    the CloudKit sample upload, reachable from Settings behind the flag.
  - `AstrotypeKeyboard/`: the keyboard extension (`com.tinypenguin.astrotype.keyboard`).
    `KeyboardViewController` hosts the shared `KeyboardView`, reads the field into a
    `Field` (features/field-types), types through
    `ProxyTarget` (the text document proxy), picks the stores (own files, mirrored to
    the App Group with Full Access), starts an `EntitlementController` (Pro from
    StoreKit, the trial from the App Group or its own first run) and, with Full
    Access, writes `ExtensionStatus` and runs a `SyncController`. `KeyboardTelemetry` starts Sentry for crash
    reports only, and `KeyboardHealthRecorder` writes the memory and the first-guess
    counts (`GuessTally`, from `KeyboardModel.onSettled`) per session for the app.
    `KeyboardDebugRecorder` writes its live memory (`KeyboardDebug`) to the App Group
    for Settings → Debug whenever it has Full Access (never sent). With Full Access and
    "Keep recording" on it gives `KeyboardModel.recorder` a `TypingRecorder` over
    `KeyboardFiles.typing` (red dot on the keys, Mark in the held-123 panel; turning it
    off deletes what was kept). `MemorySampler` takes one `MemorySample` a second
    while the keyboard shows and hands it to the stats overlay, the Debug page's file,
    `KeyboardHealthRecorder` and the log (`mem` events: on show, hide and memory
    warnings, every 10 s, on a 5 MB jump, and when a `LiveCount` changes;
    `MemoryLogPacer`). `ExtensionChecks`
    writes the StoreKit, memory and size readings into the bar's idle note while
    `Flags.extensionReadout` is on.
  - `AstrotypeKit/`: the local package, three targets:
    - `AstrotypeCore`: Core and Services. `SpaceSlide` (a finger on space: a tap, or a cursor slide after a short hold and a real move), `Layout` (key geometry, with the field's
      `BottomRow`), `Field` (what the app says about the field and what the keyboard
      makes of it: bottom row, return key, exact taps, spacing, capitals, learning), `Language` (one
      language's files from `Resources/<code>/`: `Lexicon`, the trie from
      `lexicon.tsv`, and `NgramModel`, the word pairs from `bigrams.bin`; English and
      Spanish, `Language.bundled(["en", "es"])` for both at once, a sentence keeping to the first language it shows (`Language.lock(for:)`, `Composer.lockedLanguage`, unless `mixesLanguages`); accented words sit
      under their plain letters, `Lexicon.fold`, and `Matcher` writes the accents back), `Flags`, and `Engine/`: `Composer` (touches in, effects out, pure,
      time passed in), `Matcher` (pieces to ranked candidates: trie search plus DTW,
      two-thumb orderings and split swipes, both thumbs swiping at once in
      `Matcher+Together` (letters woven by when each key was reached), the words before the open one from
      `WordContext` and the person's `PersonalIndex`), `NextWords` (the likely next words for
      the bar, from the word pairs and the person's own), `PersonalModel` (what the keyboard
      learns from the person: word and pair counts that fade, thumb offsets per key, one
      shard per install, merged and forgotten across devices; `SettledWord`, which the
      composer emits when a word is final, and `PersonalLearner`, the model as a
      keyboard holds it), `NgramModel` (the word-pair binary, read and built), `Replay`
      (the harness: a practice recording through the engine, first-guess accuracy),
      `Piece`, `Geometry`, `Accents` (what a held key offers), `LearnedWords`, `Emoji`
      (`EmojiCatalog`, the emoji by category from `Resources/emoji/emoji.tsv`, built by
      `ml/emoji/build_emoji.py`, cut to what the running iOS draws; `EmojiHistory` and its
      `EmojiStore`, Frequently used and the skin tones in `emoji.json`), `EmojiSearch`
      (`EmojiNames` from `Resources/emoji/names-en.tsv` and `names-es.tsv`, Unicode's CLDR
      names and keywords built by `ml/emoji/build_names.py`, and the search that ranks
      them), `KeyboardSettings` (the in-keyboard settings
      and their `SettingsStore`). `Sync/` holds the data layer: `Stores` (`JSONFile`,
      `WordStore` and file, memory and mirrored stores for words, settings and the
      personal model, `InstallID`),
      `KeyboardFiles` (where the files are: own container and App Group), `KeyboardDebug`
      (`MemoryReading`, a process's footprint and headroom, and the keyboard's readings
      for the Debug page), `CloudSync`
      (`SyncSnapshot`, the protocol, `Syncer`'s fetch-merge-write round, the fake),
      `CloudKitSync` (the live one), `ExtensionStatus`, `Backup`. `App/` holds the
      app's own Core and Services:
      `AppState` and `AppStateStore`, `Trial`, `Entitlement` (`ProFeature`,
      `ProStatus`, `Entitlement`, the one place Pro is checked; `ProProducts`,
      `ProStore` with `MemoryProStore`, `TrialStore` and `ProCache` as files),
      `StoreKitProStore` (the live `ProStore`), `KeyboardStatus` (is the keyboard on),
      `Metrics` (protocol; the app's live one is `Telemetry`), `TryWord` (the Try it
      words and their strokes), `Week`, `SpeedTest` (the test as it runs, `SpeedResult`),
      `Drill` (the three drills and their words), `Milestone` and `Streak`,
      `PracticeRecording` (a session's touches, `TouchRecorder`, `PracticeStore`, the
      `PracticeUploader` protocol with its fake; the live one is
      `Sync/CloudKitPracticeUploader`), `SharedWord` (what is shared: one word with its
      touches, from a session split word by word or a fix from the keyboard;
      `SharedWordStore`, the `SharedWordUploader` protocol with its fake, the live one
      the same `CloudKitPracticeUploader`), `PracticeWords` (the Practice words prompts),
      `SyntheticTyping` (noisy made-up swipes for the harness). `Handwriting/` holds the v1 engine (`Features`, `PhraseDecoder`, `Recognizer`,
      `Recording`, `StrokeSample`). `TypingLog` (the typing recorder, Gabriel 6 Nov 2026:
      `TypingEvent`, one per touch, key, bar tap, context change and effect;
      `TypingSnapshot`, settings, field, layout, languages, Pro, context and build;
      the log sent, with windows by wall clock and CloudKit parts; `timeline()`),
      `Sync/TypingLogStore` (`TypingLogFiles`, five-minute JSON-lines files in the App
      Group, half an hour kept; `TypingRecorder`, the buffered writer), and
      `Engine/TypingReplay` (a log through a fresh `Composer` as `KeyboardModel`
      drives it, effects compared with the phone's; keep it in step with
      `KeyboardModel`). Foundation only; tests run on Linux.
    - `AstrotypeTools`: the `astrotype-tools` command line (`build-ngrams`, `replay`,
      `tune` (`Tuning`'s search over `Matcher.Weights`), `synth` (`SyntheticTyping`'s
      made-up words to measure against), `prompts`,
      `next`, `typing` (a typing log's timeline and replay)), argument parsing over `AstrotypeCore` and nothing else.
    - `AstrotypeUI`: the design system (`Theme` tokens, `Components`, `Art`, `EdgeFade`: a scroll
      view's `fadeEdges`, used by the settings panel and both emoji rows) and the
      keyboard's views: `KeyboardView` (bar plus keys, the pages, the settings panel,
      the `StatsOverlayView` memory line in the keys' top corner while
      `KeyboardSettings.showsStats` is on; owns a `KeyboardModel`), `BarView` (left key, centred words, the pencil and its fix row), `KeySurfaceView` (touch stream, flashes,
      trails, rings, and the gestures: space slide (and a held space typed as soon as another finger lands), backspace swipe and hold, "123"
      hold, the slide from "123" to a number or symbol, and a held letter's accents, `AccentCallout`; keys drawn from a `KeyStyle`),
      `KeyEffects` (taps, trails, letter effects and flow with Core Animation), `MetalKeyboard` (the Aurora sky and the
      Metal letters, shaders compiled from source at first use), `SettingsPanelView`,
      `EmojiPageView` (the emoji page and its `TonePicker`), `EmojiSearchView` (the search
      field `SearchField` and the results row; while it is open `KeyboardModel` types into a
      `SearchTarget` with `Field.emojiSearch`), `KeyboardModel` (applies the composer's effects to a
      `TextTarget`, runs the autospace timer, keeps the settings and the learned words, loads the languages that are on,
      learns, boosts and forgets, and feeds each settled word to the personal model; `TextViewTarget` for a `UITextView`),
      `SyncController` (a model's words and settings in step with a `CloudSync`),
      `EntitlementController` (a model's entitlement in step with a `ProStore` and
      the trial, for the extension).
      UIKit and SwiftUI, guarded
      with `#if canImport(UIKit)` so `swift test` still builds the package on macOS.
    - `AstrotypeKitTests`: Swift Testing. `ComposerTests`, `NextWordTests`, `FieldTests`, `LanguagesTests` (Spanish, accents, both at once, picked accents, which languages are on), `PersonalModelTests`, `SharedWordTests`, `TuningTests`, `MatcherTests` (the 50-word
      fixture in `Fixtures/swipes.json`, through `Synth`'s straight-line swipes, and
      `ContextMatcherTests`), `WordContextTests`, `NgramModelTests`, `ReplayTests`, `MissedWordTests` (the bar's "Not it?"), `WrongSpaceTests` (autospace taken back out of a word, punctuation before the space), `TwoThumbTests` (two-thumb accuracy from `SyntheticTyping`'s `.two` and `.together`, Gabriel's real both-at-once swipes in `Fixtures/together-*.json`, compounds, tap places, two-thumb Not it?)
      (recordings made from `Synth` strokes replay to the live result),
      `GeometryTests`, `LayoutTests`, `EmojiTests`, `EmojiSearchTests`, `KeyboardSettingsTests`, `KeyboardDebugTests`, `TypingLogTests` (the typing recorder: format, files, windows, replay), `AppCoreTests` (the
      `App/` pieces), `ProTests` (`Entitlement`, the trial and Pro files, the memory
      store), `PracticeTests` (the speed test, streak and milestones, the drills on the
      engine, recordings), `SyncTests` (stores, snapshots, `Syncer`, `Backup`), and
      `GoldenTests` replaying
      `ml/export/golden.json` for the v1 engine.
  - `Config/`: `Astrotype.xcconfig` (bundle ID, version, `SENTRY_DSN`),
    `AstrotypeKeyboard.xcconfig` and `AstrotypeKeyboard-Info.plist` (the extension),
    `Astrotype.storekit` (the two Pro plans for local testing, on the scheme),
    `Info.plist`, `Astrotype.entitlements` and `AstrotypeKeyboard.entitlements` (the
    App Group and the iCloud container, shared by both targets),
    `testflight.json`. Keep the two `MARKETING_VERSION`s equal.
- `store/`: the App Store listing kept in the repo, synced by
  `.github/workflows/app-store.yml`: `subscriptions.json` (the Pro plans) with
  `pro-review.png` (their App Review screenshot), `screenshots/en-US/` (the App Store
  screenshots) and `privacy.md` (the App Privacy answers, matching
  `PrivacyInfo.xcprivacy`; a change to one changes the other).
- `ml/`: the v1 Python training loop (see `ml/README.md`); the opt-in practice-session
  uploads (`PracticeSession` records) land in the same container, and
  `download_samples.py --type PracticeSession` fetches them for `astrotype-tools
  replay`. Typing logs (Settings → Debug) are `PracticeSession` records of kind
  `typing.log` in parts; `download_samples.py --typing` puts them together into
  `samples/typing/<id>.json` for `astrotype-tools typing`. `ml/ngrams/` makes a language's word list (`make_lexicon.py`) and counts a
  corpus's word pairs for `build-ngrams` (its README has the commands and the data sources).
- `features/`: the bigger features after the v2 build, one folder each with a
  `FEATURE.md` (product, design, build and its phases, notes as they ship):
  `smart-matching` (context, personal learning, consented sharing, the harness),
  `languages` (Spanish and the next languages, both at once; built),
  `emoji` (the emoji key and page, skin tones; built 3 Nov 2026),
  `emoji-search` (search the emoji page by name, English and Spanish; built 3 Nov 2026),
  `missed-words` (the bar's "Not it?": type the word meant, learn from the swipe, keep
  it for debugging; built),
  `field-types` (the keyboard following email, web, search and number fields),
  `next-word` (the likely next words on the bar after each word, with the FIX chip),
  `guesses-bar` (the bar in three parts: globe key left, words centred, pencil right with the
  fix row behind it; built 3 Nov 2026),
  `customization` (Appearance split into General, Styling and Effects: themes, your own
  theme, tap and swipe effects and flow levels; in design).
- `design/`: the mockup (`mockups/astrotype.html`, the keyboard in it works), the
  screen captures the design doc links, the icon's SVGs (`icon/`) and
  `appstore/make-screenshots.mjs`, which renders the store screenshots from the mockup
  (Playwright) until real ones replace them.

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
- The keyboard must type without Full Access. The extension sends only crash reports
  (`KeyboardTelemetry`: Full Access and usage sharing on, no breadcrumbs, logs, replay,
  traces, messages or IDs, crash reasons stripped) and never metrics; its memory
  readings and first-guess counts go to the app (`KeyboardHealthRecorder` →
  `keyboard-health.json` → `AppModel.sendKeyboardHealth`). Keep the extension under 40 MB; the bar's memory
  readout (Phase 1) and `keyboard.memory_peak` in Sentry say where it stands.
- Nothing typed ever leaves the phone. Practice sessions upload only from the app, only
  when the person turns it on. The typing recorder is the one exception, for Gabriel's
  bug reports: offered only in TestFlight and Xcode builds (`AppTransaction`), off by
  default, never in fields that don't learn, and sent only when he taps Send, so the
  App Store build's privacy answers don't change.
- Never write "Nintype" into the product, and never copy its code, data or art.
- Keep this file current as the targets and commands change.
