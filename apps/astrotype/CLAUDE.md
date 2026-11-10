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
    (the welcome wizard, in order: `TurnOnView`, `LanguagesSetupView` (only on a phone set to two languages), `MakeItYoursView`, `TryItView` (also the lesson from Learn, `inSetup: false`), `SyncView`; `WizardPage`, their shared shape, with `StepProgress` and Skip from `AppModel.setupStep`),
    `HelloView`, `HomeView` (header "Astrotype", led by the one-card `SpeedCard` with its Practice and learn row, then Your keyboard, then links to Typing, Languages and Your words; a Pro look tried with Pro off lives in `AppModel.previewThemeID`/`previewEffects` and only the practice keyboards show it via `demoSettings`/`demoEntitlement`), `Home/` (features/home-and-welcome: `YourKeyboardCard` with `ThemeRow` and `EffectRow`/`EffectCard`, the drawn effect previews; `KeyboardDock`, the practice keyboard docked at the bottom of Home, shown or hidden in `@AppStorage("home.keyboardShown")`; `LearnPracticeView` and `TipsView`), `Speed/` (`SpeedViews`: `SpeedCard`, `SpeedHistoryView`,
    `SpeedChart`; the everyday typing speed, features/typing-speed; `LeaderboardView`: `LeaderboardCard`, `RankRow`,
    the weekly Game Center boards, features/leaderboards, with `App/GameCenterLeaderboards`, the live
    `LeaderboardService`), `Settings/` (`SettingsView`, the main page (status tiles, account rows; Typing, Languages and Your words open from Home) with its
    `SettingsPage`s, and `SettingsPages`, one view per page; `StyleSettings`, Appearance's hub and its General, Styling, theme editor and Effects pages with the live `StylePreview` (features/customization); `DebugSettings`, the Debug page:
    the keyboard's memory against 40 MB from `KeyboardDebug`, the switch for the
    stats overlay on the keys, and in TestFlight builds the typing recorder: "Keep
    recording", send the last 1/5/30 minutes or from a mark, share as a file, delete
    what was sent), `LearnedWordsView` (+ to add a word, Select to drop several, a Used once filter; with two languages on, a tab per language and hold a word to offer it in one language or both, features/languages), `NeverSuggestView` (blocked words: allow again, + to block one; features/word-control), `TextReplacementsView` (shortcuts and their phrases, the variable chips, Your details, copy the iPhone's own in, the iPhone's own on/off; features/text-replacements), `YourDetailsSheet` (the person's details for autofill and `{name}`…, Fill from contacts; features/autofill; also from Settings → Typing → Autofill), `WordPairsView` ("Word pairs", what Learns from you learned, features/learned-words), `MissedWordsView` ("Words it missed", features/missed-words), `SharingView` ("What
    gets shared": the words waiting to go up, drawn on the keys), `PracticeView`,
    `ProView` (the subscription screen, StoreKit's `SubscriptionStoreView`),
    `TrialOverView` (the sheet, once), `MilestoneView` (the sheet, once each),
    `Practice/` (`SpeedTestView` on ours or Apple's keyboard, `SpeedResultView`,
    `PracticeWordsView` (one prompt at a time from `PracticeWords`, from Settings → Privacy),
    `DrillView`),
    `Keyboard/KeyboardSession` (a text view whose input view is the shared keyboard,
    with Try it's replay), `Keyboard/KeyboardFrame` (that input view: the keys inside the
    margin iOS draws around the extension, so practice looks like the real keyboard: on
    iOS 26 the glass panel with rounded top corners, 5 pt sides and 4 pt top; on every
    version the home indicator strip under the keys),
    `Dictation/` (features/dictation: `DictationModel`, owned by `AppModel`, runs the
    mic for the keyboard; `SpeechListener` (live: `AVAudioEngine` plus iOS 26's
    on-device `SpeechAnalyzer`, the mic started once while the app is in front and kept
    on for the window); `DictationChannel` (the App Group state file and Darwin
    notifications); `GoBackView`, the screen `astrotype://dictate` shows over everything,
    with `SwipeHint` and the "or tap here" bubble, not on the Duo,
    `DeviceInfo.hidesBackButton`),
    `Telemetry.swift` (Sentry, see `docs/telemetry.md`), `PrivacyInfo.xcprivacy`.
    `Try/`, `Train/` and `Shared/` are v1: the handwriting pad, training recorder and
    the CloudKit sample upload, reachable from Settings behind the flag.
  - `AstrotypeKeyboard/`: the keyboard extension (`com.tinypenguin.astrotype.keyboard`).
    `DictationClient` (one per process, in `KeyboardShared`) is the keyboard's side of
    dictation: it sends `DictationCommand`s, reads `DictationState` and hands the words
    to `KeyboardModel.dictationHeard`, which writes them with `DictationText` (talk and
    type together: a key freezes what was said); a listen's words only go into the field
    they were said into: a keyboard going away marks the listen `left` in the request
    file, and a keyboard that opens follows only a listen still going that no keyboard
    left (`DictationFollow`, `KeyboardModel.dictationField`); the mic and the listening strip are
    `MicButton` and `WaveView` on `BarView`.
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
    `KeyboardFiles.typing` (red dot on the keys, Mark in the settings panel; turning it
    off deletes what was kept). `MemorySampler` takes one `MemorySample` a second
    while the keyboard shows and hands it to the stats overlay, the Debug page's file,
    `KeyboardHealthRecorder` and the log (`mem` events: on show, hide and memory
    warnings, every 10 s, on a 5 MB jump, and when a `LiveCount` changes;
    `MemoryLogPacer`). Each sample splits the non-malloc part with the kernel's
    ledgers (`MemorySplit`: gfx, ml, media, zip); show, hide and warning readings (and the
    overlay every 5 s) also walk the VM regions by tag (`MemoryRegions`: CA, malloc,
    IOSurface, ...), and `LiveCount.keyboardViews` counts KeyboardViews alive. iOS makes a new controller per presentation and can keep old
    ones alive, so the model, sync and Pro check live once per process in
    `KeyboardShared`; each controller makes its KeyboardView and `ProxyTarget` the first
    time it is about to show (`makeKeyboard`, not in `viewDidLoad`: iOS makes keyboards
    it never shows, and each cost ~9 MB of keys), becomes `showing` on appear, and
    takes its KeyboardView out of its view on `viewDidDisappear` (iOS keeps old
    controllers' views in its windows). When the app the keyboard is in goes to the
    background with it up (`NSExtensionHostDidEnterBackground`), the keys rest, the
    readings stop, the recording is written out, and the health session is marked
    suspended, so a process iOS ends there is not counted as "killed"
    (`hostDidEnterBackground`; `hostWillEnterForeground` undoes it). The keyboard in
    each app is its own process, and every one writes the health file: each puts in
    only its own session (`KeyboardHealth.put`). The first load stays light: Sentry and the
    recorders start in `makeKeyboard` too, the Metal shaders (compiled by Xcode into
    the package's bundle) load off the main thread (`MetalKeyboard.load`; the keys draw
    their own letters until then), and the
    Core ML next-word models and the first iCloud sync wait a second after the keys
    are on screen (`KeyboardShared.settleIn`); each keyboard shown after that starts a
    round at most every five minutes (`SyncController.syncOnShow`; a change here still
    goes up after two seconds). Each opening's steps go into the typing
    log as an `open` line (`OpenTiming`): "launch 180 · telemetry 12 · model 40 · keys 35 · …"
    (`launch`, for the first keyboard in a process, is from the process's start to
    `viewDidLoad`). The emoji list and search index are made once per process
    (`KeyboardView.catalog`/`search`) and dropped on a memory warning. `ExtensionChecks`
    writes the StoreKit, memory and size readings into the bar's idle note while
    `Flags.extensionReadout` is on.
  - `AstrotypeKit/`: the local package, three targets:
    - `AstrotypeCore`: Core and Services. `SpaceSlide` (a finger on space: a tap, or a cursor slide after a short hold and a real move), `Layout` (key geometry, with the field's
      `BottomRow`), `Field` (what the app says about the field and what the keyboard
      makes of it: bottom row, return key, exact taps, spacing, capitals, learning), `Language` (one
      language's files from `Resources/<code>/`: `Lexicon`, the trie from
      `lexicon.tsv`, and `NgramModel`, the word pairs from `bigrams.bin`; English and
      Spanish, `Language.bundled(["en", "es"])` for both at once, a sentence keeping to the first language it shows (`Language.lock(for:)`, `Composer.lockedLanguage`, unless `mixesLanguages`); accented words sit
      under their plain letters, `Lexicon.fold`, and `Matcher` writes the accents back; both are flat tables read in place from one block of bytes, `Storage/MappedBytes`: the word pairs mapped straight from `bigrams.bin` (format version 2), and each dictionary written once to a ready-to-read file in `Language.cacheFolder`, the keyboard's Caches, then mapped, so the keyboard holds neither in memory; the app and tests leave the folder nil and keep them in memory), `Flags`, and `Engine/`: `Composer` (touches in, effects out, pure,
      time passed in), `Matcher` (pieces to ranked candidates: trie search plus DTW,
      two-thumb orderings and split swipes, both thumbs swiping at once in
      `Matcher+Together` (letters woven by when each key was reached), the words before the open one from
      `WordContext` and the person's `PersonalIndex`, and the next-word model's say on each word when one is loaded, `Matcher.nextWords`), `NextWords` (the likely next words for
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
      them), `TextReplacements` (shortcut → phrase, the `{date}`, `{cursor}`, `{?blank}` and other variables, features/text-replacements), `PhoneReplacementsFile` (the iPhone's replacements, written by the keyboard for the app), `KeyboardSettings` (the in-keyboard settings
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
      words and their strokes), `Week`, `SpeedTest` (the test as it runs, `SpeedResult`), `TypingSpeed` (`SpeedMeter`,
      `SpeedRun`, `SpeedRunStore`, `SpeedHistory`: the everyday speed, features/typing-speed), `Leaderboards`
      (`LeaderboardRules`: what gets posted; `LeaderboardPage`, `LeaderboardService` with its fake,
      features/leaderboards; the boards themselves are in `store/game-center.json`),
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
    - `AstrotypeTools`: the `astrotype-tools` command line (`build-ngrams`, `upgrade-ngrams` (an older `bigrams.bin` in the current format), `replay`,
      `tune` (`Tuning`'s search over `Matcher.Weights`), `synth` (`SyntheticTyping`'s
      made-up words to measure against), `prompts`,
      `next`, `typing` (a typing log's timeline and replay)), argument parsing over `AstrotypeCore` and nothing else.
    - `AstrotypeUI`: the design system (`Theme` tokens, `Components`, `Art`, `EdgeFade`: a scroll
      view's `fadeEdges`, used by the settings panel and both emoji rows) and the
      keyboard's views: `KeyboardView` (bar plus keys, the pages, the settings panel,
      the `StatsOverlayView` one-line memory brief (`MemorySample.brief`: now and
      peak, more only when out of range) centred below the keys while
      `KeyboardSettings.showsStats` is on, and the recording dot in the "123" key's
      corner; owns a `KeyboardModel`), `BarView` (left key, centred words, the pencil and its fix row), `KeySurfaceView` (touch stream, flashes,
      trails, rings, and the gestures: space slide (and a held space typed as soon as another finger lands), backspace swipe and hold, "123"
      hold, the slide from "123" to a number or symbol, and a held letter's accents, `AccentCallout`; keys drawn from a `KeyStyle`),
      `KeyEffects` (taps, trails, letter effects and flow with Core Animation; the presets Calm, Arcade, Glitch,
      Rainbow, Space, Zen and Sugar Rush are in `EffectsSettings`; Glitch also jolts keys and tears rows, only on
      screen, through `KeySurfaceView.glitchKeys`/`tearRow`), `MetalKeyboard` (the skies behind the keys and the
      Metal letters; the shaders are `Shaders/KeyboardShaders.metal`, compiled by Xcode into the package's
      resource bundle and loaded at first use), `SettingsPanelView`,
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
  `samples/typing/<id>.json` for `astrotype-tools typing`. `ml/ngrams/` makes a language's word list (`make_lexicon.py`; `word-changes/<code>.txt` with `apply_word_changes.py` for the words we add or take out by hand) and counts a
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
  `guesses-bar` (the bar in three parts: the Astrotype menu button left (the settings panel, with Switch keyboard and Open Astrotype; was the globe until 8 Nov 2026), words centred, pencil right with the
  fix row behind it; built 3 Nov 2026),
  `customization` (Appearance split into General, Styling and Effects: themes, your own
  theme, tap and swipe effects and flow levels; in design),
  `text-replacements` (a shortcut typed or swiped goes in as a phrase, with `{date}`
  and other variables; the iPhone's own replacements too; built 8 Nov 2026. Phase 2:
  `{cursor}`, `{clipboard}`, `{?blanks}` asked on the bar, date math, your details,
  random picks, the snippet page (`SnippetsPageView`), suggest as you type, symbol
  shortcuts, copy the iPhone's list in).
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
