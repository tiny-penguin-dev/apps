# StackWrite v2: product definition

Status: Draft

StackWrite is an iPhone keyboard for typing fast with two thumbs. Each thumb taps or
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
- StackWrite v1 tried handwriting instead: letters drawn on top of each other. It works,
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
- **The penguin twist:** two thumbs are two flippers. The practice mode and speed test
  are a small penguin who waddles faster as you do, and the swipe trails are its tracks on
  the ice.

## 3. Principles

1. **Fast is the feature.** Every choice is judged by words per minute and how often the
   first guess is right. Cute never slows a keystroke.
2. **Nothing commits on lift.** The one rule Nintype got right. A word stays open until
   space, punctuation or a pause, so mixing taps and swipes costs nothing.
3. **A plain keyboard on day one.** With no gestures learned, it works like Apple's
   keyboard: tap letters, get suggestions, press space. The speed comes as habits form.
4. **Power one level down.** Gestures, shortcuts, snippets and themes live in the app and
   behind long-presses, never on the main keys.
5. **Private by default.** Nothing typed goes anywhere. Full Access is asked for one
   reason, iCloud sync of your words and settings, and the keyboard types without it.
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
1. A penguin slides in and says hi. One screen: "Type with both thumbs. Tap, swipe, mix,
   and press space when the word looks right."
2. "Turn on the keyboard": a short, honest walkthrough of Settings > General > Keyboard >
   Keyboards > Add New Keyboard. We cannot do this step for them (iOS rule), so the app
   shows exactly where to tap and checks when it is done.
3. "Keep your words everywhere": one screen that asks for Full Access so learned words
   and settings sync over iCloud, and says plainly that this is the only reason. Skippable;
   the keyboard works without it.
4. "Try it": a practice field in the app with the keyboard already up. Five words drawn
   over the keys, thumb by thumb. Skippable.
5. Done. The home screen shows the speed test and the practice drills. Everyone starts
   on the two-week Pro trial, so the first days are the full two-thumb keyboard.

Goal: typing in the app within **one minute**, in another app within two.

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

### 5.4 Practice and speed test (in the app)
1. "Speed test": type three sentences, see words per minute and how many words needed a
   fix. The penguin waddles at your speed.
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
- Themes, including penguin ones.

## 6. Basics vs powerful features

Free is a good basic keyboard. Pro is everything else, as a subscription with a two-week
free trial that starts on first launch.

| Basics (free) | Pro (subscription, two-week free trial) |
|---|---|
| Tap typing and one-finger swipe typing, one swipe per word, English | Two-thumb typing: taps and swipes from both thumbs, mixed in one word |
| Suggestion bar, corrections, autospace | Snippets and hold-space shortcuts |
| Space-bar cursor, backspace word delete, shift, numbers, symbols | Custom gestures and edge swipes |
| Learned words, synced over iCloud | Themes, trails and penguin outfits |
| Speed test | Drills, history and the sharing card |
| Default layout and height | Split, one-handed and custom layouts |
| | Extra languages as they are added |

The free keyboard must be a complete, pleasant keyboard on its own, on par with Apple's.
The speed test stays free so people can see what the trial gave them and come back to Pro.
When the trial ends without a subscription, the keyboard drops to the free set, with
learned words and settings kept.

## 7. The penguin twist (look and feel)

- **The penguin** lives in the app, not on the keys. It greets you, runs the practice
  drills, and waddles across the speed test at your pace. The keyboard itself stays
  clean, because every pixel there is for typing.
- **Trails and flashes** on the keys, in the Tiny Penguin palette: soft, round, quick.
  Off in battery saver and Reduce Motion.
- **Milestones**: first 40 words per minute, first week, a hundred learned words. Small
  rewards: outfits for the penguin, a keyboard theme.
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
- **No dictation.** Third-party keyboards cannot use Apple's microphone button.
- **Emoji**: in v1 the globe key switches to Apple's emoji keyboard. An emoji page of
  our own is a later item.
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
- More languages, starting with Spanish.
- Themes, penguin outfits, milestones.
- Own emoji page, next-word suggestions while nothing is being typed.

### Never
- Needing Full Access to type. It is only ever for sync.
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

## 11. Open questions

1. Pro price (monthly and yearly). Decided with the paywall screen in the design stage.

Answered (1 Nov 2026): this is StackWrite v2 rather than a new app, on the App Store.
Keep the name StackWrite for now; it will be replaced later. Free is the basic keyboard
with one-finger swipe, Pro is everything else with a two-week trial. The handwriting pad
comes later but stays in the code. iCloud sync from day one, which is why the app asks for
Full Access (section 8).

## 12. Where the ideas came from

- The research write-up: [Nintype alternatives and a rebuild](https://claude.ai/artifact/TGYNjxgqJUDXvGxXjsKnVv).
- [Nintype](https://apps.apple.com/us/app/nintype/id796959534): the input model and the
  gestures, learned by using it, never by looking inside it.
- [Kinetica](https://github.com/lurebat/kinetica): an open-source Android two-thumb
  keyboard whose README describes a working engine (per-thumb streams merged by touch
  time, a dynamic-time-warping matcher over a trie, frequency plus word-pair ranking).
  Ideas only; its GPL code stays out of this app.
- StackWrite v1 (`BRIEF.md`): the Swift package, the word list and trie, the beam-search
  decoder shape, the keyboard-extension plan and the record-and-retrain loop.
