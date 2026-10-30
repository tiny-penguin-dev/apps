"""Word-level decoding: CTC prefix beam search constrained to a dictionary trie,
plus a word-frequency prior. This is what turns sloppy letter guesses into real words."""
import math
import numpy as np
from letters import ALPHABET


class Trie:
    __slots__ = ("kids", "word_logp")

    def __init__(self):
        self.kids, self.word_logp = {}, None


def build_trie(words, freqs):
    root = Trie()
    logf = np.log(np.asarray(freqs) / np.max(freqs))
    for w, lf in zip(words, logf):
        node = root
        for c in w:
            node = node.kids.setdefault(ALPHABET.index(c) + 1, Trie())
        node.word_logp = float(lf)
    return root


def _lse(a, b):
    if a == -math.inf: return b
    if b == -math.inf: return a
    m = max(a, b)
    return m + math.log(math.exp(a - m) + math.exp(b - m))


def beam_search(logp, trie, beam=24, lm_weight=0.35, topk=5, char_prune=-8.0):
    """logp: (T, 27) numpy log-probs for one word. Returns [(word, score), ...]."""
    NEG = -math.inf
    # prefix (tuple of ids) -> [p_blank, p_nonblank, trie_node]
    beams = {(): [0.0, NEG, trie]}
    for t in range(len(logp)):
        row = logp[t]
        allowed = [k for k in range(1, 27) if row[k] > char_prune]
        nxt = {}

        def get(p, node):
            if p not in nxt:
                nxt[p] = [NEG, NEG, node]
            return nxt[p]

        for prefix, (pb, pnb, node) in beams.items():
            tot = _lse(pb, pnb)
            # stay: blank
            e = get(prefix, node); e[0] = _lse(e[0], tot + row[0])
            # stay: repeat last char without blank in between
            if prefix:
                e[1] = _lse(e[1], pnb + row[prefix[-1]])
            for k in allowed:
                child = node.kids.get(k)
                if child is None:
                    continue
                np_ = prefix + (k,)
                e2 = get(np_, child)
                if prefix and prefix[-1] == k:
                    e2[1] = _lse(e2[1], pb + row[k])   # doubled letter needs a blank between
                else:
                    e2[1] = _lse(e2[1], tot + row[k])
        beams = dict(sorted(nxt.items(), key=lambda kv: -_lse(kv[1][0], kv[1][1]))[:beam])
    out = []
    for prefix, (pb, pnb, node) in beams.items():
        if node.word_logp is not None:
            w = "".join(ALPHABET[k - 1] for k in prefix)
            out.append((w, _lse(pb, pnb) + lm_weight * node.word_logp))
    out.sort(key=lambda x: -x[1])
    return out[:topk]
