# StackWrite

An iOS keyboard for typing without looking. You write each letter on top of the last one in
the same spot, lifting your finger whenever you like. An on-device model and a dictionary
turn the strokes into words and work out where one word ends and the next begins.

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
BRIEF.md   build plan, plus the exact contracts the Swift code must match
SAMPLES.md the recorded-sample format shared by the app and the training scripts
CLAUDE.md  how to work on this app
ml/        Python prototype: data synthesis, training, decoder, Core ML export
ios/       Xcode project: the app (keyboard extension comes later)
```

![Synthetic training samples](ml/out/samples.png)
