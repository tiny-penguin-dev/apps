"""Grow a word list with the next most common words that a spelling dictionary knows.

    pip install wordfreq
    curl -LO https://unpkg.com/dictionary-en@4.0.0/index.aff
    curl -LO https://unpkg.com/dictionary-en@4.0.0/index.dic
    python3 grow_lexicon.py en ../../ios/AstrotypeKit/Sources/AstrotypeCore/Resources/en/lexicon.tsv \
        --aff index.aff --dic index.dic --size 80000

Keeps the list as it is and adds, most common first, the words after it in
wordfreq's counts until it holds `--size` words. wordfreq's counts come from web text,
so past the first 40,000 they hold slips and run-together words ("hte", "inthe",
"icecream") and names; only words the Hunspell dictionary spells (SCOWL, en_US,
lower case, with its endings expanded) are added. The new words are written after the
old ones; the keyboard ranks by the frequency on each line, not by line order.
"""
import argparse, re, sys
from wordfreq import top_n_list, word_frequency


def hunspell_words(aff_path, dic_path):
    """Every word the dictionary spells: each stem with its suffixes and prefixes."""
    rules, current = {}, None
    for line in open(aff_path, encoding="utf-8"):
        p = line.split()
        if len(p) < 4 or p[0] not in ("SFX", "PFX"):
            continue
        if len(p) == 4 and p[2] in "YN":
            rules[p[1]] = {"kind": p[0], "cross": p[2] == "Y", "rules": []}
            continue
        strip = "" if p[2] == "0" else p[2]
        add = "" if p[3] == "0" else p[3].split("/")[0]
        cond = p[4] if len(p) > 4 else "."
        rx = re.compile(cond + "$" if p[0] == "SFX" else "^" + cond)
        rules[p[1]]["rules"].append((strip, add, rx))
    words = set()
    for line in open(dic_path, encoding="utf-8").read().splitlines()[1:]:
        stem, _, flags = line.partition("/")
        flags = flags.split()[0] if flags else ""
        words.add(stem)
        suffixed, prefixes = [], []
        for flag in flags:
            rule = rules.get(flag)
            if not rule:
                continue
            for strip, add, rx in rule["rules"]:
                if not rx.search(stem):
                    continue
                if rule["kind"] == "SFX":
                    if strip and not stem.endswith(strip):
                        continue
                    w = stem[:len(stem) - len(strip)] + add
                    words.add(w)
                    if rule["cross"]:
                        suffixed.append(w)
                else:
                    if strip and not stem.startswith(strip):
                        continue
                    words.add(add + stem[len(strip):])
                    if rule["cross"]:
                        prefixes.append((add, strip))
        for w in suffixed:
            for add, strip in prefixes:
                words.add(add + w[len(strip):])
    return words


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("language")
    ap.add_argument("lexicon", help="the word list to grow, in place")
    ap.add_argument("--aff", required=True)
    ap.add_argument("--dic", required=True)
    ap.add_argument("--size", type=int, default=80_000)
    a = ap.parse_args()
    lines = open(a.lexicon, encoding="utf-8").read().splitlines()
    have = {line.split("\t")[0] for line in lines}
    spelled = hunspell_words(a.aff, a.dic)
    added = []
    for w in top_n_list(a.language, a.size * 5):
        if len(have) + len(added) >= a.size:
            break
        if w in have or len(w) < 2 or not re.fullmatch("[a-z]+", w) or w not in spelled:
            continue
        added.append(w)
    with open(a.lexicon, "w", encoding="utf-8") as f:
        f.write("\n".join(lines + [f"{w}\t{word_frequency(w, a.language):e}" for w in added]) + "\n")
    print(f"{len(added)} words added, {len(lines) + len(added)} in all; last: {' '.join(added[-10:])}", file=sys.stderr)


if __name__ == "__main__":
    main()
