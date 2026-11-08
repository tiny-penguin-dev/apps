# Astrotype: Home and welcome

Home gets a "Your keyboard" card where you pick a theme, effects and height without
digging into Settings, and first launch becomes one simple welcome wizard that sets the
keyboard up and teaches it in the same friendly, step-by-step style.

Gabriel, 8 Nov 2026: "Take some time to redesign the app itself. I think some of the
settings appearance things should be on the main section. And we should probably have
some sort of welcome configuration wizard same as when it teaches you how to use it. But
be it simple and approachable."

## Product

Status: Draft

- **The problem:**
  - The fun part of Astrotype, how the keyboard looks and feels, is three taps deep
    (Home → Settings → Appearance → Styling or Effects). Most people will never find it.
  - First launch is five separate screens with different shapes (Hello, Turn on,
    Languages, Full Access, Try it). Nothing in it lets you make the keyboard yours, and
    there is no way to see the lesson again later.
- **Who wants it:** everyone. Both are on the simple path.
- **How it works:**
  - **Home** keeps Your speed on top. Under it, a new **Your keyboard** card: a live
    keyboard you can tap, a row of themes, a row of effects, and a Height slider.
    Changes apply right away, in every app. "More styling" opens the full Appearance
    page (your own themes, flow levels, guesses bar, haptics, split) as today.
  - Below that, **Practice** (Speed practice, the three drills, Practice words and the
    week dots), then a new **Learn two thumbs again** row that replays the lesson, then
    Pro and Settings.
  - **Welcome wizard** on first launch: one screen shape for every step, with a progress
    bar, a short title, one thing to do and one big button. Steps:
    1. **Hello**: "Type with both thumbs." (as now)
    2. **Turn it on**: the three Settings steps, the chip flips to On by itself (as now)
    3. **Languages**: only on a phone with more than one language (as now)
    4. **Make it yours** (new): pick a theme and an effect on a live keyboard. Classic
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

1. **Order on Home:** Your speed first, then Your keyboard (my pick, speed is the main
   game), or Your keyboard first?
2. **Height on Home:** keep it on the card, or only themes and effects?
3. **Full Access after Try it** (my pick, it reads better once it has learned words), or
   keep it before as today?

## Design

Status: Draft

- **Mockups:** `design/mockups/home-and-welcome.html` (tap through it; every button in the phone works)
- **What changes:**
  - **Home** (`screens/01-before-home.png` → `02-home.png`): header and Your speed stay.
    New Your keyboard card. Drills, Practice words and the week move into one Practice
    section. The old "Settings · Autospace, gestures, trails, sync" row becomes a plain
    Settings row at the bottom, next to Pro.
  - **Setup screens** (before: the app's `design/screens/01-hello.png` to `04-try.png`; after: `11-hello.png` to `17-keep-words.png`): Hello, Turn on, Languages,
    Keep your words and Try it all use one `WizardPage`, with the progress bar on top and
    Skip in the corner. Their words stay the same.
- **New screens:**
  - **Your keyboard card** (`02-home.png`, `03-home-dark.png`, `04-home-free.png`, `05-home-scrolled.png`): a live keyboard (the same `StylePreview`
    the Styling page uses), tap it to see the effect. Under it, theme cards in a
    sideways row (Classic, Iceberg, Tuxedo, Krill, Midnight, Paper, Arcade, Bold, then
    your own) and effect chips (Calm, Arcade, Glitch, Rainbow, Space, Zen, Sugar Rush,
    Off). A Height slider. "More styling ›" at the bottom.
  - **Make it yours** (`14-make-it-yours.png`, `18-style-dark.png`): the same card, bigger, as a wizard step.
  - **Learn two thumbs again**: a row in Practice that opens Try it on its own (no
    progress bar, Done instead of Skip; `19-lesson.png`).
- **Motion and copy:**
  - The progress bar fills with a spring between steps; pages slide in from the right
    (fade under Reduce Motion), as now.
  - Picking a theme: the preview keys flip to the new colours with a small bounce, light
    haptic. Picking an effect plays it once on the preview by itself.
  - Copy: "Make it yours" / "Pick a look and a little sparkle. You can change it any
    time on Home." · Card: "Your keyboard" / "Tap the keys to try it." · "More styling ›"
    · "Learn two thumbs again" / "The five-word lesson from the start." · Trial over on
    the card: "Pro looks are resting. Classic and Calm are on."
- **Design system:** uses `Card`, `SectionLabel`, `Chip`, `ProBadge`, `SettingsSlider`,
  `StylePreview`, and the theme card from Styling (moves to AstrotypeUI as `ThemeCard`).
  New: `WizardPage` (replaces `SetupPage`: progress, title, line, content, buttons) and
  `StepProgress` (the bar).
- **Sizes:** on the small phone the card's theme row scrolls sideways and the preview
  gets shorter (`06-home-small.png`). On the wide Duo screen Home has two columns: Your
  speed and Your keyboard on the left, Practice on the right (`07-home-wide.png`); the
  wizard stays a centred 560-wide column with a bigger preview (`16-style-wide.png`).
- **Accessibility:** theme cards read "Iceberg theme, Pro, selected". The progress bar
  reads "Step 4 of 6". The live preview is decorative to VoiceOver; picking reads the
  new name. Reduce Motion: no bounce, effects preview shows one still frame.

### Open questions

None beyond the Product ones.

## Build

Status: Not started
