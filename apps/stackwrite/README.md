# StackWrite

An iPhone keyboard for typing fast with two thumbs: each thumb taps or swipes a few
letters at a time, both at once, and the keyboard turns the pieces into the word you meant.
A clean-room rebuild of Nintype for the App Store.

- [PRODUCT.md](PRODUCT.md): what v2 is and why (approved)
- [DESIGN.md](DESIGN.md): screens, the keyboard, motion and copy, with a
  [mockup](design/mockups/stackwrite.html) whose keyboard you can try

v1 was a handwriting keyboard (letters written on top of each other). It is still in this
folder and may come back as an input mode; the sections below describe it.

## Status

- **v2, Phase 1 (building):** the keyboard extension types plain taps in any app, the
  design system and the shared key surface are in `ios/StackWriteKit`, Sentry is wired.
  Phases in `BUILD.md`.
- **v1 model prototype: done** (`ml/`), kept for the practice-session loop. Trained on
  synthetic phrases only: 98.7% of 1–4 word phrases come out exactly right.
- **v1 handwriting pad:** in the code behind `Flags.handwritingPad`, not shown.

## Commands

Run `make` in this folder to see them: set up, download recordings, retrain and ship, score,
test, build.

## Layout

```
PRODUCT.md the v2 product definition (two-thumb typing), DESIGN.md its design, BUILD.md the build plan
BRIEF.md   v1 build plan, plus the exact contracts the Swift code must match
SAMPLES.md the recorded-sample format shared by the app and the training scripts
CLAUDE.md  how to work on this app
ml/        Python prototype: data synthesis, training, decoder, Core ML export
ios/       Xcode project: the app, the keyboard extension and the StackWriteKit package
```

![Synthetic training samples](ml/out/samples.png)
