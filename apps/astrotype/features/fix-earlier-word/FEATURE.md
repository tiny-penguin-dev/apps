# Astrotype: Fix an earlier word

Tap into a word you already wrote, or select it, and the bar shows that word with its
other readings: tap one to swap it in, type the right one, or tell the keyboard never
to suggest it.

## Product

Status: Draft

- **The problem** (Gabriel, 8 Nov 2026): "Sometimes I mistype a word, but I don't
  realize until I've typed a next word." Today only the last word can be fixed
  (backspace reopens it, the FIX bar, "Not it?"). For anything earlier you backspace
  through the words after it, or fix it by hand letter by letter, and the keyboard
  learns nothing from the fix. Moving the cursor just resets the bar.
- **Why now:** the underlined open word is gone (PR #184, 8 Nov 2026). While a word
  was underlined, iOS hid taps and selections from the keyboard. Without it the
  keyboard sees where the cursor is and what's selected, so this is possible.
- **Who wants it:** everyone who swipes. It's how Gboard and SwiftKey already work.
- **Basics or powerful:** basic. Nothing to learn beyond "tap the word".
- **How it works:**
  - **Tap into a word** (anywhere in it, or right after it with no space) or **select
    just that word**. The bar switches to the *earlier word* state: the word in the
    pill with a small **Fixing** tag, its other readings either side, the pencil on the
    right. It's the FIX bar you already know, for any word.
  - **The readings** are the ones from your swipe when the word is one of the last 20
    you wrote in this field. Otherwise (an older word, or text you didn't type with
    Astrotype) they're the nearest words to its letters, ranked by the words around it.
    No readings at all: the bar shows the word and the pencil only.
  - **Tap a reading:** it replaces the word in place and the cursor goes back to where
    it was before you tapped in (usually the end of what you were writing), so you just
    keep typing. The bar says "Changed “cage” to “cafe”" with **Undo** for 4 seconds.
    The keyboard learns from it the same way as fixing the last word does today: the
    right word gets the credit for that swipe and those neighbours.
  - **The pencil (Not it?)** opens the same "What did you mean?" field as today, for
    this word. Save replaces it, and remembers the swipe shape for the right word when
    it still has it.
  - **Hold the word or a reading:** the word menu from features/word-control (Never
    suggest / Suggest more). Never suggest doesn't change the text by itself.
  - **Anything else goes back to normal:** a key types at the cursor as today, a swipe
    starts a new word there, and moving the cursor out of the word puts the bar back.
    More than one word selected: the bar stays as it is, and a key types over the
    selection (as today).
- **What it changes:** the guesses bar (a new state, reusing the FIX layout), what
  happens when the cursor moves (today it only resets), and the typing recorder (new
  events, so a replay shows it).
- **Scope:**
  - *This version:* everything above, in other apps and the app's own fields.
  - *Later:* fixing a word in the middle of a word you're typing; showing readings
    for words typed before the keyboard last opened (we don't keep swipes once it
    closes).
  - *Never:* drawing on the host app's text (a keyboard can't highlight words in
    another app's field).
- **What we measure** (`docs/telemetry.md`, counts only, never the words):
  - `earlier.shown` with `how` = cursor / select: the bar showed an earlier word.
  - `earlier.fixed` with `how` = reading / typed: one was replaced.
  - `earlier.undone`: Undo after a swap.
  Shown vs fixed tells us whether it pops up when people don't want it.
- **Open questions** for Gabriel:
  1. After a swap, the cursor jumps back to where you were (my pick), or stays right
     after the fixed word like Gboard?
  2. Should it also show up when the cursor lands *right after* a word with no space,
     or only inside the word? (I'd say yes: that's where you land after tapping the
     end of a word.)

## Design

Status: Draft

- **Mockups:** `design/mockups/fix-earlier-word.html` (Artifact:
  https://claude.ai/artifact/EffF4jcg2YrfSP6Esn24Xw). Screens: the mistake noticed
  late, tap into the word, after a swap, the word menu, after Never suggest, Not it?
  for the word, selecting the word, typing a key instead. Small, Phone and Wide, light
  and dark.
- **Keyboard:**
  - Before (`design/screens/typed.png`): next words after "tomorrow".
  - Tap into "cage" (`tap.png`, `tap-dark.png`, small: `tap-small.png`, wide:
    `tap-wide.png`): the FIX layout, the word in the pill with a **Fixing** tag on top,
    readings either side, the pencil on the right.
  - Swapped (`swapped.png`): the UndoNote from word-control, "Changed “cage” to
    “cafe”", cursor back after "tomorrow".
  - Hold (`menu.png`) → Never suggest (`blocked.png`): the WordMenu and UndoNote as
    they are.
  - Not it? (`typeit.png`): the missed-words field as it is.
  - Select (`select.png`): iOS draws the selection; the bar is the same as tapping in.
- **Copy:** tag "Fixing"; note "Changed “cage” to “cafe”", button "Undo". Everything
  else is existing copy.
- **Motion and haptics:** the bar's new words rise in like the FIX row (0.2 s); a commit
  haptic and the bar's squeeze on a swap. Reduce Motion: a plain swap.
- **Design system:** reuses BarView's FIX state, the pill, WordMenu, UndoNote and the
  Not it? field. New: **EarlierTag** (the small uppercase pill over the bar's pill, the
  theme's accent, 10 pt heavy).
- **Sizes:** the bar is the same at every size; on the small phone the outer readings
  drop before the pill shrinks, as the FIX bar does today. Wide: unchanged.
- **Accessibility:** VoiceOver reads the bar as "Fixing cage. Readings: cafe, case".
  The Never suggest / Suggest more custom actions work on each reading.
- **Open questions** for Gabriel: is the **Fixing** tag useful, or is the pill on a
  word you're not typing clear enough without it?

## Build

Status: Not started (written once Product and Design are approved)

Notes for later, from reading the code (8 Nov 2026):

- `KeyboardModel.contextChanged` runs on every `selectionDidChange` and
  `textDidChange`; the keyboard's own edits don't call them in other apps (and the app's
  field now skips them while it swaps a word, #184). So a call with no open word and the
  cursor touching a word is the person moving the cursor.
- The word around the cursor comes from `documentContextBeforeInput` +
  `documentContextAfterInput` (or `selectedText`). To swap it: `adjustTextPosition` to
  the word's end, delete it, insert the reading, then move back by what was after it.
- `Composer.Committed` keeps only the last word today; keep the last 20 (word, pieces,
  guesses, previous word) per field, matched by the word and the words before it.
  Otherwise `Matcher.nearestWords(to:points:limit:)` with the context gives readings.
- Swapping reuses the fix path (`chooseFix` / `saveCorrection`) on that record, so
  learning and remembered swipes work as for the last word.
