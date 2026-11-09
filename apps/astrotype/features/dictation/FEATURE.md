# Astrotype: Dictation

A mic button on the keyboard: tap it (or hold it) and talk, and your words go into the
text field. iOS doesn't let keyboards use the microphone, so the Astrotype app does the
listening, and the keyboard just asks it to.

## Product

Status: Approved 2026-11-09 (Gabriel's ask in the dictation thread, 9 Nov 2026, after
seven test rounds)

- **The problem:** Apple's mic button only works with Apple's keyboard. People who use
  Astrotype have to switch keyboards to dictate, and switch back.
- **Who wants it:** everyone who dictates now and then. Basics: one button, no setup
  beyond allowing the mic once.
- **What iOS allows** (tested on device, 6 to 9 Nov 2026):
  - A keyboard can't record, even with Full Access.
  - The app can record in the background, but it has to *start* the mic while it's
    open (or from Siri, the Action Button or a Live Activity button). Once the mic
    stops, it can't start again from the background.
  - So the app opens once to turn the mic on, and then keeps it on for a while. While
    it's on, iOS shows its orange mic dot. No Live Activity is needed.
- **How it works:**
  1. You tap the mic button on the keyboard.
  2. If the mic is already on (you dictated in the last few minutes), Astrotype starts
     listening right away. You stay where you are.
  3. If it isn't, the Astrotype app opens, turns the mic on, and shows a screen that
     points at how to go back (swipe along the bottom edge). You go back and talk.
  4. Your words appear in the field as you speak. Tap the button again to stop, or
     hold the button while you talk and let go to stop.
  5. The mic stays on for 5 minutes after you last used it, so the next dictation
     needs no trip to the app. Then it turns off and the orange dot goes away.
- **What it changes:** the guesses bar gets a mic button, and a listening state. The
  app gets the "go back" screen and a Dictation page in Settings. `PRODUCT.md` drops
  "No dictation".
- **Scope:**
  - Now: tap to start and stop, hold to talk, text as you speak, the go-back screen,
    the 5 minute window, Settings → Dictation, the keyboard's typing log and Sentry
    covering every step.
  - Later: voice commands ("new line", "delete that"), picking a dictation language
    apart from the keyboard's, cleaning up filler words with a model.
  - Never: sending audio or text off the phone. Listening and speech to text happen on
    the device, and nothing is kept.
- **What we measure** (Sentry, counts and timings only, never what was said):
  - `dictation.started` count, `{"mic": "ready" | "opened_app"}`: how often the mic
    was already on versus needing the trip to the app.
  - `dictation.returned` duration: from the app opening to listening in the other app.
    Shows whether the go-back screen is clear.
  - `dictation.finished` count, `{"how": "tap" | "hold" | "cancel"}` and
    `dictation.length` duration: how people use it.
  - `dictation.session_ended` count, `{"why": "idle" | "user" | "system"}`: how often
    iOS stops us before the 5 minutes.
  - `dictation.failed` count, `{"step": "permission" | "mic" | "speech" | "no_app"}`.
- **Decided** (Gabriel, 9 Nov 2026): free; 5 minutes by default, with 1, 5 or 15 in
  Settings.

## Design

Status: Approved 2026-11-09 (Gabriel: "put the mic on the top right and do what you
said. You can start building.")

- **Mockups:** `design/mockups/dictation.html` (Artifact link: https://claude.ai/artifact/1X9CUKqafCqWTwL2ace9qu)
- **What changes:**
  - **Where the mic goes:** top right (Gabriel picked it, 9 Nov 2026). Both were mocked:
    - *Top right:* the bar's right end holds one button. It's the pencil when the last
      word has something to fix (as today), otherwise the mic. Snippets leave the bar
      and become a row in the Astrotype menu (the logo), next to Switch keyboard and
      Open Astrotype. In the split middle column the same one button sits on the
      bottom row next to the logo (`BarView.layoutRows()`, from the split-column work).
    - *Bottom right:* a mic key left of return, near where iOS puts its own; space gets
      a little shorter. The bar's right end keeps only the pencil.
    - Either way, a small mint dot on the mic means the mic is on and ready.
  - **Listening state:** the bar turns into a listening strip: ✕ at the left (stop and
    take back what was said), a wide live sound wave across the middle, and a mint ✓
    at the right (stop and keep). The words go straight into the field as you speak, so
    the bar doesn't repeat them (Gabriel, 9 Nov 2026).
  - **Talk and type together** (Gabriel, 9 Nov 2026): the keys keep working while it
    listens. A key freezes what was said so far, as it stands, and types as usual; the
    next words you say go after what you typed ("hello how" + type "r" + say "you" →
    "hello how r you"), with spaces and capitals at each join done like autospace.
    Speech that arrives while a word is half typed waits until that word goes in.
    Backspace deletes as usual (the newest dictated words first); return starts a new
    line and the next words go there. Frozen words miss iOS's late fixes to the last
    word or two, which is rare.
  - **Hold to talk:** holding the mic for 0.3 s or more listens only while held; the
    strip says "Let go to stop". A short tap toggles.
- **New screens:**
  - **Go back** (app, full screen, on top of whatever was open): a mint mic, "Mic's on",
    "Swipe right along the bottom edge to go back and talk." A teal swipe trail (the
    keyboard's own trail) slides along the real bottom edge over and over, with a thumb
    dot riding it, so it's obvious where to drag. On phones that show "◀ App" at the top
    left, a small bubble points up at it: "or tap here". On the iPhone Duo there's no
    such button, so the bubble isn't shown. A "Not now" text button turns the mic off.
  - **First time:** the same screen first asks for the microphone (and speech
    recognition if iOS needs it), with one line on why, then continues.
  - **Settings → Dictation:** Mic button on the keyboard (on), Keep the mic ready
    (1, 5 or 15 minutes, 5 by default), and a footnote on privacy (on the phone, nothing
    kept).
- **Motion and copy:**
  - The mic button pops (spring) when tapped. Listening, the wave follows your voice;
    with Reduce Motion it becomes a steady level bar.
  - Go back's trail loops every 1.6 s; with Reduce Motion it's a still arrow.
  - A light haptic when listening starts and stops.
  - Copy: "Listening…", "Let go to stop", "Mic's on", "Swipe right along the bottom
    edge to go back and talk.", "or tap here", "Not now", "Turn on Full Access to
    dictate" (when it's off), "Astrotype needs the mic to hear you. It listens only
    while you dictate, on your phone."
- **Design system:** reuses the bar's three parts, `Icon` buttons, `PrimaryButton`,
  `SettingsGroup`, `SettingsToggle`, `Segmented`, `Trails`. Adds `MicButton` (idle,
  ready, listening, held), `ListeningStrip` (wave, words, ✕, ✓) and `SwipeHint` (a
  looping trail along an edge).
- **Sizes:** the wave fills whatever width the middle has. On the
  Duo's inner screen the go-back screen centres its text in a narrower column and the
  trail still runs along the full bottom edge. In a column layout (split keyboard) the
  strip stacks: the wave, then ✕ and ✓.
- **Accessibility:** the mic button reads "Dictate" ("Dictate, mic ready" when on), with
  the hint "Double tap to start. Double tap and hold to talk." The strip's buttons read
  "Stop and discard" and "Done". VoiceOver hears "Listening" when it starts. The
  go-back screen's text says what to do without the animation.
- **Decided:** top right, one button (pencil when there's something to fix, else mic).

## Build

Status: Approved 2026-11-09

- **Approach:** the keyboard and the app already share an App Group, and the spike
  proved Darwin notifications reach the running app. The app owns the mic and speech
  to text; the keyboard sends start, stop and cancel, and reads the words back.
  - The keyboard opens the app with `astrotype://dictate` (the same responder-chain
    open as "Open Astrotype").
  - The app starts the mic while it's open (`AVAudioSession` play and record,
    `UIBackgroundModes` audio), runs Apple's on-device `SpeechAnalyzer` with
    `SpeechTranscriber`, and writes the words as they change to the App Group.
  - The keyboard replaces what it wrote last with the new words, the way it replaces
    the open word, and commits them when listening stops.
- **Core pieces** (`AstrotypeKit`, tested with `swift test`):
  - `DictationState` (Codable): `phase` (off, ready, listening, finishing), `words`,
    `revision`, `lastUsed`. What both sides read.
  - `DictationCommand`: start, stop, cancel, sent as Darwin notifications by name.
  - `DictationEdit.between(written:, now:) -> (delete: Int, insert: String)`: how the
    keyboard turns new words into backspaces and an insert, keeping the shared start.
  - `DictationMerge`: talk and type together. Tracks the live (still changing) part of
    the text; a key freezes it and tells the app to start a new segment; works out the
    space and capital at each join from the text before it.
  - `DictationPress`: tells a tap from a hold (0.3 s), so the keyboard and its tests
    agree.
  - `DictationWindow`: when the mic should turn off (last used plus the setting).
  - In the app: `SpeechListener` protocol (live: mic plus `SpeechAnalyzer`; fake for
    tests) and `DictationChannel` (App Group file plus notifications; fake for tests).
  - `DictationModel` (`@Observable`, owned by `AppModel`): the session, the window,
    metrics.
- **Logging:** each step writes to the keyboard's typing log (`TypingEvent.Kind`
  dictation start, stop, cancel, opened app, words in) and, in the app, a Sentry
  breadcrumb (never the words). Failures go to Sentry with the step and the iOS error
  code.
- **Phases:**
  1. **Clean up and core:** remove all the test code (the DictationTest folders, the
     Live Activity extension, the push workflow and push entitlement, the CloudKit
     nudge, the Debug section) and add the core pieces with tests. Done when the
     Debug page has no dictation test and `swift test` passes.
  2. **Dictation end to end:** the mic button, opening the app, the go-back screen,
     listening in the background, words into the field, tap and hold, the 5 minute
     window, logging. Done when, on the phone, a tap in Notes opens Astrotype, you
     swipe back, talk, and see your words; a second dictation within 5 minutes needs
     no trip.
  3. **Settings and finish:** Settings → Dictation, Full Access and permission states,
     metrics, the small and Duo sizes, VoiceOver. Fold this into `PRODUCT.md` and
     `DESIGN.md`. Done when it's in TestFlight and checked at the small size, the
     largest text size and the Duo.
- **Risks:**
  - iOS may stop the app in the background before the 5 minutes (memory, a phone
    call, another app taking the mic). The keyboard then sees the state as off and the
    next tap opens the app again; we count it as `session_ended` `system`.
  - `SpeechTranscriber` needs its language model on the phone. The first use may
    download it; the go-back screen shows that.
  - Opening the app from a keyboard isn't official. Gboard and others do it, but review
    could push back (guideline 4.4.1).
  - The Duo has no "◀ App" button. The app tells the Duo by its model identifier (to
    confirm on Gabriel's Duo).
- **Metrics:** the ones under Product, with `Telemetry`.
- **Last step:** fold this feature into `PRODUCT.md` and `DESIGN.md`.
