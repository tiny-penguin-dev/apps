# Astrotype: Fix a word from what comes next

When you type fast and the next word makes it clear the word before was wrong, the
keyboard swaps it for the right one ("thai" becomes "this" once "is" follows).

## Product

Status: Draft

- **The problem** (Gabriel, 11 Nov 2026): "When typing a word, our model looks
  backwards to see which word is the highest probability… But sometimes it is still
  ambiguous… but the next word will actually give it a good hint. This can also happen
  when it's the first word in the sentence." He typed "thai" when he meant "this".
  Today a word is decided once, when it goes in, from its swipe or taps and the words
  before it (`Matcher.contextScore`, the next-word model since PR #165). The first word
  of a message has no words before it, so only the swipe and how common each word is
  decide. The word after it is never used, so a clear hint like "is" or "the" comes too
  late, and the person has to notice and fix it by hand (features/fix-earlier-word).
- **Who wants it:** everyone who swipes or types fast with two thumbs. Gboard and
  SwiftKey do this already.
- **Basics or powerful:** basics. On by default and free, with a switch on the Typing
  page for people who don't want the keyboard touching words they already wrote.
- **How it works:**
  - **When it looks back:** when a word goes in (space, autospace or punctuation), the
    keyboard checks the word before it, only if:
    - you were **typing fast**, which is the most important rule (Gabriel, 11 Nov
      2026: "it should only happen when typing fast… for small corrections"). Two hard
      limits, both must hold:
      - **Started fast:** the new word began within **1 second** of the earlier word
        going in. If you paused, you likely saw the word and kept it, so it stays.
      - **Fixed fast:** the earlier word can only change in the first **2 seconds**
        after it went in. Once the new word ends later than that (a long or slow word),
        the earlier one is final. A word on screen longer than that never changes.
      Both numbers are checked against Gabriel's recordings in phase 1 and can only get
      stricter, not looser.
    - the word before was the **keyboard's own guess** from a swipe or taps, and had
      other close readings. Never a word you picked from the bar, fixed, typed with
      "Not it?", a text shortcut, a word typed with "Type taps exactly" on, or a word
      you told it to keep (Undo, below).
    - both words are in the **same sentence** (a comma is fine, a full stop isn't), and
      nothing was changed or moved in between.
  - **What it checks:** for each other reading of the earlier word, how well the new
    word follows it. It adds that to how well the reading matched your swipe and the
    words before it. Example: "thai is" vs "this is". If another reading wins by a clear
    margin, it swaps.
  - **The swap:** the earlier word changes in place and the cursor stays where you are,
    so you keep typing. Its casing stays ("Thai" becomes "This"). The bar says
    "Changed “thai” to “this”" with **Undo** for a few seconds, the same note as fixing
    an earlier word yourself.
  - **Undo** puts the old word back and the keyboard won't swap that word again. You
    can also tap into the word later and pick from its readings, as today.
  - **Small fixes only, never a sentence:** it looks back exactly **one word**, using
    the one word after it. At most **one word changes** per check, a word it already
    changed is never changed again, and the word right after a changed word is never
    changed (no chain of changes). It only swaps between the readings your swipe or
    taps already had, so it's never a different-looking word. Your own habits
    (Learns from you) count, so a phrase you write a lot isn't "fixed" away.
- **What it changes:** what happens when a word goes in (one more check), the
  guesses bar (the change note), when a word "settles" and is learned (it waits for this
  check, so the keyboard learns the right word), and the typing recorder (a new event,
  so a replay shows it). A new switch on the Typing page.
- **How we know it's good:** before building, we measure it on the held-out test
  sentences with made-up swipes (the same way PR #165 was measured) and on Gabriel's
  typing recordings. It ships only if it fixes at least 3 wrong words for each right
  word it breaks, and breaks fewer than 1 word in 500. That sets how big the "clear
  margin" is.
- **Speed:** at most 3 extra model reads per word (one per other reading), only when
  the earlier word had close readings. Target: under 10 ms on the oldest phone.
- **Scope:**
  - *This version:* everything above, English and Spanish, swipes and taps.
  - *Later:* looking two words ahead or two words back; fixing the earlier word when
    you end the sentence right after it.
  - *Never:* changing a word you chose or fixed yourself; changing words after you
    paused on them or after 2 seconds; rewriting more than one word.
- **What we measure** (`docs/telemetry.md`, counts only, never the words):
  - `lookback.changed`: the keyboard swapped an earlier word.
  - `lookback.undone`: Undo after one of those swaps.
  Undone vs changed tells us if it's too eager. `earlier.fixed` (people still fixing
  earlier words by hand) tells us what it misses.
- **Open questions** for Gabriel:
  1. ~~Swap the word and show Undo, or only offer it on the bar?~~ Decided 12 Nov
     2026 (Gabriel): **swap it and show Undo**.
  2. A switch on the Typing page, on by default ("Fix words as you go")? Recommended.

## Design

Status: Draft

- **Mockups:** none new. It reuses the change note from features/fix-earlier-word:
  `features/fix-earlier-word/design/screens/swapped.png` ("Changed “cage” to “cafe”",
  Undo). Here it reads "Changed “thai” to “this”".
- **What changes:**
  - The guesses bar: after a swap, the change note with Undo shows for 3 seconds, then
    the bar goes back to what it would show (the next words, or the FIX readings for the
    word just typed).
  - Typing settings: a new switch, **Fix words as you go**, with the footer "When the
    next word shows the one before was wrong, Astrotype changes it. Only while you're
    typing fast." Under the other autocorrect switches (Real words, Split words).
- **Motion and haptics:** the note rises in like today's; no extra haptic (the word you
  just typed already gave one), so it doesn't buzz twice.
- **Design system:** BarView's UndoNote (`say(_:undo:)`) and the settings row. Nothing
  new.
- **Sizes:** unchanged at every size (the note already fits the small phone and the
  Duo's wide screen).
- **Accessibility:** VoiceOver announces "Changed thai to this" with an Undo action.
- **Open questions:** none beyond the Product ones.

## Build

Status: Draft

- **Approach:** all in the core (`Composer`); the keyboard model only shows the note
  and plays the text edits it already knows.
- **Core pieces:**
  - `Composer.Committed` keeps each reading's score, not only its word (`readings:
    [Candidate]`), plus when it went in and whether it may be looked back at.
  - `LookBack` (new, AstrotypeCore): given the earlier word's readings with their scores,
    the words before it and the new word, returns the reading to swap to or nil. It asks
    the next-word model `scores(before: "<words before> <reading> ")` for each reading
    and adds `weight * bonus(new word)`, the same bonus `Matcher.contextScore` uses.
    Without the model (not loaded, or the word unknown to it) it uses the word pairs.
    Pure and testable: `LookBack.choose(readings:, before:, next:, models:, margin:)`.
  - `Composer.commit`: after the new word goes in, if the earlier word qualifies, runs
    `LookBack`; a swap edits the text with the effects fix-earlier-word added
    (`moveCursor`, delete, insert, back) and updates `recentWords`.
  - Settling waits for the check: the earlier word settles (and is learned) only after
    it, so a swapped word teaches the right word, never the wrong one. A swap the
    person didn't undo counts as the keyboard's own guess, not as a fix by the person.
  - `undoLookBack()` puts it back and marks the word as kept. The typing log records
    `lookBack` and `lookBackUndo`, and `TypingReplay` plays them.
  - `KeyboardSettings.fixesAsYouGo` (default on) and its row on the Typing page.
- **Phases:**
  1. **Measure** (no app change): a test that replays the held-out test sentences with
     made-up swipes and two-thumb taps through `Composer`, and Gabriel's recordings,
     counting words fixed and broken at several margins and "fast" gaps. Done when:
     numbers in the PR and a margin picked that meets the ship rule above, or a note
     that it doesn't and why.
  2. **Build it:** everything in Core pieces, the note, the switch, the metrics. Done
     when: on TestFlight, swiping "thai is" fast types "this is" with the note; pausing
     after "thai" keeps it; Undo puts it back.
- **Risks:** swapping a word the person meant (held down by the margin, "typing fast"
  and Undo); a few ms more per word (only words with close readings are checked); the
  text edit going wrong in apps that change text under the keyboard (skip when the
  text before the cursor isn't exactly what we wrote).
- **Metrics:** `lookback.changed`, `lookback.undone`: counted in `GuessTally` by the
  keyboard (it never sends metrics itself) and sent by the app with `Telemetry`, like
  `earlier.*`.
- **Last step:** fold this feature into `PRODUCT.md` and `DESIGN.md`.
