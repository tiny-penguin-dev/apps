"""Casual sentences for the next-word model, split into training text and a test set.

    python3 make_text.py en fineweb-en.parquet --tatoeba eng_sentences.tsv --out data/en
    python3 make_text.py es fineweb2-es.parquet --tatoeba spa_sentences.tsv --out data/es

Reads FineWeb (English) or FineWeb-2 (Spanish) parquet shards (ODC-BY), keeps the
pages that read like people talking (forums, comments, reviews, Q&A, or text full of
"I" and "you"), splits them into sentences and writes one sentence per line as the
keyboard sees words: lowercase, accents off (`Lexicon.fold`), apostrophes dropped
("don't" is "dont"), words outside the lexicon as `<unk>`. A comma or other break
inside a sentence is written as `,`, since the keyboard offers nothing after one.

Whole pages go to the test set by a hash of their id (about 2%), so no test sentence
shares a page with a training one. Tatoeba's sentences (CC BY 2.0 FR) go to training
only: the shipped word pairs were counted on all of them, so testing on them would
flatter the pairs.

Writes `<out>/train.txt`, `<out>/test.txt` and `<out>/stats.txt`.
"""
import argparse, hashlib, os, re, sys, unicodedata

import pyarrow.parquet as pq

TOKEN = re.compile(r"[^\W\d_]+(?:['’][^\W\d_]+)?|[.!?]+|[,;:()\"“”—–-]+|\d+")
SENTENCE = re.compile(r"(?<=[.!?])\s+|\n+")
CASUAL_URL = re.compile(r"forum|thread|topic|comment|community|discuss|review|answers|question|viewtopic|"
                        r"showthread|reddit|quora|blog|/qa/|stackexchange|chat|foro|opinion|preguntas|respuestas",
                        re.I)
CASUAL_WORDS = {
    "en": {"i", "im", "ive", "id", "ill", "you", "youre", "my", "me", "your", "we", "lol", "thanks", "yeah"},
    "es": {"yo", "tu", "te", "me", "mi", "estoy", "tengo", "quiero", "gracias", "vos", "usted", "jaja", "nosotros"},
}
DROP_URL = re.compile(r"\.(pdf|gov)|wikipedia|legal|terms|privacy|recipe", re.I)


def fold(word):
    return "".join(c for c in unicodedata.normalize("NFD", word.lower()) if not unicodedata.combining(c))


def load_lexicon(path):
    words = set()
    with open(path, encoding="utf-8") as f:
        for line in f:
            w = line.split("\t")[0].strip()
            if w:
                words.add(fold(w).replace("'", ""))
    return words


def tokens(sentence, vocab):
    """The sentence as the keyboard's words, or None when too little of it is typeable."""
    out, known, words = [], 0, 0
    for t in TOKEN.findall(sentence):
        if t[0].isdigit():
            out.append("<unk>")
            words += 1
        elif t[0] in ".!?":
            break
        elif not t[0].isalpha():
            if out and out[-1] != ",":
                out.append(",")
        else:
            w = fold(t).replace("'", "").replace("’", "")
            words += 1
            if w in vocab:
                known += 1
                out.append(w)
            else:
                out.append("<unk>")
    while out and out[-1] == ",":
        out.pop()
    # 31 tokens at most: with `<s>` the whole sentence fits the model's 32-token window.
    if words < 3 or len(out) > 31 or known < 0.9 * words:
        return None
    return out


def casual(text, lang):
    head = [fold(w).replace("'", "").replace("’", "") for w in TOKEN.findall(text[:3000]) if w[0].isalpha()]
    if len(head) < 20:
        return False
    hits = sum(w in CASUAL_WORDS[lang] for w in head)
    return hits / len(head) >= 0.03


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("lang", choices=["en", "es"])
    ap.add_argument("parquet", nargs="+")
    ap.add_argument("--lexicon", help="defaults to the app's Resources/<lang>/lexicon.tsv")
    ap.add_argument("--tatoeba", help="Tatoeba's per-language export (training only)")
    ap.add_argument("--drop", default="tom,toms,mary,marys,maria,sami,layla,fadil")
    ap.add_argument("--max-sentences", type=int, default=6_000_000)
    ap.add_argument("--test-share", type=float, default=0.02)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    lexicon = a.lexicon or os.path.join(here, "../../ios/AstrotypeKit/Sources/AstrotypeCore/Resources", a.lang, "lexicon.tsv")
    vocab = load_lexicon(lexicon)
    os.makedirs(a.out, exist_ok=True)
    train = open(os.path.join(a.out, "train.txt"), "w", encoding="utf-8")
    test = open(os.path.join(a.out, "test.txt"), "w", encoding="utf-8")
    n = {"pages": 0, "casual_pages": 0, "train": 0, "test": 0, "tatoeba": 0}
    done = False
    for path in a.parquet:
        f = pq.ParquetFile(path)
        for batch in f.iter_batches(batch_size=2000, columns=["text", "id", "url"]):
            for text, pid, url in zip(*(batch.column(i).to_pylist() for i in range(3))):
                n["pages"] += 1
                url = url or ""
                if DROP_URL.search(url):
                    continue
                if not (CASUAL_URL.search(url) or casual(text, a.lang)):
                    continue
                n["casual_pages"] += 1
                held = int(hashlib.sha1(pid.encode()).hexdigest()[:8], 16) / 0xFFFFFFFF < a.test_share
                for s in SENTENCE.split(text):
                    t = tokens(s, vocab)
                    if t is None:
                        continue
                    (test if held else train).write(" ".join(t) + "\n")
                    n["test" if held else "train"] += 1
                if n["train"] >= a.max_sentences:
                    done = True
                    break
            if done:
                break
            print(f"\r{n}", end="", file=sys.stderr)
        if done:
            break
    if a.tatoeba:
        drop = {w for w in a.drop.split(",") if w}
        with open(a.tatoeba, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 3:
                    continue
                t = tokens(parts[2], vocab)
                if t is None or drop & set(t):
                    continue
                train.write(" ".join(t) + "\n")
                n["tatoeba"] += 1
    train.close()
    test.close()
    with open(os.path.join(a.out, "stats.txt"), "w") as f:
        f.write(f"{n}\n")
    print(f"\n{n}", file=sys.stderr)


if __name__ == "__main__":
    main()
