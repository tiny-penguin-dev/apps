# StackWrite — build brief for the iOS app

You're picking up a prototype for an iOS handwriting keyboard. This brief covers what
exists, the exact contracts the Swift side has to match, and the build plan. The Python
prototype in `ml/` is the reference implementation. When this brief and the code
disagree, the code is right.

## The idea

An iOS keyboard you can use **without looking**. You write with **every letter stacked on
top of the previous one in the same spot**, lifting your finger whenever you like. Nothing
special marks the end of a word: the model weighs the evidence (a longer lift than this
writer usually makes, a tap, or letters that only make sense as two words) and a dictionary
decoder picks the most likely words, so sloppy letters still come out right.

Example: writing "the cat" means drawing t, h, e on top of each other (lifting or not),
pausing a moment or tapping, then c, a, t in the same spot.

The first version took one word per stroke (lifting ended the word). Gabriel found that
unnatural, so since 2026-10-30 the model reads multi-stroke writing and predicts the spaces
itself (`ml/phrases.py`, `ml/train_phrases.py`, `ml/decode_phrase.py`).

## What already exists (`ml/`)

Paths in this table are relative to `ml/`.

| Path | What it is |
|---|---|
| `letters.py`, `synth.py` | Synthetic data: letter shapes (3 styles), stacking, connectors, augmentation, **feature extraction** (`featurize`) |
| `model.py` | `ConvStrokeNet`: all-conv 1-D CNN, ~660k params, CTC over blank + a–z + space |
| `phrases.py` | Multi-stroke phrase synthesis (lifts, taps, pauses, writer habits) and **feature extraction** (`featurize_strokes`) |
| `train_phrases.py`, `eval_phrases.py` | Phrase training on freshly synthesized data, scoring with and without the decoder |
| `decode_phrase.py` | The phrase decoder (below) |
| `decode.py` | The old single-word decoder |
| `train.py`, `data.py`, `evaluate.py` | Dataset building, time-budgeted training (CPU only), scoring |
| `runs/phrase.pt` | Phrase model weights (on Gabriel's Mac; `runs/final.pt` is the old single-word model) |
| `export/StackWrite.mlpackage` | Core ML model (fp16, mlprogram, iOS 16+). **Never run on a device yet.** |
| `export/StackWrite.onnx` | Same model; matches PyTorch to ~4e-5 |
| `export/lexicon.tsv` | 40,000 words with frequencies (`word<TAB>freq`), the decoder's dictionary |
| `export/golden.json` | 6 test phrases with raw strokes, expected features, logprobs and decoded phrases (full and cut off halfway), **for Swift parity tests** |
| `README.md`, `results/` | Commands and accuracy results |
| `out/samples.png` | Picture of the synthetic training data |

### Current accuracy (synthetic data only)

- Phrase model, 1–4 word synthetic phrases: 98.7% exactly right with the decoder (word
  error rate 1.1%); without the dictionary 83.7%. The misses were compounds split in two
  ("water fall").
- Old single-word model: 99.9% top-1 on styles it saw, 7.8% on an unseen style, 87.4%
  after fine-tuning on 50 sample words.

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

### 2. Features (`phrases.featurize_strokes`), strokes → `[T, 9]` Float32
Each stroke is resampled on its own, then the rows are concatenated in stroke order.
1. **Resample** a stroke by arc length every `STEP = 0.04` box units: sample positions
   `0, 0.04, 0.08, …` strictly less than its length, x and y linearly interpolated.
   Shorter than 0.04 (a tap): `[first, last]`, or just `[first]` if it moved under 1e-4.
2. `ang[i] = atan2(dy, dx)` to the next point, last angle repeated; a one-point stroke has
   angle 0 and no direction.
3. `turn[0] = 0`, `turn[i] = ang[i] - ang[i-1]`, wrapped into [-π, π).
4. Each row is `[x - 0.5, y - 0.5, cos(ang), sin(ang), turn / π, start, lift, relLift, len]`:
   `start` is 1 on a stroke's first row; `lift = log1p(gap / 0.25)` and
   `relLift = log1p(gap / writerLift)` on a stroke's first row (0 for the first stroke),
   where `gap` is the seconds the finger was up; `len = log(stroke length + 0.01)` on
   every row.
5. `writerLift` is the writer's usual lift between letters: the median of the shorter half
   of their recent lifts, clamped to 0.05–1 s, or 0.2 s with fewer than 4 lifts. The app
   keeps the last 100 lifts; Python measures them from the phrase when not given.

### 3. Model I/O (Core ML)
- Input `strokes`: shape `(1, T, 9)` Float32, `16 ≤ T ≤ 2048`. Shorter inputs are padded by
  repeating the last row with turn, start and lifts zeroed.
- Output `logprobs`: shape `(1, ceil(T/4), 28)`, log-softmax. 0 is the CTC blank, 1–26
  a–z, 27 space.

### 4. Decoder (`decode_phrase.beam_search`), ported as `PhraseDecoder`
- A trie built from `lexicon.tsv`; each word's prior is `log(freq / maxFreq)`.
- CTC prefix beam search (separate blank and non-blank probabilities; a repeated label needs
  a blank between; letters with logprob ≤ -8 skipped), extending along trie edges, plus:
  - a space after a complete word commits it and returns to the root;
  - a space inside a word can be ignored for `swallow_pen` (-1.5) ("televi sion" →
    "television"), and a space at the root (leading or extra) is ignored for free;
  - after a complete word, a letter can start a new word with no space for `break_pen` (-4).
- Each committed word adds `0.5 * wordPrior + 0.5`. Beams are ranked by CTC probability
  plus that score; keep 32.
- At the end an unfinished last word is dropped, unless decoding `partial` (live typing),
  where it stays as typed so far. Return the top 5 texts.
- `golden.json` checks the same features → logprobs within fp16 tolerance → the same texts.

## Build plan

> **Status (2026-10-30):** Phases 1 and 2 are built, now for multi-stroke phrases: the
> training screen prompts 1–4 words and saves the strokes on Done (sample format v2), and
> "Try the keyboard" reads continuous writing, showing the words as tentative (marked) text
> until two more words follow, the writer stops for 2 s, or taps a suggestion, space or
> punctuation. The model is trained on synthetic phrases only. Earlier: the "Write training words" screen
> (format in `SAMPLES.md`, word groups instead of single words), `ml/import_captures.py`,
> `ml/finetune.py`, `StackWriteKit` with golden tests, and "Try the keyboard", an in-app
> version of Phase 3's keyboard. Not yet measured on a device: speed, memory, accuracy on
> real writing. Inputs shorter than 16 frames are padded by repeating the last row.

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
