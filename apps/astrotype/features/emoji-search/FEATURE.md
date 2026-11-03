# Astrotype: Emoji search

A search bar on the emoji page, so you can find an emoji by typing what it is
("pizza", "heart", "corazón") instead of scrolling for it.

Gabriel, 3 Nov 2026, after trying the emoji page on his phone: "I do think we should
also add a search bar for ours." The emoji page (`features/emoji`) left search for
Later.

## Product

Status: Approved 2026-11-03 (Gabriel in the thread: "Build it"; the open questions go as proposed)

- **The problem:** there are about 1,900 emoji. Frequently used covers the everyday
  ones, but anything else means scrolling sideways and scanning. Apple's keyboard has
  search, so ours feels like a step back without it.
- **Who wants it:** everyone who uses emoji beyond their usual few.
- **Basics or powerful:** basics. One bar on the emoji page, no settings. Free.
- **How it works:**
  - *The bar.* "Search emoji" sits on top of the emoji page.
  - *Searching.* Tap it and the letters come back, with the search field on top and a
    row of results where the guesses bar usually is. Taps and swipes both work. The
    word goes into the search field, not the message.
  - *Results.* Results update as you type. Matches on the emoji's name come first, then
    matches on its keywords (🍕 is "pizza", and also "cheese", "slice", "hungry").
    Emoji you use often come first among equal matches, and each shows in the skin
    tone you picked. Before you type anything, the row shows Frequently used.
  - *Typing one.* Tap a result and it goes into the message, like on the emoji page.
    Search stays open so you can add another. The smiley key (or `done`) goes back to
    the emoji page, and `ABC` goes back to typing.
  - *Nothing found.* "No emoji for "xyz"". Delete, or clear the field with ×.
  - *Languages.* Names and keywords come in English and Spanish. Search uses the
    languages you have on, so "corazón" and "heart" both work with both on.
- **What it changes:** the emoji page (the bar on top, the grid goes from five rows to
  four at the same emoji size), and the keyboard grows by one row while you search,
  like Apple's.
- **Where it's kept:** nothing new. What you search for is never saved or learned, and
  never leaves the phone.
- **Scope:**
  - *This version:* the bar, search by name and keyword in English and Spanish, ranking
    by your use, skin tones.
  - *Later:* emoji suggestions in the guesses bar while typing ("pizza" offers 🍕),
    numbers and symbols in the search ("100" for 💯).
  - *Never:* Genmoji or anything that sends the search anywhere.
- **What we measure:** nothing new. The extension never sends metrics.
- **Open questions** for Gabriel
  1. The grid goes to four rows to make room for the bar, with emoji the same size
     (proposed). Or keep five rows with smaller emoji?
  2. The keyboard grows by one row while searching (proposed, like Apple's). Or keep its
     height and make the keys shorter while searching?

## Design

Status: Approved 2026-11-03 (Gabriel in the thread: "Build it"; the open questions go as proposed)

- **Mockups:** `design/mockups/emoji-search.html` (Artifact link:
  https://claude.ai/artifact/T8Vi21XSm1E6vMN9WMCxnE). Tap "Search emoji", type, tap a
  result, clear with ×, the smiley key goes back. It has "today", the three sizes and
  both themes. The mockup has a sample of emoji with English names; the app has all of
  them.
- **What changes:**

  | Screen | Before | After |
  |---|---|---|
  | Emoji page | [titles, no search](design/screens/01-before.png) | [search bar, no titles](design/screens/02-emoji.png) |

  The titles are already gone in PR #108; this adds the bar.
- **New screens:**
  - *Searching* ([empty](design/screens/03-search.png),
    [results](design/screens/04-found.png), [nothing found](design/screens/05-none.png),
    [dark](design/screens/06-found-dark.png)): the search field (rounded, on `key`, with
    a magnifier and ×), a row of results in the bar's place, then the letter keys. The
    bottom row is `ABC`, the smiley key (highlighted on `ice`, back to the page),
    space and `done`.
- **Motion and copy:**
  - Switching between the page and search is instant, like the numbers page.
  - Results swap in as you type, no animation (they'd jump under the thumb).
  - Copy: "Search emoji", "No emoji for "pizzz"", `done`. VoiceOver: "Search emoji",
    "Clear", "Back to emoji".
- **Design system:** reuses `Key`, the emoji cell, the `kb`, `key`, `keyDark`, `ice`
  and `muted` tokens. Adds one component, `SearchField` (the rounded field with a
  magnifier, text, caret and ×), which the app's own settings can reuse later.
- **Sizes:**
  - *Small (Duo outer)* and *phone:* bar 36 pt, four rows of about 37 pt emoji
    ([small](design/screens/07-emoji-small.png)).
  - *Wide (Duo inner):* the bar spans the width; emoji 46 pt, as now
    ([wide](design/screens/08-found-wide.png)).
  - *Resizing:* search keeps its text and results when the width changes.
- **Accessibility:** results are buttons named by the emoji (iOS reads its name). The
  field reads its text, and VoiceOver announces the number of results after a pause.
  The × has a 44 pt target.
- **Open questions** for Gabriel: none beyond the two in Product.

## Build

Status: Approved 2026-11-03 (Gabriel in the thread: "Build it"; the open questions go as proposed)

- **Approach:** a search mode of the shared `KeyboardView`, so the app's practice fields
  get it too. Names, keywords and ranking are pure and tested in `AstrotypeCore`; the
  field and the results row are in `AstrotypeUI`.
- **Core pieces:**
  - `EmojiNames` (Core): names and keywords per language, read from
    `Resources/emoji/names-en.tsv` and `names-es.tsv` (about 100 KB each), built by
    `ml/emoji/build_emoji.py` from Unicode's CLDR annotations. Every emoji in the list
    has a name in both languages (checked).
  - `EmojiSearch` (Core): `search(_ query:, in catalog:, history:) -> [Emoji]`. Each
    word of the query must start a word of the name or a keyword. Matches on the first
    word of the name rank first, then the rest of the name, then keywords, then by use.
    Accents and case don't matter ("corazon" finds ❤️).

        let search = EmojiSearch(names: [.bundled("en"), .bundled("es")])
        search.results(for: "pizza", in: catalog, history: history)   // [🍕]

  - `Composer` gets a text sink so taps and swipes write into the search field instead
    of the app, with no learning and no guesses.
  - `KeyboardView`: a search mode (field, results row, letters), one row taller.
- **Phases:**
  1. *Search.* Names, search, the bar and the search mode. Done when: on a phone,
     "pizza" finds 🍕, "corazón" finds ❤️ with Spanish on, a result goes into the
     message, and the smiley key goes back to the page.
- **Risks:**
  - *Memory.* The names load when search first opens (about 100 KB per language).
    Check the bar's memory readout with search open.
  - *Height change.* Some apps animate badly when a keyboard changes height. Test in
    Messages, Notes and WhatsApp; if it misbehaves, fall back to shorter keys at the same
    height.
- **Metrics:** none.
- **Last step:** fold this feature into `PRODUCT.md` and `DESIGN.md`, and remove search
  from Later in `features/emoji/FEATURE.md`.

## Notes as it shipped

- 3 Nov 2026: one PR. `EmojiNames` reads `Resources/emoji/names-en.tsv` and
  `names-es.tsv` (108 and 94 KB, every emoji in the list named) built by
  `ml/emoji/build_names.py` from CLDR's `annotations` and `annotationsDerived`.
  `EmojiSearch` keeps an index of every folded word to the emoji it names (first word
  of the name 3, rest of the name 2, keyword 1; a whole word scores one more than the
  start of one) and adds up the words of the search, all of which have to fit. It is
  built when search first opens, for the languages on then. While search is open,
  `KeyboardModel` points the engine at a `SearchTarget` (text in memory) with
  `Field.emojiSearch` (guesses as usual, never learns, return says "done"), and gives
  the host's field back when it closes; a result goes straight into the app.
- The bottom row while searching is the usual `123`, emoji, space, `done` (the mockup's
  `ABC` key there would have needed a new row); the smiley key and `done` go back to the
  page, and `ABC` on the page goes to the letters.
- The grid keeps the emoji size five rows had (four rows fit under the field with a
  little room to spare).
