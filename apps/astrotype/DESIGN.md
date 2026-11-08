# Astrotype v2: design

Status: Approved 2026-11-01

Builds on `PRODUCT.md` (approved 2026-11-01). This PR also edits `PRODUCT.md` in two
small ways: no mascot (Gabriel, 2026-11-01), and a "What we measure" section as
`docs/telemetry.md` asks for.

## Mockups

- Clickable mockup: `design/mockups/astrotype.html` (Artifact link:
  https://claude.ai/artifact/PckLFxQcL1QDv5R3kSDZzc)
- Screenshots: `design/screens/` (phone, dark, and the small and wide sizes)

The keyboard in the mockup is real: keys tap, swipes draw trails and are decoded against
the app's own 1,500 most common words, and on a phone both thumbs work at once. It is a
sketch of the feel, not the engine: the matcher is a crude subsequence lookup, so it
guesses wrong more often than the real one will. The Size buttons show the same screens
on the iPhone Duo's outer and inner screens.

## Look

- **Feeling:** ice and speed. A pale glacier background, cool teal for actions, and two
  thumb colors that show up everywhere typing happens. No mascot: the graphics are the
  keyboard itself with a teal and a coral trail on it, and a few flat shapes in the same
  colors (a cloud, a bolt, a star).
- **Colors (light / dark):**
  - Background: glacier `#F3F8FA` / deep water `#111A24`
  - Cards and keys: white `#FFFFFF` / `#1A2634` (keys `#2A3A4A`)
  - Text: navy `#1E2945` / `#EEF4F8`
  - Main color (buttons, links, open word): teal `#139FB5` / `#2FC6DC`
  - Left thumb: the same teal. Right thumb: coral `#FF6F86` / `#FF8A9E`. Every trail,
    key flash and drill hint uses these two, so people learn which thumb did what.
  - Pro: sun yellow `#FFC24D`. Done and on: mint `#2FBF96`. Ice `#D9EDF3` for chips.
  - Keyboard background: `#DCE6EC` / `#131E29`, close to Apple's so the keyboard feels at
    home in any app.
- **Type:** SF Pro Rounded in the app. On the keys, the same face at 21 pt, bold, so
  letters read at a glance under a moving thumb. Numbers use tabular figures.
- **Shapes:** big round corners in the app (18 to 28 pt), pill buttons with a pressable
  bottom edge. Keys are 7 pt radius like Apple's, because the keyboard must feel like a
  keyboard, not like the app.
- **App icon:** a white "A" key with a teal and a coral orbit around it, on a starry
  navy. Space and typing in one picture, the two thumb colors, no character. Light,
  dark and tinted appearances; the sources are in `design/icon/` (its README says how
  they become the PNGs in the asset catalog).

## Design system

One set of tokens and components, named the same in the mockup's CSS, here and in the
code (`AstrotypeKit/Theme`, `docs/building.md` rule 1). Screens only use these.

**Tokens**

| Token | Light | Dark | Used for |
|---|---|---|---|
| `bg` | `#F3F8FA` | `#111A24` | screen background |
| `card` | `#FFFFFF` | `#1A2634` | cards, rows, the bar's top guess |
| `ink` | `#1E2945` | `#EEF4F8` | text |
| `muted` | `#67748F` | `#97A6B8` | secondary text |
| `line` | `#DCE6EC` | `#2A3B4C` | dividers, toggles off, meter tracks |
| `accent` | `#139FB5` | `#2FC6DC` | buttons, links, the open word |
| `accentInk` | `#FFFFFF` | `#06202A` | text on accent |
| `left` / `right` | `#139FB5` / `#FF6F86` | `#2FC6DC` / `#FF8A9E` | the two thumbs |
| `sun` | `#FFC24D` | `#FFCD66` | Pro, rewards |
| `mint` | `#2FBF96` | `#45D3AA` | done, on, correct |
| `ice` | `#D9EDF3` | `#1D3240` | chips, step numbers |
| `key` / `keyDark` | `#FFFFFF` / `#C9D6DE` | `#2A3A4A` / `#1C2834` | letter keys / function keys |
| `kb` | `#DCE6EC` | `#131E29` | keyboard background |
| `returnAction` | `#007AFF` | `#0A84FF` | a return key that acts ("go", "search"), Apple's blue |

- Type: `title` 30 pt black, `heading` 20 pt heavy, `body` 16 pt, `small` 13 pt, `big`
  64 pt tabular (the speed number), `key` 21 pt bold. All SF Pro Rounded, all Dynamic
  Type in the app; the keyboard follows the system keyboard's sizing.
- Spacing: 4, 8, 12, 16, 22 (screen gutter), 32. Radii: `lg` 28, `md` 18, `sm` 12,
  `key` 7, pills 999.
- Motion: `spring` (overshoot, 0.25 to 0.45 s) for buttons, toggles and screens; `trail
  fade` 1.2 s; `tap ring` 0.6 s; `key hit` 0.15 s; autospace squeeze 0.2 s.

**Components**

- `PrimaryButton` (pill, accent, pressable bottom edge; `.ghost` and `.small` variants),
  `BackButton`.
- `Card` and `Row` (card with a leading number or tick, title, subtitle, trailing
  control), `SectionLabel` (small caps), `Chip`, `ProBadge`.
- Settings: `SettingsGroup` (several rows in one card, hairlines between), `SettingsRow`,
  `SettingsToggle`, `SettingsLink`, `SettingsSlider`, `GroupFootnote`, `StatusTile`,
  `IconTile` (a coloured symbol square), `KeyboardPreview`; in the keyboard,
  `QuickTile`. Tokens `danger` (`#E0526A` / `#FF7A8E`) and `slate` (`#5B6B8C` / `#6E7FA0`).
- `Toggle`, `Segmented`, `Slider`, `PriceOption`, `Perk`.
- `Steps` (numbered setup steps), `Meter` (you versus Apple), `WordCards` (drill words),
  `WeekDots`.
- `Art` (the generic graphics, see Graphics), `Confetti`.
- The keyboard: `KeyboardView`, `Key` (letter, wide, function, space, return), `Bar`
  (idle, open word, fix), `Trails`, `TextPreview` (the open word).

## Screens

| # | Screen | What it's for | Screenshot |
|---|---|---|---|
| 1 | Hello | A keyboard with two thumb trails drawing themselves. "Type with both thumbs." One button. | [01](design/screens/01-hello.png) |
| 2 | Turn on the keyboard | The three Settings steps, a status chip that flips to "On" when the keyboard appears, "Open Settings". | [02](design/screens/02-turn-on.png) |
| 3 | Keep your words everywhere | The Full Access ask, with its one reason (iCloud sync of words and settings) and "Nothing you type is ever sent anywhere". A cloud linked to a phone and a Mac. Skippable. | [03](design/screens/03-sync.png) |
| 4 | Try it | A practice field with the keyboard up. Five words, each with a thumb-by-thumb hint. "Show me" replays the word with trails. | [04](design/screens/04-try.png), [dark](design/screens/04-try-dark.png), [small](design/screens/04-try-small.png), [wide](design/screens/04-try-wide.png) |
| 5 | Home | "Both flippers, go." Speed test card (best, versus Apple's keyboard), trial status, drills, this week, Settings. A yellow banner if the keyboard is not on. | [05](design/screens/05-home.png), [dark](design/screens/05-home-dark.png), [small](design/screens/05-home-small.png), [wide](design/screens/05-home-wide.png) |
| 6 | Speed test | A sentence to type with the typed part turning mint, a timer, the keyboard. | [06](design/screens/06-speed.png) |
| 7 | Speed test result | A bolt in a sun, the words per minute, fixes, versus Apple's, confetti on a new best. | [07](design/screens/07-result.png) |
| 8 | Drill | One habit per drill. Word cards, the keys of the next word outlined in the thumb's color. | [08](design/screens/08-drill.png) |
| 9 | Settings | Status tiles (keyboard, sync, Pro), then a page per area: Typing (two thumbs, autospace, real words, split words, gestures), Appearance (height with a live preview, guesses bar, trails, haptics, wide-screen layout), Languages (a switch per language, features/languages), Your words, Privacy and sharing, About. On wide screens the main page is a sidebar. From `features/settings` (3 Nov 2026). | [main](features/settings/design/screens/01-settings.png), [typing](features/settings/design/screens/02-typing.png), [appearance](features/settings/design/screens/03-appearance.png), [wide](features/settings/design/screens/08-settings-wide.png) |
| 10 | Astrotype Pro | A gold star tile with the two trails, four perks, yearly and monthly, "Start 14 days free". | [10](design/screens/10-pro.png) |
| 11 | Trial over | The keyboard faded, with z's. What is resting, what still works, the person's own best speed as the reason to keep Pro. | [11](design/screens/11-trial-over.png) |
| 12 | Typing in Messages | The keyboard in another app. The bar after a commit (the three-part bar is in features/guesses-bar), the open word in the field. | [12](design/screens/12-messages.png), [dark](design/screens/12-messages-dark.png), [small](design/screens/12-messages-small.png), [wide](design/screens/12-messages-wide.png) |
| 13 | Free keyboard | After the trial: taps and one-finger swipes. A second thumb shows "Two thumbs is in Astrotype Pro" in the bar instead of typing. | [13](design/screens/13-free.png) |

Not drawn yet (simple, same style): the numbers and symbols pages, the in-keyboard
settings panel (under a held `123`: four quick tiles, autospace, guesses bar, haptics
and trails, plus split on a wide screen, a Languages row that opens the list of
languages with a tick on each one that's on, and four sliders, height, real words, split
words and autospace's wait; it covers the guesses bar too, which has nothing to say
while it's open (Gabriel, 3 Nov 2026); the rest is in the app; `features/settings`, 3 Nov 2026,
[panel](features/settings/design/screens/09-panel.png)), the learned
words and word pairs lists (Settings → Your words: + adds a word, Select drops several,
pairs searchable by most used or newest with a four-bar meter; `features/learned-words`,
6 Nov 2026, [pairs](features/learned-words/design/screens/pairs.png)), snippets editor, one-handed layouts, the milestone sheet. The split layout
(an option on wide screens, Gabriel, 1 Nov 2026) is exactly Apple's: Q to T, A to G
and Z to V on the left, Y to P, G to L and V to M on the right (G and V on both halves,
nothing repeated on the top row; Gabriel, 2 Nov 2026, after trying more overlap). Settings
"Extra letters on split" adds one more past the middle to each half (Y H B left, T F C
right) for swiping across. The numbers and symbols pages follow the same rules: "?"
sits under V on both halves, and the extra letters add 6 $ ! (% > ! on #+=) to the left
and 5 ( , (# < ,) to the right (Gabriel, 8 Nov 2026). Space on
both sides, the guesses in the open middle (Gabriel, 2 Nov 2026). Split, the keys beside space
(`123`, globe, emoji) are a fifth narrower than on the whole keyboard and return is
exactly two of them wide, so both halves of space keep their room (Gabriel, 8 Nov 2026).

## The keyboard

This is the product, so it gets its own section.

- **Keycaps:** Apple's (iOS 26): white keys on light grey in light mode, #464646 keys
  on the system glass in dark, SF Pro regular letters, Apple's glyphs for shift, delete,
  globe, emoji and return, 8.5 pt corners. Only the thumb flashes and trails are ours (Gabriel,
  2 Nov 2026).
- **Layout:** Apple's QWERTY proportions, so muscle memory carries over. Rows of 10, 9
  and 7 letters, shift and backspace on the third row, `123`, emoji, space and return on
  the fourth, as on Apple's (iOS draws its globe under the keyboard). Where iOS draws
  none (a Home button phone, the iPhone Duo), our globe sits at the left end of the
  guesses bar, so space keeps its room; with the bar off or in a column it goes back
  before the emoji key (`features/space-bar`, 3 Nov 2026). Space reads "Astrotype" when idle, like Apple's reads the language.
- **Size:** every key sits where Apple's does, so muscle memory carries over: the top
  of our top row is the top of Apple's, and the bottom of our bottom row is the bottom
  of Apple's (measured on iOS 26: rows spanning 213 pt on a phone with 7 pt under them,
  208 pt on the iPhone Duo open with 4 pt under them, 8 pt when split). The keys are
  only 2 pt apart, across and down, so they are bigger than Apple's and a tap rarely
  lands in a gap (a tap that does, or one under the bottom row, goes to the nearest
  key). No padding at the sides or the top: iOS adds its margins around the keyboard.
  The guesses bar on top adds to the height rather than taking from the keys.
  "Keyboard height" (in Settings and the in-keyboard settings, 80 to 120%, 100% by
  default) makes the keys taller or shorter; the bottom row stays put and the top row
  moves. If iOS grants less height than asked, the keys shrink to fit and the
  in-keyboard settings say so (Gabriel, 3 Nov 2026).
- **Where the guesses go:** where the keys leave a column of 96 pt or more (the middle
  of a split keyboard, the sides of a wide one) the guesses stack there, and the keys
  get the whole height. Otherwise (a phone) they are a bar above the keys, which
  Settings ("Guesses bar") can turn off to give the keys its room.
- **The bar** (or column) has three parts that never move (features/guesses-bar, where
  the before and after screenshots are): a 44 pt key at the left end (the globe, where
  our keyboard draws one, features/space-bar; ✕ while fixing), the words in the middle,
  packed together and centred on the keyboard, and a 44 pt pencil ("Not it?") at the
  right end. The middle holds one kind of thing at a time. When three words don't fit
  whole, the outer ones drop (never the chosen one) rather than cut a word. In a column
  the words stack and the pencil sits under them; the globe goes back next to 123.
  The middle's states:
  - *Idle:* a short note ("Both thumbs, one word") or, with nothing to say, empty.
  - *Open word:* up to three guesses, the chosen one in a pill in the centre with
    the others either side. The pill takes the theme's shift/delete/return colour and
    see-through with the letters' colour at 80%. Everything else on the bar has no key behind it, so
    it follows the look instead of the theme: white (dark) or black (light), at 80% for
    readings and typed text and 60% for other words, notes and the bar's icons (globe,
    pencil, ✕). Bar text is never fully solid and never a separate gray. That one is what space writes. Tapping any guess writes it.
  - *Fix:* right after a commit, when there are no next words (or "Guess the next word"
    is off): the word just written in the pill, its other readings either side. Tap one
    and it replaces the word just written. Any new tap or swipe clears it.
  - *Next:* with no word open, up to three likely next words, in the plain guess style
    (no pill: space does not write them). A tap writes one with a space after it, and
    the bar guesses the word after that. At a sentence start they are capitalised ("I",
    "The"). Nothing after a comma, inside a word, in fields that do not learn, or in
    the app's practice fields. Any tap or swipe on the keys clears it. New guesses rise
    in over 0.25 s (at once with Reduce Motion). From features/next-word.
  - *Fix row:* when the last word has other readings, the pencil opens them: ✕ at the
    left end, the readings in the middle, and "Type it" last (outlined). A reading
    replaces the last word and the bar goes back to next words; ✕ goes back unchanged.
  - *Not it?* (features/missed-words): after a swiped word (open, FIX, next words or
    idle right after it), "Type it", or the pencil when there are no readings to pick,
    turns the bar into a field: ✕, the word typed so far ("What did you mean?" while
    empty), and a Save pill. Taps type exact letters into it, backspace edits, space or
    return saves; Save replaces the swiped word and squeezes the bar like a commit.
- **Pieces:** a touch is a tap if it lifts within 18 pt of where it landed and crossed no
  other key, otherwise a swipe. Taps flash the key in the thumb's color and leave a ring
  that pings out. Swipes draw a 9 pt rounded trail in the thumb's color that fades over a
  second after lift. Which thumb: left half of the keyboard is teal, right half coral.
  (The real engine will tell thumbs apart by touch identity and position, not only by
  side.)
- **The open word** shows in the text field as plain text, replaced as the guesses
  change, in other apps and the app's own fields alike. It is never underlined (marked
  text): through the keyboard's proxy that put spaces before words (2 Nov 2026), and
  while a word was underlined iOS hid the person's taps and selections from the
  keyboard. Gabriel had the underline removed on 8 Nov 2026, so
  the person sees what space will write without looking at the bar.
- **Commit:** space, punctuation, or autospace after 0.9 s with no finger down (the
  delay is a setting, 0.1 to 1.5 s), for swiped and pecked words alike (Gabriel, 2 Nov
  2026: swipe-only broke one-word pecks and "I" or "a"). One space between words: a
  space pressed right after autospace (or a guess from the bar) wrote one adds nothing
  (and no period); a double tap on space, after autospace or not, makes it ". ";
  punctuation goes before that space ("word. "), and return drops it. On autospace the bar gives a
  tiny squeeze so the person notices the word went in.
- **Backspace:** with an open word, removes the last piece. Otherwise one character.
  Swipe left on it deletes the last word; the keys to the left of it do not need to be
  crossed, 40 pt of travel is enough.
- **Shift:** one tap capitalises the next word, two taps lock caps. Sentence starts are
  capitalised automatically.
- **Free mode:** one active thumb at a time. A second touch does not type; the bar says
  "Two thumbs is in Astrotype Pro" for 1.6 s. Nothing shakes, nothing is lost.
- **Emoji page** (`features/emoji`, [mockup](features/emoji/design/mockups/emoji.html),
  [screens](features/emoji/design/screens/03-emoji.png)): the emoji key swaps the bar and
  the keys for a "Search emoji" field over a sideways grid, four rows high: Frequently
  used, then Apple's eight categories, a gap between sections and no titles (they cost a
  column). A strip below has `ABC`, a button per
  category (the one in view highlighted) and delete. Tapping types the emoji (an open
  word goes in first, with its space; nothing after the emoji). Holding a hand or a
  person opens the skin tones; the pick is kept for that emoji.
- **Emoji search** (`features/emoji-search`, [mockup](features/emoji-search/design/mockups/emoji-search.html),
  [screens](features/emoji-search/design/screens/04-found.png)): tapping the field
  brings the letters back with the field and a row of results above them, one row
  taller than the keyboard with its bar. Taps and swipes write into the field (never
  learned); results update as you type, by name, then keyword, then use. The smiley key
  and `done` go back to the page.
- **Field types** (features/field-types, 3 Nov 2026): the keyboard follows the field,
  like Apple's. 123, the globe or emoji key and return keep their place (where both
  the globe and emoji are shown, the field's row keeps only the globe); the field's keys take
  space's room on the letters page: @ and . in an email or username field, . / and
  .com (no space) in a web address, . in a web search, @ and # in a social post (on a
  split keyboard the keys share out between the halves). A number field opens on the
  123 page. Return shows the app's word ("go", "search", "send", "done"...) in lower
  case, on Apple's blue for an action and grey for "next", and is dimmed while a field
  that waits for text is empty. In addresses, numbers and codes taps are typed
  exactly, with no autospace, no space after a guess, no ". " on a double space and
  no capitals; swipes are still guessed. A field with corrections off types taps
  exactly but keeps autospace. Capitals follow the field (none, words, sentences, all).
  Mockup: `features/field-types/design/mockups/field-types.html`.
- **Not in the mockup, in the build:** slide on space to move the cursor (after a short hold and a 20 pt move, so a quick tap that drifts is still a space), the numbers
  page, edge swipes, snippets, the globe key switching keyboards. Held keys show their
  accents in a row above the key (á on a, ñ on n, ¿ on ?, when Spanish is on); slide
  along and lift to type one (features/languages, 3 Nov 2026). Like Apple's, a finger
  that slides off `123` brings up the numbers page under it, types the number or symbol
  it lifts on and goes back to the letters; holding `123` still opens the settings
  (Gabriel, 3 Nov 2026).

## Flows

- **First launch** (PRODUCT 5.1): Hello → Turn on the keyboard → (only on a phone set
  to both English and Spanish: Which languages do you type in?) → Keep your words
  everywhere → Try it (five words) → Home. Everyone starts on the Pro trial, so Try it
  teaches two thumbs from the first word.
- **Typing a word** (5.2): pieces → open word in the bar and the field → space, pause or
  punctuation commits → the bar offers fixes for a moment → next word.
- **Learning** (5.3): tapping out an unknown word letter by letter learns it once it
  settles (the next word starts), so a word fixed before that is never learned. Hold a
  guess in the bar for the word menu (Never suggest · word · Suggest more / Learn it,
  then Undo), or slide up or down to boost or block it at once (features/word-control).
- **Practice** (5.4): Home → Speed test → Result → Again or Done. Home → Drill → five words
  → back to Home with the drill ticked.
- **Customize** (5.5): Home → Settings. Pro rows carry the PRO badge and open the Pro
  screen when the trial is over.
- **Trial end:** on the first launch after the trial ends, the Trial over sheet. From then
  on, the Free keyboard with its one-line nudge, never a popup inside another app.
- **Keyboard not on:** the Home banner, and Settings' sync row, both lead back to the
  setup screens.

## Graphics

No mascot (Gabriel, 2026-11-01). The art is generic, flat, and built from the product's
own shapes in the design system colors, so it reads as "this is a keyboard app" without a
character to maintain. If a penguin ever shows up, it is Squawk's, not a new one. The
penguin connection stays in the studio name and in the copy ("Both flippers, go.").

| Art | Looks | Where |
|---|---|---|
| Keyboard with trails | A rounded key panel, a teal trail on the left and a coral trail on the right, each ending in a dot. On first show the trails draw themselves and the dots pop. | Hello (large), Home (small, top right) |
| Cloud | A cloud above a phone and a laptop, a teal and a coral line joining them | Keep your words everywhere |
| Bolt | A lightning bolt in a sun-yellow disc with slowly turning rays | Speed test result |
| Star tile | A sun-yellow key tile with a star, a trail curling at each corner | Pro |
| Resting keyboard | The keyboard faded to half, two z's floating up | Trial over, empty history |

All of it is vector, drawn from the same key rectangles the keyboard uses, so it scales
and recolors with the theme. Milestone rewards are keyboard themes and trail colors, not
outfits.

## Motion

- **Trails and flashes** are the main animation and they carry meaning: which thumb,
  which keys, where the swipe went. They are quick (the trail fades in 1.2 s, the tap ring
  in 0.6 s) so they never lag behind typing.
- **Keys** scale up 6% when hit and spring back.
- **Springs** in the app: screens slide in with a small overshoot, buttons squash, toggles
  wobble.
- **Art:** the trails on the Hello and Home keyboard draw themselves once; the cloud and
  star tile float gently; the bolt's rays turn slowly.
- **Speed test:** the typed words turn mint one by one. A wrong word shakes the field.
- **Success:** confetti in the four colors on a new best and when the keyboard is first
  turned on.
- **Haptics:** a light tap on every commit, a softer one on each key hit if Full Access
  allows it (checked in the build), success on a new best, error on a wrong drill word.
- **Sounds:** none in v1. Key clicks are a later setting.
- **Reduce Motion:** trails still draw (they are information) but do not fade with
  motion, just disappear; no key scaling, no floating or confetti; the art shows finished;
  screens fade.
- **Battery saver and Zen mode:** a setting that turns trails and flashes off.

## Copy

- Hello: "Type with both thumbs." / "Tap with one, swipe with the other, mix them any
  way you like. Press space when the word looks right. We'll show you." / **Let's go**
- Turn on: "Turn on Astrotype" / "iPhone keyboards switch on in Settings. It takes three
  taps, and I'll know when it's done." / **Open Settings**, I'll do it later / chip: "Not
  on yet" → "On" / "Astrotype is on. Hold 🌐 in any app to pick it."
- Full Access: "Keep your words everywhere" / "Astrotype learns your words. With Full
  Access they sync over iCloud to your other devices, along with your settings. That is
  the only thing it is used for. Nothing you type is ever sent anywhere." / **Open
  Settings**, Skip for now
- Try it: "Type this word" / "Left thumb taps s and e. Right thumb swipes o→m, then
  t→h→i→n→g. Space when it says something." / **Show me**, or just try it
- Home: "Both flippers, go." / banner: "Astrotype isn't on yet." **Turn on** / "Pro
  trial · 11 days left."
- Bar notes: "Both thumbs, one word" / "Tap or swipe. Space writes the word." / FIX /
  free: "One finger at a time", "Two thumbs is in Astrotype Pro"
- Speed test: "Type this" / result: "52" "words per minute" / "3 words needed a fix.
  That's 21 faster than Apple's keyboard and a new best." / **Again**, Done
- Drill: "Switching thumbs" / "Left swipes w→e, right swipes n→t. Keys light up to show
  which thumb."
- Pro: "Astrotype Pro" / "The fast keyboard, all of it." / **Start 14 days free** / "Then
  $19.99 a year. Renews automatically, cancel anytime."
- Trial over: "Your trial ended" / "Two-thumb typing, gestures and layouts are resting.
  The keyboard still works with taps and one-finger swipes, and your learned words are
  safe." / **Keep two-thumb typing**, Stay on the free keyboard
- Errors: "I couldn't sync your words. Check that iCloud is on for Astrotype in
  Settings." No puns in errors.

## Sizes

Three sizes, all in the mockup's Size buttons (`docs/building.md` rule 2):

- **Small** (iPhone Duo outer screen, 5.4", shorter and wider): the keyboard keeps
  Apple's proportions and grows a little wider, so thumbs reach the same keys. Screens
  with the keyboard up keep the keyboard full height and shrink the content above it
  (Try it shows the field and one line of hint, Messages shows the last two bubbles).
  Home scrolls. Hello and the other full-page screens lose their top spacing first.
  [Home](design/screens/05-home-small.png), [Try it](design/screens/04-try-small.png),
  [Messages](design/screens/12-messages-small.png).
- **Phone** (iPhone, the default): as in the screenshots.
- **Wide** (iPhone Duo inner screen, 7.8", and iPad later): the keyboard stays one
  keyboard, keys up to 64 pt wide and 51 pt tall (or as tall as the room allows) with 2 pt gaps, so a swipe is the same
  shape as on a phone, just bigger. Home becomes two columns (speed test and trial on the
  left, drills, week and Settings on the right). Titles step up to 36 pt. Everything else
  keeps its width and centers. [Home](design/screens/05-home-wide.png),
  [Try it](design/screens/04-try-wide.png),
  [Messages](design/screens/12-messages-wide.png).
- **Resizing** (unfolding, or Duo side by side): screens relayout live, no screen pops
  or loses its place. An open word, a running speed test and a drill in progress survive
  the change. The keyboard asks the system for the new width and redraws its trails on
  the new key positions.
- **Largest text size:** the app's rows wrap to two lines and buttons grow; the keyboard
  does not change height (its height is what thumbs learned), the bar text scales one
  step.

## Accessibility

- **Dynamic Type:** the app scales fully. The keyboard follows the system keyboard's
  sizing instead, because its height is what people's thumbs have learned; the bar text
  scales one step.
- **VoiceOver:** the keyboard works like Apple's (touch to hear a key, double-tap or lift
  to type; swipe typing is off under VoiceOver). The bar reads "Suggestions" with each
  guess, the first as "selected". The art has short labels ("A keyboard with two thumb
  trails") or is decorative. Trails and flashes carry no information VoiceOver needs: the
  bar does.
- **Order:** title, main content, the main button.
- **Contrast:** text and buttons meet WCAG AA in both themes; the teal button uses navy
  text in dark mode. Teal and coral are also different in brightness, so the two thumbs
  stay apart for people who cannot tell the hues.
- **Reduce Motion:** see Motion. Trails remain, because they say which keys a swipe hit.
- **One thumb:** everything works with one finger and swipes; two thumbs is faster, never
  required.

## Open questions

1. ~~The app icon: a key tile with the two trails, or something else?~~ Answered
   (1 Nov 2026): the orbit icon (see Look), picked over the key tile with trails and
   an A drawn by two thumb trails.

Answered (1 Nov 2026): Pro is $19.99 a year and $2.99 a month, as on the Pro screen.
