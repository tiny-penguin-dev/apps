# Astrotype: See and edit your words

Settings → Your words lets you see the word pairs the keyboard learned, add a learned
word by hand, and delete several words or pairs at once.

## Product

Status: Approved 2026-11-06 (Gabriel: "Ok build", in the project thread)

- **The problem:** "Learns from you" says it learned 2,500 word pairs, but there's no
  way to see them (Gabriel, 6 Nov 2026: "It doesn't let me see them though"). A wrong
  pair (from a typo or a one-off message) can only go with "Forget what it learned",
  which drops everything. Learned words can be seen, but only removed one swipe at a
  time, and a word can only be added by pecking it out in another app.
- **Who wants it:** people who care how the keyboard guesses, and anyone who wants to
  check what it keeps. Most people never open it.
- **Basics or powerful:** powerful, one level down in Settings → Your words. Nothing
  changes on the main path or in the keyboard.
- **How it works:**
  - **Your words** gets a new row, **Word pairs**, with the count, between Learned words
    and Learns from you. "Learns from you" keeps its switch; its line now only says how
    the thumbs are going ("Thumbs mapped").
  - **Word pairs:** one line on what they are, a search field ("Find a word", matches
    either word), and **Most used / Newest**. Each row is the pair ("see *you*") with a
    small four-bar meter for how often you write it (no raw numbers: the counts fade,
    so "42" would mean nothing). Pairs that only say a word starts a sentence aren't
    listed, as they aren't counted today.
  - **Learned words:** as today, plus a **+** in the top bar. It opens a small sheet,
    "Add a word": type one word (letters only), tap Add. The keyboard offers it from
    then on, on every device, like a word you pecked out and kept. Words added this way
    show an **Added** chip; kept ones keep **Kept**.
  - **Deleting:** both lists keep swipe left to drop one. **Select** in the top bar
    puts a circle on each row; tap rows, then **Delete N** at the bottom. Done leaves.
    No confirmation, as with one swipe today.
  - A deleted pair is forgotten on every device. It comes back only if you keep
    writing it, as it would after "Forget what it learned". A deleted learned word is
    not offered again (as today), unless you add it back.
- **What it changes:** Settings → Your words (one new row, one changed line), the
  Learned words screen (+, Select), the personal model (remembers deleted pairs so a
  sync doesn't bring them back).
- **Scope:**
  - *This version:* the pairs list with search, sort and delete; add a word; select
    several and delete, in both lists.
  - *Later:* the single words it uses more than most people (the other half of "Learns
    from you", up to 2,000) as a third list; editing a pair; adding a pair by hand.
  - *Never:* sharing pairs. They stay on your devices and iCloud.
- **What we measure** (`docs/telemetry.md`, counts only, never the words):
  - `words.added`: a word added by hand.
  - `words.deleted` with `how` = swipe or select, and `count`.
  - `pairs.opened`: the pairs list opened (does anyone look?).
  - `pairs.deleted` with `how` and `count`.
- **Open questions** for Gabriel: none. You chose "see and remove" on 6 Nov 2026 and
  asked for add and select-to-delete the same day.

## Design

Status: Approved 2026-11-06 (Gabriel: "Ok build", in the project thread)

- **Mockups:** `design/mockups/learned-words.html` (Artifact: https://claude.ai/artifact/BqBdEvExHvZfCinMhAhTQx), built on the Settings mockup.
  Screens: Your words, Learned words, Learned words: add one, Word pairs, Word pairs:
  selecting. Small, Phone and Wide sizes, light and dark.
- **What changes:** Your words (`design/screens/words.png`): new Word pairs row with
  the count; Learned words gets a subtitle; the Learns from you line is shorter.
  Learned words (`learned.png`): Select and + in the top bar, Added chip.
- **New screens:** Word pairs (`pairs.png`, `pairs-select.png`) and the Add a word
  sheet (`learned-add.png`).
- **Copy:**
  - Word pairs intro: "Words you write one after another. It uses them to guess your
    next word and to pick between close swipes. They fade if you stop writing them."
  - Footers: "Swipe a pair left to drop it, or tap Select to drop several. A pair comes
    back if you keep writing it." / "Swipe a word left to drop it, or tap Select to
    drop several. Tap + to add one."
  - Add sheet: "Add a word", placeholder "A word the keyboard should know", note "The
    keyboard offers it from now on, on all your devices." Errors: "One word, letters
    only." / "It already knows that one."
  - Empty: "No word pairs yet. It learns them as you type in other apps." / "No pairs
    with “…”."
- **Motion:** the sheet slides up; rows leave with the list's own delete animation.
  Light haptic on Delete.
- **Design system:** existing Row, Chip, Segmented and SettingsGroup. New: SearchField
  (the rounded card field, also used by the add sheet), SelectCircle and the
  bottom ActionBar ("N selected · Delete N"), and the four-bar UseMeter. In SwiftUI
  these are `List` selection and `.searchable`-style field styled with `Theme`.
- **Sizes:** on the small phone the list scrolls under the search and sort; on the
  wide screen the page sits beside Settings like the others and the add sheet is a
  centred card (`learned-wide.png`, `pairs-small.png`).
- **Accessibility:** the meter reads "Often", "Sometimes"… to VoiceOver; each pair
  reads as "see, then you". Select mode uses the system's selection traits, so
  VoiceOver says "selected". Works at the largest text size (rows grow, meter stays).
- **Open questions** for Gabriel: none.

## Build

Status: Built 2026-11-06 (one PR, with this plan)

- **Approach:** the app already reads the personal model (`AppModel.personal`) and
  writes it to the App Group and iCloud for "Forget what it learned". The lists read
  from it; edits go through `AppModel`, are saved, then synced, and the keyboard picks
  them up when it merges the shared copy, as it does today.
- **Core pieces:**
  - `PersonalModel.learnedPairs(at:)` → `[LearnedPair]` (`previous`, `word`, `count`,
    `lastDay`), all shards summed, sentence starts left out.
  - `PersonalModel.forgetPairs(_:at:)`: a deleted pair is kept as a tombstone
    (`forgottenPairs: [String: Int]`, pair → day), merged like `forgottenAt` (the
    later day wins, capped at 4,000 entries). `MirroredPersonalStore.save` merges the
    App Group copy first, so a keyboard that loaded earlier doesn't write over a delete. `PersonalIndex` and `pairs(at:)` skip
    counts not written after it, and `learn` starts a forgotten pair over from zero,
    so writing it again brings it back. Older keyboards ignore the field.
  - `LearnedWords.add(_:at:)`: learned and kept, marked `added` so the list shows the
    chip; deleting several is `forget` on each.
- **Phases:** one PR. Done when, on a phone: Word pairs lists your pairs and matches
  the Learns from you count; search and sort work; deleting three pairs removes them
  here and, after a sync, on a second device; + adds a word that the keyboard then
  offers; Select deletes several learned words.
- **Risks:** 4,000 pairs per device in a `List` is fine; summing and sorting them
  runs once when the screen opens (well under 50 ms). The tombstones add up to
  ~100 KB to the iCloud record in the worst case, under its 1 MB.
- **Metrics:** the four under Product, through `LiveMetrics`.
- **Last step:** fold this into `PRODUCT.md` and `DESIGN.md`.
