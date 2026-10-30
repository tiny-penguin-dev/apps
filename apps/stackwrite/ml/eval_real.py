"""Score the phrase model on recorded phrases (sample format v2).

    python3 download_samples.py
    python3 eval_real.py samples/cloud --model runs/phrase.pt

Each writer's usual lift comes from all of their recordings, as the app does.
"""
import argparse
from collections import defaultdict
import numpy as np, torch
from decode_phrase import beam_search, build_trie
from eval_phrases import score
from model import ConvStrokeNet
from phrases import FEATURES, N_CLASSES, featurize_strokes, writer_lift_scale
from samples import load, strokes_of
from synth import lexicon
from train_phrases import greedy


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--model", default="runs/phrase.pt")
    ap.add_argument("--show", type=int, default=40, help="print this many mistakes")
    a = ap.parse_args()

    samples = [s for s in load(a.paths, phrases=True) if s.get("version", 1) >= 2]
    print(f"{len(samples)} phrase recordings")
    if not samples:
        return
    lifts = defaultdict(list)
    for s in samples:
        st = strokes_of(s)
        lifts[s.get("writer")] += [b[0, 2] - p[-1, 2] for p, b in zip(st, st[1:])]
    scales = {w: writer_lift_scale([l for l in ls if l < 5]) for w, ls in lifts.items()}
    print("usual lift per writer (s):", {w[:8]: round(v, 3) for w, v in scales.items()})

    m = ConvStrokeNet(features=FEATURES, classes=N_CLASSES)
    m.load_state_dict(torch.load(a.model, map_location="cpu")); m.eval()
    trie = build_trie(*lexicon())
    truths, greedies, decoded = [], [], []
    for s in samples:
        f = featurize_strokes(strokes_of(s), lift_scale=scales[s.get("writer")])
        with torch.no_grad():
            lp = m(torch.from_numpy(f)[None])[0]
        truths.append(s["label"])
        greedies.append(greedy(lp[None], torch.tensor([len(lp)]))[0])
        decoded.append((beam_search(lp.numpy(), trie) or [("", 0)])[0][0])
    print("greedy: ", score(greedies, truths))
    print("decoder:", score(decoded, truths))
    words = sum(len(t.split()) for t in truths)
    print(f"{words} words; {sum(d == t for d, t in zip(decoded, truths))}/{len(truths)} phrases exactly right")
    shown = 0
    for t, d, g, s in zip(truths, decoded, greedies, samples):
        if d != t and shown < a.show:
            print(f"  want {t!r:30} got {d!r:30} greedy {g!r:30} ({len(s['strokes'])} strokes)")
            shown += 1


if __name__ == "__main__":
    main()
