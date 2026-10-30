"""Score a phrase model on fresh synthetic phrases, with and without the
dictionary decoder.

    python eval_phrases.py runs/phrase.pt --n 300
"""
import argparse, itertools, time
import numpy as np, torch
from decode_phrase import beam_search, build_trie
from model import ConvStrokeNet
from phrases import FEATURES, N_CLASSES
from train import edit
from train_phrases import collate, fixed_set, greedy, word_list


def wer(pred, truth):
    p, t = pred.split(), truth.split()
    return edit(p, t), len(t)


def score(preds, truths):
    errs = words = exact = breaks = 0
    for p, t in zip(preds, truths):
        e, n = wer(p, t)
        errs += e; words += n; exact += p == t
        breaks += len(p.split()) == len(t.split())
    n = len(truths)
    return dict(wer=errs / words, exact=exact / n, breaks=breaks / n)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model")
    ap.add_argument("--n", type=int, default=300)
    ap.add_argument("--seed", type=int, default=777)
    ap.add_argument("--tune", action="store_true", help="try a grid of decoder settings")
    ap.add_argument("--show", type=int, default=15, help="print this many mistakes")
    a = ap.parse_args()

    words, probs = word_list()
    # dictionary words only: that's what the keyboard decodes
    items = fixed_set(a.n, a.seed, words, probs, p_random=0.0)
    model = ConvStrokeNet(features=FEATURES, classes=N_CLASSES)
    model.load_state_dict(torch.load(a.model, map_location="cpu"))
    model.eval()
    truths, lps = [], []
    with torch.no_grad():
        for i in range(0, len(items), 64):
            x, lens, _, _, ls = collate(items[i:i + 64])
            lp = model(x, lens)
            ol = model.out_lens(lens)
            lps += [lp[b, :ol[b]].numpy() for b in range(len(ls))]
            truths += ls
    g = [greedy(torch.from_numpy(l)[None], torch.tensor([len(l)]))[0] for l in lps]
    print("greedy:", score(g, truths))

    trie = build_trie(*word_list_raw())
    grid = [dict()]
    if a.tune:
        grid = [dict(lm_weight=l, word_bonus=wb, break_pen=bp, swallow_pen=sp)
                for l, wb, bp, sp in itertools.product((0.2, 0.35, 0.5), (0.5, 1.5, 2.5),
                                                       (-2.0, -4.0, -6.0), (-1.5, -3.0, -5.0))]
    best = None
    for kw in grid:
        t0 = time.time()
        d = [(beam_search(l, trie, **kw) or [("", 0)])[0][0] for l in lps]
        s = score(d, truths)
        print(f"decoder {kw}: {s} ({(time.time() - t0) / len(lps) * 1000:.0f} ms/phrase)", flush=True)
        if best is None or s["wer"] < best[0]["wer"]:
            best = (s, kw, d)
    s, kw, d = best
    print("best:", kw, s)
    shown = 0
    for p, gg, t in zip(d, g, truths):
        if p != t and shown < a.show:
            print(f"  want {t!r:32} got {p!r:32} greedy {gg!r}")
            shown += 1


def word_list_raw():
    from synth import lexicon
    return lexicon()


if __name__ == "__main__":
    main()
