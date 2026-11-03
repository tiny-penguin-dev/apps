"""Builds the keyboard's emoji list from Unicode's emoji-test.txt.

    curl -sSLO https://unicode.org/Public/emoji/latest/emoji-test.txt
    python3 build_emoji.py emoji-test.txt \
        ../../ios/AstrotypeKit/Sources/AstrotypeCore/Resources/emoji/emoji.tsv

One line per emoji, in Unicode's order within Apple's eight categories:
`category<TAB>version<TAB>emoji<TAB>tones`, where tones is the five skin tone forms
(light to dark) separated by spaces, or empty. Read by `EmojiCatalog`
(features/emoji/FEATURE.md). Only fully-qualified emoji; forms that mix two skin tones
are left out (the picker offers one tone per emoji).
"""
import re
import sys

GROUPS = {
    "Smileys & Emotion": "smileys",
    "People & Body": "smileys",
    "Animals & Nature": "nature",
    "Food & Drink": "food",
    "Activities": "activity",
    "Travel & Places": "travel",
    "Objects": "objects",
    "Symbols": "symbols",
    "Flags": "flags",
}
ORDER = ["smileys", "nature", "food", "activity", "travel", "objects", "symbols", "flags"]
TONES = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]
LINE = re.compile(r"^([0-9A-F ]+?)\s*; fully-qualified\s*# (\S+) E(\d+\.\d+)")


def main(source, target):
    group = None
    rows = {c: [] for c in ORDER}  # category -> [(points, emoji, version)]
    toned = {}  # base points without FE0F -> {tone index: emoji}
    for line in open(source, encoding="utf-8"):
        if line.startswith("# group:"):
            group = GROUPS.get(line.split(":", 1)[1].strip())
            continue
        m = LINE.match(line)
        if not m or group is None:
            continue
        points = [int(p, 16) for p in m.group(1).split()]
        emoji = "".join(chr(p) for p in points)
        tones = {p for p in points if p in TONES}
        if tones:
            if len(tones) == 1:
                base = tuple(p for p in points if p not in TONES and p != 0xFE0F)
                toned.setdefault(base, {})[TONES.index(tones.pop())] = emoji
            continue
        rows[group].append((points, emoji, m.group(3)))
    with open(target, "w", encoding="utf-8") as out:
        for category in ORDER:
            for points, emoji, version in rows[category]:
                forms = toned.get(tuple(p for p in points if p != 0xFE0F), {})
                tones = " ".join(forms[i] for i in range(5)) if len(forms) == 5 else ""
                out.write(f"{category}\t{version}\t{emoji}\t{tones}\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
