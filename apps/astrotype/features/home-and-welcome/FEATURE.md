# Astrotype: Home and welcome

Home gets a "Your keyboard" card where you pick a theme, effects and height without
digging into Settings, and first launch becomes one simple welcome wizard that sets the
keyboard up and teaches it in the same friendly, step-by-step style.

Gabriel, 8 Nov 2026: "Take some time to redesign the app itself. I think some of the
settings appearance things should be on the main section. And we should probably have
some sort of welcome configuration wizard same as when it teaches you how to use it. But
be it simple and approachable."

## Product

Status: Approved 2026-11-09 (Gabriel: "go ahead and build it")

- **The problem:**
  - The fun part of Astrotype, how the keyboard looks and feels, is three taps deep
    (Home → Settings → Appearance → Styling or Effects). Most people will never find it.
  - First launch is five separate screens with different shapes (Hello, Turn on,
    Languages, Full Access, Try it). Nothing in it lets you make the keyboard yours, and
    there is no way to see the lesson again later.
- **Who wants it:** everyone. Both are on the simple path.
- **How it works:**
  - **Home** keeps Your speed on top. Under it, a new **Your keyboard** card with a
    row of themes, a row of effects and a Height slider. The live keyboard itself is
    **docked at the bottom of Home, like a real keyboard** (Gabriel, 9 Nov 2026), so
    it's always there to tap while you pick. **Hide** slides it away and a small
    **Keyboard** button in the corner brings it back; Home remembers which way you left
    it. Changes apply right away, in every app. "More styling" opens the full Appearance
    page (your own themes, flow levels, guesses bar, haptics, split) as today.
  - **Learn and practice** get their own screen (Gabriel, 9 Nov 2026). The bottom of
    the Your speed card has two links into it: **Practice** (Speed practice, the three
    drills, Practice words, the week) and **Learn** (the two-thumb lesson again, and
    short tips). Each jumps to its half of the screen. Home then ends with Pro and
    Settings.
  - **Effects pick from a sideways row**, like the themes, not a stack of chips
    (Gabriel, 9 Nov 2026: the vertical list was hard to read). Each card plays its own
    effect on one little key, over and over, so you can tell them apart at a glance.
    The Appearance → Effects page's presets get the same row.
  - **Welcome wizard** on first launch: one screen shape for every step, with a progress
    bar, a short title, one thing to do and one big button. Steps:
    1. **Hello**: "Type with both thumbs." (as now)
    2. **Turn it on**: the three Settings steps, the chip flips to On by itself (as now)
    3. **Languages**: only on a phone with more than one language (as now)
    4. **Make it yours** (new): pick a theme and an effect, with the keyboard docked at the bottom to try them. Classic
       and Calm are picked to start. "You can change this any time on Home."
    5. **Try it**: the five words with thumb hints and Show me (as now), typed on the
       style you just picked
    6. **Keep your words**: the Full Access ask, now after Try it, when it already has
       words to keep. Then Home, with confetti.
  - Every step after Hello has **Skip** in the corner; "I'll do it later" on Turn it on
    still works. Skipping never loses anything already picked.
- **Pro:** everyone starts on the trial, so every theme and effect can be picked in the
  wizard and on Home. Pro ones carry the small PRO tag. When the trial ends, the keyboard
  falls back to Classic and Calm as it does today, and Home's card says so.
- **What it changes:** Home (new card, practice grouped), Settings → Appearance (same
  pages, now also reached from Home), the setup screens (one shared shape, a new step,
  Full Access moved after Try it). The held-123 panel on the keyboard doesn't change.
- **Scope:** in this version: the Home card, the wizard, Learn again. Later: picking a
  layout (split) in the wizard on the iPhone Duo. Never: a wizard that can't be skipped.

### What we measure

| Metric | What it tells us |
|---|---|
| `setup.step` (count, tag `step`: hello, turn_on, languages, style, try, sync, done) | Where people drop off in the wizard |
| `setup.style` (count, tags `theme`, `effects`, `changed`: yes/no) | Whether people make it theirs, and which looks they pick |
| `home.style_changed` (count, tag `part`: theme, effects, height) | Whether the Home card gets used |
| `lesson.replayed` (count) | Whether people want the lesson again |

`setup.keyboard_on`, `setup.full_access` and `onboarding.finished` stay as they are.

### Open questions

None. Gabriel liked the mockup as shown (9 Nov 2026), so: Your speed first, then Your
keyboard; Height stays on the card; Full Access comes after Try it. The Home header is
just "Astrotype" (Gabriel, 9 Nov 2026), not the "Both flippers, go." tagline.

- **Leaderboards** (PR #203, built in another thread): its rank chip sits in Your
  speed's card, which this redesign keeps as is, so the two fit together.

## Design

Status: Approved 2026-11-09 (Gabriel: "go ahead and build it")

- **Mockups:** `design/mockups/home-and-welcome.html` (Artifact: https://claude.ai/artifact/CYaxjuqLHErz1c2uJtQgsm) (tap through it; every button in the phone works)
- **What changes:**
  - **Home** (`screens/01-before-home.png` → `02-home.png`): the header becomes just "Astrotype"; Your speed stays.
    New Your keyboard card. Drills, Practice words and the week move to the new Learn and
    practice screen, linked from the bottom of Your speed. The old "Settings · Autospace, gestures, trails, sync" row becomes a plain
    Settings row at the bottom, next to Pro.
  - **Setup screens** (before: the app's `design/screens/01-hello.png` to `04-try.png`; after: `11-hello.png` to `17-keep-words.png`): Hello, Turn on, Languages,
    Keep your words and Try it all use one `WizardPage`, with the progress bar on top and
    Skip in the corner. Their words stay the same.
- **New screens:**
  - **Your keyboard card** (`02-home.png`, `03-home-dark.png`, `04-home-free.png`, `05-home-scrolled.png`): theme cards in a
    sideways row (Classic, Iceberg, Tuxedo, Krill, Midnight, Paper, Arcade, Bold, then
    your own), then effect cards in a second sideways row (Calm, Arcade, Glitch, Rainbow,
    Space, Zen, Sugar Rush, Off). Each `EffectCard` is the theme card's size, tinted in the
    effect's colour, with one key in the middle that the effect taps and swipes across
    every 1.6 s (the real Metal effect on a single key; a still frame under Reduce Motion
    or Low Power Mode, and only the cards on screen run). A Height slider. "More styling ›" at the bottom.
  - **Keyboard dock** (`02-home.png`, `08-home-kb-hidden.png`): the practice keyboard in
    the same glass frame as the real one (`KeyboardFrame`), pinned to the bottom of
    Home, with a grab handle, a line that shows what you type ("Type anything. It stays
    right here.") and a **Hide** button. Hidden, it leaves a **Keyboard** button in the
    corner. Home scrolls above it, so nothing is covered. On the wide screen it spans
    the bottom with the keys centred (`07-home-wide.png`).
  - **Make it yours** (`14-make-it-yours.png`, `18-style-dark.png`): the same card, bigger, as a wizard step.
  - **Learn and practice** (`09-learn-practice.png`): Practice (Speed practice, the three
    drills, Practice words), This week, then Learn (the two-thumb lesson, Tips). Opened from
    the two links at the bottom of Your speed (Practice shows the week's dots).
  - **The two-thumb lesson** from Learn opens Try it on its own (no progress bar, Done
    instead of Skip; `19-lesson.png`). **Tips** is a short list of cards (slide on
    space, swipe left on ⌫, hold a guess, the 123 panel).
- **Motion and copy:**
  - The dock slides up and down with a spring (fade under Reduce Motion).
  - The progress bar fills with a spring between steps; pages slide in from the right
    (fade under Reduce Motion), as now.
  - Picking a theme: the preview keys flip to the new colours with a small bounce, light
    haptic. Picking an effect plays it once on the preview by itself.
  - Copy: "Make it yours" / "Pick a look and a little sparkle. You can change it any
    time on Home." · Card: "Your keyboard" · Dock: "Type anything. It stays right here." / "Hide" / "Keyboard" · "More styling ›"
    · "Learn two thumbs again" / "The five-word lesson from the start." · Trial over on
    the card: "Pro looks are resting. Classic and Calm are on."
- **Design system:** uses `Card`, `SectionLabel`, `Chip`, `ProBadge`, `SettingsSlider`,
  `StylePreview`, and the theme card from Styling (moves to AstrotypeUI as `ThemeCard`).
  New: `WizardPage` (replaces `SetupPage`: progress, title, line, content, buttons) and
  `StepProgress` (the bar).
- **Sizes:** on the small phone the card's theme row scrolls sideways and the dock drops
  its typed line (`06-home-small.png`). On the wide Duo screen Home has two columns: Your
  speed, Pro and Settings on the left, Your keyboard on the right (`07-home-wide.png`); the
  wizard stays a centred 560-wide column with a bigger preview (`16-style-wide.png`).
- **Accessibility:** theme cards read "Iceberg theme, Pro, selected". The progress bar
  reads "Step 4 of 6". The docked keyboard is decorative to VoiceOver (its Hide/Keyboard buttons are not); picking reads the
  new name. Reduce Motion: no bounce, effects preview shows one still frame.

### Open questions

None beyond the Product ones.

## Build

Status: Approved 2026-11-09 (Gabriel: "go ahead and build it")

- **Approach:** app-only (no keyboard or package changes). Home's pieces go in a new
  `Astrotype/Home/` folder; the setup screens stay in `Onboarding/`.
- **Core pieces:**
  - `KeyboardDock` (Home's docked keyboard): a one-line `KeyboardField` whose input view
    is a `KeyboardSession`'s keys, so iOS raises and lowers them like any keyboard.
    `KeyboardField(focusesOnAppear: false)`, `KeyboardSession.unfocus()` and
    `onFocusChange` are the only changes to the session. Shown or hidden is kept in
    `@AppStorage("home.keyboardShown")`; the keys go down while another screen or a sheet
    is over Home.
  - `YourKeyboardCard` with `ThemeRow` (the Styling page's `ThemeCard`, now shared) and
    `EffectRow`/`EffectCard` (a `Canvas` in a `TimelineView`, paused under Reduce Motion
    and Low Power Mode; picking one plays a burst on the dock's real keys).
  - `LearnPracticeView` (+ `TipsView`), opened from two tiles under `SpeedCard`.
  - `WizardPage` + `StepProgress` replace `SetupPage`; `AppModel.Screen` gains `.style`
    and the order becomes hello → turnOn → languages → style → tryIt → sync → home.
- **Phases:**
  1. **Home** (one PR): header "Astrotype", Your keyboard card, the dock, effect cards,
     Learn and practice, Tips, the lesson from Learn. *Done when* Home shows the card and
     the keys at the bottom, Hide and Keyboard work, and the tiles open Learn and practice.
  2. **Welcome wizard** (one PR): `WizardPage`/`StepProgress` on every setup screen, the
     Make it yours step, Full Access after Try it, the `setup.step`/`setup.style`
     metrics, and the docs folded into `PRODUCT.md`/`DESIGN.md`. *Done when* a fresh
     install walks the six steps with the progress bar and lands on Home.
- **Risks:** the dock's keys and a pushed screen's own keys swapping on push and pop;
  checked on TestFlight. The effect cards are drawn sketches, not the Metal effects
  themselves (eight live keyboards would cost too much); the real one plays on the dock.
- **Metrics:** `home.style_changed` (theme, effects) and `lesson.replayed` in phase 1;
  `setup.step` and `setup.style` in phase 2.
- **Last step:** fold this feature into the app's `PRODUCT.md` and `DESIGN.md`.
