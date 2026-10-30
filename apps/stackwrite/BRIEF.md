# StackWrite — build brief for the iOS app

You're picking up a prototype for an iOS handwriting keyboard. This brief covers what
exists, the exact contracts the Swift side has to match, and the build plan. The Python
prototype in `ml/` is the reference implementation. When this brief and the code
disagree, the code is right.

## The idea

An iOS keyboard you can use **without looking**. You write a whole word as **one finger
stroke**, with **every letter stacked on top of the previous one in the same spot**. Lifting
the finger ends the word. A small on-device model reads the motion, and a dictionary
decoder picks the most likely word, so sloppy letters still come out right.

Example: writing "hello" means drawing h, then e on top of it, then l, l, o, all in one
continuous stroke in roughly the same square.

## What already exists (`ml/`)

Paths in this table are relative to `ml/`.

| Path | What it is |
|---|---|
| `letters.py`, `synth.py` | Synthetic data: letter shapes (3 styles), stacking, connectors, augmentation, **feature extraction** (`featurize`) |
| `model.py` | `ConvStrokeNet`: all-conv 1-D CNN, ~660k params, CTC over blank + a–z |
| `decode.py` | Dictionary-constrained CTC prefix beam search + word-frequency prior |
| `train.py`, `data.py`, `evaluate.py` | Dataset building, time-budgeted training (CPU only), scoring |
| `runs/final.pt` | Trained weights |
| `export/StackWrite.mlpackage` | Core ML model (fp16, mlprogram, iOS 16+). **Never run on a device yet.** |
| `export/StackWrite.onnx` | Same model; matches PyTorch to ~4e-5 |
| `export/lexicon.tsv` | 40,000 words with frequencies (`word<TAB>freq`), the decoder's dictionary |
| `export/golden.json` | 6 test words with raw path, expected features, expected logprobs and expected top words, **for Swift parity tests** |
| `README.md`, `results/` | Commands and accuracy results |
| `out/samples.png` | Picture of the synthetic training data |

### Current accuracy (synthetic data only)

- Letter styles seen in training: 99.9% top-1 word, 100% top-3
- A completely unseen style: 7.8% top-1
- Same unseen style after fine-tuning on 50 sample words: 87.4% (300 words: 96.3%)

**Takeaway:** personalization on real samples matters a lot. Nothing has been tested on
real finger input yet.

## Contracts the Swift port must match exactly

### 1. Coordinates ("box units")
- The writing pad is a square. Box units go from 0 to 1 on both axes, with **(0,0) at the
  bottom-left and y pointing up**.
- On iOS (y points down): `x = touch.x / side`, `y = 1 - touch.y / side`.
- If the pad isn't square, normalize by its height and center x:
  `x = (touch.x - (w - h)/2) / h`.
- Training data puts words roughly in the middle, with an x-height of about 0.28–0.5 of the
  box and the baseline around y ≈ 0.25–0.4. Position is a model input, so the pad's size
  and shape affect results.

### 2. Features (`synth.featurize`), one stroke → `[T, 5]` Float32
1. **Resample** by arc length every `STEP = 0.04` box units: compute the cumulative length
   `s` along the raw path, take sample positions `t = 0, 0.04, 0.08, …` strictly less than
   the total length, and linearly interpolate x and y at each.
   - If the total length is under 0.04, use just `[first, last]`.
   - If there are fewer than 3 points, append `last + 0.001` and `last + 0.002` (both coordinates).
2. `ang[i] = atan2(p[i+1].y - p[i].y, p[i+1].x - p[i].x)`, then repeat the last angle so
   `ang` has length T.
3. `turn[0] = 0`, `turn[i] = ang[i] - ang[i-1]`, wrapped into [-π, π).
4. Each row is `[x - 0.5, y - 0.5, cos(ang), sin(ang), turn / π]`.

Timestamps aren't used yet, but the capture app should still record them (see below).

### 3. Model I/O (Core ML)
- Input `strokes`: shape `(1, T, 5)` Float32, with `16 ≤ T ≤ 2048`. Inputs shorter than 16
  are untested. Pick a fix (pad or resample finer) and test it.
- Output `logprobs`: shape `(1, ceil(T/4), 27)`, log-softmax. Index 0 is the CTC blank;
  1–26 are a–z.

### 4. Decoder (`decode.beam_search`), port to Swift
- A trie built from `lexicon.tsv`. Each word's prior is `log(freq / maxFreq)`.
- CTC prefix beam search, keeping separate blank and non-blank probabilities per prefix,
  and **only extending prefixes along trie edges**:
  - A repeated letter (as in "ll") requires a blank between the two.
  - At each frame, skip letters with logprob ≤ -8.
  - Keep the best 24 prefixes, ranked by total probability.
- At the end, keep only prefixes that are complete words. Score each as
  `ctcLogProb + 0.35 * wordPrior` and return the top 5.
- Check against `golden.json`: the same features → logprobs within fp16 tolerance → the same
  top word for every case.

## Build plan

### Phase 1: Capture app (SwiftUI). Do this first.
Purpose: collect real finger data for accuracy numbers and personalization.
- Show a prompt word, then provide a square writing pad. One continuous stroke = one sample.
  Include Redo and Skip.
- Draw the live path faintly, with a fading trail.
- Pick prompt words from `lexicon.tsv`, weighted toward common words, with some short and
  some long.
- Save one JSON per sample:
  `{ "word", "points": [[x, y, t], ...] (box units, y up, t in seconds from touch down), "padSidePt", "device", "createdAt" }`
- Export everything through the share sheet or Files as a folder or zip.
- Also write `ml/import_captures.py`, which turns these JSON files into the `.npz` format in
  `data.py` (`X` = concatenated features as float16, `lens`, `labels`) by running each path
  through `featurize`.
- **Done when:** you can record 100 words in about 10 minutes and they import into `.npz`
  without errors.

### Phase 2: On-device recognition in the app
- Swift `featurize`, Core ML inference, and the Swift beam search decoder, in a Swift
  package shared by the app and the keyboard.
- Unit tests that replay `golden.json`.
- Add a "test mode" to the capture app: write a word and see the top 3 guesses plus
  timings.
- **Done when:** golden tests pass, and on device the model plus decoder take under about
  20 ms per word. Record the actual memory use.

### Phase 3: Keyboard extension
- A `UIInputViewController` that hosts the writing pad and a suggestion bar with the top 3
  words.
- Lifting the finger commits the top word.
- Keep everything on device. The model and decoder must work **without Full Access**.
- Watch memory closely: keyboard extensions have a strict, low memory limit. Load the model
  once, and keep the trie compact (for example, flat arrays instead of class nodes).
- **Done when:** you can type a sentence in Notes and Messages without the extension being
  killed.

### Phase 4: Personalization
- First version: export samples from the app, fine-tune on the Mac, re-export Core ML, and
  ship the new model to the app. Fine-tuning recipe: about 4k replay samples plus your
  samples repeated to about 4k, about 3 minutes, lr 5e-4, `--init runs/final.pt` (see
  `ml/README.md`).
- Later: corrections inside the keyboard (when the user picks suggestion #2 or #3) become
  training samples. Saving them to an App Group container the app can read probably needs
  Full Access, so verify that before building it.
- Optional later: on-device updates (fine-tune only the last layer, or a small adapter).

### Phase 5: Model improvements (Python, on the Mac)
- `ml/train.py` only runs on CPU. Add support for `mps`.
- Add uppercase letters, digits, and punctuation, plus more shape variants per letter, to
  `ml/letters.py`.
- Re-run `ml/evaluate.py`, and add a real-data test set from Phase 1.
- When exporting, note that coremltools 9.0 was only tested with torch ≤ 2.7. Use that
  version for exporting if conversion looks wrong.

## Open questions for Gabriel (ask before Phase 3)
1. How do you type space, backspace, punctuation, and capitals? Options: gestures (a flick
   right for space, a flick left to delete the last word), small buttons around the pad, or
   automatic spacing.
2. Should the capture tool live inside the keyboard's containing app, or be a separate
   target?
3. Is this just for personal use, or for the App Store eventually? That affects privacy
   wording, Full Access, and how much to polish.

## Known gaps and risks
- All accuracy numbers come from synthetic data. Real finger writing may look different
  (size, placement, speed, corners).
- The Core ML model has never run on a device.
- The model only knows a–z, lowercase. Words outside the 40k dictionary can't be produced
  yet, so you'll need a fallback such as showing the raw letter guess.
- Password fields always switch to Apple's keyboard (an iOS rule).
