# StackWrite

An iPhone keyboard for typing fast with two thumbs: each thumb taps or swipes a few
letters at a time, both at once, and the keyboard turns the pieces into the word you meant.
A clean-room rebuild of Nintype for the App Store. See [`PRODUCT.md`](PRODUCT.md) for
what v2 is and why.

v1 was a handwriting keyboard (letters written on top of each other). It is still in this
folder and may come back as an input mode; the sections below describe it.

## Status

- **Model prototype: done** (`ml/`). Trained on synthetic phrases only: 98.7% of 1–4 word
  phrases come out exactly right, word breaks included. Real writing is the next test.
- **iOS app: in-app keyboard and training.** "Try the keyboard" types into a text field
  with the StackWrite pad, all on device. "Write training phrases" records labeled samples
  (format in `SAMPLES.md`) and exports them as a zip. No keyboard extension yet. See
  `BRIEF.md` for the build plan.
- **Training on real writing:** `ml/finetune.py` takes exported samples, fine-tunes the
  model (Apple GPU on a Mac), scores it on held-back words and can copy it into the app.

## Commands

Run `make` in this folder to see them: set up, download recordings, retrain and ship, score,
test, build.

## Layout

```
PRODUCT.md the v2 product definition (two-thumb typing); DESIGN.md and BUILD.md follow once approved
BRIEF.md   v1 build plan, plus the exact contracts the Swift code must match
SAMPLES.md the recorded-sample format shared by the app and the training scripts
CLAUDE.md  how to work on this app
ml/        Python prototype: data synthesis, training, decoder, Core ML export
ios/       Xcode project: the app (keyboard extension comes later)
```

![Synthetic training samples](ml/out/samples.png)
