# Astrotype v2: product definition

Status: Approved 2026-11-01

Astrotype is an iPhone keyboard for typing fast with two thumbs. Each thumb taps or
swipes a few letters at a time, both at once, and the keyboard turns the pieces into the
word you meant. It is a rebuild of Nintype, the keyboard that did this best and stopped
being updated in 2019, made for the App Store with the Tiny Penguin look.

Easy by default. Powerful when you want it.

## 1. The problem

- Typing on a phone is slow. Tapping is accurate but one letter at a time. Swipe typing
  (Gboard, SwiftKey, Apple's keyboard) is faster but takes one long swipe per word with
  one finger, which gets clumsy past five or six letters and leaves the other thumb idle.
- Nintype solved this in 2014: swipe and tap with both thumbs, mix them inside one word,
  and the word is not finished until you press space. People who learned it report about
  100 words per minute. It has not been updated since 2019, the Android version is gone,
  and nothing on iOS today does two-thumb typing.
- Astrotype v1 tried handwriting instead: letters drawn on top of each other. It works,
  but one stroke per letter is slow by design, so it never beat typing. The pieces built
  for it (the Swift package, the word list, the decoder, the training loop) are reused here.

## 2. Who it's for

**Main user: people who type a lot on their phone and want to go faster.** Messages,
notes, email, chat with assistants. They are willing to spend a week learning a new habit
if it pays off every day after that.

Also for:
- Former Nintype users looking for a home. There are enough of them to fill forums and
  three Android revival projects.
- Tinkerers who want shortcuts, snippets and custom gestures in their keyboard.

Not for (now): people who want AI rewriting, GIF search, or a keyboard for many languages
on day one.

## 2b. What makes it different

- **Two thumbs, one word.** Tap with one thumb, swipe with the other, switch mid-word.
  Nothing commits until space, so short swipes and taps mix freely. No other iOS keyboard
  does this.
- **Fast without staring.** Each thumb only ever covers its half of the keyboard, so
  travel is short and the rhythm is close to a physical keyboard.
- **Learns you, keeps your words.** Typing runs on the phone and nothing you type ever
  leaves it. No account: your learned words and settings follow you to a new phone over
  iCloud.
- **The penguin twist, kept light:** no mascot. The app talks about flippers ("Both
  flippers, go."), and the graphics are a keyboard with two coloured thumb trails. If a
  penguin ever appears, it is Squawk's, not a new one.

## 3. Principles

1. **Fast is the feature.** Every choice is judged by words per minute and how often the
   first guess is right. Cute never slows a keystroke.
2. **Nothing commits on lift.** The one rule Nintype got right. A word stays open until
   space, punctuation or a pause, so mixing taps and swipes costs nothing.
3. **A plain keyboard on day one.** With no gestures learned, it works like Apple's
   keyboard: tap letters, get suggestions, press space. The speed comes as habits form.
   Like Apple's, it changes for the field: @ and . in email fields, . / and .com in web
   addresses, the app's word on return ("go", "search"), and no autospace or
   corrections where they get in the way (`features/field-types`).
4. **Power one level down.** Gestures, shortcuts, snippets and themes live in the app and
   behind long-presses, never on the main keys.
5. **Private by default.** Nothing typed goes anywhere. Full Access is asked for one
   reason, iCloud sync of your words and settings, and the keyboard types without it.
   With it on, and anonymous usage data on, the keyboard also sends crash reports,
   which hold where it crashed and never any text (section 10b).
   Typing data for tuning leaves the phone only from the practice screen in the app, and
   only if you turn it on.
6. **Clean-room.** We match how Nintype feels by using and measuring it, never by copying
   its code, data or name.

## 4. Key ideas (the words we use)

| Word | What it means |
|---|---|
| **Piece** | One touch from one thumb: a tap on a key, or a swipe across a few keys. |
| **Open word** | The word being built from pieces. Shown in the bar, not committed yet. |
| **Commit** | The moment the open word is written: space, punctuation, or autospace after a pause. |
| **Bar** | The strip above the keys with the top guesses for the open word, and after a commit, fixes for the last word. |
| **Pad** | The v1 handwriting surface. Kept in the code, not in v1 (see scope). |
| **Snippet** | Saved text you insert with a long-press (an email address, a street address). |

## 5. Core flows

### 5.1 First launch
1. A short animation of two thumb trails meeting on a keyboard. One screen: "Type with
   both thumbs. Tap, swipe, mix, and press space when the word looks right."
2. "Turn on the keyboard": a short, honest walkthrough of Settings > General > Keyboard >
   Keyboards > Add New Keyboard. We cannot do this step for them (iOS rule), so the app
   shows exactly where to tap and checks when it is done.
3. "Make it yours" (features/home-and-welcome): pick a theme and an effect, with the
   keyboard up to try them. Classic and Calm are picked to start. Skippable.
4. "Try it": a practice field in the app with the keyboard already up. Five words drawn
   over the keys, thumb by thumb. Skippable.
5. "Keep your words everywhere": one screen that asks for Full Access so learned words
   and settings sync over iCloud, and says plainly that this is the only reason. Skippable;
   the keyboard works without it. Last, so it comes once the keyboard has words to keep.
6. Done, with confetti. Every step after Hello shares one shape: a progress bar, Skip in
   the corner, one thing to do. Home leads with Your speed, then Your keyboard (themes,
   effects, height, with the keyboard docked at the bottom to try them); practice and
   the lesson are one tap away in Learn and practice. Everyone starts on the two-week
   Pro trial, so the first days are the full two-thumb keyboard.

### 5.2 Typing a word
1. Tap or swipe with either thumb, in any order, overlapping if you like. Each piece
   lights its keys and leaves a short trail.
2. The bar shows the best guesses as pieces arrive. The first one is what space will write.
3. Press space, or type punctuation, and the word goes in. Or pause, and autospace writes
   it for you (on by default, with a delay you can change).
4. Wrong word? Tap another guess in the bar, and it replaces the last word. Backspace to
   the end of a word reopens it, so you can add a tap or a swipe.

### 5.3 Learning your words
- A word the dictionary does not know: tap it out letter by letter and it is learned.
- A word you keep choosing outranks a more common one.
- Hold a guess in the bar and slide it down to forget it, or up to make it stick.
- A swipe that came out wrong: tap **Not it?** in the bar and type the word meant. The
  text is fixed, the keyboard remembers that swipe for the word, and the miss is kept
  in Settings → Your words → Words it missed (and shared with "Include corrections"
  on). From `features/missed-words` (3 Nov 2026).

### 5.4 Practice and speed test (in the app)
1. "Speed test": type three sentences, see words per minute and how many words needed a
   fix, next to Apple's keyboard for comparison.
2. "Drills": short sets built around one habit at a time (two-letter swipes, switching
   thumbs, doubled letters).
3. Your best speed and your streak live on the home screen. Optional: send the gestures
   from these sessions to us to tune the keyboard. Off by default, never from other apps.

### 5.5 Customize (powerful)
- Gestures: what a slide on the space bar does, what backspace swipes do, edge swipes for
  punctuation.
- Shortcuts: hold space and tap a letter to insert a snippet.
- Autospace delay, tap-versus-swipe sensitivity, trail and flash animations, haptics.
- Layout: full width, left, right, split, one-handed, keyboard height.
- Themes.

## 6. Basics vs powerful features

Free is a good basic keyboard. Pro is everything else, as a subscription with a two-week
free trial that starts on first launch.

| Basics (free) | Pro (subscription, two-week free trial) |
|---|---|
| Tap typing and one-finger swipe typing, one swipe per word, in any one language (English or Spanish) | Two-thumb typing: taps and swipes from both thumbs, mixed in one word |
| Suggestion bar, corrections, next-word guesses, autospace | Snippets and hold-space shortcuts |
| Space-bar cursor, backspace word delete, shift, numbers, symbols | Custom gestures and edge swipes |
| Learned words, synced over iCloud | Themes and trails |
| Speed test, and your everyday speed with its graph (features/typing-speed) | Drills, drill history and the sharing card |
| Default layout and height | Split, one-handed and custom layouts |
| | Two languages at once, guessed from both with no switching (features/languages, 3 Nov 2026) |

The free keyboard must be a complete, pleasant keyboard on its own, on par with Apple's.
The speed test stays free so people can see what the trial gave them and come back to Pro.
When the trial ends without a subscription, the keyboard drops to the free set, with
learned words and settings kept.

## 7. Look and feel

- **No mascot.** Astrotype is a tool people live in all day, so the app stays clean and
  the graphics are generic: a keyboard with two thumb trails, in the app's two thumb
  colours. The penguin connection is the studio's name and the flipper wording, and if a
  penguin ever shows up it is the same one as Squawk's. The keyboard itself has no
  decoration, because every pixel there is for typing.
- **Trails and flashes** on the keys, in the Tiny Penguin palette: soft, round, quick.
  Off in battery saver and Reduce Motion.
- **Milestones**: first 40 words per minute, first week, a hundred learned words. Small
  rewards: a keyboard theme, a trail colour.
- **Copy tone**: short, warm, a bit silly. "Both flippers, go." "Space when it looks right."
- Shared Tiny Penguin look and voice come from [`docs/brand.md`](../../docs/brand.md).

## 8. Platform and keyboard-extension limits

These shape the design, so they are listed here, not only in the build doc.

- **iOS 18 or later**, iPhone first. iPad works but the split layout is a later item.
- **The user has to turn the keyboard on in Settings** and switch to it with the globe
  key. We can only explain and detect it. This is the biggest drop-off point for any
  third-party keyboard, so the first-launch flow spends its effort here.
- **Full Access is what iCloud sync costs.** Without it a keyboard extension has no
  network, no shared clipboard and no shared storage with its app, so it cannot sync and
  cannot read settings made in the app. iOS shows a warning when it is turned on. So the
  first-launch flow asks for it with an honest, one-reason explanation, and the keyboard
  must still type well without it: defaults built in, learned words in its own storage, and
  a settings panel inside the keyboard for the few things that matter there. Recorded
  practice sessions never come from the extension; they come from the practice field in
  the app, which runs the same keyboard code.
- **Pro status inside the extension.** The keyboard has to know whether Pro is active
  without relying on the app. Whether StoreKit can be read from the extension is checked
  first thing in the build stage; the fallback is the app passing it through shared storage,
  which needs Full Access.
- **Memory is tight.** iOS kills a keyboard extension at a limit developers measure at
  roughly 30 to 60 MB. The dictionary, the decoder and the views must fit well under it.
  No neural model in the extension in v1; the matcher is dictionary plus dynamic time
  warping, which Kinetica shows decodes in a few milliseconds.
- **Password fields always switch to Apple's keyboard.** Secure fields never see ours.
- **Dictation goes through the app.** A keyboard can't use the microphone, so the
  mic button on the bar asks the Astrotype app to listen (features/dictation). The
  first dictation in a while opens the app once to turn the mic on; then the mic stays
  ready for 5 minutes (1, 5 or 15 in Settings) and iOS shows its orange dot. Speech
  turns into text on the phone and nothing is kept. It needs iOS 26 and Full Access.
- **Emoji**: Astrotype has its own emoji page (`features/emoji`), so nobody switches to
  Apple's keyboard for one. Where iOS draws its own globe under the keyboard (Face ID
  iPhones) the emoji key takes our globe's place; Home button phones keep both. Emoji
  search finds them by name in English and Spanish (`features/emoji-search`).
- **Haptics and key sounds** may need Full Access on some iOS versions. We check in the
  build stage and fall back to visual feedback.
- **Multitouch works** inside keyboard extensions. Nintype did two-thumb input there in
  2014, so there is no platform blocker.

## 8b. Built to grow

v1 ships one language and a fixed set of gestures, but its shape must make the later
items easy:

- **Languages** are data plus a layout, so adding one is adding files, not code.
- **Gestures** are a table from (key, gesture) to action, so custom gestures and new
  actions do not touch the typing engine.
- **Input modes** (QWERTY, pad) share the bar, the commit rules and the dictionary, so the
  pad is a view that produces pieces, not a second keyboard.

## 9. Scope

### v1
- English QWERTY with two-thumb tap and swipe typing, the bar, autospace, corrections.
- Space-bar cursor, backspace word delete, shift and caps, numbers and symbols pages.
- Learned words, forget and boost, synced over iCloud with the settings.
- Free and Pro as in section 6, with the two-week trial and the paywall.
- The app: first launch, Settings walkthrough, Full Access ask, practice field, speed
  test, three drills, opt-in session upload for tuning.
- Default layout, height adjustable, light and dark.

### Later
- Snippets and hold-space shortcuts, custom gestures, edge-swipe punctuation.
- Split, one-handed and iPad layouts.
- The handwriting pad from v1 as an input mode. Its engine and pad stay in the code,
  behind a flag, so they are not lost and not shipped.
- More languages after Spanish (Spanish shipped with `features/languages`, 3 Nov 2026;
  languages are built into the app, about 2 MB each, not downloaded, since the keyboard
  can only read downloads with Full Access).
- Themes and milestones.
- Emoji suggestions while typing, and Frequently used synced with iCloud
  (`features/emoji`).

### Never
- Needing Full Access to type. It is only ever asked for sync.
- Sending what you type anywhere. No cloud prediction, no AI rewriting of your text.
- Ads.
- Android.

## 10. What success looks like

- Gabriel types faster in the speed test than on Apple's keyboard within a week of daily
  use, and keeps using it after 30 days.
- The first guess is right for 9 in 10 words after two weeks of learning.
- Setup: most people who open the app get the keyboard turned on, measured on device.
- The extension is never killed for memory in normal use.
- Reviews mention "fast" and "like Nintype".

## 10b. What we measure

Anonymous counts only, sent to Sentry from the app (see `docs/telemetry.md`). Nothing
typed, no words, no text. People can turn this off in Settings.

The keyboard sends one thing itself: crash reports, with Full Access and the switch
on. A report says where the code crashed (stack traces), on which device, OS and
version, and how much memory was in use. It never carries text: no breadcrumbs, logs,
screenshots, session replay, traces, messages or user ID, and Astrotype strips any
crash reason that could quote a string. The keyboard's memory readings and its word
counts go to the app through the App Group, and the app sends them (the `keyboard.*`
and `guess.*` rows below).

| Metric | What it tells us |
|---|---|
| `setup.keyboard_on` | How many people get past the Settings step (the big drop-off) |
| `setup.full_access` (`on` / `skipped`) | How many accept the sync ask |
| `onboarding.finished` (duration) | How long first setup takes (goal: under two minutes) |
| `setup.step` (`step`) | Where people drop off in the welcome wizard |
| `setup.restarted` | How often people walk the welcome steps again from Settings → Run setup again |
| `setup.style` (`theme`, `effects`, `changed`) | Whether people make the keyboard theirs in setup |
| `home.style_changed` (`part`: theme, effects, theme_preview, effects_preview) | Whether Home's Your keyboard card gets used, and how often free users try a Pro look |
| `lesson.replayed` | Whether people want the two-thumb lesson again |
| `speedtest.finished` (gauge: words per minute) | Whether people get faster over time |
| `speed.everyday` (gauge: words per minute, once per finished day with a speed) | Whether people really type faster with Astrotype, outside practice (features/typing-speed) |
| `speed.opened` (count) | Whether people look at their speed graph |
| `leaderboard.joined` (count) | How many people join the leaderboards (features/leaderboards) |
| `leaderboard.opened` (count, tags `board`, `scope`) | Whether people come back to the boards, and whether Friends gets used |
| `drill.finished` (`drill`) | Which habits people practise |
| `trial.started`, `pro.subscribed` (`plan`) | Whether the trial converts |
| `sync.failed` | iCloud sync problems (goal: zero) |
| `practice.shared` (`kind`) | How many words people share, practice or corrections (features/smart-matching) |
| `personal.reset` | How often people wipe what the keyboard learned (features/smart-matching) |
| `words.added`, `words.deleted` (by count; `how`: `swipe` / `select`) | Learned words typed in by hand, and dropped (features/learned-words) |
| `pairs.opened`, `pairs.deleted` (by count; `how`) | Whether anyone looks at the word pairs, and how many they delete (features/learned-words) |
| `word.menu`, `word.blocked`, `word.boosted`, `word.allowed` (`how`: `menu` / `slide` / `voiceover` / `settings` / `swipe` / `select` / `undo`) | Whether people teach and block words from the bar, and how (features/word-control) |
| `earlier.shown` (`how`: `cursor` / `select`), `earlier.fixed` (`how`: `reading` / `typed`), `earlier.undone` | Whether people fix words written earlier from the bar, and whether it shows up when they don't want it (features/fix-earlier-word) |
| `languages.enabled` (`set`: `en`, `es`, `en+es`) | Which languages people turn on, and how many want two at once (features/languages) |
| `keyboard.memory_peak` (MB, per time the keyboard is shown; `parts`: what was open, like `keys`, `emoji`, `emoji+settings`, `metal`) | Memory regressions before they hit the extension's limit (budget: 40 MB), and which part of the keyboard caused them |
| `miss.saved` (count) | Words typed with "Not it?" because a swipe missed them (features/missed-words). Falling over time means the matcher is getting better |
| `keyboard.memory_headroom` (MB, the least left; `parts`) | How close the keyboard gets to iOS ending it |
| `keyboard.ended_while_showing` (`parts`; `how`: `crash`, `killed`, `unknown`) | Keyboards ended while on screen: crashes, and the memory kills no crash report sees (`killed`: no crash report, so most likely memory). A keyboard whose app went to the background with it up and was ended there is not counted: iOS ends suspended keyboards as it likes |
| `guess.words`, `guess.first` (counts, `kind`: `swipe` / `tap`) | How many words went in, and how many as the keyboard's first guess (goal: 9 in 10, §9). Counted per time the keyboard is shown, never which words, and not in fields that don't learn (like passwords) |
| `guess.first_share` (gauge: percent, `kind`) | The same share for one time the keyboard was shown, sent when it had at least 10 words, to read at a glance |
| `nextword.picked` (count) | Words written by tapping a next-word guess, per time the keyboard is shown, beside `guess.words` (features/next-word) |

More get added here as phases land.

## 11. Open questions

None right now.

Answered (1 Nov 2026): this is v2 of the same app, on the App Store. It was called
StackWrite (after the v1 handwriting) until 1 Nov 2026, when Gabriel renamed it
Astrotype, a one-word mashup like Nintype's name. The rename went all the way down: new
bundle IDs (`com.tinypenguin.astrotype`, `.keyboard`), App Group, iCloud container and
Sentry project, a new App Store Connect app, and the folder and code renamed to match.
No build had shipped beyond TestFlight, so nothing was migrated. Free is the basic keyboard
with one-finger swipe, Pro is everything else with a two-week trial. The handwriting pad
comes later but stays in the code. iCloud sync from day one, which is why the app asks for
Full Access (section 8). Pro is $19.99 a year and $2.99 a month (1 Nov 2026).

## 12. Where the ideas came from

- The research write-up: [Nintype alternatives and a rebuild](https://claude.ai/artifact/TGYNjxgqJUDXvGxXjsKnVv).
- [Nintype](https://apps.apple.com/us/app/nintype/id796959534): the input model and the
  gestures, learned by using it, never by looking inside it.
- [Kinetica](https://github.com/lurebat/kinetica): an open-source Android two-thumb
  keyboard whose README describes a working engine (per-thumb streams merged by touch
  time, a dynamic-time-warping matcher over a trie, frequency plus word-pair ranking).
  Ideas only; its GPL code stays out of this app.
- Astrotype v1 (`BRIEF.md`): the Swift package, the word list and trie, the beam-search
  decoder shape, the keyboard-extension plan and the record-and-retrain loop.
