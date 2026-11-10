"""Apply the word changes in word-changes/<code>.txt to a language's word list.

    python3 apply_word_changes.py en
    python3 apply_word_changes.py es

Run it after any rebuild of a list (make_lexicon.py, grow_lexicon.py), so the words
we added stay in and the ones we took out stay out. It rewrites
Resources/<code>/lexicon.tsv in place: taken-out words go, added words go in at the
end (the keyboard ranks by the frequency on each line, not by line order), and a word
already there keeps its line unless the change gives it a frequency.
"""
import argparse, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RESOURCES = os.path.join(HERE, "../../ios/AstrotypeKit/Sources/AstrotypeCore/Resources")
DEFAULT_FREQUENCY = 1e-6


def read_changes(path):
    """(added {word: frequency or None}, removed {word}) from a changes file."""
    added, removed = {}, set()
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        sign, *rest = line.split()
        if sign not in "+-" or not rest or len(rest) > 2 or (sign == "-" and len(rest) > 1):
            sys.exit(f"{path}:{number}: expected '+ word [frequency]' or '- word'")
        word = rest[0].lower()
        if sign == "+":
            added[word] = float(rest[1]) if len(rest) > 1 else None
        else:
            removed.add(word)
    both = removed & added.keys()
    if both:
        sys.exit(f"{path}: both added and taken out: {', '.join(sorted(both))}")
    return added, removed


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("language")
    args = ap.parse_args()
    added, removed = read_changes(os.path.join(HERE, "word-changes", f"{args.language}.txt"))
    path = os.path.join(RESOURCES, args.language, "lexicon.tsv")
    lines = open(path, encoding="utf-8").read().splitlines()
    out, seen = [], set()
    for line in lines:
        word = line.split("\t", 1)[0]
        if word in removed:
            continue
        if word in added and added[word] is not None:
            line = f"{word}\t{added[word]:e}"
        seen.add(word)
        out.append(line)
    for word, frequency in added.items():
        if word not in seen:
            out.append(f"{word}\t{(frequency or DEFAULT_FREQUENCY):e}")
    open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"{args.language}: {len(lines)} → {len(out)} words", file=sys.stderr)


if __name__ == "__main__":
    main()
