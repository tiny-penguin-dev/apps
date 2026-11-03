"""Write a language's word list for the keyboard, from wordfreq's counts.

    pip install wordfreq
    python3 make_lexicon.py es --tatoeba spa_sentences.tsv > ../../ios/AstrotypeKit/Sources/AstrotypeCore/Resources/es/lexicon.tsv

Writes `word<TAB>frequency` for the commonest words made only of the language's
letters (a to z plus its accented ones), most common first. Words with accents are
written as they are ("canción"); the keyboard files them under their plain letters
and puts the accents back itself. For a language other than English, words that are
far more common in English than in the language itself ("the", "you": wordfreq's
Spanish counts include English tweets and lyrics) are left out, unless they carry
the language's own accents or the language's own sentences use them (`--tatoeba`,
the language's Tatoeba export, the same file `count_pairs.py` reads: Spanish "he",
"has" and "come" are words, "the" and "you" are not). Single letters are kept only
when they are words. A spelling with fewer accents than a spelling of the same
plain letters 20 times more common is left out ("manana" beside "mañana", "segun"
beside "según": a missing accent, not a word); "qué" beside "que" stays.
"""
import argparse, collections, re, sys, unicodedata
from wordfreq import top_n_list, word_frequency

LETTERS = {
    "en": "a-z",
    "es": "a-záéíóúüñ",
}
SINGLE = {
    "en": set("ai"),
    "es": set("aeouy"),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("language", choices=sorted(LETTERS))
    ap.add_argument("--size", type=int, default=40_000)
    ap.add_argument("--english-ratio", type=float, default=3.0,
                    help="leave out a plain word this many times more common in English")
    ap.add_argument("--tatoeba", help="the language's Tatoeba sentences: an English-looking word used this "
                    "often there (--min-uses) is kept")
    ap.add_argument("--spelling-ratio", type=float, default=20.0)
    ap.add_argument("--min-uses", type=int, default=20)
    a = ap.parse_args()
    uses = collections.Counter()
    if a.tatoeba:
        with open(a.tatoeba, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 3:
                    uses.update(re.findall(f"[{LETTERS[a.language]}]+", parts[2].lower()))
    word = re.compile(f"[{LETTERS[a.language]}]+")
    plain = re.compile("[a-z]+")
    out, dropped = [], []
    for w in top_n_list(a.language, a.size * 3):
        if len(out) >= a.size:
            break
        if not word.fullmatch(w):
            continue
        if len(w) == 1 and w not in SINGLE[a.language]:
            continue
        f = word_frequency(w, a.language)
        if a.language != "en" and plain.fullmatch(w) and word_frequency(w, "en") > a.english_ratio * f \
                and uses[w] < a.min_uses:
            dropped.append(w)
            continue
        out.append((w, f))
    def fold(w):
        return "".join(c for c in unicodedata.normalize("NFD", w) if not unicodedata.combining(c))
    def accents(w):
        return sum(1 for c in unicodedata.normalize("NFD", w) if unicodedata.combining(c))
    groups = collections.defaultdict(list)
    for w, f in out:
        groups[fold(w)].append((w, f))

    def unaccented_typo(w, f):
        return any(accents(o) > accents(w) and g > a.spelling_ratio * f for o, g in groups[fold(w)])
    rare = [w for w, f in out if unaccented_typo(w, f)]
    out = [(w, f) for w, f in out if not unaccented_typo(w, f)]
    print(f"{len(rare)} rare spellings left out: {' '.join(rare[:20])} ...", file=sys.stderr)
    for w, f in out:
        sys.stdout.write(f"{w}\t{f:e}\n")
    print(f"{len(out)} words; {len(dropped)} left out as English: {' '.join(dropped[:40])} ...", file=sys.stderr)


if __name__ == "__main__":
    main()
