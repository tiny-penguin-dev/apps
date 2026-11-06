# Next-word model

The keyboard's next-word guesses come from a tiny word-level transformer per language
(features/next-word-model). Core ML runs it on the Neural Engine. This folder makes
the text, trains the model, scores it the same way the app scores the word pairs, and
exports it.

## Everything at once (on a Mac with an M chip)

```bash
cd apps/astrotype/ml/nextword
./run.sh en     # about 7 GB of downloads, then 2.5 hours of training
./run.sh es
```

`run.sh` downloads the text, makes the sentences, trains, scores, and exports
`nextword.mlpackage` and `nextword-vocab.txt` into
`ios/AstrotypeKit/Sources/AstrotypeCore/Resources/<lang>/`. Its log ends with the
model's score next to the word pairs' score.

## Step by step

1. **Text** (`make_text.py`): pages from FineWeb (English) and FineWeb-2 (Spanish),
   both ODC-BY, that read like people talking (forums, comments, reviews, or full of
   "I" and "you"), split into sentences of at most 31 words as the keyboard sees them:
   lowercase, accents off, apostrophes dropped, words outside the lexicon as `<unk>`,
   breaks as `,`. About 2% of pages are held back as the test set, whole. Tatoeba
   (CC BY 2.0 FR) is added to training only, since the word pairs were counted on it.
2. **Baseline:** `swift run -c release astrotype-tools nexteval data/en/test.txt
   --language en` scores the shipped word pairs on the test set.
3. **Train** (`train.py`): 16,000 words, 4 layers, 256 wide, 32-word window, about 7
   million weights. Uses the Mac's GPU (MPS). It scores the test set every 10 minutes
   and keeps the best checkpoint.
4. **Score** (`evaluate.py`): the same rules as the app's `NextWordEval`. For every
   word that could be offered, is it among the three guesses made from the words
   before it?
5. **Export** (`export.py`): Core ML for iOS 18, weights palettized to 4 bits, about
   3.5 MB. The word table has a multiple of 64 rows so it compresses in groups.

## Results

| Language | Test words | Word pairs top-3 | Model top-3 | Size |
|---|---|---|---|---|
| English | 57,401 sentences | 19.4% | | |
| Spanish | | | | |
