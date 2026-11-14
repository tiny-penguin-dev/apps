# Astrotype: Typing setup

A new welcome step, "How it types", where you pick Autocorrect and Autospace, each with
our recommended choice and a short reason, so new people start on the setup that types
best with two thumbs and know why.

Gabriel, 14 Nov 2026: "In the initial setup, you can configure this specific setting,
just the always match, and maybe some basic settings like auto space. And we should have
a recommendation of which one to use. [...] Recommend always, but explain why. [...] it
might mistake some words at the beginning because they don't exist in their library, but
you will be able to teach it [...] So over time, it will get much better. [...] Same for
auto space being off. [...] that way you can dual type better, and also correct words
easier. But it's an option for people if they want it."

## Product

Status: Draft

- **The problem:** Autocorrect (Always / Most of the time / Only when sure / Never, PR
  #237) and Autospace shape how Astrotype feels more than anything else, but they sit in
  Typing, which new people never open. Today a new keyboard starts on "Most of the time"
  with Autospace on, which isn't what we'd recommend.
- **Who wants it:** everyone. It's on the simple path, one screen in the welcome wizard.
- **How it works:**
  - A new wizard step, **How it types**, after Make it yours and before Try it, so the
    lesson already types the way you just chose. The wizard goes from 6 steps to 7.
  - Two groups of choices, each with our pick ticked and tagged **Recommended**:
    - **Autocorrect**: the four levels, as in Typing. Recommended: **Always**. Why: type
      fast and loose and it lands on the word you meant. At first it may change a word it
      doesn't know yet, like a name; hold that word on the bar to teach it, or block one
      you never want. It learns your words, so it keeps getting better.
    - **Autospace**: Off or On. Recommended: **Off**. Why: you can start a word with one
      thumb and finish it with the other, or stop to fix it, and nothing jumps ahead of
      you. Turn it on if you'd rather not press space after a swipe; it stays out of the way while you tap (PR #240).
  - "Sounds good" moves on. Skip keeps what's ticked, so skipping gets our picks too.
  - **Run setup again** (Settings) shows your current choices ticked, with the same
    Recommended tags.
  - **New defaults:** a fresh install starts on Always and Autospace off, so someone who
    skips the whole wizard (or "I'll do it later") gets the same. People who already
    have the app keep what they have. The Autospace wait (0.9 s) and Fix missed spaces
    (on) aren't on this step; they stay in Typing.
- **What it changes:** the welcome wizard (one more step), `KeyboardSettings`' defaults
  for new installs. Typing in Settings doesn't change.
- **Scope:** in this version: the step and the new defaults. Later: other basics if we
  find people change them a lot (Next words, the guesses bar). Never: a step that can't
  be skipped.

### What we measure

| Metric | What it tells us |
|---|---|
| `setup.step` with the new tag value `typing` | Drop-off on the new step |
| `setup.typing` (count, tags `autocorrect`: always/mostOfTheTime/whenSure/never, `autospace`: on/off, `changed`: yes/no) | How many keep our picks, and what the rest choose |

### Open questions

1. **New defaults:** OK to make Always and Autospace off the defaults for new installs
   (my recommendation), or keep today's defaults and only tick our picks on this step?

## Design

Status: Draft

- **Mockups:** `design/mockups/typing-setup.html` (Artifact: https://claude.ai/artifact/Bxp26oVfYyBk3mMdjYJBbL) (tap the choices and the buttons; size and light/dark switches on the side)
- **What changes:** Make it yours' "Looks good" now goes to How it types
  (`screens/01-before-style.png`), and the progress bar counts 7 steps.
- **New screen, How it types** (`screens/02-typing.png`, scrolled `07-typing-scrolled.png`):
  - Title "How it types", line "Two settings shape how Astrotype feels. We've ticked the
    ones we like best. You can change them any time in Typing."
  - **Autocorrect** label, a group of four rows (title and the level's line, the same
    words as Typing), a tick on the picked one, a **RECOMMENDED** tag on Always.
  - A **Why we pick Always** note under it (pale ice card with an info dot).
  - **Autospace** label, two rows: Off ("You press space when the word looks right",
    RECOMMENDED) and On ("Adds a space after each swiped word. Tapping? It stays out
    of your way until you swipe."), matching how autospace works since PR #240: tapped
    words get no space until you swipe one.
  - A **Why we pick Off** note.
  - "Sounds good" at the bottom; Skip in the corner, as on every step. A thin line above
    the button while there's more to scroll.
  - Picking another option only moves the tick; the reasons stay (`04-typing-other.png`).
- **Motion and copy:** the tick pops in with the app's spring and a light haptic, as
  pickers do elsewhere (fade under Reduce Motion). Copy as above; the Why notes:
  - "Type fast and loose, and it lands on the word you meant. At first it may change a
    word it doesn't know yet, like a name. Hold that word on the bar to teach it, or
    block one you never want. It learns your words as you go, so it keeps getting better."
  - "You can start a word with one thumb and finish it with the other, or stop to fix
    it, and nothing jumps ahead of you. Space becomes part of the rhythm. Turn it on if
    you'd rather not press it after a swipe. It won't get in the way while you tap."
- **Design system:** uses `WizardPage`, `StepProgress`, `SectionLabel`, the settings
  group card and `Theme` tokens. New: `ChoiceRow` (a row in a pick-one group: tick,
  title, line, optional Recommended tag) and `WhyNote` (the ice note with an info dot).
  Both go in AstrotypeUI; Typing's Autocorrect menu could use `ChoiceRow` later.
- **Sizes:** on the small phone (`05-typing-small.png`) the page scrolls and the button
  stays pinned. On the wide Duo screen (`06-typing-wide.png`) it's the wizard's centred
  560-wide column; nearly everything fits without scrolling.
- **Dark:** `03-typing-dark.png`.
- **Accessibility:** each group is a radio group ("Autocorrect, Always, recommended,
  selected, 1 of 4"); the Why notes read after their group. Rows grow with Dynamic Type
  and the tag wraps under the title.

### Open questions

None beyond the Product one.

## Build

Status: Not started
