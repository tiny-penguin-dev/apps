# CLAUDE.md: StackWrite

**Read `BRIEF.md` first.** It covers the idea, what exists, the exact feature, model and
decoder contracts, the phased build plan with "done when" checks, and the open questions
to ask Gabriel before Phase 3.

## Layout

- `ml/`: Python reference implementation. It's the source of truth for features
  (`phrases.featurize_strokes`), the model (`model.ConvStrokeNet`, 9 features in, blank +
  a–z + space out) and the decoder (`decode_phrase.beam_search`). The single-word versions
  (`synth.featurize`, `decode.py`, `train.py`, `finetune.py`) predate finger lifts.
- `ml/export/`: what the iOS side consumes. Rebuild `lexicon.tsv` and `golden.json` with `python3 make_golden.py`.
  - `StackWrite.mlpackage`: the Core ML model
  - `lexicon.tsv`: the word list
  - `golden.json`: parity test cases
- `ios/`: the Xcode project. Right now it's a skeleton app that only shows its name and
  version, used to prove the TestFlight pipeline.
  - `StackWrite.xcodeproj`: one app target, `StackWrite`, with a shared scheme
  - `StackWrite/`: app sources and assets (a synchronized folder, so new files are picked
    up without editing the project)
    - `Try/`: "Try the keyboard": a text view whose `inputView` is the StackWrite pad.
      `KeyboardController` holds the typing logic behind a `TextTarget` protocol shaped
      like `UITextDocumentProxy`, so the keyboard extension can reuse it.
    - `Train/`: the training screen: prompts 1–4 words and saves their strokes as one sample
    - `Shared/`: the writing pad, model loading, sample storage and the CloudKit upload
      (`SampleUploader`, off until the user turns it on)
    - `Model/`: copies of `ml/export/StackWrite.mlpackage` (as `StrokeModel.mlpackage`)
      and `lexicon.tsv`. Copy them over after `export.py` (see Python below).
  - `StackWriteKit/`: local Swift package shared by the app and (later) the keyboard:
    the sample format (`StrokeSample`, see `SAMPLES.md`), `Recording`, `Features.featurize`,
    `Lexicon` (flat-array trie), `PhraseDecoder` (beam search) and `Recognizer` (Core ML).
    Its tests replay `ml/export/golden.json`.
  - `Config/`: `StackWrite.xcconfig` (bundle ID `com.tinypenguin.stackwrite`, version,
    display name), `Project.xcconfig`, `Info.plist`, `StackWrite.entitlements` (iCloud
    container `iCloud.com.tinypenguin.stackwrite`, CloudKit)
- `cloudkit/`: the CloudKit schema for uploaded samples and the one-time console setup, `testflight.json` (TestFlight
    testers, synced on every upload; see `docs/ios-release.md`)
  - Still to add: the keyboard extension target (`com.tinypenguin.stackwrite.keyboard`)

  Keep `StackWriteKit` inside this app. Don't move it to the repo's `packages/` unless a
  second app needs it.

## iOS (ios/)

```bash
cd ios
xcodebuild build -project StackWrite.xcodeproj -scheme StackWrite \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Package tests (featurize and decoder also run on Linux with a Swift toolchain; the
Core ML test needs macOS):

```bash
swift test --package-path ios/StackWriteKit
```

CI is `.github/workflows/stackwrite-ios.yml`. It runs the package tests, then builds. PRs build; pushes to `main` also upload to
TestFlight. See `docs/ios-release.md` at the repo root.

## Python (ml/)

```bash
cd ml
pip install -r requirements.txt
python3 viz.py                                   # render sample synthetic words → out/samples.png
python3 evaluate.py --model runs/final.pt --sets data/test_all.npz   # needs data built first
python3 train_phrases.py --init runs/final.pt --out runs/phrase.pt --minutes 60   # Mac GPU, ~1 h
python3 eval_phrases.py runs/phrase.pt --n 300 [--tune]          # word error rate, word breaks
python3 export.py --model runs/phrase.pt --out export/StackWrite
python3 make_golden.py --model runs/phrase.pt                    # Swift parity cases
cp -R export/StackWrite.mlpackage ../ios/StackWrite/Model/StrokeModel.mlpackage  # after rm -rf the old one
python3 download_samples.py                                      # uploaded samples → samples/cloud
python3 eval_real.py samples/cloud --model runs/phrase.pt        # how it reads recorded phrases
python3 finetune_phrases.py samples/cloud [--ship]               # fine-tune on them (+ copy into the app)
```

### Retraining on recorded samples

`ml/train_and_ship.py` does the whole loop: download samples, fine-tune `ml/models/base.pt`
(the synthetic-only phrase model) on all of them, score it against the model in the app
(`ml/models/shipped.pt`) on held-back sessions, and if it's better, export it into the app
and update `models/shipped.pt` and `models/shipped.json`. Two ways to run it:

- **Mac (now):** `ml/train_and_ship.sh [--minutes 15]` from the main checkout on Gabriel's
  Mac. It pushes to main itself, which builds and uploads to TestFlight.
- **GitHub button (later, off for now):** Actions → "StackWrite train" →
  Run workflow (`stackwrite-train.yml`) runs the same on a dedicated Mac registered as a
  self-hosted runner with the label `stackwrite`, commits to main and starts the
  TestFlight build. Turn it on by setting the repo variable `STACKWRITE_TRAINER` to `on`.
  The runner uses the iCloud key in `~/.config/stackwrite`, or the repo secrets
  `CLOUDKIT_KEY_ID` and `CLOUDKIT_PRIVATE_KEY` if set.

See `ml/README.md` for building data, training and personalizing. `data/` and
intermediate `runs/` are gitignored. Only `runs/final.pt` and the logs are committed;
`runs/phrase.pt` lives on Gabriel's Mac. `finetune_phrases.py` trains on recorded phrases
(v2) and the older one-word recordings (v1) mixed with synthetic phrases; `finetune.py` is
for the old one-stroke model.

## Rules

- If you change `featurize`, the model's input/output, or the decoder in Python, update
  the Swift port, `BRIEF.md`, and regenerate `export/golden.json` in the same change.
- When you retrain, re-export the Core ML model and regenerate `golden.json` so the Swift
  parity tests keep passing.
- `train.py` picks cuda, then the Apple GPU (`mps`), then CPU (`--device` to force one).
  CTC loss always runs on the CPU because MPS doesn't implement it.
- Recorded samples use the format in `SAMPLES.md`. Change it in `StrokeSample` and
  `ml/samples.py` together, and bump `version` if a field changes meaning.
- Keep recognition fully on-device. The keyboard must work without Full Access.
- Keep this file up to date as the iOS project takes shape (build, run and test commands).
