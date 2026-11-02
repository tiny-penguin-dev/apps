# Word pairs for the context model

The keyboard ranks its guesses by the words before the cursor
(`features/smart-matching/FEATURE.md`). The data for that is a word-pair model per
language, built here and shipped as `ios/AstrotypeKit/Sources/AstrotypeCore/Resources/<code>/bigrams.bin`.

## English, from Tatoeba

Tatoeba's sentences (tatoeba.org) are CC BY 2.0 FR; the app credits them in
Settings → About. Download the English export and count the pairs:

```bash
curl -LO https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2
bunzip2 eng_sentences.tsv.bz2
python3 count_pairs.py --tatoeba eng_sentences.tsv \
    ../../ios/AstrotypeKit/Sources/AstrotypeCore/Resources/en/lexicon.tsv \
    --drop tom,toms,mary,marys,sami,layla,fadil > pairs.tsv
```

`count_pairs.py` keeps only words in the lexicon (the keyboard can type nothing else),
treats `<s>` as the start of a sentence, breaks a pair at punctuation, and drops any
sentence that names one of Tatoeba's stock characters, which start a third of its
sentences and would make "tom" the likeliest first word of any sentence.

Then the binary, with the Swift tool (the format is `NgramModel` in `AstrotypeCore`,
so the tool and the keyboard cannot disagree):

```bash
cd ../../ios/AstrotypeKit
swift run -c release astrotype-tools build-ngrams ../../ml/ngrams/pairs.tsv Sources/AstrotypeCore/Resources/en/bigrams.bin
swift run -c release astrotype-tools next thank      # you 0.862, god 0.043, ...
```

`build-ngrams` keeps the 300,000 most common pairs (`--max-pairs`) at about 1.1 MB;
`--lambda` sets the interpolation weight (0.7). Shipped on 2026-11-02 from the
export of that day: 24,250 words, 300,000 pairs.

## Another language

Add `Resources/<code>/lexicon.tsv` (word, count per line) and build its
`bigrams.bin` the same way from any sentence corpus (one sentence per line without
`--tatoeba`), then list the code in `Language.bundledCodes`. The engine needs
nothing else.

## Measuring

`astrotype-tools replay <folder>` plays practice recordings through the engine and
prints first-guess and top-three accuracy with the misses. Get the sessions people
chose to share with `python3 ../download_samples.py --type PracticeSession`.
Only recordings from builds with this phase in them (version 2, with commit times) replay; older ones are counted as skipped.
