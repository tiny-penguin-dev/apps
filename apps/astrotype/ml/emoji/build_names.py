"""Builds the emoji names and keywords that emoji search reads, from Unicode's CLDR.

    for f in annotations annotationsDerived; do
      curl -sSL -o $f-en.xml https://raw.githubusercontent.com/unicode-org/cldr/main/common/$f/en.xml
      curl -sSL -o $f-es.xml https://raw.githubusercontent.com/unicode-org/cldr/main/common/$f/es.xml
    done
    R=../../ios/AstrotypeKit/Sources/AstrotypeCore/Resources/emoji
    python3 build_names.py $R/emoji.tsv $R/names-en.tsv annotations-en.xml annotationsDerived-en.xml
    python3 build_names.py $R/emoji.tsv $R/names-es.tsv annotations-es.xml annotationsDerived-es.xml

One line per emoji in `emoji.tsv`, in its order: `emoji<TAB>name<TAB>keywords`, the
keywords separated by `|` (the name itself left out). Read by `EmojiNames`
(features/emoji-search/FEATURE.md). Fails if an emoji has no name, so a new emoji list
can't ship with a hole in search.
"""
import re
import sys

ANNOTATION = re.compile(r'<annotation cp="([^"]+)"( type="tts")?>([^<]*)</annotation>')


def plain(emoji):
    return emoji.replace("️", "")


def unescape(text):
    return text.replace("&amp;", "&").replace("&quot;", '"').replace("&apos;", "'").replace("&lt;", "<").replace("&gt;", ">")


def main(emoji_tsv, target, *sources):
    names, keywords = {}, {}
    for source in sources:
        for cp, tts, text in ANNOTATION.findall(open(source, encoding="utf-8").read()):
            key = plain(unescape(cp))
            if tts:
                names[key] = unescape(text).strip()
            else:
                keywords[key] = [k.strip() for k in unescape(text).split("|") if k.strip()]
    missing = []
    with open(target, "w", encoding="utf-8") as out:
        for line in open(emoji_tsv, encoding="utf-8"):
            emoji = line.rstrip("\n").split("\t")[2]
            name = names.get(plain(emoji))
            if not name:
                missing.append(emoji)
                continue
            words = [k for k in keywords.get(plain(emoji), []) if k.lower() != name.lower()]
            out.write(f"{emoji}\t{name}\t{'|'.join(words)}\n")
    if missing:
        sys.exit(f"no name for {len(missing)} emoji: {' '.join(missing[:20])}")


if __name__ == "__main__":
    main(*sys.argv[1:])
