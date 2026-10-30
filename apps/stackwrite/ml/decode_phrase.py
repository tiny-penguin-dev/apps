"""Phrase decoding: CTC prefix beam search over a dictionary trie that can
move from one word to the next.

The model's "space" is evidence, not a rule. A space at the end of a
dictionary word commits it; a space in the middle of a word can be
swallowed for a penalty ("televi" + "sion" → "television"); and a word can
end without any space for a penalty (the writer gave no sign, but the
letters only make sense as two words).
"""
import math
from decode import build_trie, _lse
from phrases import CLASSES

SPACE = len(CLASSES)          # class id of the space (27)
BREAK, SWALLOW = -1, -2       # tokens in a hypothesis: implicit break, ignored space
NEG = -math.inf


def _frame_label(tok):
    return SPACE if tok == SWALLOW else tok


def _last_label(prefix):
    for tok in reversed(prefix):
        if tok != BREAK:
            return _frame_label(tok)
    return None


def text_of(prefix):
    out = []
    for tok in prefix:
        if tok in (SPACE, BREAK):
            out.append(" ")
        elif tok > 0:
            out.append(CLASSES[tok - 1])
    return " ".join("".join(out).split())


def beam_search(logp, trie, beam=32, lm_weight=0.5, word_bonus=0.5, break_pen=-4.0,
                swallow_pen=-1.5, char_prune=-8.0, topk=5, partial=False):
    """logp: (T, 28) log-probs. Returns [(text, score), ...].

    partial=True keeps hypotheses whose last word is unfinished (for live
    typing, where the writer may still be in the middle of a word)."""
    # prefix -> [p_blank, p_nonblank, trie node, lm score]
    beams = {(): [0.0, NEG, trie, 0.0]}
    word = lambda node: lm_weight * node.word_logp + word_bonus
    for t in range(len(logp)):
        row = logp[t]
        allowed = [k for k in range(1, SPACE) if row[k] > char_prune]
        space_ok = row[SPACE] > char_prune
        nxt = {}

        def add(prefix, node, lm, which, p):
            e = nxt.get(prefix)
            if e is None:
                e = nxt[prefix] = [NEG, NEG, node, lm]
            e[which] = _lse(e[which], p)

        for prefix, (pb, pnb, node, lm) in beams.items():
            tot = _lse(pb, pnb)
            last = _last_label(prefix)
            add(prefix, node, lm, 0, tot + row[0])
            if last is not None:
                add(prefix, node, lm, 1, pnb + row[last])
            # a letter in this word, or (no space seen) the first of a new word
            starts = [(node, prefix, lm)]
            if node is not trie and node.word_logp is not None:
                starts.append((trie, prefix + (BREAK,), lm + word(node) + break_pen))
            for k in allowed:
                for n0, p0, lm0 in starts:
                    child = n0.kids.get(k)
                    if child is None:
                        continue
                    src = pb if last == k else tot
                    add(p0 + (k,), child, lm0, 1, src + row[k])
            if not space_ok:
                continue
            src = pb if last == SPACE else tot
            if node is not trie and node.word_logp is not None:
                add(prefix + (SPACE,), trie, lm + word(node), 1, src + row[SPACE])
            if node is not trie:
                add(prefix + (SWALLOW,), node, lm + swallow_pen, 1, src + row[SPACE])
            elif last != SPACE:
                add(prefix + (SWALLOW,), node, lm, 1, src + row[SPACE])   # extra or leading space
        beams = dict(sorted(nxt.items(),
                            key=lambda kv: -(_lse(kv[1][0], kv[1][1]) + kv[1][3]))[:beam])

    out = {}
    for prefix, (pb, pnb, node, lm) in beams.items():
        s = _lse(pb, pnb) + lm
        if node is not trie:
            if node.word_logp is not None:
                s += word(node)
            elif not partial:
                continue
        text = text_of(prefix)
        if text and s > out.get(text, NEG):
            out[text] = s
    return sorted(out.items(), key=lambda x: -x[1])[:topk]
