# CLAUDE.md: StackWrite

**Read `BRIEF.md` first.** It covers the idea, what exists, the exact feature, model and
decoder contracts, the phased build plan with "done when" checks, and the open questions
to ask Gabriel before Phase 3.

## Layout

- `ml/`: Python reference implementation. It's the source of truth for features
  (`synth.featurize`), the model (`model.ConvStrokeNet`) and the decoder
  (`decode.beam_search`).
- `ml/export/`: what the iOS side consumes. Rebuild `lexicon.tsv` and `golden.json` with `python3 make_golden.py`.
  - `StackWrite.mlpackage`: the Core ML model
  - `lexicon.tsv`: the word list
  - `golden.json`: parity test cases
- `ios/`: the Xcode project. Right now it's a skeleton app that only shows its name and
  version, used to prove the TestFlight pipeline.
  - `StackWrite.xcodeproj`: one app target, `StackWrite`, with a shared scheme
  - `StackWrite/`: app sources and assets (a synchronized folder, so new files are picked
    up without editing the project)
  - `Config/`: `StackWrite.xcconfig` (bundle ID `com.tinypenguin.stackwrite`, version,
    display name), `Project.xcconfig`, `Info.plist`
  - Still to add: the keyboard extension target (`com.tinypenguin.stackwrite.keyboard`)
    and a local Swift package (e.g. `ios/StackWriteKit`) for featurize, inference and
    decoder, shared by both targets

  Keep that package inside this app. Don't move it to the repo's `packages/` unless a
  second app needs it.

## iOS (ios/)

```bash
cd ios
xcodebuild build -project StackWrite.xcodeproj -scheme StackWrite \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

CI is `.github/workflows/stackwrite-ios.yml`. PRs build; pushes to `main` also upload to
TestFlight. See `docs/ios-release.md` at the repo root.

## Python (ml/)

```bash
cd ml
pip install -r requirements.txt
python3 viz.py                                   # render sample synthetic words → out/samples.png
python3 evaluate.py --model runs/final.pt --sets data/test_all.npz   # needs data built first
python3 export.py --model runs/final.pt --out export/StackWrite
```

See `ml/README.md` for building data, training and personalizing. `data/` and
intermediate `runs/` are gitignored. Only `runs/final.pt` and the logs are committed.

## Rules

- If you change `featurize`, the model's input/output, or the decoder in Python, update
  the Swift port, `BRIEF.md`, and regenerate `export/golden.json` in the same change.
- When you retrain, re-export the Core ML model and regenerate `golden.json` so the Swift
  parity tests keep passing.
- Training currently runs on CPU only. Add `mps` support before doing long runs on a Mac.
- Keep recognition fully on-device. The keyboard must work without Full Access.
- Keep this file up to date as the iOS project takes shape (build, run and test commands).
