# Astrotype: Missed words

A "Not it?" button in the bar for when a swipe writes the wrong word and the right one
isn't offered: type the word you meant, and the keyboard fixes the text, learns from
that swipe, and keeps it so we can see what went wrong.

## Product

Status: Draft (Gabriel answered the open questions, 3 Nov 2026)

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
       like it gets that word first (on this phone, and your other devices with sync);
     - the word gets the same boost as picking it in the bar.
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
  - *This version:* the button, the field, fixing the text, learning (word, shape,
    boost), the list, uploading with corrections.
  - *Later:* "Not it?" for pecked words; exporting misses as a file; editing a miss in the app; a debug view that
    shows the matcher's top ten with scores for a miss (handy for us, not for people).
  - *Never:* anything typed around the word leaves the phone; misses sent without
    "Include corrections" on.
- **Free or Pro:** free. A keyboard that can't be taught sells nothing.
- **What we measure** (anonymous, with "Share anonymous usage data", sent by the app
  like `guess.words`, never from the extension):
  - `miss.saved` (count, by `known`: whether the word was in the dictionary): how often
    swipes fail badly enough to need it. Falling over time means the matcher improves.
  - `miss.shape_hit` (count): later swipes that a remembered shape got right. Shows
    whether learning from misses works.
  - Nothing about which words.
- **Decided** (Gabriel, 3 Nov 2026)
  1. **Not it?** shows only after a swiped word.
  2. Save fixes the word in the text and teaches the keyboard.
  3. Misses upload to iCloud with the sharing switches, from anyone who turns them on,
     rather than a file to share.

## Design

Status: Not started

## Build

Status: Not started

Notes for later, so the plan fits the code:

- Core (`AstrotypeCore`, tested): `MissedWord` (or a `SharedWord` with a new kind,
  `word.miss`, so `CloudKitPracticeUploader`, `download_samples.py` and replay already read it) and a `MissStore` with a cap;
  `ShapeMemory` (remembered swipes per word, scored by DTW against a new swipe, synced
  with the personal model's shards); `Matcher` takes its guesses beside the dictionary.
- The composer gets a field mode: taps go to a buffer, not the text target; Save emits
  "replace the last word with X" and a `.miss` effect for `KeyboardModel` to store.
- Phases: A, the button, field, text fix and miss store (with a test that a saved miss
  replays); B, shape memory in the matcher; C, the Settings list and the upload.
