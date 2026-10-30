# StackWrite

An iOS keyboard for typing without looking. You write a whole word as one finger stroke,
with each letter stacked on top of the last one in the same spot. An on-device model and a
dictionary turn that stroke into a word.

## Status

- **Model prototype: done** (`ml/`). Trained on synthetic data only. It's 99.9% accurate on
  the letter styles it has seen, but needs about 50+ of your own sample words to read a new
  style well.
- **iOS app and keyboard: not started.** See `BRIEF.md` for the build plan.

## Layout

```
BRIEF.md   build plan, plus the exact contracts the Swift code must match
CLAUDE.md  how to work on this app
ml/        Python prototype: data synthesis, training, decoder, Core ML export
ios/       (to be created) Xcode project: capture app + keyboard extension
```

![Synthetic training samples](ml/out/samples.png)
