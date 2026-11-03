# Astrotype: Emoji page

Astrotype gets its own emoji page, so an emoji is one tap away and you never leave the
keyboard (or lose the word you were swiping) to reach Apple's.

Gabriel, 3 Nov 2026, picked from the list of next features: "Our own emoji page. Today
the globe key sends you to Apple's keyboard for emoji, so you have to switch back and
forth." `PRODUCT.md` has it under Later ("Own emoji page").

## Product

Status: Approved 2026-11-03 (Gabriel in the thread: "Build it"; the open questions
go as proposed until he says otherwise)

- **The problem:** to type an emoji today you tap our globe key, land on Apple's
  keyboard, find the emoji, then tap the globe again (sometimes twice) to come back. It
  breaks the flow of typing with two thumbs, and on Face ID iPhones our globe key
  repeats the one iOS already draws under the keyboard.
- **Who wants it:** everyone who sends messages. Emoji are as everyday as punctuation.
- **Basics or powerful:** basics. One key, one page, no settings. Free, not Pro.
- **How it works:**
  - *The emoji key.* On every iPhone where iOS draws its own globe under the keyboard
    (all Face ID iPhones, and the iPhone Duo), our globe key becomes an emoji key, so
    the bottom row is Apple's: `123`, emoji, space, return. Switching keyboards stays
    one tap away on iOS's globe. On iPhones with a Home button (iPhone SE), iOS draws no
    globe, so ours stays and the emoji key sits next to it: `123`, globe, emoji, space,
    return. The app reads this from iOS (`needsInputModeSwitchKey`), so it is always
    right for the phone.
  - *The page.* Tapping the emoji key swaps the keys (and the guesses bar) for the emoji
    page, at the same height. A grid of emoji scrolls sideways: Frequently used first,
    then Apple's eight categories (Smileys & people, Animals & nature, Food & drink,
    Activity, Travel & places, Objects, Symbols, Flags). A strip along the bottom has
    `ABC` (back to the letters), one icon per category (tap to jump; the one you're in
    is highlighted) and delete.
  - *Typing an emoji.* Tap it and it goes in at the cursor. If a word was open, the
    word goes in first, as if you'd pressed space, then the emoji. No space is added
    after an emoji (you may want another one), and the keyboard stays on the emoji page
    until you tap `ABC`.
  - *Skin tones.* Hold an emoji that has them (hands, people) for the six choices. The
    one you pick is remembered for that emoji and shown in the grid from then on, like
    Apple's.
  - *Frequently used.* The last 30 you used, most used first, fading over time. It
    updates when you next open the page, so nothing moves under your thumb. Empty at
    first, it starts from a short default row (the most common emoji).
  - *Which emoji.* All of Unicode's emoji that the phone's iOS can draw, so a new emoji
    shows up only once the system can show it.
- **What it changes:** the bottom row of the letters, numbers and symbols pages (globe
  becomes emoji on Face ID phones), `DESIGN.md` "The keyboard", and `PRODUCT.md`
  ("Emoji" under platform limits, and Later).
- **Where it's kept:** frequently used and skin tones are stored with the keyboard's
  other files on the phone. They don't sync to other devices in this version.
- **Scope:**
  - *This version:* the emoji key, the page, categories, frequently used, skin tones,
    in other apps and in the app's own practice fields.
  - *Later:* searching emoji by name (built as `features/emoji-search`), emoji suggestions in the guesses bar while
    typing ("pizza" offers 🍕), syncing frequently used with iCloud, a long-press menu of
    keyboards on our globe key (Home button phones).
  - *Never:* stickers, GIFs or Memoji (third-party keyboards can't reach them), or
    anything that sends what you pick anywhere.
- **What we measure:** nothing new. The extension never sends metrics
  (`CLAUDE.md` rules), and the emoji page lives in the extension.
- **Open questions** for Gabriel
  1. Replace our globe key with the emoji key on Face ID phones (proposed), or keep
     both and make space shorter, as on Home button phones?
  2. Frequently used stays on this phone for now (proposed). Want it synced like the
     learned words from the start?
  3. Search is Later (proposed). Is it a must for you in the first version?

## Design

Status: Approved 2026-11-03 (Gabriel in the thread: "Build it"; the open questions
go as proposed until he says otherwise)

- **Mockups:** `design/mockups/emoji.html` (Artifact link:
  https://claude.ai/artifact/L3VnKo9QKPmrWoXr3AtQhP). Tap the emoji key, tap emoji into
  the message, hold 👍 for skin tones, tap a category, `ABC` to go back. It has
  "Today" for comparison, the Home button phone, the three sizes and both themes.
- **What changes:**

  | Screen | Before | After |
  |---|---|---|
  | Letters page (Face ID phone) | [today: globe](design/screens/01-before.png) | [emoji key](design/screens/02-letters.png) |
  | Letters page (Home button phone) | [today: globe](design/screens/01-before.png) | [globe and emoji](design/screens/06-home-button.png) |

  The numbers and symbols pages get the same bottom row as the letters page.
- **New screens:**
  - *Emoji page* ([phone](design/screens/03-emoji.png),
    [dark](design/screens/05-emoji-dark.png), [small](design/screens/07-emoji-small.png),
    [wide](design/screens/08-emoji-wide.png)): takes the room of the bar and the keys
    together, so the keyboard's height doesn't change. A section label (small caps,
    `muted`) over five rows of emoji, scrolling sideways, then the bottom strip.
  - *Skin tones* ([04](design/screens/04-tones.png)): a rounded popover on `key` above
    the held emoji, the default yellow, a thin divider, then the five tones; the current
    choice sits on `ice`. Slide to one and lift, or tap one.
- **Motion and copy:**
  - Tapping an emoji gives it a quick pop (scale 1.3 and back, `key hit` timing) and the
    key click and haptic the letters get. Reduce Motion: no pop.
  - Switching to and from the page is instant, like the numbers page.
  - The skin tone popover rises in with `spring`.
  - Copy: section names are Apple's ("Frequently used", "Smileys & people", ...).
    Keys: `ABC`, and VoiceOver labels "Emoji", "Next keyboard", "Delete".
- **Design system:** reuses `Key` (function style for the emoji key, `ABC` and delete),
  `SectionLabel`, the `kb`, `key`, `keyDark`, `ice` and `muted` tokens and the `key hit`
  timing. Adds three keyboard components: `EmojiPage` (grid plus strip),
  `EmojiCell` (one emoji, its tap and hold) and `TonePicker` (the popover). Category
  icons are SF Symbols (`clock`, `face.smiling`, `leaf`, `cup.and.saucer`,
  `soccerball`, `car`, `lightbulb`, `heart`, `flag`). The emoji key is SF Symbol
  `face.smiling`, as on Apple's.
- **Sizes:**
  - *Small (Duo outer)* and *phone:* cells about 37 pt, five rows, roughly eight to
    nine columns visible.
  - *Wide (Duo inner):* the keys are taller there, so the cells are too (about 46 pt),
    still five rows, about fifteen columns visible. When the letters are split, the
    emoji page is not: the grid runs the full width (emoji are tapped, not swiped).
  - *Resizing:* the page lays out from the keyboard's width and height like the keys,
    and keeps the category you were in when the width changes.
  - The keyboard doesn't follow Dynamic Type (neither does Apple's); emoji size comes
    from the keyboard height setting.
- **Accessibility:** VoiceOver reads each emoji by its system name (the emoji itself is
  the label, iOS speaks it), categories are buttons named after their section, and
  holding with VoiceOver on opens the tones as a list of buttons. Delete and `ABC` keep
  the 44 pt target. Emoji cells are smaller (about 37 pt on a phone, as on Apple's), so
  VoiceOver users can also swipe through them one by one.
- **Open questions** for Gabriel
  1. The page hides the guesses bar while it's open (proposed, like Apple's). Fine?

## Build

Status: Approved 2026-11-03 (Gabriel in the thread: "Build it"; the open questions
go as proposed until he says otherwise)

- **Approach:** a new page of the shared `KeyboardView`, next to letters, numbers and
  symbols, so the extension and the app's practice fields both get it. The data and the
  logic are pure and tested in `AstrotypeCore`; the views are in `AstrotypeUI` from
  the `Theme` tokens.
- **Core pieces:**
  - `EmojiCatalog` (Core): the emoji by category with their skin tone forms, read from
    a compact bundled file built from Unicode's `emoji-test.txt` (about 60 KB), and
    filtered by the newest emoji version the running iOS draws.

        let catalog = try EmojiCatalog.bundled(upTo: EmojiCatalog.version(forOS: 18.4))
        catalog.categories   // [EmojiCategory(id: .smileys, emoji: ["😀", ...]), ...]
        catalog.hasTones("👍")  // true

  - `EmojiHistory` (Core): frequently used and the chosen tones, a value with
    `record(_:at:)`, `top(30)` and `tone(for:)`, counts fading like `PersonalModel`;
    saved by an `EmojiStore` (`emoji.json` in the keyboard's own files, as the settings).
  - `Key.emoji` and `Layout`: the bottom row takes `showsGlobe` (from
    `needsInputModeSwitchKey`), so the emoji key replaces or joins the globe; key
    positions otherwise unchanged and covered by `LayoutTests`.
  - `Composer.insert(emoji:)`: settles an open word (as space would, without its space)
    and types the emoji, with no autospace and no punctuation rules.
- **Phases:**
  1. *Emoji key and page.* Catalog, history, the key in the bottom row, the page with
     categories and frequently used. Done when: on a phone, tapping the emoji key opens
     the page in Messages, an emoji goes in after a swiped word with the word kept, and
     `ABC` comes back; checked at the small, wide and largest text sizes.
  2. *Skin tones.* Hold for the popover, remembered per emoji. Done when: holding 👍,
     picking a tone, then reopening the page shows 👍 in that tone.
- **Risks:**
  - *Memory.* The extension must stay under 40 MB. Colour emoji glyphs are expensive
    to draw, so the grid is a `UICollectionView` that reuses cells (only what's on
    screen is drawn) and the catalog loads when the page first opens. Check the bar's
    memory readout and `keyboard.memory_peak` after Phase 1.
  - *Which emoji iOS draws.* The version table is per iOS release; an emoji the system
    can't draw would show as a box. A test checks the table covers the iOS versions we
    support.
- **Metrics:** none (see Product).
- **Last step:** fold this feature into `PRODUCT.md` (Emoji under platform limits, Later)
  and `DESIGN.md` (The keyboard, the bottom row) with the screenshots.

## Notes as it shipped

- 3 Nov 2026: both phases in one PR. `EmojiCatalog` reads `Resources/emoji/emoji.tsv`
  (1,923 emoji, 332 with skin tones, 62 KB) built by `ml/emoji/build_emoji.py` from
  Unicode's `emoji-test.txt` (Emoji 18.0). The version table keeps a step behind:
  iOS 18.0 to 18.3 get Emoji 15.1, iOS 18.4 to 26 get 16.0, 27 gets 17.0, so no emoji
  shows as a box. `EmojiHistory` (counts halve every 30 days, 100 kept, 30 shown, a
  starter row until then) lives in `emoji.json` in the extension's own files. The
  grid is `EmojiPageView` (a horizontal compositional layout, five rows, headers per
  section) with `TonePicker`; `KeyboardView.showsGlobe` comes from
  `needsInputModeSwitchKey`. Section headers use Apple's capitalised names
  ("Smileys & People").
- 3 Nov 2026, after Gabriel tried it: the section titles came out as a column of
  their own beside each section (a horizontal layout puts a leading header before the
  items), which took too much room. Gabriel: drop them and leave a gap. Sections now
  have no titles, a 28 pt gap between them, and the strip's highlighted icon says
  where you are. Cells stay the same size (he likes them a bit smaller than Apple's).
  The category names are still the strip buttons' VoiceOver labels.
