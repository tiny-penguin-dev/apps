# Astrotype: Settings redesign

Settings gets tidier and nicer to look at: rows grouped into a few cards with short
labels, the rarely touched privacy rows on their own screen, a live keyboard preview
for the height, and a short list of core switches under a held `123` in the keyboard.

Gabriel, 3 Nov 2026: "Improve the settings screen. I want it to be a bit more organized
and look better. It's okay to keep most of the settings in the main app but have some
core ones in the keyboard by holding 123."

## Product

Status: Draft

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
  - *App Settings:* three status tiles at the top (keyboard, iCloud sync, Pro), then
    groups: Typing, Keyboard, Gestures, Wide screens, Your words, More. Long
    explanations become one short footnote under a group. Privacy and sharing (five
    rows) moves to its own screen under More, next to Pro, Restore and About.
  - *In the keyboard (hold `123`):* the core few. Four quick tiles (Autospace, Guesses
    bar, Haptics, Trails, plus Split on a wide screen) and three sliders (Height, Real
    words, Wait). A line at the bottom says the rest is in the app.
- **What it changes:** `SettingsView` (screen 9), a new Privacy and sharing screen, and
  `SettingsPanelView`. No setting is added or removed, and no stored value changes.
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

Status: Draft

- **Mockups:** `design/mockups/settings.html` (Artifact link:
  https://claude.ai/artifact/XNKQVaSVP9u72y8NfVbaiC). It has the new screens and
  "Today" versions of both for comparison; switches and sliders work, and the height
  slider moves the keyboard preview live.
- **What changes:**

  | Screen | Before | After |
  |---|---|---|
  | Settings | [today](design/screens/10-before-settings.png) | [top](design/screens/01-settings.png), [lower](design/screens/02-settings-lower.png), [dark](design/screens/03-settings-dark.png) |
  | Keyboard panel (hold `123`) | [today](design/screens/11-before-panel.png) | [new](design/screens/07-panel.png), [dark](design/screens/08-panel-dark.png) |

  Settings, top to bottom:
  - *Status tiles:* Keyboard (On / Not on yet, taps to the setup screen), iCloud sync
    (last synced, or Set up), Pro trial (days left, or Pro). A dot in mint when fine,
    sun yellow when it wants a look.
  - *Typing:* Two-thumb typing (PRO), Autospace with its wait slider right under it
    (dimmed when off), Real words with its value. Footnote explains Real words.
  - *Keyboard:* a live preview of the keyboard at the chosen height, with or without the
    guesses bar, then Height, Guesses bar, Trails and flashes, Haptics, Underline the
    open word. Footnote: "At 100% every key sits where Apple's does."
  - *Gestures:* Slide on space, Swipe left on ⌫.
  - *Wide screens* (PRO in the section label): Full / Split, and Extra letters when split.
  - *Your words:* Learned words (count, opens the list), Learns from you (with the
    summary as its subtitle), Forget what it learned (red, asks to confirm as today).
  - *More:* Privacy and sharing ›, Astrotype Pro ›, Restore purchases, About ›.
  - Full Access note and Tatoeba credit move into the sync tile's screen and About.
- **New screens:** Privacy and sharing ([06](design/screens/06-privacy.png)): one line
  up top ("Nothing you type in other apps is ever sent"), then Share anonymous usage
  data, and a "Help tune the keyboard" group: Send practice sessions, Include
  corrections (dimmed until practice is on), What gets shared ›, Practice words ›.
- **Motion and copy:** toggles and screens keep the `spring`. The preview keys grow and
  shrink with a spring as the height slider moves. Quick tiles squeeze to 95% on press
  and fill with `accent` when on. Copy is shorter: every subtitle fits on one or two
  lines on a phone; the longer "why" moves to group footnotes.
- **Design system:** reuses `Card`, `Row`, `SectionLabel`, `Toggle`, `Segmented`,
  `Slider`, `Chip`, `ProBadge`, `PrimaryButton.small`. Adds four components, named the
  same in the mockup CSS and the code:
  - `Group`: one card with several rows and hairlines between them (replaces one card
    per row in Settings).
  - `IconTile`: a 30 pt rounded square with a glyph (SF Symbols in the app), colored by
    what the row is about: teal typing, coral the right-thumb things (trails, delete),
    mint your words, sun Pro, slate system rows.
  - `QuickTile`: the keyboard panel's square switch, `key` when off and `accent` when on.
  - `KeyboardPreview`: a small keyboard drawn from `Layout` at the chosen height.
  One new color token, `danger` (`#E0526A` / `#FF7A8E`), the right-thumb coral made a
  little darker so red text passes contrast, for Forget.
- **Sizes:** Small ([04](design/screens/04-settings-small.png)) is the phone layout
  with a little less height; the status tiles wrap their second line. Wide
  ([05](design/screens/05-settings-wide.png), [panel](design/screens/09-panel-wide.png))
  puts Settings in two columns (Typing and Keyboard left, the rest right) and adds the
  Split tile to the panel. On resize the columns reflow and the scroll position stays
  on the same group. The panel fits the keyboard's height without scrolling at 100% on
  every phone; at 80% or with large text it scrolls, as today.
- **Accessibility:** icon tiles are decorative (the row's title is the label). Quick
  tiles are switches with their label as the name. The preview reads "Keyboard at 100%".
  At the largest text sizes rows wrap, the status tiles stack to one column, and the
  panel's four tiles become two rows of two.
- **Open questions** for Gabriel
  1. Icon tiles on every row (as in the mockup) or only on the group headers? They make
     the list easier to scan but busier.

## Build

Status: Not started

- **Last step:** fold this into `PRODUCT.md` and `DESIGN.md` (screen 9 and the panel
  note under "Not drawn yet").
