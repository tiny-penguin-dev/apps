# Astrotype: Teach and block words

Hold a word on the guesses bar to say "never suggest this" or "suggest this more". See
and edit both lists in Settings → Your words. And learn new words more carefully, so
one-off typos stop piling up as "words".

## Product

Status: Approved 2026-11-07 (Gabriel: "Build it", in the project thread)

- **The problem** (Gabriel, 7 Nov 2026):
  - Keeping to known words ("Real words" near "Words only") works well, so the words
    the keyboard knows matter more. There should be an easy way to teach it a word and
    to drop one you'll never write.
  - "It accumulates a lot of words that make no sense." Today one tap-out is enough:
    any word of 2+ letters you peck out that the dictionary doesn't know is learned
    when it goes in, and from then on it competes with real words (and counts as a
    real word under "Words only").
  - Holding a guess and sliding up or down already boosts or hides it, but nothing
    says so, and hidden words aren't listed anywhere, so they can't be brought back.
- **Who wants it:** anyone who sees the same wrong guess twice. The hold menu is on the
  main path but only for people who look for it; the lists are one level down in
  Settings, like the other word lists.
- **Basics or powerful:** the hold menu is basic (the first thing you'd try when a
  guess annoys you). The lists are powerful.
- **How it works:**
  - **Hold a word on the bar** (a guess, a next word, or a fix reading) for a third of
    a second. The bar turns into the **word menu**: the word in the middle,
    **Never suggest** on its left and **Suggest more** on its right.
    (Gabriel, 7 Nov 2026). For a word it doesn't know yet (the letters you just pecked out),
    the second button reads **Learn it**.
    - *Never suggest:* the word is never offered again as a guess, a fix or a next
      word, on any of your devices. The bar says "Won't suggest “end”" with **Undo**
      for 4 seconds, then goes back. Typing it letter by letter still types it, and
      that doesn't unblock it.
    - *Suggest more / Learn it:* the word is learned now and ranked
      higher, as a boost from the slide does today. The bar says "Will suggest
      “Ximena” more" with Undo.
    - Tapping the word, a key, or 4 seconds with no touch closes the menu with nothing
      changed.
    - Sliding up or down on the held word still works, as a shortcut.
  - **Learning keeps what you meant, not what you fixed.** A word you peck out that
    the dictionary doesn't know is still learned the first time (Gabriel, 7 Nov 2026:
    "it should always learn if I type it"). What changes is *when*: it's learned once
    you move on to the next word with it still there, not the moment it goes in. So:
    - Type "helo", backspace into it and fix it to "hello": nothing is learned. Today
      "helo" stays learned, because only deleting the whole word takes it back.
    - Letters that read as two words with a missed space ("textseparately") are never
      learned by themselves; they wait in the bar for Learn it.
    - Fixing it with "Not it?", or Learn it on the bar, learns it at once.
  - **The letters you tapped are always on the bar.** Even with Real words at "Words
    only", the exact letters you pecked out stay as the last guess (never picked for
    you), so holding them and tapping Learn it is always one step away. Today "Words
    only" drops them.
  - **Settings → Your words** gets a **Never suggest** row with the count, under
    Learned words. The footer under Learns from you says how to teach or block a word.
  - **Learned words** as today, plus the **More** chip on boosted words and a **Used
    once** filter beside search. Deleting a word blocks it, as today.
  - **Never suggest** (new list): every blocked word, newest first, with the day it was
    blocked, and search. Swipe left to **Allow** it again; Select to allow several; +
    opens the same add sheet to block any word, even a dictionary one.
- **What happens to the words learned so far:** they stay. Learned words gets a
  **Used once** filter so the junk from before is easy to find and drop with Select.
  Words hidden with the slide before now show up in Never suggest.
- **What it changes:** the guesses bar (word menu, undo note), how a new word is
  learned, Settings → Your words (one row, two lines), Learned words (a section, a
  chip), a new Never suggest screen. The next-word model's guesses already skip hidden
  words, so nothing changes there.
- **Scope:**
  - *This version:* everything above.
  - *Later:* a "Suggest less" step between normal and never; blocking a word pair
    ("see" then "end") rather than a word; noticing a fix made by moving the cursor
    back into a word (the keyboard can't see that reliably today).
  - *Never:* a shared or downloaded block list. Your lists stay on your devices and
    iCloud.
- **What we measure** (`docs/telemetry.md`, counts only, never the words):
  - `word.menu`: the hold menu opened.
  - `word.blocked` with `how` = menu / slide / settings.
  - `word.boosted` with `how` = menu / slide (Learn it counts here too).
  - `word.allowed` with `how` = swipe / select / undo.
- **Open questions** for Gabriel: none. You said on 7 Nov 2026 that a word you type
  should always be learned, and that the junk comes from typing and then fixing.

## Design

Status: Approved 2026-11-07 (Gabriel: "Build it", in the project thread)

- **Mockups:** `design/mockups/word-control.html` (Artifact: https://claude.ai/artifact/P8xuLiKGC4tuKJrfxkUTRT). Screens:
  guesses as today, the hold menu, after Never suggest, Learn it on a new word,
  Your words, Learned words, Never suggest, and its add sheet. Small, Phone and Wide,
  light and dark.
- **Keyboard:**
  - Today (`design/screens/bar.png`) → hold (`menu.png`, `menu-dark.png`) → blocked
    (`blocked.png`). Learn it on letters it doesn't know: `learning.png`.
  - The menu takes the bar's whole width, side slots included (no ✕: the word itself
    cancels): the word in its pill in the centre, Never suggest left of it, Suggest more (or Learn it)
    right of it, each action sized to its label so the word stays dead centre.
  - When the word plus both full labels don't fit (long words, the small phone:
    `menu-small.png`), the labels shorten to **Never** / **More** / **Learn**, keeping
    their icons. The word truncates last, with an ellipsis in the middle at most.
- **Settings:** Your words (`words.png`), Learned words (`learned.png`,
  `learned-dark.png`, wide: `learned-wide.png`), Never suggest (`never.png`), add sheet
  (`never-add.png`).
- **Copy:**
  - Menu: "Never suggest", "Suggest more", "Learn it" (short: "Never", "More",
    "Learn"). Undo notes: "Won't suggest “end”", "Will suggest “Ximena” more",
    "Learned “Ximena”", button "Undo".
  - Your words footer: "It learns a new word when you tap it out and leave it in. Hold
    a guess on the keyboard to teach or block a word right away."
  - Learned words: filter "All / Used once"; chip "More".
  - Never suggest: intro "The keyboard won't offer these, on any of your devices. You
    can still type them letter by letter." Footer "Swipe a word left to allow it again,
    or tap Select to allow several. Tap + to add one." Swipe action "Allow"; select bar
    "Allow N". Add sheet title "Never suggest", note "It stops offering this word, on
    all your devices." Empty: "Nothing blocked. Hold a guess on the keyboard and tap
    Never suggest."
- **Motion:** the menu rises into the bar like the fix row (0.2 s); the held word
  scales up first, as today. Light haptic when the menu opens, a commit haptic on an
  action. Reduce Motion: no rise, just a swap.
- **Design system:** existing BarView zones, pills, Row, Chip, SettingsGroup,
  SearchField, SelectCircle, ActionBar. New: **WordAction** (a pill button with an
  icon, coral for never, mint for more/learn, same colors the slide uses today),
  **UndoNote** (a muted line and an Undo pill, in the bar), and the **More** chip (sun
  tint).
- **Sizes:** small phone uses short labels; Wide puts the lists beside Settings like
  the other pages, and the menu keeps full labels.
- **Accessibility:** VoiceOver users can't hold-and-slide reliably, so each guess gets
  two custom actions, "Never suggest" and "Suggest more", which do the same thing
  without the menu. The undo note is announced. Works at the
  largest text size (rows grow; the bar keeps its fixed size, like today).
- **Open questions** for Gabriel: none.

## Build

Status: Approved 2026-11-07 (Gabriel: "Build it", in the project thread)

- **Approach:** everything already lives in `LearnedWords` (weight, uses, added,
  changed, merged per word across devices by the later change). A blocked word is
  the existing weight -10 entry, so blocks already sync, and the next-word path
  already drops them (`NextWords.guesses`). The work is: learn on settle instead of on
  commit, keep the tapped letters on the bar, a hard filter for blocked words, the
  bar menu, and one new screen.
- **Where the junk comes from today** (read in `Composer`): `wordToLearn` learns a
  pecked word on commit. Backspace reopens it and remembers it (`reopenedLearned`),
  but only deleting every letter takes the use back (`unlearnReopened`); deleting one
  letter and retyping commits the fixed word and drops `reopenedLearned` without
  unlearning. Fast taps with a missed space also commit and learn the glued letters
  when the split isn't sure.
- **Core pieces:**
  - `Composer`: `Committed.learned` is learned when the word *settles* (`settle()`,
    the next word starting, the field ending, or the cursor moving away) rather than
    in the commit's effects. A reopened word that changes is never learned. Letters
    with a confident-enough split (`Matcher.split`) aren't auto-learned.
  - `Matcher.resolve`: at strictness 1 the literal stays as the last candidate
    (today it's dropped), never first.
  - `Matcher`: a blocked word is never a candidate, unless its letters were tapped out
    exactly (today a -10 score can still win when it's the only reading).
  - `LearnedWords`: `block(_:)` (today's `forget`, kept as an alias), `allow(_:)`
    (drops the entry), `teach(_:)` (learned now and boosted), `blocked` (the list with
    the day), `usedOnce`.
  - The menu and the undo note are `BarView` view state, like the fix row. Its
    actions call `KeyboardModel.boost` / `forget` (now `teach` / `block`, with a `how`)
    and `undoWordChange` (`LearnedWords.restore`, dated now so it wins a sync); the
    typing log gets a `wordUndo` event and `TypingReplay` mirrors it.
  - App: `AppModel.allow`, `block`, `teach`; `NeverSuggestView`; `LearnedWordsView`
    gets the More chip and the Used once filter.
- **Phases:**
  1. *Learn on settle + letters always on the bar + Never suggest list.* Done when, on
     a phone: typing "helo", fixing it to "hello" and going on leaves no "helo" in
     Learned words; a new name tapped out and left in is learned; at "Words only" the
     tapped letters still show last; words hidden with the slide are in Never suggest
     and Allow brings them back. Tests in `AstrotypeKitTests` for each.
  2. *Word menu on the bar:* the menu, undo note, VoiceOver actions. Done when, on a
     phone: holding a next word and tapping Never suggest makes it disappear from the
     bar on both devices after a sync, and Undo brings it back.
- **Risks:** a fix made by moving the cursor back into a word isn't seen, so that typo
  is still learned (the Used once filter is the cleanup). Settling later means the
  learned word reaches iCloud a word later, which doesn't matter.
- **Metrics:** the four under Product, through `LiveMetrics` (app) and the keyboard's
  tally (`GuessTally`) for the bar ones.
- **Last step:** fold this into `PRODUCT.md` and `DESIGN.md` ("Learning"). Done in
  the build PR (DESIGN.md "Learning", PRODUCT.md metrics).
- **Built** 2026-11-07, both phases in one PR.
