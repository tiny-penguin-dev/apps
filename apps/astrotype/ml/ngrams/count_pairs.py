"""Count word pairs in a corpus, for the keyboard's context model.

    python3 count_pairs.py corpus.txt lexicon.tsv > pairs.tsv
    python3 count_pairs.py --tatoeba eng_sentences.tsv lexicon.tsv --drop tom,toms,mary,marys,sami,layla,fadil > pairs.tsv

Reads one sentence per line (with --tatoeba, Tatoeba's `id<TAB>lang<TAB>sentence`
export), lowercases it, takes the accents off as the keyboard does ("mañana" counts
as "manana", the key the trie and the context use), keeps only the words in the lexicon (the keyboard can only
type those), and writes `previous<TAB>next<TAB>count` for every pair of neighbouring
words inside a sentence, most common first. `<s>` stands for the start of a sentence,
so the first word of a sentence gets context too. Punctuation ends a run: "hello,
world" gives no pair. The Swift tool `astrotype-tools build-ngrams` turns the counts
into the binary the keyboard loads (see README.md here).
"""
import argparse, collections, re, sys, unicodedata

TOKEN = re.compile(r"[^\W\d_]+(?:'[^\W\d_]+)?|[^\w\s]+|[\d_]+")
ENDERS = set(".!?;:,()\"")
# Open a question or an exclamation in Spanish: no break, and no word.
OPENERS = set("¿¡")


def fold(word):
    """The keys a word is typed with, as the keyboard files it (`Lexicon.fold`):
    lowercase, accents and tildes off ("mañana" is "manana")."""
    return "".join(c for c in unicodedata.normalize("NFD", word.lower()) if not unicodedata.combining(c))


def sentences(path, tatoeba):
    with open(path, encoding="utf-8") as f:
        for line in f:
            if tatoeba:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 3:
                    continue
                yield parts[2]
            else:
                yield line


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("corpus")
    ap.add_argument("lexicon")
    ap.add_argument("--tatoeba", action="store_true", help="the corpus is Tatoeba's per-language sentence export")
    ap.add_argument("--min-count", type=int, default=2)
    ap.add_argument("--drop", default="", help="comma-separated words: a sentence that has any of them is skipped "
                    "(Tatoeba's stock names: Tom, Mary, Sami, Layla and Fadil start a third of its sentences)")
    a = ap.parse_args()
    drop = {w.strip().lower() for w in a.drop.split(",") if w.strip()}

    vocab = set()
    with open(a.lexicon, encoding="utf-8") as f:
        for line in f:
            word = line.split("\t")[0].strip()
            if word:
                vocab.add(fold(word))

    counts = collections.Counter()
    total = 0
    skipped = 0
    for sentence in sentences(a.corpus, a.tatoeba):
        tokens = TOKEN.findall(sentence.lower())
        if drop and any(fold(t).replace("'", "") in drop for t in tokens):
            skipped += 1
            continue
        previous = "<s>"
        for token in tokens:
            if all(c in OPENERS for c in token):
                continue
            token = fold(token)
            if not token:
                continue
            if token[0] not in "abcdefghijklmnopqrstuvwxyz":
                # Punctuation: the next word starts a new run (a comma or a full stop
                # both break the pair; a new sentence gets <s> again only after . ! ?).
                previous = "<s>" if token[0] in ".!?" else None
                continue
            word = token.replace("'", "")
            if word in vocab:
                if previous is not None:
                    counts[(previous, word)] += 1
                    total += 1
                previous = word
            else:
                previous = None
    kept = [(pair, n) for pair, n in counts.items() if n >= a.min_count]
    kept.sort(key=lambda item: (-item[1], item[0]))
    out = sys.stdout
    for (previous, word), n in kept:
        out.write(f"{previous}\t{word}\t{n}\n")
    print(f"{total} pairs seen, {len(counts)} distinct, {len(kept)} kept (count >= {a.min_count}), {skipped} sentences dropped", file=sys.stderr)


if __name__ == "__main__":
    main()
