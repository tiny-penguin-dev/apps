# Astrotype: Missed words

A "Not it?" button in the bar for when a swipe writes the wrong word and the right one
isn't offered: type the word you meant, and the keyboard fixes the text, learns from
that swipe, and keeps it so we can see what went wrong.

## Product

Status: Approved 2026-11-03 (Gabriel: "Build it and merge automatically")

- **The problem:** when a swipe comes out wrong and the word you meant isn't among the
  guesses, all you can do is delete it and peck the word out. The keyboard learns
  nothing from that, so the same swipe fails again tomorrow. We can't fix it either:
  the swipe is gone, and "swiping 'second' always fails" (Gabriel, 3 Nov 2026) can't be
  reproduced from a description. Straight, made-up swipes of "second" come out right
  97% of the time in the engine, so the miss is in how a real thumb draws it, and we
  need that drawing.
- **Who wants it:** everyone who swipes, a few times a week. Gabriel most, while the
  matcher is being tuned.
- **Basics or powerful:** the button is basic (one tap, in the bar, where the wrong
  word is). The list of missed words and sharing them live one level down, in Settings.
- **How it works:**
  1. A swiped word goes in wrong ("song"). The bar shows its other readings as today
     (FIX), and at its end a small **Not it?** button. It is there while a swiped word
     is open and in FIX right after it, never for pecked words (those are typed
     exactly).
  2. Tap it: the bar becomes a little field, "What did you mean?". Taps on the keys type
     into it letter by letter, exactly as tapped (no guessing); backspace deletes.
     The text in the app isn't touched yet.
  3. Tap **Save** (or space): the wrong word in the text is replaced with the one you
     typed, the bar gives a small happy bounce, and you carry on. **✕** goes back with
     nothing changed.
  4. The keyboard learns from it right away:
     - a word it didn't know is added to your learned words;
     - the swipe is remembered as a shape for that word, so the next swipe that looks
       like it gets that word first (on this phone, and your other devices with sync).
  5. The swipe is kept as a **missed word**: the word you meant, the word it wrote,
     and the path your thumb drew. Nothing else, never the text around it.
- **Seeing and sharing misses:** Settings → Your words → **Words it missed**: a list
  (newest first) with the word meant, what it wrote, and the swipe drawn on a little
  keyboard. Swipe a row to delete it; "Forget what it learned" also clears the list.
  The list keeps the last 200.
  - **Uploading (iCloud, for anyone):** with "Send practice sessions" and "Include
    corrections" on, misses go up to our iCloud container with the corrections. They
    are the same kind of record (one word, its swipe and the word written, no text
    around it), so anyone who turned sharing on helps, not just us. They show on "What
    gets shared" before they go, and the app sends them, never the extension.
    Each row in the list says "Shared" or "On this phone".
  - **Debugging:** `download_samples.py --type PracticeSession` fetches them and
    `astrotype-tools replay` plays them through the engine, so a miss like "second"
    becomes a test and a fix (Gabriel, 3 Nov 2026: "Do iCloud so anyone can upload").
- **What it changes:**
  - The bar: the new button in the FIX and open-word states, and a new "field" state.
  - The keyboard: while the field is open, taps type into it instead of into the app.
  - The matcher: remembered shapes, a new source of guesses beside the dictionary.
  - Settings → Your words: one new row.
  - "Forget what it learned" also forgets shapes and misses.
- **Scope:**
  - *This version:* the button, the field, fixing the text, learning (word and
    shape), the list, uploading with corrections.
  - *Later:* "Not it?" for pecked words; exporting misses as a file; editing a miss in the app; a debug view that
    shows the matcher's top ten with scores for a miss (handy for us, not for people).
  - *Never:* anything typed around the word leaves the phone; misses sent without
    "Include corrections" on.
- **Free or Pro:** free. A keyboard that can't be taught sells nothing.
- **What we measure** (anonymous, with "Share anonymous usage data", sent by the app
  like `guess.words`, never from the extension):
  - `miss.saved` (count): how often swipes fail badly enough to need it. Falling over time means the matcher improves.
  - Nothing about which words.
- **Decided** (Gabriel, 3 Nov 2026)
  1. **Not it?** shows only after a swiped word.
  2. Save fixes the word in the text and teaches the keyboard.
  3. Misses upload to iCloud with the sharing switches, from anyone who turns them on,
     rather than a file to share.

## Design

Status: Approved 2026-11-03 (Gabriel: "No need for design mockup"; built from the
existing bar and Settings components)

- **The bar, after a swiped word** (open word or FIX, and the idle bar right after a
  swiped word went in with no other readings): the guesses as today, then a small
  ghost button at the end, a pencil glyph and "Not it?" in `muted` 13 pt bold. In a
  column (split or wide) it sits under the guesses. It goes away with the next touch,
  like FIX. With "Guesses bar" off there is no bar, so no button.
- **The field** (a new bar state): an ✕ on the left, then the word being typed in `ink`
  with a teal caret, "What did you mean?" in `muted` while empty, then a **Save** pill
  in `accent` (dimmed until there is a letter). Keys type into it: taps add their
  letter exactly, a held key's accent adds that letter, backspace removes one, space
  and return save, swipes and punctuation do nothing. The word is cased like the word
  it replaces.
- **Motion and copy:** Save gives the bar the commit squeeze and the commit haptic; ✕
  goes straight back. Copy: "Not it?", "What did you mean?", "Save". VoiceOver reads
  the button "Not it? Type the word you meant", and the field "What did you mean,
  text field".
- **Settings → Your words → Words it missed** (Phase C): a `Group` row with the count,
  opening a list: each row is the word meant, "wrote: song" under it in `muted`, and
  the swipe drawn on a small keyboard as on "What gets shared"; "Shared" or "On this
  phone" on the right; swipe to delete. Empty: "Nothing missed yet. When a swipe gets a
  word wrong, tap Not it? in the bar."
- **Design system:** reuses `Theme` tokens, the bar's guess pill and the `Group`, `Row`
  and keyboard-with-paths drawing from "What gets shared". Nothing new.
- **Sizes:** the button and field fit the 320 pt bar (the field's word truncates at
  the head); in a column the field stacks: word, then Save and ✕.

## Build

Status: Approved 2026-11-03 (with the design, at Gabriel's request)

- **Approach:** a correction is a fix from the bar where the person typed the word.
  The pieces already exist for fixes (`Composer.choose` on FIX, `SettledWord.fixedFrom`,
  `SharedWord.correction`, the App Group sharing folder the app uploads), so this adds
  a field mode to the composer and a kind of shared word, then shapes and a list.
- **Core pieces** (`AstrotypeCore`, tested):
  - `Composer.Bar.correcting(String)`, `State.canCorrect` (a swiped word is open or
    just went in), `Composer.beginCorrection()`, `cancelCorrection()` and
    `saveCorrection(time:)`. While correcting, touches and keys edit the field instead
    of the text. Save writes the word in place of the open or last word (casing kept),
    learns it when the dictionary doesn't have it (`.learn`), and leaves a `Committed`
    marked `missed`, so it settles with `SettledWord.missed`.
  - `SharedWord.missKind` (`"word.miss"`): `SharedWord.correction` gives that kind for a
    missed word. `CloudKitPracticeUploader`, `download_samples.py` and `Replay` read it
    as any shared word.
  - `ShapeMemory` (Phase B): per word, up to three remembered swipes, resampled to 32
    points in key widths, kept in the personal model's shard (synced and forgotten with
    it). `Matcher` compares a swipe with them by DTW and adds the word as a guess when
    one is close, scored like a clean swipe of it.
- **Model and UI:** `KeyboardModel.beginCorrection/cancelCorrection/saveCorrection`,
  `onMiss(SharedWord)`; the extension keeps misses in a `SharedWordStore` folder
  (`KeyboardFiles.misses`, the App Group with Full Access, its own files otherwise,
  limit 200) and puts them in the sharing folder too when "Include corrections" is on.
  `BarView` draws the button and the field.
- **Phases:**
  - **A. Not it?** The button, the field, the text fix, learning the word, keeping and
    sharing the miss. Done when: swipe a word wrong, tap Not it?, type it, Save, and
    the text has the word; with sharing on the miss shows on "What gets shared"; a test
    replays a saved miss.
  - **B. Shapes.** `ShapeMemory` in the matcher. Done when: after one miss saved for a
    swipe, the same swipe gives that word first (test), and `candidatesAreFast` holds.
  - **C. Words it missed.** The Settings list. Done when: misses show with their
    swipes, and delete works.
- **Risks:** the shape match must stay inside the matcher's time budget (a handful of
  DTWs per lift); a wrong miss saved must not stick forever (delete in the list, and
  "Forget" clears it).
- **Metrics:** `miss.saved` goes with the keyboard health counts the
  app already sends (`KeyboardHealthRecorder`), in Phases A and B.
- **Last step:** fold this into `PRODUCT.md` and `DESIGN.md`.

### Notes as it ships

- **Phase A** (3 Nov 2026): `Composer.Bar.correcting`, `beginCorrection`,
  `cancelCorrection`, `saveCorrection`; `SettledWord.missed`; `SharedWord.missKind`;
  misses kept by the extension in `KeyboardFiles.misses` (App Group with Full Access);
  `GuessTally.missed` sends `miss.saved` with the keyboard health counts.
  `MissedWordTests`.
- **Phase B** (3 Nov 2026): `PersonalModel.Shape` (16 points, fractions of the keys'
  width and height) in each shard's `shapes`, three per word, 300 words;
  `SettledWord.shape`, made by the composer for a one-stroke miss on unsplit keys;
  `PersonalIndex.shapes`; `Matcher.remembered` puts a word first when a lone swipe
  starts and ends within `shapeEnds` (0.7 key) of a remembered one and its DTW
  distance is under `shapeRadius` (0.5 key), ahead of the best guess by up to
  `shapeLift` (0.3). On made-up sloppy swipes of "second" that came out "song", one
  saved miss took the next 40 from 23 right to 37; "song", "sold", "send" and the like
  stayed as they were. `miss.shape_hit` was dropped: the bar can't tell which guesses
  a shape decided without more bookkeeping than it's worth.
- **Phase C** (3 Nov 2026): `MissedWordsView` from Settings → Your words → Words it
  missed (`HomeView.Route.missedWords`): the swipe drawn on the keys
  (`SharedPathsView`, shared with "What gets shared"), each miss with what it wrote and
  "Shared", "Waiting to share" or "On this phone" (`SharedWordStore.uploadedIDs`);
  swipe to delete (also takes it off the sharing list). "Forget what it learned"
  clears the list with the shapes. Folded into `PRODUCT.md` 5.3 and `DESIGN.md` "The
  bar".
- **Fix** (3 Nov 2026): a miss settled only when the next word started, so saving
  "second" and closing the keyboard could lose it (Gabriel's first real miss never
  arrived). `Composer.keyboardWillHide()` settles the last word when the keyboard goes
  away (`KeyboardModel.keyboardWillHide`, from `viewWillDisappear`).
