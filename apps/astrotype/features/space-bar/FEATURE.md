# Astrotype: Wider space bar

Where our keyboard shows its own globe key, the globe moves into the guesses bar, so
space gets the room.

Gabriel, 3 Nov 2026: "I want more space for the actual spacebar key." Then, after a
first plan that moved the emoji key: "Let's keep the emoji button on the bottom near
the 1, 2, 3 ... move the globe button by default to the top left. And then if the user
hides that bar, it goes to next to the 1, 2, 3 as right now." And: "No setting exists
to remove it or move it."

## Product

Status: Approved 2026-11-03 (Gabriel: "Merge")

- **The problem:** where iOS draws no globe of its own (Home button iPhones, and the
  iPhone Duo, Gabriel, 3 Nov 2026), our bottom row is `123`, globe, emoji, space,
  return, so space is short (about 126 pt on a 375 pt phone).
- **Who wants it:** everyone on those phones. Nothing changes where iOS draws the globe
  (Face ID iPhones), since our globe doesn't show there.
- **Basics or powerful:** basics. No setting.
- **How it works:**
  - Whenever our keyboard shows a globe (`needsInputModeSwitchKey`), it sits at the left
    end of the guesses bar, in every bar state. The row becomes `123`, emoji, space,
    return; space is about 39% wider (175 pt on a 375 pt phone).
  - When there's no bar on top to hold it (Settings "Guesses bar" is off, or the
    guesses sit in a column on a wide or split keyboard), the globe goes back on the
    row next to `123`, as before.
  - The emoji key stays on the row next to `123` everywhere. No setting moves or hides
    either key.
  - The numbers and symbols pages follow the letters page.
- **What it changes:** `KeyboardView` (where the globe goes), `BarView` (a globe button
  at the leading end). `Layout` is unchanged: its `globe` flag now means "on the row".
- **Scope:** this version: the above. Never: hiding the globe (Apple asks keyboards to
  show one where iOS doesn't).
- **What we measure:** nothing new (the extension sends no metrics).

## Design

Status: Approved 2026-11-03 (Gabriel: "Merge")

- **Mockup:** `design/mockups/space-bar.html` (Artifact link:
  https://claude.ai/artifact/KbrM45mHqsnCDTf5UNYM4A).

  | Screen | Before | After |
  |---|---|---|
  | Letters, phone with our globe | [today](design/screens/01-today.png) | [globe in the bar](design/screens/02-globe-in-bar.png), [dark](design/screens/05-globe-in-bar-dark.png) |
  | Letters, guesses bar off | [today](design/screens/01-today.png) | [same as today](design/screens/03-bar-off.png) |
  | Letters, Face ID iPhone | [no change](design/screens/04-face-id.png) | |

- **The bar's globe:** 44 pt wide, the bar's full height to touch, SF Symbol `globe` at
  20 pt in `keyInk`, no key background. The guesses, FIX, "Not it?" and its field
  share what's left to its right. The guesses bar is being redesigned
  (features/guesses-bar) with a button slot at each end; the globe takes the left slot
  there.
- **Accessibility:** "Next keyboard", read first in the bar.

## Build

Status: Approved 2026-11-03 (built with the design, Gabriel: "Merge")

- [x] `BarView.showsGlobe` and `onGlobe`: the button at the leading end.
- [x] `KeyboardView`: the globe goes in the bar when the bar is on top, else on the row
  (`rowGlobe(_:)`); the bar's globe calls `onSystemKey(.globe)` like the key did.
