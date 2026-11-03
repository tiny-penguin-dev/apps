# Astrotype: Wider space bar

Space gets more room: the emoji key (and our globe, on Home button phones) can move off
the bottom row into the guesses bar, or out of sight under a held `123`.

Gabriel, 3 Nov 2026: "I want more space for the actual spacebar key. Could we move it so
that maybe the emoji and the world buttons are on the top thing instead? ... One other
option is we could have it be an option that the user can select ... it would be
available only under the 1, 2, 3 menu."

## Product

Status: Draft

- **The problem:** since the emoji page (features/emoji) the bottom row is `123`,
  emoji, space, return, so space is about 186 pt on a 390 pt iPhone. On a Home button
  phone our globe sits there too and space drops to about 126 pt. Space is the key
  both thumbs hit most, and a short one gets missed.
- **Who wants it:** everyone; most of all people on smaller phones and people who rarely
  type emoji.
- **Basics or powerful:** the new default is basics (nothing to learn). Where the emoji
  key lives is a powerful setting, tucked into Appearance.
- **How it works (proposed):**
  - *A setting,* Settings → Appearance → "Emoji key", three choices:
    - **In the guesses bar** (the default): the emoji key sits at the left end of the
      bar, the row becomes `123`, space, return, and space is about 27% wider (237 pt
      on a 390 pt phone).
    - **On the bottom row:** today's row, for people who want it where Apple's is.
    - **Hold 123 only:** no emoji key; hold `123` and tap "Emoji" at the top of the
      keyboard panel. Space is as wide as in the bar option.
  - *Our globe, Home button phones only* (iPhone SE; iOS draws its own globe under the
    keyboard on every other iPhone): it follows the emoji key into the bar, at the
    bar's right end, after "Not it?". Space is then about 78% wider (224 pt). Apple
    asks keyboards to show a next-keyboard key on these phones (`needsInputModeSwitchKey`,
    App Review 4.4.1), so in "Hold 123 only" our globe stays on the row and only the
    emoji key goes.
  - *When there's no bar:* if "Guesses bar" is off, or the guesses sit in a column (wide
    screens and the split keyboard, where space is already wide), the "In the guesses
    bar" choice puts the keys back on the bottom row, so they never vanish by accident.
  - The numbers and symbols pages get the same bottom row as the letters page.
  - The held-`123` panel gains the "Emoji" button in every choice (it's a cheap way
    to reach the page), but only "Hold 123 only" relies on it.
- **What it changes:** `Layout.qwerty` (the bottom row without the emoji key), the
  guesses bar (`BarView`: a key at each end), the keyboard panel (`SettingsPanelView`: an Emoji button),
  `KeyboardSettings` (one new value, `emojiKey`), and the Appearance page. No stored
  value changes; the default moves the emoji key, so people see it in the bar after
  the update.
- **Scope:** this version: the three choices above. Later: nothing planned. Never:
  hiding our globe on a Home button phone.
- **What we measure:** nothing new (the extension sends no metrics).
- **Open questions** for Gabriel
  1. Default: in the bar (proposed), or keep the row as the default and make the bar
     and "Hold 123 only" opt-in?
  2. Is "Hold 123 only" worth having next to the bar option, or is the bar enough?

## Design

Status: Draft

- **Mockup:** `design/mockups/space-bar.html` (Artifact link:
  https://claude.ai/artifact/KbrM45mHqsnCDTf5UNYM4A). Pick an option and a phone; tap
  the emoji key, or hold `123` where it's gone. Space shows its width in points.
- **What changes:**

  | Screen | Before | After |
  |---|---|---|
  | Letters, Face ID phone | [today](design/screens/01-today.png) | [in the bar](design/screens/02-bar.png), [hold 123 only](design/screens/03-hold.png) |
  | Letters, Home button phone | [today](design/screens/07-today-se.png) | [in the bar](design/screens/05-bar-se.png), [hold 123 only](design/screens/06-hold-se.png) |
  | Keyboard panel (held `123`) | [today](../settings/design/screens/09-panel.png) | [with Emoji](design/screens/04-hold-panel.png) |

  Dark: [in the bar](design/screens/08-bar-dark.png).
- **The bar keys:** 40 pt wide, the full bar height (44 pt) to touch, the SF Symbol
  (`face.smiling`, `globe`) at 22 pt in `ink`, no key background, so they read as part
  of the bar rather than as keys. Pressed: a `keyDark` rounded fill. The guesses share
  what's left between them, as now. While "Not it?" is a field the emoji key hides
  (the field needs the room). On the emoji page the bar is hidden anyway.
- **The panel button:** a full-width card row at the top of the panel, `face.smiling`
  and "Emoji", 48 pt high. It closes the panel and opens the emoji page.
- **Setting copy:** Appearance → "Emoji key": "In the guesses bar", "On the bottom row",
  "Hold 123 only". Footnote: "Moving it off the row makes space wider."
- **Motion:** none new. Changing the setting relays the keys at once, like the height.
- **Sizes:** phone and small (Duo outer) as drawn. Wide (Duo inner) and split put the
  guesses in a column, so the keys stay on the row there in the bar option.
- **Accessibility:** the bar keys keep the labels "Emoji" and "Next keyboard" and a
  44 pt target. VoiceOver reads them before the guesses (left) and after (right).
