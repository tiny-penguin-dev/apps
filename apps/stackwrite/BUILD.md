# StackWrite v2: build plan

Status: Draft

Builds on `PRODUCT.md` (approved 2026-11-01) and `DESIGN.md` (approved 2026-11-01).

## Architecture

- **SwiftUI app plus a keyboard extension, iOS 18+, iPhone first.** The existing
  `ios/StackWrite.xcodeproj` keeps its app target (`com.tinypenguin.stackwrite`) and
  gains a keyboard extension target, `StackWriteKeyboard`
  (`com.tinypenguin.stackwrite.keyboard`). Both share an App Group
  (`group.com.tinypenguin.stackwrite`), which only the extension with Full Access can
  read. CI stays `.github/workflows/stackwrite-ios.yml`.
- **One local package, `ios/StackWriteKit`, with three targets:**
  - `StackWriteCore`: Core and Services (`docs/building.md` §4). The typing engine, the
    rules for Free and Pro, the stores and the sync, all Foundation only, tested with
    `swift test` on Linux in CI. The v1 handwriting pieces (`Features`, `PhraseDecoder`,
    `Recognizer`, `StrokeSample`) move into a `Handwriting/` folder here behind
    `Flags.handwritingPad`, compiled and tested, never shown. `Lexicon` (the flat-array
    trie) stays and is reused as the dictionary.
  - `StackWriteUI`: the design system and the keyboard's views, shared by the app's
    practice field and the extension. The key surface is one UIKit view (multitouch
    with stable touch identities, drawn with layers, cheap in memory); everything else
    is SwiftUI.
  - `StackWriteKitTests`: Swift Testing. The engine is tested by replaying recorded
    touch sequences (`Tests/Fixtures/*.json`) and checking the words that come out.
- **The engine runs in both processes.** The extension owns a `KeyboardModel`; the
  app's `AppModel` owns one too for Try it, the speed test and drills. Both are built
  on the same pure `Composer`, so what is tested once is true everywhere. Nothing in
  the package knows about `AppModel` or `KeyboardModel`.
- **Data:** learned words and settings are a small versioned JSON file. The extension
  writes it in its own container (always available) and, with Full Access, mirrors it to
  the App Group and to iCloud (`CKRecord` per device, merged by last change). The app
  reads and writes the App Group copy. Without Full Access the keyboard has its own copy
  and its in-keyboard settings panel; nothing breaks, nothing syncs.
- **Pro is checked in one place** (`Entitlement`, fed by StoreKit 2). The extension
  reads StoreKit's current entitlements itself if that works inside an extension
  (checked first thing in Phase 1); otherwise the app writes the status to the App
  Group and the keyboard falls back to it, which needs Full Access.
- **Memory budget: 40 MB in the extension**, measured on a phone every phase. The
  dictionary is a trie over 40,000 words (about 2 MB), the matcher works on resampled
  paths, there is no Core ML model in the extension.
- **Crash reports and metrics** use Sentry through `Telemetry` (`docs/telemetry.md`),
  added to this older app as that doc describes. Only the app sends; the extension
  never does.
- **The ML loop from v1** (`ml/`, CloudKit sample upload) is kept for the practice
  sessions people opt into, and is otherwise untouched.

## Core pieces

Each gets its API written down here, then tests, then use (`docs/building.md` §3).

**`Theme`** (`StackWriteUI`): the tokens from `DESIGN.md`, nothing else in a screen
names a colour or a size.

```swift
Text("Both flippers, go.").font(.sw(.title)).foregroundStyle(Theme.ink)
PrimaryButton("Let's go") { model.next() }
Row(title: "Autospace", subtitle: "Write the word after a short pause") { Toggle(...) }
```

**`Layout`** (`StackWriteCore`): where the keys are, for a width. Pure geometry, so the
matcher and the view agree, and every size (`DESIGN.md` Sizes) is a number.

```swift
let layout = Layout.qwerty(width: 390, height: 216)
layout.key(at: CGPoint(x: 40, y: 30))        // .letter("w")
layout.frame(of: .space)                     // CGRect
layout.side(of: .letter("h"))                // .right
```

**`Composer`** (`StackWriteCore`): the typing engine. Touches in, text edits out.
Pure: no timers of its own, the caller passes the time, so tests replay fixtures and
autospace is a function of time.

```swift
var composer = Composer(dictionary: lexicon, learned: words, layout: layout, settings: settings)
composer.touchDown(id: 1, at: p, time: t)    // each returns [Effect]
composer.touchMoved(id: 1, to: p, time: t)
composer.touchUp(id: 1, at: p, time: t)
composer.tick(time: t)                       // autospace, fix bar timeout
composer.press(.space, time: t)              // or .backspace, .shift, .returnKey, .character(",")
composer.choose(guess: 1)                    // from the bar
composer.state.openWord                      // "someth", guesses: ["something", "smoothing"]
composer.state.bar                           // .idle(note) | .guesses([...]) | .fix([...])

enum Effect { case insert(String), deleteBackward(Int), replaceLastWord(with: String),
              flash(Key, Side), trail([CGPoint], Side), haptic(Haptic) }
```

**`Matcher`** (`StackWriteCore`): the pieces of one open word to ranked candidates.
Dynamic time warping over resampled swipe paths against the trie, taps as exact
letters, pieces merged by touch-down time with a 120 ms swap window, then frequency,
word-pair and personal weight. Under 5 ms a call on an iPhone 12.

```swift
let matcher = Matcher(dictionary: lexicon, learned: words, layout: layout)
matcher.candidates(for: pieces, limit: 3)    // [Candidate(word:"something", score:0.91), ...]
```

**`Entitlement`** (`StackWriteCore`): what the person may use, from one status.

```swift
let ent = Entitlement(status: .trial(endsOn: date), now: now)
ent.allows(.twoThumbs)                       // true
ent.allows(.splitLayout)                     // true on trial, false on .free
Entitlement.features(for: .free)             // the table in PRODUCT.md §6
```

**`Settings`** and **`LearnedWords`** (`StackWriteCore`): value types with a version
number, read and written by `SettingsStore` and `WordStore` (protocols with a
`FileStore` and an in-memory fake). `CloudSync` (protocol, `CloudKitSync` live, fake in
tests) merges two copies by last change.

```swift
var words = LearnedWords()
words.learn("flotilla", at: now)             // typed letter by letter
words.boost("penguin"); words.forget("teh")
words.merged(with: otherDevice)              // last change wins per word
```

**`Telemetry`**: the repo's wrapper, as in `docs/telemetry.md`. Metric names below.

## Metrics

| Metric | Phase |
|---|---|
| `setup.keyboard_on` | 4 |
| `setup.full_access` (`on` / `skipped`) | 4 |
| `onboarding.finished` (duration) | 4 |
| `sync.failed` | 5 |
| `trial.started`, `pro.subscribed` (`plan`) | 6 |
| `speedtest.finished` (gauge: words per minute) | 7 |
| `drill.finished` (`drill`) | 7 |

## Phases

Each phase is one PR and leaves something to try in TestFlight. Every "done when" is
checked at the small size (iPhone Duo outer), the largest text size and the wide size
(Duo inner), in the simulator or on a Duo.

### Phase 1: Extension, design system, two spikes

The keyboard extension target with a plain tap keyboard (`Layout`, `Theme`, the key
surface, no decoding yet), the three package targets with the v1 code moved behind the
flag, Sentry added as `docs/telemetry.md` says, the app's `CLAUDE.md` rewritten for v2.
Two checks that decide later phases, each a note in this doc: can the extension read
StoreKit entitlements, and do haptics work in it without Full Access. Memory measured
with the dictionary loaded.

**Done when:** the TestFlight build opens to the Hello screen, the keyboard can be
turned on in Settings and types letters into Notes, the key surface fits the three sizes
with Apple's proportions, and the extension sits under 40 MB.

### Phase 2: One finger, the whole engine

`Composer` and `Matcher` with taps and one-finger swipes, the bar's three states, the
open word underlined in the field, commit on space, punctuation and autospace, the fix
bar after a commit, backspace reopening a word. Tested on recorded fixtures. The app's
practice field runs the same keyboard.

**Done when:** swiping t-h-e-r-e writes "there", a tap inside a swipe writes a doubled
letter, the first guess is right for 9 of 10 words in a 50-word fixture, and a candidate
list takes under 5 ms on a phone.

### Phase 3: Two thumbs and the keyboard's gestures

Multitouch pieces merged by touch-down time with the swap window, left and right
colouring, shift and caps lock, auto-capitalised sentences, the numbers and symbols
pages, slide on space to move the cursor, swipe left on backspace to delete a word, the
globe key, in-keyboard settings panel (autospace, delay, trails) for when Full Access is
off.

**Done when:** "something" types as the Try it screen describes (left taps s and e,
right swipes o-m and t-h-i-n-g, overlapping), and every gesture in `DESIGN.md`'s
keyboard section works in Messages.

### Phase 4: The app

First launch (Hello, Turn on the keyboard with detection through the active input
modes, Keep your words everywhere, Try it with five words and Show me replays), Home,
Settings, the yellow banner when the keyboard is off, the art and the springs from
`DESIGN.md`. Metrics: `setup.*`, `onboarding.finished`.

**Done when:** a new person reaches typing in the app within a minute and in Messages
within two, the chip flips to "On" by itself after Settings, and Home lays out in two
columns on the wide size.

### Phase 5: Learned words and sync

Learning on commit, boost and forget from the bar, the learned words list in Settings,
`WordStore` and `SettingsStore` in the extension's container and the App Group,
`CloudKitSync` of words and settings with Full Access, the sync row in Settings.
Metric: `sync.failed`.

**Done when:** a word tapped out on one phone is a first guess on a second phone within
a minute, with no Full Access the keyboard still learns and keeps its words, and the
backup before a version change leaves nothing behind.

### Phase 6: StackWrite Pro

StoreKit 2 subscription ($19.99 a year, $2.99 a month, two-week trial from first
launch), `Entitlement`, the Pro screen, Pro badges in Settings, the Trial over
sheet, free mode in the keyboard (one thumb, the one-line nudge), Pro status inside the
extension by whichever route Phase 1 found. Metrics: `trial.started`, `pro.subscribed`.

**Done when:** in TestFlight's sandbox the trial starts on first launch, a second thumb
types during the trial and shows the nudge after it, subscribing turns two thumbs back
on in Messages without opening the app, and restoring works after a reinstall.

### Phase 7: Speed test and drills

The speed test (three sentences, words per minute, fixes, versus Apple's, best and
streak), the result screen with confetti, the three drills with their thumb hints, This
week, the milestone sheet, and the opt-in upload of practice sessions through the v1
CloudKit loop. Metrics: `speedtest.finished`, `drill.finished`.

**Done when:** a test gives a believable words per minute, a new best shows the bolt and
confetti, finishing a drill ticks it on Home, and an uploaded session appears in
`ml/samples/cloud`.

### Phase 8: Polish and the store

Dark mode pass, Dynamic Type and VoiceOver as in `DESIGN.md` Accessibility, Reduce
Motion, haptics by whichever route Phase 1 found, the battery saver setting, the app
icon, App Store screenshots at every size, the privacy label matching the manifest.

**Done when:** every screen and the keyboard work at the largest text size and with
VoiceOver, trails still draw under Reduce Motion, and the App Store listing is ready to
submit.

## Risks

- **Memory in the extension.** iOS kills keyboards quietly. Phase 1 measures with the
  real dictionary loaded and keeps a margin; if 40 MB is tight, the dictionary shrinks
  to 20,000 words before anything else gives.
- **Matching quality.** Dynamic time warping over a trie is proven (Kinetica) but needs
  tuning on real thumbs. Fixtures from Gabriel's own typing from Phase 2 on, and the
  opt-in practice uploads from Phase 7, are how we see it. If the first guess stays
  under 9 of 10, a small n-gram model comes before any neural one.
- **StoreKit and haptics inside the extension.** Both checked in Phase 1. The fallbacks
  (App Group pass-through, visual feedback only) are in the plan, so neither blocks.
- **Detecting that the keyboard is on.** `UITextInputMode.activeInputModes` lists our
  bundle identifier once the keyboard is added; Phase 4 confirms it on iOS 18 and 26.
- **The design may need to move.** If a keyboard gesture does not survive real thumbs,
  `DESIGN.md` changes in the same PR and says so.
- **No Xcode in Claude's container.** Every change is checked by the GitHub Actions
  build, and the engine's tests run on Linux so they run on every PR.

## Open questions

None right now. Answered by Gabriel (1 Nov 2026): Pro is $19.99 a year and $2.99 a
month, as on the Pro screen; practice-session uploads keep the v1 CloudKit container
(`iCloud.com.tinypenguin.stackwrite`).
