# Tiny Penguin look and feel

Every Tiny Penguin app should feel like it comes from the same small, happy studio.
This is the shared bar. Each app's `DESIGN.md` says how it applies it.

## The feeling

- **Friendly.** The app is on your side. It never scolds, guilts or nags.
- **Cute.** Soft shapes, round corners, warm colors, small characters with personality.
- **Alive.** Lots of animation: things bounce, wiggle, settle and react to your touch.
  Motion should make the app feel playful, never slow you down.
- **Fun.** Little surprises and rewards: a celebration when you finish something, a
  sleepy penguin when there's nothing to show.
- **A bit penguin.** Each app has a penguin connection: a mascot, a name, a sound, an
  icon or a small detail. Light touch, not a costume.

## Simple first, powerful when you want it

- The basics take one or two taps and need no explanation.
- Powerful options exist, but they live one level down (a "More options" row, a detail
  screen), so they never crowd the main screen.
- Good defaults beat settings. Add a setting only when people really disagree.

## Words

- Short, warm and plain. Talk like a kind friend, not a system.
- A little playful is good ("Rise and waddle!"). Puns: sometimes, never in errors.
- Errors say what happened and what to do next, without blame.
- Never use guilt or fake urgency to keep people engaged.

## Motion

- Use springy, physical motion (SwiftUI springs), not linear fades.
- Every main action gets feedback: a bounce, a haptic, a small sound where it fits.
- Respect Reduce Motion: swap big movement for fades, keep the meaning.
- Animations must never block the user; they can always tap through.

## Look

- Rounded type (SF Pro Rounded), generous spacing, big tap targets.
- Bright but soft color, with a full dark mode. Each app picks its own main color.
- Characters and illustrations are simple and rounded, made with SwiftUI shapes, SF
  Symbols, or a small set of drawn assets, so they can animate.
- Works with Dynamic Type and VoiceOver from day one.
- Fits every size, from the smallest phone to the open iPhone Duo, and keeps its place
  when the screen changes (`building.md`).
- Built from one design system per app, so every screen uses the same pieces
  (`building.md`).
