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

## Spanish

The word list comes from `wordfreq`'s Spanish counts, with accents as they are
written; English words that only show up in Spanish tweets ("the", "you") and
spellings that just miss an accent ("segun" beside "según") are left out
(`make_lexicon.py` says how). The word pairs come from Tatoeba's Spanish sentences
(CC BY 2.0 FR), counted on the plain letters the keyboard files words under
("mañana" is "manana"):

```bash
pip install wordfreq
curl -LO https://downloads.tatoeba.org/exports/per_language/spa/spa_sentences.tsv.bz2
bunzip2 spa_sentences.tsv.bz2
python3 make_lexicon.py es --tatoeba spa_sentences.tsv > ../../ios/AstrotypeKit/Sources/AstrotypeCore/Resources/es/lexicon.tsv
python3 count_pairs.py --tatoeba spa_sentences.tsv \
    ../../ios/AstrotypeKit/Sources/AstrotypeCore/Resources/es/lexicon.tsv --drop tom,mary,maria > pairs-es.tsv
cd ../../ios/AstrotypeKit
swift run -c release astrotype-tools build-ngrams ../../ml/ngrams/pairs-es.tsv Sources/AstrotypeCore/Resources/es/bigrams.bin
swift run -c release astrotype-tools next el --language es
```

Shipped on 2026-11-03: 39,782 words (about 7,000 with accents), 180,369 pairs over
22,925 words (813 KB), from 443,000 sentences with the 41,000 naming Tom, Mary or
María dropped.

## Another language

Add `Resources/<code>/lexicon.tsv` (word, count per line, accents as written: the
keyboard files each word under its plain letters and puts the accents back) and
build its `bigrams.bin` the same way from any sentence corpus (one sentence per line
without `--tatoeba`); `make_lexicon.py` makes the list for any language `wordfreq`
knows once its letters are in `LETTERS`. Then add the folder to `Package.swift`'s
resources and the code to `Language.bundledCodes` and `Language.names`. The engine
needs nothing else.

## Measuring

`astrotype-tools replay <folder>` plays practice recordings through the engine and
prints first-guess and top-three accuracy with the misses. Get the sessions people
chose to share with `python3 ../download_samples.py --type PracticeSession`.
Only recordings from builds with this phase in them (version 2, with commit times) replay; older ones are counted as skipped.
