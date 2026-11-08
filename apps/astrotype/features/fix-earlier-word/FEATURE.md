# Astrotype: Fix an earlier word

Tap into a word you already wrote, or select it, and the bar shows that word with its
other readings: tap one to swap it in, type the right one, or tell the keyboard never
to suggest it.

## Product

Status: Approved 2026-11-08 (Gabriel: "Build it", in the project thread)

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
- **Decided** (8 Nov 2026, built with the recommended picks): after a swap the cursor
  goes back to where you were typing; it also shows when the cursor is right after a
  word; the pill keeps the "Fixing" tag.

## Design

Status: Approved 2026-11-08 (Gabriel: "Build it", in the project thread)

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
- **Open questions:** none (the Fixing tag stays).

## Build

Status: Approved 2026-11-08 (Gabriel: "Build it", in the project thread)

- **Approach:** the core finds the word at the cursor and owns the swap; the keyboard
  model decides when the person (not the keyboard) moved the cursor; the bar draws the
  new state with the existing FIX layout.
- **Core pieces:**
  - `EarlierSpot.find(before:after:selected:typedAfter:)` (new, AstrotypeCore): the
    word the cursor is in or right after (or the one selected word), how many letters
    are before the cursor, and how far past it typing was (`rest`), from the text
    around the cursor and what was after it when the keyboard last typed.
  - `Composer`: keeps the last 20 words that went in (`recentWords`, memory only,
    dropped when the keyboard hides). `cursorLanded(at:)` shows `Bar.earlier(words,
    chosen:)` (the swipe's readings, or `Matcher.nearestWords` cased like the word,
    blocked words left out); `choose(guess:)` and `saveCorrection` swap it with the new
    `Effect.moveCursor` (to the word's end, delete, insert, back to `rest`) and settle
    it as a fix when its swipe is known; `undoEarlierFix()` puts it back. Any key,
    touch, emoji, cursor slide or reset closes it.
  - `KeyboardModel.contextChanged` calls `lookAtCursor()`: only with no open word, in a
    field that learns, not in practice fields, and not within 0.3 s of the keyboard's
    own edit. `TextTarget` gains `textAfterCursor` and `selectedText`.
  - `BarView`: the `.earlier` state (FIX layout plus the "Fixing" tag) and
    `say(_:undo:)` for the swap's undo note. The typing log records `earlier` and
    `earlierUndo`, and `TypingReplay` plays them.
- **Phases:** one PR (this one). Done when, on a phone in Messages: swipe "cafe" so it
  writes "cage", type "tomorrow", tap into "cage": the bar shows it tagged Fixing with
  "cafe" beside it; tapping "cafe" fixes it and the cursor is back after "tomorrow";
  Undo puts "cage" back. Tests: `EarlierWordTests`.
- **Risks:** some apps report only part of the text after the cursor, so the cursor
  may come back short of where typing was. The app's own fields don't report cursor
  moves to the keyboard model, so it only works in other apps for now.
- **Metrics:** `earlier.shown`, `earlier.fixed`, `earlier.undone` through
  `onWordAction` (the keyboard's tally), added to PRODUCT.md.
- **Last step:** folded into DESIGN.md (the bar's "Earlier word" state) and PRODUCT.md
  (metrics) in this PR.
