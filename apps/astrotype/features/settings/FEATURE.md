# Astrotype: Settings redesign

Settings gets tidier and nicer to look at, and ready to grow: a short main page that
opens one page per area (Typing, Appearance, Your words, Privacy and sharing), rows
grouped into cards with short labels, a live keyboard preview for the height, and a
short list of core switches under a held `123` in the keyboard.

Gabriel, 3 Nov 2026: "Improve the settings screen. I want it to be a bit more organized
and look better. It's okay to keep most of the settings in the main app but have some
core ones in the keyboard by holding 123." Then: "These settings are going to grow a
lot. Separate features from appearance in different pages."

## Product

Status: Approved 2026-11-03 (Gabriel asked to merge it)

- **The problem:** Settings is one long list of 30 rows, each its own card, most with a
  two-line explanation. It is hard to scan, the privacy rows sit between the things
  people actually tweak, and the status of the keyboard, sync and Pro is buried at the
  bottom. The in-keyboard panel copies eight settings, including learning and forget,
  which makes it a second, smaller Settings rather than a quick one.
- **Who wants it:** everyone who opens Settings. The in-keyboard panel is for anyone who
  wants to change autospace or the height without leaving the app they're typing in,
  and for people without Full Access, where the app's Settings can't reach the keyboard.
- **Basics or powerful:** basics. Nothing new to learn, only easier to find.
- **How it works:**
  - *Settings (main page):* three status tiles at the top (keyboard, iCloud sync, Pro),
    then two short groups of links. Keyboard: Typing, Appearance, Your words. Account:
    Privacy and sharing, Astrotype Pro, Restore purchases, About. Each link says what's
    inside or its current state ("Height 100%, guesses bar, trails, split").
  - *One page per area:* Typing is what the keyboard does (two thumbs, autospace, real
    words, gestures). Appearance is how it looks and feels (height, guesses bar, trails,
    haptics, underline, the wide-screen layout). Your words is learned words and
    learning. Privacy and sharing holds the five sharing rows. New settings go on the
    page they belong to, so the main page stays the same length as the app grows; a page
    that gets long splits into its own sections or sub-pages the same way.
  - Long explanations become one short footnote under a group.
  - *In the keyboard (hold `123`):* the core few. Four quick tiles (Autospace, Guesses
    bar, Haptics, Trails, plus Split on a wide screen) and four sliders (Height, Real
    words, Split words, Wait). A line at the bottom says the rest is in the app.
- **Split words** (`KeyboardSettings.splitStrictness`, 0 to 100%, 80% by default) is
  being added in its own PR from the auto-split thread, right under Real words in
  today's screens. This redesign moves it with Real words: on the Typing page and in
  the panel. Slider ends "Never" and "Whenever it's sure".
- **What it changes:** `SettingsView` (screen 9) becomes the main page, four new pages
  (Typing, Appearance, Your words, Privacy and sharing), and `SettingsPanelView`. No setting is added or removed, and no stored value changes.
  "Learn from my typing" and "Forget" leave the keyboard panel (see open questions).
- **Scope:** this version: the layout and look above. Later: search in Settings.
  Never: a setting that only exists in the keyboard.
- **What we measure:** nothing new. Settings changes aren't counted today, and this
  doesn't need it.
- **Open questions** for Gabriel
  1. Without Full Access the app can't reach the keyboard, so settings that leave the
     panel (learning, forget, gestures, underline) stay at their defaults in other apps
     for those people. Proposed: fine, the panel keeps the ones people change most. Or
     keep "Learn from my typing" in the panel as a fifth tile?
  2. Is "Wait" clear enough for the autospace delay in the panel? (The app says
     "Autospace" with Quick to Relaxed under it.)

## Design

Status: Approved 2026-11-03 (Gabriel asked to merge it)

- **Mockups:** `design/mockups/settings.html` (Artifact link:
  https://claude.ai/artifact/XNKQVaSVP9u72y8NfVbaiC). It has the new screens and
  "Today" versions of both for comparison; switches and sliders work, and the height
  slider moves the keyboard preview live.
- **What changes:**

  | Screen | Before | After |
  |---|---|---|
  | Settings | [today](design/screens/12-before-settings.png) | [main page](design/screens/01-settings.png) |
  | Keyboard panel (hold `123`) | [today](design/screens/13-before-panel.png) | [new](design/screens/09-panel.png), [dark](design/screens/10-panel-dark.png) |

  *Settings, the main page* ([01](design/screens/01-settings.png)):
  - *Status tiles:* Keyboard (On / Not on yet, taps to the setup screen), iCloud sync
    (last synced, or Set up), Pro trial (days left, or Pro). A dot in mint when fine,
    sun yellow when it wants a look.
  - *Keyboard:* Typing ›, Appearance ›, Your words ›, each with a one-line summary.
  - *Account:* Privacy and sharing ›, Astrotype Pro ›, Restore purchases, About ›.
  - The Full Access note moves to the sync tile's screen, the Tatoeba credit to About.
- **New screens:**
  - *Typing* ([02](design/screens/02-typing.png)): Words group (Two-thumb typing PRO,
    Autospace with its wait slider right under it and dimmed when off, Real words and
    Split words with their values and one footnote for both), then Gestures (Slide on space, Swipe left on ⌫).
  - *Appearance* ([03](design/screens/03-appearance.png),
    [dark](design/screens/04-appearance-dark.png)): Size (a live preview of the keyboard
    at the chosen height, with or without the guesses bar, then Height and Guesses bar),
    Look and feel (Trails and flashes, Haptics, Underline the open word), Wide screens
    with PRO in the label (Full / Split, Extra letters when split).
  - *Your words* ([05](design/screens/05-words.png)): Learned words (count, opens the
    list), Learns from you (the summary as its subtitle), and Forget what it learned in
    its own card, red, asking to confirm as today.
  - *Privacy and sharing* ([06](design/screens/06-privacy.png)): one line up top
    ("Nothing you type in other apps is ever sent"), Share anonymous usage data, and a
    "Help tune the keyboard" group: Send practice sessions, Include corrections (dimmed
    until practice is on), What gets shared ›, Practice words ›.
  - Where a new setting goes: if it changes what a touch does, Typing; if it changes
    what you see or feel, Appearance; if it's about what the keyboard remembers, Your
    words. A page that passes about a dozen rows gets a sub-page for its rarer group.
- **Motion and copy:** toggles and screens keep the `spring`. The preview keys grow and
  shrink with a spring as the height slider moves. Quick tiles squeeze to 95% on press
  and fill with `accent` when on. Copy is shorter: every subtitle fits on one or two
  lines on a phone; the longer "why" moves to group footnotes.
- **Design system:** reuses `Card`, `Row`, `SectionLabel`, `Toggle`, `Segmented`,
  `Slider`, `Chip`, `ProBadge`, `PrimaryButton.small`. Adds four components, named the
  same in the mockup CSS and the code:
  - `Group`: one card with several rows and hairlines between them (replaces one card
    per row in Settings). Link rows use the same `Row` with a chevron.
  - `IconTile`: a 30 pt rounded square with a glyph (SF Symbols in the app), colored by
    what the row is about: teal typing, coral the right-thumb things (trails, delete),
    mint your words, sun Pro, slate system rows.
  - `QuickTile`: the keyboard panel's square switch, `key` when off and `accent` when on.
  - `KeyboardPreview`: a small keyboard drawn from `Layout` at the chosen height.
  One new color token, `danger` (`#E0526A` / `#FF7A8E`), the right-thumb coral made a
  little darker so red text passes contrast, for Forget.
- **Sizes:** Small ([07](design/screens/07-settings-small.png)) is the phone layout
  with a little less height. Wide ([08](design/screens/08-settings-wide.png),
  [panel](design/screens/11-panel-wide.png)) shows the main page as a sidebar and the
  chosen page beside it (Typing to start), like Apple's Settings on iPad, and adds the
  Split tile to the panel. On resize (folding the Duo) the open page stays open: wide
  to phone pushes it over the main page with a back button, phone to wide puts the
  sidebar back beside it. The panel is about 300 pt tall with four sliders, a
  little more than the keys' space without the guesses bar, so on a phone the last
  slider may sit under a short scroll (it scrolls as today, with the indicator flashed).
- **Accessibility:** icon tiles are decorative (the row's title is the label). Quick
  tiles are switches with their label as the name. The preview reads "Keyboard at 100%".
  At the largest text sizes rows wrap, the status tiles stack to one column, and the
  panel's four tiles become two rows of two.
- **Open questions** for Gabriel
  1. Icon tiles on every row (as in the mockup) or only on the main page's links? They
     make the lists easier to scan but busier.

## Build

Status: Approved 2026-11-03 (Gabriel: "Merge and build")

- **Approach:** screens only, no Core change. `SettingsView` becomes the main page
  and gains `SettingsPage` (typing, appearance, words, privacy, about); each page is a
  view in `Astrotype/Settings/SettingsPages.swift`. On a phone the open page is pushed
  with `navigationDestination(item:)`; at 700 pt and wider the main page is a 340 pt
  sidebar with the page beside it. The same `open` state drives both, so folding or
  unfolding keeps the page open. About became a small page of its own (version and the
  Tatoeba credit).
- **Core pieces (design system, `AstrotypeUI`):** `SettingsGroup` (named so, not
  `Group`, which SwiftUI already has), `SettingsRow`, `SettingsToggle`, `SettingsLink`,
  `SettingsSlider`, `GroupFootnote`, `StatusTile`, `IconTile`, `KeyboardPreview`, in
  `SettingsComponents.swift`, plus `SectionLabel(_:pro:)` and the `danger` and `slate`
  tokens. Called like:

  ```swift
  SectionLabel("Gestures")
  SettingsGroup {
      SettingsToggle("Slide on space", subtitle: "Move the cursor", symbol: "arrow.left.and.right",
                     tint: Theme.left, isOn: $model.keyboardSettings.spaceSlide)
      SettingsLink("Learned words", symbol: "book.closed", tint: Theme.mint, value: "214") { open() }
  }
  GroupFootnote("…")
  ```

  The panel's `QuickTile` stays private to `SettingsPanelView` until something else needs it.
- **Phases:** one PR: the components, the five pages, and the new panel.
  Done when: Settings shows the tiles and links; each page opens; the height slider
  moves the preview; on a wide screen the sidebar and page sit side by side and folding
  keeps the page; holding 123 shows four tiles and four sliders, plus Split on a wide
  screen; at the largest text size rows wrap and the tiles go two by two.
- **Risks:** no Xcode in the container, so the build is checked on CI.
- **Metrics:** none.
- **Last step:** folded into `DESIGN.md` (screen 9, the design system and the panel note).
