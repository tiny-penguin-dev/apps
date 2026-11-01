# Astrotype — model prototype

A handwriting recognizer for a keyboard where every letter is **stacked in the same spot**
(no looking).

## Phrases with finger lifts (current)

You lift your finger whenever you like, and the model decides where words end.

- `phrases.py` synthesizes 1–4 word phrases as timed strokes. Each synthetic writer has a
  speed, a usual lift, how often they join letters, tap between words, pause between words,
  or stop to think mid-word, so no single cue decides a word break.
- Features (`featurize_strokes`, 9 per point): the 5 below plus stroke start, the lift
  before the stroke (absolute and relative to the writer's usual lift) and stroke length.
- The model is `ConvStrokeNet` with 9 inputs and 28 outputs (blank, a–z, space).
  `train_phrases.py` generates fresh phrases in worker processes as it trains, starting
  from the single-word model.
- `decode_phrase.py` searches the dictionary with word transitions: a space after a word
  commits it, a space mid-word can be ignored ("televi sion" → "television"), and a word can
  end with no space at all, each for a penalty.

Result after 1 hour on an M-series GPU, 300 synthetic phrases: 98.7% exactly right with the
decoder, word error rate 1.1% (83.7% exact without the dictionary).

```bash
python3 train_phrases.py --init runs/final.pt --out runs/phrase.pt --minutes 60
python3 eval_phrases.py runs/phrase.pt --n 300 --tune
```

The rest of this file describes the original one-stroke-per-word model.

## How it works

1. **Touch path → features.** The finger path (in "box units": the writing area is 1×1)
   is resampled every `0.04` units. Each point becomes 5 numbers: position, direction
   (cos/sin), and how sharply it turns. See `synth.featurize`.
2. **Model → letter scores.** A small all-convolution network (`model.ConvStrokeNet`,
   ~660k params, 1.4 MB as Core ML fp16) outputs per-frame scores for blank + a–z.
   Trained with CTC, so it never needs to know where one letter ends and the next begins.
3. **Dictionary decoding.** `decode.beam_search` walks a word trie (40k English words
   from `wordfreq`) and adds a word-frequency bonus, so `"suuiued"` still becomes
   `survived`. Returns the top few words for a suggestion bar.

## Training data (all synthetic for now)

`letters.py` has three letter "styles":
- **natural** — hand-made one-stroke paths, drawn the way people tend to write with a
  finger (circles counter-clockwise, stems top-down, dot/crossbar last)
- **futural** — Hershey single-line print font
- **scripts** — Hershey single-line cursive font

`synth.py` stacks letters in one spot, joins them with the in-air moves a finger makes
when it never lifts, then adds slant, size changes, drift, wobble and jitter.
`python3 viz.py` renders examples to `out/samples.png`.

## Results (synthetic test words, 1000 each)

| Setup | Top-1 word | In top 3 |
|---|---|---|
| Final model, styles it trained on | 99.9% | 100% |
| Style it never saw (cursive held out), 0 samples | 7.8% | 11.6% |
| Same unseen style + **50** example words, ~3 min fine-tune | 87.4% | 92.8% |
| Same unseen style + **300** example words | 96.3% | 98.2% |

Fine-tuning didn't hurt the original styles (still ~98% exact letters).
Speed: ~1.5 ms per word for the model on 2 cloud CPU cores; ~2–3 ms for the Python
decoder (Swift will be faster).

**Takeaway:** the model reads styles it has seen very well, but does NOT magically read a
style that looks totally different. A short "teach me your handwriting" step (50+ words)
fixes that. Real finger data is the next step — these numbers are on synthetic data only.

## Commands

```bash
pip install torch numpy wordfreq Hershey-Fonts matplotlib coremltools onnx onnxruntime

# data
python3 data.py --n 150000 --seed 1 --styles natural,futural --out data/train_A.npz
python3 data.py --n 80000  --seed 4 --styles natural,futural,scripts --out data/train_B.npz
python3 data.py --n 3000   --seed 5 --styles natural,futural,scripts --p_random 0 --out data/test_all.npz

# train (time-budgeted; uses the Apple GPU via mps when available, --device cpu to force CPU)
python3 train.py --train data/train_A.npz --val data/test_all.npz --minutes 25 --out runs/A.pt
python3 train.py --train data/train_B.npz --val data/test_all.npz --minutes 10 --lr 8e-4 --init runs/A.pt --out runs/final.pt

# personalize: mix your samples (repeated) with some replay data, short low-LR run
python3 train.py --train data/replay_4k.npz data/mine.npz data/mine.npz ... --val data/test_all.npz \
  --minutes 3 --lr 5e-4 --init runs/final.pt --out runs/mine.pt

# train on samples recorded in the app (one command: import, replay data, fine-tune, score)
python3 finetune.py ~/Downloads/Astrotype-samples-*.zip
python3 finetune.py samples/ --minutes 5 --ship    # also export Core ML + golden.json and copy into the iOS app
python3 import_captures.py samples/ --out data/mine.npz --test 0.15   # just the import step

# score + export
python3 evaluate.py --model runs/final.pt --sets data/test_all.npz
python3 export.py --model runs/final.pt --out export/Astrotype
```

## Files

- `runs/final.pt` — trained PyTorch weights
- `export/Astrotype.mlpackage` — Core ML (fp16, iOS 16+). Input `strokes` (1, T, 5),
  T = 16…2048; output `logprobs` (1, ⌈T/4⌉, 27), index 0 = blank, 1–26 = a–z.
  **Not yet run on a device** — converted on Linux, where Core ML can't execute.
- `export/Astrotype.onnx` — same model; checked against PyTorch (max diff ~4e-5).
- `results/` — full evaluation output with example decodes.

## Next steps

1. **Real data.** A simple capture screen (iOS or web) that shows a word, records your
   finger path with timestamps, and saves JSON. Needed for both honest accuracy numbers
   and personalization.
2. **More letter styles** in synthesis (uppercase, digits, punctuation, more variants per
   letter) to raise accuracy before any personalization.
3. **On-device:** port `featurize` + `beam_search` to Swift, run the Core ML model in a
   keyboard extension, check memory use (~a few MB expected).
4. **On-device learning:** store corrections; fine-tune on the Mac at first, later
   on-device (Core ML updatable layers or a small adapter on the last layer).
